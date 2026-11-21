from dataclasses import replace
from uuid import UUID

import pytest

from app.invitation_outbox import decrypt_invitation, encrypt_invitation
from app import invitation_outbox


KEY = bytes(range(32))  # Synthetic test key, never used outside these tests.
JOB = UUID("00000000-0000-4000-8000-000000000101")
INVITATION = UUID("00000000-0000-4000-8000-000000000102")
CAPSULE = UUID("00000000-0000-4000-8000-000000000103")
EMAIL = "recipient@example.invalid"


def encrypt():
    return encrypt_invitation(KEY, "test-key-1", JOB, INVITATION, CAPSULE, EMAIL)


def decrypt(item, *, key=KEY, key_id="test-key-1", job=JOB, invitation=INVITATION,
            capsule=CAPSULE, email=EMAIL):
    return decrypt_invitation(key, key_id, job, invitation, capsule, email,
                              item.nonce, item.ciphertext)


def test_encrypt_round_trip_and_fake_delivery(caplog):
    item = encrypt()
    claim = decrypt(item)
    secret = claim.secret.get_secret_value()
    assert len(item.nonce) == 12 and len(item.ciphertext) == 59
    assert claim.digest() == item.digest
    assert secret.encode() not in item.ciphertext
    assert secret not in repr(item) + repr(claim) + caplog.text
    # Simulate only a trusted local delivery after verifying the digest.
    fake_delivery = []
    if claim.digest() == item.digest:
        fake_delivery.append((EMAIL, secret))
    assert fake_delivery == [(EMAIL, secret)]


@pytest.mark.parametrize("changed", [
    {"key": b"x" * 32}, {"key_id": "other"}, {"job": UUID(int=1)},
    {"invitation": UUID(int=2)}, {"capsule": UUID(int=3)},
    {"email": "other@example.invalid"},
])
def test_wrong_key_or_context_fails_without_disclosure(changed):
    item = encrypt()
    with pytest.raises(ValueError, match="^Invalid encrypted invitation$"):
        decrypt(item, **changed)


def test_tampering_and_bad_sizes_fail():
    item = encrypt()
    for modified in (
        replace(item, nonce=bytes([item.nonce[0] ^ 1]) + item.nonce[1:]),
        replace(item, ciphertext=item.ciphertext[:-1] + bytes([item.ciphertext[-1] ^ 1])),
        replace(item, nonce=b"short"), replace(item, ciphertext=b"short"),
    ):
        with pytest.raises(ValueError, match="^Invalid encrypted invitation$"):
            decrypt(modified)


def test_fresh_secrets_and_nonces_and_retry_uses_same_ciphertext():
    first, second = encrypt(), encrypt()
    assert first.nonce != second.nonce and first.digest != second.digest
    assert decrypt(first).digest() == first.digest
    assert decrypt(first).secret.get_secret_value() == decrypt(first).secret.get_secret_value()


def test_nonce_random_source_failure_is_not_replaced_or_logged(monkeypatch, caplog):
    calls = []

    def random_bytes(count):
        calls.append(count)
        if count == 32:
            return bytes(range(32))
        raise OSError("nonce source unavailable")

    monkeypatch.setattr(invitation_outbox.secrets, "token_bytes", random_bytes)
    with pytest.raises(OSError, match="nonce source unavailable"):
        encrypt()
    assert calls == [12]
    assert "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8" not in caplog.text


@pytest.mark.parametrize("key", [None, b"", b"x" * 16, b"x" * 33, "x" * 32])
def test_invalid_or_missing_key_fails(key):
    with pytest.raises(ValueError, match="^Invalid invitation encryption key$"):
        encrypt_invitation(key, "test-key-1", JOB, INVITATION, CAPSULE, EMAIL)


@pytest.mark.parametrize("key_id,email", [
    ("", EMAIL), ("bad key", EMAIL), ("x" * 65, EMAIL),
    ("test", " Recipient@example.invalid "), ("test", "broken"),
    ("test", "recipient@example.invalid\x00"), ("test", "a\ud800@example.invalid"),
])
def test_invalid_context_fails_safely(key_id, email):
    with pytest.raises(ValueError, match="^Invalid invitation context$") as error:
        encrypt_invitation(KEY, key_id, JOB, INVITATION, CAPSULE, email)
    assert email not in str(error.value)
