"""Opt-in, synthetic-only integration with real Psycopg and fake mail."""

import os
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest

if os.environ.get("AFTERTIME_LOCAL_DELIVERY_TEST") != "1":
    pytest.skip("explicit local delivery test opt-in required", allow_module_level=True)

from app.direct_capsules import DirectClaimRequest
from app.invitation_delivery_worker import TransitionOutcomeUnknown, dispatch_transition_committed
from local_delivery_adapter import (
    CLAIMANT, OWNER, FakeProvider, FakeProviderRetryable, FixtureConnection, LocalDelivery, ProviderOutcome, cleanup_fixture,
    connect_local, create_job, setup_fixture,
)
import local_delivery_adapter


@pytest.fixture
def local_delivery():
    marker = setup_fixture()
    try:
        yield LocalDelivery()
    finally:
        cleanup_fixture(marker)


def row(job_id):
    with connect_local() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT status, attempts, ciphertext, lease_token, lease_generation, next_attempt_at, dispatch_generation "
                        "FROM fixture014i4.invitation_delivery_outbox WHERE id=%s", (job_id,))
            return cur.fetchone()


def update(sql, params):
    with connect_local() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)


def actor_rpc(query, args):
    with connect_local() as conn:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL ROLE service_role")
            cur.execute(query, args)
            return cur.fetchall()


def cancel(capsule):
    return actor_rpc("SELECT * FROM fixture014i4.aftertime_cancel_direct_capsule(%s,%s)", (capsule, OWNER))


def claim(capsule, digest):
    return actor_rpc("SELECT * FROM fixture014i4.aftertime_claim_direct_capsule(%s,%s,%s)",
                     (capsule, CLAIMANT, digest))


def expire_lease(job_id):
    update("UPDATE fixture014i4.invitation_delivery_outbox SET lease_until=clock_timestamp()-interval '1 second' WHERE id=%s", (job_id,))


def invalidate_invitation(event, capsule, invitation, digest):
    if event == "cancel":
        assert len(cancel(capsule)) == 1
    elif event == "revoke":
        update("UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=%s", (invitation,))
    elif event == "expire":
        update("UPDATE fixture014i4.direct_capsule_invitations SET expires_at=clock_timestamp()-interval '1 second' WHERE id=%s",
               (invitation,))
    elif event == "delete":
        update("UPDATE fixture014i4.direct_capsules SET deleted_at=clock_timestamp() WHERE id=%s", (capsule,))
    else:
        assert len(claim(capsule, digest)) == 1


def test_real_driver_success_and_ciphertext_cleanup(local_delivery, caplog):
    job, _, _, digest = create_job()
    provider = FakeProvider()
    assert local_delivery.candidates() == [job]
    assert local_delivery.process(job, provider) == "sent"
    assert len(provider.accepted) == 1 and provider.requests == 1
    _, email, secret = provider.accepted[0]
    assert DirectClaimRequest(secret=secret).digest() == digest
    assert email not in caplog.text and secret not in caplog.text
    status, attempts, ciphertext, token, _, _, dispatch_generation = row(job)
    assert (status, attempts, ciphertext, token) == ("sent", 1, None, None)
    assert dispatch_generation == 1
    assert local_delivery.candidates() == []
    assert local_delivery.process(job, provider) == "unavailable"
    assert provider.requests == 1


def test_concurrent_workers_dispatch_only_one_active_lease(local_delivery):
    job, _, _, _ = create_job()
    provider, barrier = FakeProvider(), Barrier(2)
    def worker(_):
        barrier.wait(timeout=5)
        return local_delivery.process(job, provider)
    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(worker, range(2)))
    assert sorted(outcomes) == ["sent", "unavailable"]
    assert len(provider.accepted) == 1 and provider.requests == 1


