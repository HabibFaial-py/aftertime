"""Verified-session inbox and reveal against copied SQL on disposable PostgreSQL."""

import os
from concurrent.futures import ThreadPoolExecutor
from threading import Event
from uuid import uuid4

import pytest

if os.environ.get("AFTERTIME_LOCAL_DELIVERY_TEST") != "1":
    pytest.skip("explicit local database test opt-in required", allow_module_level=True)

from app.invitation_claim import ClaimOutcome, build_invitation_link, claim_invitation
from app.recipient_capsules import RecipientReadOutcomeUnknown, list_received_capsules, reveal_received_capsule
from local_delivery_adapter import (
    CLAIMANT, OWNER, FakeProvider, InboxConnection, LocalDelivery, RevealConnection,
    cleanup_fixture, connect_local, create_job, setup_fixture,
)
from test_auth import setup_auth
from test_local_invitation_claim import ClaimConnection, credentials


BODY = "synthetic body"


@pytest.fixture
def recipient_fixture():
    marker = setup_fixture(recipient_reads=True)
    try:
        yield marker
    finally:
        cleanup_fixture(marker)


def prepare_invitation():
    job, capsule, invitation, _ = create_job()
    provider = FakeProvider()
    assert LocalDelivery().process(job, provider) == "sent"
    _, _, secret = provider.accepted[0]
    return capsule, invitation, build_invitation_link(capsule, secret)


def claim_fixture(link, session, connection_factory=None):
    if connection_factory is None:
        connection_factory = lambda: ClaimConnection([])
    return claim_invitation(link, session, confirmed=True, connection_factory=connection_factory)


def set_past_unlock(capsule):
    with connect_local() as connection:
        connection.execute("UPDATE fixture014i4.direct_capsules SET created_at=statement_timestamp()-interval '2 days', "
                           "unlock_at=statement_timestamp()-interval '1 hour' WHERE id=%s", (capsule,))


def inbox(session, *, connection_factory=InboxConnection, **pagination):
    return list_received_capsules(session, connection_factory=connection_factory, **pagination)


def reveal(capsule, session, *, connection_factory=RevealConnection):
    return reveal_received_capsule(capsule, session, connection_factory=connection_factory)


def test_claimed_inbox_excludes_unclaimed_and_reveals_only_after_database_unlock(recipient_fixture, credentials, caplog):
    capsule, _, link = prepare_invitation()
    _, unclaimed, _, _ = create_job()
    session = credentials(email="another-mailbox@example.invalid")
    assert inbox(session) == [] and reveal(capsule, session) is None
    assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED

    item, = inbox(session)
    assert item.id == capsule and item.id != unclaimed and item.sender_id == OWNER and item.status == "locked"
    assert set(item.model_dump()) == {"id", "sender_id", "created_at", "unlock_at", "status"}
    assert item.created_at < item.unlock_at and BODY not in repr(item) + caplog.text
    assert reveal(capsule, session) is None

    set_past_unlock(capsule)
    item, = inbox(session)
    assert item.status == "unlocked" and "body" not in item.model_dump()
    result = reveal(capsule, session)
    assert result.model_dump() == {"id": capsule, "body": BODY} and BODY not in repr(result) + caplog.text


def test_sender_and_other_eligible_account_cannot_read_or_reveal(recipient_fixture, credentials):
    capsule, _, link = prepare_invitation()
    assert claim_fixture(link, credentials()).outcome is ClaimOutcome.CLAIMED
    set_past_unlock(capsule)
    other = uuid4()
    email = "recipient-isolation014j3@example.invalid"
    with connect_local() as connection:
        connection.execute("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES (%s,%s,clock_timestamp())", (other, email))
    try:
        for subject in (OWNER, other):
            session = credentials(subject)
            assert inbox(session) == [] and reveal(capsule, session) is None
    finally:
        with connect_local() as connection:
            assert connection.execute("DELETE FROM auth.users WHERE id=%s AND email=%s RETURNING id",
                                      (other, email)).fetchone() == (other,)


def test_inbox_orders_and_paginates_claimed_capsules(recipient_fixture, credentials):
    session = credentials()
    first, _, earlier = prepare_invitation()
    last, _, later = prepare_invitation()
    assert claim_fixture(earlier, session).outcome is ClaimOutcome.CLAIMED
    assert claim_fixture(later, session).outcome is ClaimOutcome.CLAIMED
    assert [item.id for item in inbox(session)] == [last, first]
    assert [item.id for item in inbox(session, limit=1)] == [last]
    assert [item.id for item in inbox(session, limit=1, offset=1)] == [first]
    assert inbox(session, limit=1, offset=2) == []


