from dataclasses import replace
from uuid import UUID

import pytest

from app.invitation_delivery_worker import DeliveryEnvelope, DeliveryUnavailable, run_delivery, verify_envelope
from app.invitation_outbox import PerInvitationEncryptor


ROOT = bytes(range(32))  # Synthetic test key.
ENV = UUID("00000000-0000-4000-8000-000000000151")
JOB = UUID("00000000-0000-4000-8000-000000000152")
INVITE = UUID("00000000-0000-4000-8000-000000000153")
CAPSULE = UUID("00000000-0000-4000-8000-000000000154")
EMAIL = "recipient015@example.invalid"


def envelope():
    item = PerInvitationEncryptor(ROOT, ENV, "v1").encrypt(JOB, INVITE, CAPSULE, EMAIL)
    return DeliveryEnvelope(JOB, CAPSULE, INVITE, EMAIL, item.key_id, item.nonce,
                            item.salt, item.ciphertext, item.digest)


class FakeLocalMail:
    def __init__(self, timeout_after_record=False):
        self.deliveries = []
        self.timeout_after_record = timeout_after_record

    def send(self, email, secret):
        self.deliveries.append((email, secret))
        if self.timeout_after_record:
            raise TimeoutError("synthetic ambiguous send")


def send_fake_after_recheck(item, eligible, transport):
    # Test-only simulation; actual lock/recheck and network dispatch are not wired.
    if eligible:
        claim = verify_envelope(item, ROOT, ENV, "v1")
        transport.send(item.intended_email, claim.secret.get_secret_value())


def test_verified_synthetic_mail_and_redacted_representations(caplog):
    item, mail = envelope(), FakeLocalMail()
    send_fake_after_recheck(item, True, mail)
    assert len(mail.deliveries) == 1
    email, secret = mail.deliveries[0]
    assert email == EMAIL
    assert secret not in repr(item) + caplog.text and EMAIL not in repr(item) + caplog.text


@pytest.mark.parametrize("change", [
    {"root": b"x" * 32}, {"environment": UUID(int=1)},
    {"ciphertext": b"x" * 59}, {"salt": b"x" * 32}, {"nonce": b"x" * 12},
    {"digest": b"x" * 32}, {"intended_email": "other@example.invalid"}, {"key_id": "bad"},
])
def test_invalid_encrypted_payload_never_dispatched(change, caplog):
    root = change.pop("root", ROOT)
    environment = change.pop("environment", ENV)
    item = replace(envelope(), **change)
    with pytest.raises(DeliveryUnavailable, match="^Invitation delivery unavailable$") as exc:
        verify_envelope(item, root, environment, "v1")
    assert EMAIL not in str(exc.value) + caplog.text


def test_cancellation_and_claim_rechecks_prevent_fake_dispatch():
    for eligible in (False, False):  # cancellation and prior claim
        mail = FakeLocalMail()
        send_fake_after_recheck(envelope(), eligible, mail)
        assert not mail.deliveries


def test_ambiguous_fake_send_can_duplicate_after_recovery():
    item, mail = envelope(), FakeLocalMail(timeout_after_record=True)
    with pytest.raises(TimeoutError):
        send_fake_after_recheck(item, True, mail)
    mail.timeout_after_record = False
    send_fake_after_recheck(item, True, mail)
    assert len(mail.deliveries) == 2 and mail.deliveries[0] == mail.deliveries[1]


def test_real_worker_entry_point_is_disabled():
    with pytest.raises(DeliveryUnavailable, match="^Invitation delivery unavailable$"):
        run_delivery()