def test_reservation_is_one_time_and_resolution_requires_exact_attempt(local_delivery):
    job, _, _, _ = create_job()
    lease = dispatch_transition_committed(FixtureConnection, job, "lease")
    prepare = dispatch_transition_committed(FixtureConnection, job, "prepare", lease.lease_token, 1)
    assert prepare.envelope is not None and prepare.dispatch_generation is None and row(job)[6] is None
    assert dispatch_transition_committed(FixtureConnection, job, "accept", lease.lease_token, 1, 1) is None

    with connect_local() as conn:
        conn.execute("SET LOCAL synchronous_commit = 'off'")
        conn.execute("SET LOCAL ROLE aftertime_invitation_worker")
        reserved = conn.execute("SELECT * FROM fixture014i4.aftertime_invitation_worker_transition_v3("
                                "%s,'reserve',%s,1,NULL)", (job, lease.lease_token)).fetchone()
        assert reserved[0] == "reserved" and reserved[5:13] == (None,) * 8 and reserved[13] == 1
        assert conn.execute("SHOW synchronous_commit").fetchone() == ("on",)
        assert row(job)[6] is None  # The other connection sees the committed state only.

    repeated = dispatch_transition_committed(FixtureConnection, job, "reserve", lease.lease_token, 1)
    assert repeated.outcome == "reconcile" and repeated.envelope is None and repeated.dispatch_generation == 1
    expire_lease(job)
    recovered = dispatch_transition_committed(FixtureConnection, job, "lease")
    assert recovered.lease_generation == 2
    assert dispatch_transition_committed(FixtureConnection, job, "reject", recovered.lease_token, 2, 2) is None
    assert dispatch_transition_committed(FixtureConnection, job, "accept", lease.lease_token, 2, 1) is None
    assert dispatch_transition_committed(FixtureConnection, job, "fail", recovered.lease_token, 2) is None
    assert row(job)[0] == "pending" and row(job)[6] == 1
    assert dispatch_transition_committed(FixtureConnection, job, "accept", recovered.lease_token, 2, 1).outcome == "sent"


def test_cancellation_between_payload_verification_and_reservation_blocks_send(local_delivery, monkeypatch):
    job, capsule, _, _ = create_job()
    provider = FakeProvider()
    original_verify = local_delivery_adapter.verify_envelope

    def verify(*args):
        claim_request = original_verify(*args)
        assert len(cancel(capsule)) == 1
        return claim_request

    monkeypatch.setattr(local_delivery_adapter, "verify_envelope", verify)
    assert local_delivery.process(job, provider) == "ineligible"
    assert provider.requests == 0 and row(job)[0] == "cancelled" and row(job)[6] is None


@pytest.mark.parametrize("event", ["cancel", "claim", "revoke"])
def test_cancellation_claim_or_revocation_before_prepare_blocks_send(local_delivery, event):
    job, capsule, invitation, digest = create_job()
    provider = FakeProvider()
    assert local_delivery.process(
        job, provider, before_prepare=lambda: invalidate_invitation(event, capsule, invitation, digest),
    ) == "ineligible"
    assert provider.requests == 0 and row(job)[0] == "cancelled" and row(job)[2] is None


def test_expired_lease_recovery_fences_old_worker(local_delivery):
    job, _, _, _ = create_job()
    old = dispatch_transition_committed(FixtureConnection, job, "lease")
    expire_lease(job)
    assert dispatch_transition_committed(FixtureConnection, job, "prepare", old.lease_token, old.lease_generation) is None
    provider = FakeProvider()
    assert local_delivery.process(job, provider) == "sent"
    assert row(job)[1] == 2 and row(job)[4] == old.lease_generation + 1
    assert dispatch_transition_committed(FixtureConnection, job, "accept", old.lease_token, old.lease_generation, 1) is None


@pytest.mark.parametrize("action", ["lease", "prepare", "reserve", "accept"])
@pytest.mark.parametrize("fault", ["disconnect_before_commit", "lose_commit_ack"])
def test_unacknowledged_transition_never_retries(local_delivery, action, fault):
    job, _, _, _ = create_job()
    provider = FakeProvider()
    with pytest.raises(TransitionOutcomeUnknown):
        local_delivery.process(job, provider, commit_fault=(action, fault))

    sent = action == "accept"
    assert provider.requests == len(provider.accepted) == int(sent)
    status, attempts, ciphertext, token, generation, _, dispatch_generation = row(job)
    committed = fault == "lose_commit_ack"
    leased = action != "lease" or committed
    terminal = sent and committed
    assert (status, attempts, generation) == ("sent" if terminal else "pending", int(leased), int(leased))
    assert (token is not None) == (leased and not terminal)
    assert (ciphertext is None) == terminal
    assert dispatch_generation == (1 if sent or (action == "reserve" and committed) else None)


