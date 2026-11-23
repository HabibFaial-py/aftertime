from datetime import datetime, timezone
from uuid import UUID

import pytest

from app.invitation_delivery_worker import (
    DeliveryUnavailable, TransitionOutcomeUnknown, dispatch_transition_committed, transition_committed, verify_envelope,
)
from app.invitation_outbox import PerInvitationEncryptor


JOB = UUID("00000000-0000-4000-8000-000000000161")
TOKEN = UUID("00000000-0000-4000-8000-000000000162")
ENV = UUID("00000000-0000-4000-8000-000000000163")
CAPSULE = UUID("00000000-0000-4000-8000-000000000164")
INVITATION = UUID("00000000-0000-4000-8000-000000000165")
ROOT = bytes(range(32))  # Synthetic test key.


class Cursor:
    def __init__(self, connection):
        self.connection = connection

    def execute(self, query, args):
        self.connection.events.append(("execute", args))
        if self.connection.execute_fails:
            raise TimeoutError("synthetic database error")

    def fetchall(self):
        return self.connection.rows

    def close(self):
        self.connection.events.append("cursor-close")


class Connection:
    autocommit = False

    def __init__(self, rows, *, commit_fails=False, execute_fails=False):
        self.rows, self.commit_fails, self.execute_fails = rows, commit_fails, execute_fails
        self.events = []

    def cursor(self):
        return Cursor(self)

    def commit(self):
        self.events.append("commit")
        if self.commit_fails:
            raise TimeoutError("synthetic commit timeout")

    def rollback(self):
        self.events.append("rollback")

    def close(self):
        self.events.append("close")


def row(outcome="leased", token=TOKEN, generation=1):
    until = datetime.now(timezone.utc) if outcome in {"leased", "prepared", "reserved", "reconcile"} else None
    if until is None:
        token = None
    return (outcome, JOB, token, generation, until, None, None, None, None, None, None, None, None)


def prepared_row():
    encrypted = PerInvitationEncryptor(ROOT, ENV, "v1").encrypt(JOB, INVITATION, CAPSULE, "recipient@example.invalid")
    return ("prepared", JOB, TOKEN, 1, datetime.now(timezone.utc), CAPSULE, INVITATION,
            "recipient@example.invalid", encrypted.key_id, encrypted.nonce, encrypted.salt,
            encrypted.ciphertext, encrypted.digest)


class FakeProvider:
    def __init__(self, fail_after_send=False):
        self.sent = []
        self.fail_after_send = fail_after_send

    def send(self, address, secret):
        self.sent.append((address, secret))
        if self.fail_after_send:
            raise TimeoutError("synthetic provider timeout")


def fake_dispatch(connection, provider):
    # Test-only coordinator: commit the final DB recheck before fake sending.
    result = transition_committed(lambda: connection, JOB, "prepare", TOKEN, 1)
    if result is not None and result.outcome == "prepared":
        claim = verify_envelope(result.envelope, ROOT, ENV, "v1")
        assert connection.events[-1] == "close"
        provider.send(result.envelope.intended_email, claim.secret.get_secret_value())


def test_lease_acknowledged_only_after_successful_commit():
    connection = Connection([row()])
    result = transition_committed(lambda: connection, JOB, "lease")
    assert result.outcome == "leased" and result.lease_token == TOKEN and result.lease_generation == 1
    assert connection.events == [("execute", (str(JOB), "lease", None, None)), "commit", "cursor-close", "close"]
    assert str(TOKEN) not in repr(result)


@pytest.mark.parametrize("outcome,action", [("sent", "sent"), ("retry", "retry"), ("failed", "fail"),
                                            ("cancelled", "prepare"), ("expired", "prepare")])
def test_terminal_or_retry_ack_and_denial_are_distinct(outcome, action):
    connection = Connection([row(outcome)])
    assert transition_committed(lambda: connection, JOB, action, TOKEN, 1).outcome == outcome
    denied = Connection([])
    assert transition_committed(lambda: denied, JOB, action, TOKEN, 1) is None
    assert "commit" in connection.events and "commit" in denied.events


def test_lost_commit_ack_is_unknown_and_never_retried(caplog):
    connection = Connection([row()], commit_fails=True)
    with pytest.raises(TransitionOutcomeUnknown, match="^Invitation transition outcome unknown$") as exc:
        transition_committed(lambda: connection, JOB, "lease")
    assert sum(isinstance(event, tuple) and event[0] == "execute" for event in connection.events) == 1
    assert connection.events[1:3] == ["commit", "rollback"]
    assert "synthetic commit timeout" not in str(exc.value) + caplog.text


def test_execute_failure_and_malformed_response_do_not_acknowledge():
    broken = Connection([], execute_fails=True)
    with pytest.raises(DeliveryUnavailable):
        transition_committed(lambda: broken, JOB, "lease")
    assert "commit" not in broken.events and "rollback" in broken.events
    malformed = Connection([row("sent")])
    with pytest.raises(DeliveryUnavailable):
        transition_committed(lambda: malformed, JOB, "lease")
    assert "commit" not in malformed.events and "rollback" in malformed.events


def test_stale_generation_and_autocommit_fail_closed():
    connection = Connection([row("sent", generation=2)])
    with pytest.raises(DeliveryUnavailable):
        transition_committed(lambda: connection, JOB, "sent", TOKEN, 1)
    assert "commit" not in connection.events
    unsafe = Connection([row()])
    unsafe.autocommit = True
    with pytest.raises(DeliveryUnavailable):
        transition_committed(lambda: unsafe, JOB, "lease")
    assert "commit" not in unsafe.events


@pytest.mark.parametrize("outcome,dispatch", [("reserved", 1), ("reconcile", None), ("reconcile", 3)])
def test_v3_invalid_reservation_acknowledgement_rolls_back(outcome, dispatch):
    connection = Connection([(*row(outcome, generation=2), dispatch)])
    with pytest.raises(DeliveryUnavailable):
        dispatch_transition_committed(lambda: connection, JOB, "reserve", TOKEN, 2)
    assert "commit" not in connection.events and "rollback" in connection.events


def test_v3_resolution_acknowledgement_must_match_supplied_attempt():
    connection = Connection([(*row("sent", generation=3), 2)])
    with pytest.raises(DeliveryUnavailable):
        dispatch_transition_committed(lambda: connection, JOB, "accept", TOKEN, 3, 1)
    assert "commit" not in connection.events and "rollback" in connection.events


def test_cancelled_before_dispatch_and_unknown_commit_never_send():
    provider = FakeProvider()
    fake_dispatch(Connection([row("cancelled")]), provider)
    with pytest.raises(TransitionOutcomeUnknown):
        fake_dispatch(Connection([prepared_row()], commit_fails=True), provider)
    assert provider.sent == []


def test_fake_provider_timeout_is_not_retried_and_can_duplicate_later():
    provider = FakeProvider(fail_after_send=True)
    prepared = prepared_row()
    with pytest.raises(TimeoutError):
        fake_dispatch(Connection([prepared]), provider)
    assert len(provider.sent) == 1
    provider.fail_after_send = False
    fake_dispatch(Connection([prepared]), provider)
    assert len(provider.sent) == 2 and provider.sent[0] == provider.sent[1]