@pytest.mark.parametrize("case", ["cancelled", "deleted_capsule", "revoked", "banned", "deleted_account", "missing_profile"])
def test_ineligible_claimed_capsules_are_hidden_and_reveal_is_unavailable(recipient_fixture, credentials, case):
    capsule, invitation, link = prepare_invitation()
    session = credentials()
    assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED
    set_past_unlock(capsule)
    with connect_local() as connection:
        if case == "cancelled":
            connection.execute("UPDATE fixture014i4.direct_capsules SET cancelled_at=unlock_at-interval '1 second' WHERE id=%s",
                               (capsule,))
        elif case == "deleted_capsule":
            connection.execute("UPDATE fixture014i4.direct_capsules SET deleted_at=clock_timestamp() WHERE id=%s", (capsule,))
        elif case == "revoked":
            connection.execute("UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=%s",
                               (invitation,))
        elif case == "banned":
            connection.execute("UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 day' WHERE id=%s", (CLAIMANT,))
        elif case == "deleted_account":
            connection.execute("UPDATE auth.users SET deleted_at=clock_timestamp() WHERE id=%s", (CLAIMANT,))
        else:
            connection.execute("DELETE FROM public.profiles WHERE id=%s", (CLAIMANT,))
    assert inbox(session) == [] and reveal(capsule, session) is None


def test_claimed_binding_survives_the_original_claim_window(recipient_fixture, credentials):
    capsule, invitation, link = prepare_invitation()
    session = credentials()
    assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED
    with connect_local() as connection:
        connection.execute("UPDATE fixture014i4.direct_capsules SET created_at=statement_timestamp()-interval '8 days', "
                           "unlock_at=statement_timestamp()-interval '1 hour' WHERE id=%s", (capsule,))
        connection.execute("UPDATE fixture014i4.direct_capsule_invitations SET "
                           "created_at=statement_timestamp()-interval '8 days', claimed_at=statement_timestamp()-interval '2 days', "
                           "expires_at=statement_timestamp()-interval '1 day' WHERE id=%s", (invitation,))
    assert [item.id for item in inbox(session)] == [capsule]
    assert reveal(capsule, session).body == BODY


def test_concurrent_reads_observe_only_committed_claim(recipient_fixture, credentials):
    capsule, _, link = prepare_invitation()
    set_past_unlock(capsule)
    session = credentials()
    claim_pending, allow_commit = Event(), Event()

    class PausedClaimConnection(ClaimConnection):
        def commit(self):
            claim_pending.set()
            if not allow_commit.wait(timeout=10):
                raise TimeoutError("Synthetic wait for test reads")
            super().commit()

    with ThreadPoolExecutor(max_workers=1) as pool:
        claim = pool.submit(claim_fixture, link, session, lambda: PausedClaimConnection([]))
        try:
            assert claim_pending.wait(timeout=8)
            assert inbox(session) == [] and reveal(capsule, session) is None
        finally:
            allow_commit.set()
        assert claim.result(timeout=8).outcome is ClaimOutcome.CLAIMED
    assert [item.id for item in inbox(session)] == [capsule]
    assert reveal(capsule, session).body == BODY


@pytest.mark.parametrize("fault", ["disconnect_before_commit", "lose_commit_ack"])
@pytest.mark.parametrize("operation", ["inbox", "reveal"])
def test_ambiguous_read_does_not_release_provisional_data_or_retry(recipient_fixture, credentials, caplog, operation, fault):
    capsule, _, link = prepare_invitation()
    session = credentials()
    assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED
    set_past_unlock(capsule)
    connection_type = InboxConnection if operation == "inbox" else RevealConnection
    attempts = []

    def connect():
        attempts.append(True)
        return connection_type(fault)

    with pytest.raises(RecipientReadOutcomeUnknown, match="^Recipient capsules unavailable$") as exc:
        if operation == "inbox":
            inbox(session, connection_factory=connect)
        else:
            reveal(capsule, session, connection_factory=connect)
    assert attempts == [True] and BODY not in repr(exc.value) + caplog.text