def test_expiry_after_reservation_can_send_but_cannot_complete_new_lease(local_delivery, monkeypatch):
    job, _, _, _ = create_job()
    provider = FakeProvider()
    original_send = provider.send

    def send_after_recovery(*args):
        old_token = row(job)[3]
        expire_lease(job)
        new = dispatch_transition_committed(FixtureConnection, job, "lease")
        assert new.outcome == "leased" and new.lease_generation == 2 and new.lease_token != old_token
        return original_send(*args)

    monkeypatch.setattr(provider, "send", send_after_recovery)
    assert local_delivery.process(job, provider) == "accepted_unrecorded"
    assert provider.requests == len(provider.accepted) == 1
    state = row(job)
    assert state[:2] == ("pending", 1) and state[3] is not None and state[4] == 2


def test_cancellation_after_reservation_can_send_but_late_claim_is_denied(local_delivery, monkeypatch):
    job, capsule, _, digest = create_job()
    provider = FakeProvider()
    original_send = provider.send

    def send_after_cancellation(*args):
        # The actor can take the row locks because reserve already committed.
        assert len(cancel(capsule)) == 1
        return original_send(*args)

    monkeypatch.setattr(provider, "send", send_after_cancellation)
    assert local_delivery.process(job, provider) == "cancelled"
    assert provider.requests == len(provider.accepted) == 1
    assert claim(capsule, digest) == []
    assert row(job)[:4] == ("cancelled", 1, None, None)


