import copy
from concurrent.futures import ThreadPoolExecutor
from uuid import UUID

import pytest

from app import invitation_outbox as outbox


ROOT = bytes(range(32))  # Synthetic test key.
ENV = UUID("00000000-0000-4000-8000-000000000101")
JOB = UUID("00000000-0000-4000-8000-000000000102")
INVITE = UUID("00000000-0000-4000-8000-000000000103")
CAPSULE = UUID("00000000-0000-4000-8000-000000000104")
EMAIL = "recipient@example.invalid"


def encryptor():
    return outbox.PerInvitationEncryptor(ROOT, ENV, "v1")


def decrypt(item, **changes):
    values = dict(root_key=ROOT, environment_id=ENV, key_version="v1", job_id=JOB,
                  invitation_id=INVITE, capsule_id=CAPSULE, recipient_email=EMAIL,
                  salt=item.salt, nonce=item.nonce, ciphertext=item.ciphertext)
    values.update(changes)
    return outbox.decrypt_per_invitation(**values)


def test_round_trip_digest_and_fresh_derived_keys(caplog):
    first = encryptor().encrypt(JOB, INVITE, CAPSULE, EMAIL)
    second = encryptor().encrypt(JOB, INVITE, CAPSULE, EMAIL)
    claim = decrypt(first)
    assert first.salt != second.salt and len(first.salt) == 32 and len(first.nonce) == 12
    assert claim.digest() == first.digest and decrypt(second).digest() == second.digest
    first_key = outbox._invitation_key(ROOT, ENV, "v1", first.salt, JOB, INVITE, CAPSULE)[1]
    second_key = outbox._invitation_key(ROOT, ENV, "v1", second.salt, JOB, INVITE, CAPSULE)[1]
    assert first_key != second_key
    assert claim.secret.get_secret_value() not in repr(first) + caplog.text


def test_same_salt_collision_with_different_context_derives_distinct_key():
    salt = bytes(32)
    first = outbox._invitation_key(ROOT, ENV, "v1", salt, JOB, INVITE, CAPSULE)[1]
    second = outbox._invitation_key(ROOT, ENV, "v1", salt, JOB, UUID(int=123), CAPSULE)[1]
    assert first != second
    # A duplicate salt AND context deterministically repeats a key: no local
    # database constraint can prevent this across rollback, restore or hosts.
    assert first == outbox._invitation_key(ROOT, ENV, "v1", salt, JOB, INVITE, CAPSULE)[1]


@pytest.mark.parametrize("changes", [
    {"root_key": b"x" * 32}, {"environment_id": UUID(int=5)}, {"key_version": "v2"},
    {"job_id": UUID(int=6)}, {"invitation_id": UUID(int=7)}, {"capsule_id": UUID(int=8)},
    {"recipient_email": "other@example.invalid"}, {"salt": b"s" * 32},
    {"nonce": b"n" * 12}, {"ciphertext": b"c" * 59},
])
def test_wrong_key_or_tampered_metadata_fails(changes):
    item = encryptor().encrypt(JOB, INVITE, CAPSULE, EMAIL)
    with pytest.raises(ValueError, match="^Invalid encrypted invitation$"):
        decrypt(item, **changes)


def test_encryptor_reuse_rejected_concurrently_and_cannot_be_copied():
    item = encryptor()
    def attempt(_):
        try:
            item.encrypt(JOB, INVITE, CAPSULE, EMAIL)
            return True
        except ValueError:
            return False
    with ThreadPoolExecutor(max_workers=8) as pool:
        assert sum(pool.map(attempt, range(16))) == 1
    with pytest.raises(TypeError):
        copy.copy(item)
    with pytest.raises(TypeError):
        copy.deepcopy(item)


def test_rng_failure_burns_attempt_without_fallback(monkeypatch):
    item = encryptor()
    def fail(_):
        raise OSError("source unavailable")
    monkeypatch.setattr(outbox.secrets, "token_bytes", fail)
    with pytest.raises(OSError):
        item.encrypt(JOB, INVITE, CAPSULE, EMAIL)
    with pytest.raises(ValueError, match="^Encryption already attempted$"):
        item.encrypt(JOB, INVITE, CAPSULE, EMAIL)


@pytest.mark.parametrize("root,env,version", [(b"short", ENV, "v1"), (ROOT, UUID(int=0), "v1"),
                                              (ROOT, ENV, ""), (ROOT, ENV, "bad id")])
def test_invalid_key_configuration_fails(root, env, version):
    with pytest.raises(ValueError, match="^Invalid encryption configuration$"):
        outbox.PerInvitationEncryptor(root, env, version)