def test_lost_provider_ack_reconciles_after_expiry_without_resending(local_delivery):
    job, _, _, _ = create_job()
    provider = FakeProvider(deduplicate=False, timeout_after_accept=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    assert provider.requests == 1 and row(job)[0:2] == ("pending", 1)
    assert local_delivery.process(job, provider) == "unavailable"
    expire_lease(job)
    assert local_delivery.candidates() == [job]
    assert LocalDelivery().process(job, provider) == "sent"
    assert provider.requests == len(provider.accepted) == 1
    assert provider.lookups == [(job, 1)]
    assert row(job)[:5] == ("sent", 1, None, None, 2)


@pytest.mark.parametrize("deduplicate,expected_accepted", [(True, 1), (False, 2)])
def test_duplicate_submission_to_provider_depends_on_provider_idempotency(local_delivery, deduplicate, expected_accepted):
    job, _, _, _ = create_job()
    provider = FakeProvider(deduplicate=deduplicate, timeout_after_accept=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    _, recipient, secret = provider.accepted[0]
    # Inject a duplicate outside the coordinator, as could happen at the transport boundary.
    assert provider.send(job, 1, recipient, secret) is ProviderOutcome.ACCEPTED
    assert provider.requests == 2 and len(provider.accepted) == expected_accepted
    expire_lease(job)
    assert LocalDelivery().process(job, provider) == "sent"
    assert provider.requests == 2


def test_definite_fake_rejection_schedules_retry_without_sending(local_delivery):
    job, _, _, _ = create_job()
    provider = FakeProvider(reject_before_accept=True)
    assert local_delivery.process(job, provider) == "retry"
    state = row(job)
    assert provider.requests == 1 and provider.accepted == []
    assert state[0:2] == ("pending", 1) and state[3] is None and state[5] is not None
    assert state[6] is None
    assert local_delivery.candidates() == []
    update("UPDATE fixture014i4.invitation_delivery_outbox SET next_attempt_at=clock_timestamp() WHERE id=%s", (job,))
    provider.reject_before_accept = False
    assert local_delivery.candidates() == [job]
    assert local_delivery.process(job, provider) == "sent"
    assert provider.requests == 2 and len(provider.accepted) == 1
    assert row(job)[:4] == ("sent", 2, None, None)


@pytest.mark.parametrize("hidden_acceptance", [False, True])
def test_unresolved_lookup_stays_pending_without_resending_or_consuming_attempts(local_delivery, hidden_acceptance):
    job, _, _, _ = create_job()
    provider = FakeProvider(timeout_after_accept=hidden_acceptance, lookup_available=not hidden_acceptance,
                            timeout_without_outcome=not hidden_acceptance)
    assert local_delivery.process(job, provider) == "send_unknown"
    for generation in range(2, 7):
        expire_lease(job)
        assert LocalDelivery().process(job, provider) == "send_unknown"
        state = row(job)
        assert state[:2] == ("pending", 1) and state[4] == generation and state[6] == 1
    assert provider.requests == 1 and len(provider.accepted) == int(hidden_acceptance)
    assert provider.lookups == [(job, 1)] * 5


@pytest.mark.parametrize("after_acceptance", [False, True])
def test_worker_crash_after_reservation_recovers_by_lookup_only(local_delivery, monkeypatch, after_acceptance):
    job, _, _, _ = create_job()
    provider = FakeProvider()
    original_send = provider.send

    def crash(*args):
        assert row(job)[6] == 1
        if after_acceptance:
            original_send(*args)
        raise RuntimeError("Synthetic worker crash")

    monkeypatch.setattr(provider, "send", crash)
    with pytest.raises(RuntimeError, match="Synthetic worker crash"):
        local_delivery.process(job, provider)
    monkeypatch.setattr(provider, "send", original_send)
    expire_lease(job)
    assert LocalDelivery().process(job, provider) == ("sent" if after_acceptance else "send_unknown")
    assert provider.requests == len(provider.accepted) == int(after_acceptance)
    assert provider.lookups == [(job, 1)]


@pytest.mark.parametrize("event", ["cancel", "revoke", "claim", "expire", "delete"])
def test_ineligible_unresolved_job_clears_payload_without_resend(local_delivery, event):
    job, capsule, invitation, digest = create_job()
    provider = FakeProvider(timeout_without_outcome=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    invalidate_invitation(event, capsule, invitation, digest)
    expire_lease(job)
    terminal = "expired" if event == "expire" else "cancelled"
    assert LocalDelivery().process(job, provider) == terminal
    assert row(job)[:4] == (terminal, 1, None, None)
    assert provider.requests == 1 and provider.lookups == []


def test_hard_deleted_invitation_cascades_unresolved_job(local_delivery):
    job, _, invitation, _ = create_job()
    provider = FakeProvider(timeout_without_outcome=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    update("DELETE FROM fixture014i4.direct_capsule_invitations WHERE id=%s", (invitation,))
    assert row(job) is None and local_delivery.process(job, provider) == "unavailable"
    assert provider.requests == 1 and provider.lookups == []


def test_cancellation_during_lookup_is_rechecked_before_completion(local_delivery, monkeypatch):
    job, capsule, _, _ = create_job()
    provider = FakeProvider(timeout_after_accept=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    expire_lease(job)
    original_lookup = provider.lookup

    def lookup(*args):
        outcome = original_lookup(*args)
        assert len(cancel(capsule)) == 1
        return outcome

    monkeypatch.setattr(provider, "lookup", lookup)
    assert LocalDelivery().process(job, provider) == "cancelled"
    assert row(job)[:4] == ("cancelled", 1, None, None)
    assert provider.requests == len(provider.accepted) == 1


@pytest.mark.parametrize("event", ["cancel", "claim", "revoke"])
def test_uncommitted_actor_locks_block_reconciliation_write(local_delivery, monkeypatch, event):
    job, capsule, invitation, digest = create_job()
    provider = FakeProvider(timeout_after_accept=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    expire_lease(job)
    original_lookup = provider.lookup

    with connect_local() as actor:
        def lookup(*args):
            outcome = original_lookup(*args)
            if event == "revoke":
                actor.execute("UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=%s",
                              (invitation,))
            else:
                actor.execute("SET LOCAL ROLE service_role")
                if event == "cancel":
                    changed = actor.execute("SELECT * FROM fixture014i4.aftertime_cancel_direct_capsule(%s,%s)",
                                            (capsule, OWNER)).fetchall()
                else:
                    changed = actor.execute("SELECT * FROM fixture014i4.aftertime_claim_direct_capsule(%s,%s,%s)",
                                            (capsule, CLAIMANT, digest)).fetchall()
                assert len(changed) == 1
            return outcome

        monkeypatch.setattr(provider, "lookup", lookup)
        assert local_delivery.process(job, provider) == "accepted_unrecorded"
        assert row(job)[0] == "pending"

    expire_lease(job)
    assert local_delivery.process(job, provider) == "cancelled"
    assert row(job)[:4] == ("cancelled", 1, None, None)
    assert provider.requests == 1 and provider.lookups == [(job, 1)]


def test_stale_lookup_cannot_finish_a_newer_lease(local_delivery, monkeypatch):
    job, _, _, _ = create_job()
    provider = FakeProvider(timeout_after_accept=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    expire_lease(job)
    original_lookup = provider.lookup

    def lookup(*args):
        outcome = original_lookup(*args)
        old_token = row(job)[3]
        expire_lease(job)
        new_lease = dispatch_transition_committed(FixtureConnection, job, "lease")
        assert new_lease.lease_generation == 3 and new_lease.lease_token != old_token
        return outcome

    monkeypatch.setattr(provider, "lookup", lookup)
    assert LocalDelivery().process(job, provider) == "accepted_unrecorded"
    state = row(job)
    assert state[:2] == ("pending", 1) and state[4] == 3 and state[6] == 1
    monkeypatch.setattr(provider, "lookup", original_lookup)
    expire_lease(job)
    assert LocalDelivery().process(job, provider) == "sent"
    assert provider.requests == 1 and provider.lookups == [(job, 1), (job, 1)]


@pytest.mark.parametrize("fault", ["disconnect_before_commit", "lose_commit_ack"])
def test_reconciliation_completion_requires_committed_ack(local_delivery, fault):
    job, _, _, _ = create_job()
    provider = FakeProvider(timeout_after_accept=True)
    assert local_delivery.process(job, provider) == "send_unknown"
    expire_lease(job)
    with pytest.raises(TransitionOutcomeUnknown):
        LocalDelivery().process(job, provider, commit_fault=("accept", fault))
    if fault == "lose_commit_ack":
        assert row(job)[0] == "sent"
        assert LocalDelivery().process(job, provider) == "unavailable"
    else:
        assert row(job)[0] == "pending"
        expire_lease(job)
        assert LocalDelivery().process(job, provider) == "sent"
    assert provider.requests == len(provider.accepted) == 1


def test_reconciliation_retries_only_a_confirmed_rejection(local_delivery):
    job, _, _, _ = create_job()
    provider = FakeProvider(reject_before_accept=True)
    with pytest.raises(TransitionOutcomeUnknown):
        local_delivery.process(job, provider, commit_fault=("reject", "disconnect_before_commit"))
    assert row(job)[6] == 1
    expire_lease(job)
    provider.reject_before_accept = False
    assert LocalDelivery().process(job, provider) == "retry"
    assert provider.requests == 1 and provider.lookups == [(job, 1)]
    assert row(job)[6] is None
    with pytest.raises(FakeProviderRetryable):
        provider.send(job, 1, "recipient014i7@example.invalid", "synthetic")
    assert provider.accepted == []
    update("UPDATE fixture014i4.invitation_delivery_outbox SET next_attempt_at=clock_timestamp() WHERE id=%s", (job,))
    assert LocalDelivery().process(job, provider) == "sent"
    assert row(job)[1] == 2 and row(job)[6] == 3
    assert provider.requests == 3 and len(provider.accepted) == 1


@pytest.mark.parametrize("accepted", [True, False])
def test_fifth_dispatch_can_reconcile_at_attempt_limit(local_delivery, accepted):
    job, _, _, _ = create_job()
    update("UPDATE fixture014i4.invitation_delivery_outbox SET attempts=4 WHERE id=%s", (job,))
    provider = FakeProvider(timeout_after_accept=accepted, reject_before_accept=not accepted)
    if accepted:
        assert local_delivery.process(job, provider) == "send_unknown"
    else:
        with pytest.raises(TransitionOutcomeUnknown):
            local_delivery.process(job, provider, commit_fault=("reject", "disconnect_before_commit"))
    assert row(job)[:2] == ("pending", 5)
    expire_lease(job)
    terminal = "sent" if accepted else "failed"
    assert local_delivery.process(job, provider) == terminal
    assert row(job)[:5] == (terminal, 5, None, None, 2)
    assert provider.requests == 1 and provider.lookups == [(job, 1)]


@pytest.mark.parametrize("field", ["ciphertext", "digest"])
def test_tampered_ciphertext_or_digest_fails_terminally(local_delivery, field):
    job, _, invitation, _ = create_job()
    if field == "ciphertext":
        update("UPDATE fixture014i4.invitation_delivery_outbox SET ciphertext=set_byte(ciphertext,0,get_byte(ciphertext,0) # 1) WHERE id=%s", (job,))
    else:
        update("UPDATE fixture014i4.direct_capsule_invitations SET claim_secret_digest=set_byte(claim_secret_digest,0,get_byte(claim_secret_digest,0) # 1) WHERE id=%s", (invitation,))
    provider = FakeProvider()
    assert local_delivery.process(job, provider) == "failed"
    assert provider.requests == 0 and row(job)[0] == "failed" and row(job)[2] is None
