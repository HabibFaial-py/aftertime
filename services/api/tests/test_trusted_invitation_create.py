import copy
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest

from app.direct_capsules import CreateDirectCapsule
from app.invitation_outbox import PerInvitationEncryptor, decrypt_per_invitation
from app.trusted_invitation_create import (
    EncryptionLease, InvitationCreationUnavailable, create_with_outbox as disabled_create,
    _create_with_per_invitation_key as create_with_outbox, scoped_key,
)


ROOT = bytes(range(32))  # Synthetic, test-only key.
ENV = UUID("00000000-0000-4000-8000-000000000123")
OWNER = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
NONCE = bytes(range(12))


def capsule():
    return CreateDirectCapsule(title="fixture", body="private fixture", recipient_email="to@example.invalid",
                               unlock_at=(datetime.now(timezone.utc) + timedelta(days=1)).isoformat())


def lease():
    return EncryptionLease(ROOT, ENV, "v1", NONCE)


def encryptor():
    return PerInvitationEncryptor(ROOT, ENV, "v1")


def decode_bytea(value):
    assert value.startswith("\\x")
    return bytes.fromhex(value[2:])


def successful_rpc(calls):
    def rpc(name, fields):
        calls.append((name, fields))
        return [{"id": fields["p_capsule_id"], "unlock_at": fields["p_unlock_at"],
                 "created_at": datetime.now(timezone.utc).isoformat()}]
    return rpc


def test_one_rpc_binds_digest_ciphertext_context_and_safe_response(caplog):
    calls = []
    result = create_with_outbox(OWNER, capsule(), encryptor_provider=encryptor, rpc=successful_rpc(calls))
    assert len(calls) == 1
    name, args = calls[0]
    assert name == "aftertime_create_direct_with_outbox" and args["p_owner_id"] == OWNER
    key_id, _ = scoped_key(ROOT, ENV, "v1")
    assert args["p_key_id"] == key_id
    claim = decrypt_per_invitation(ROOT, ENV, "v1", UUID(args["p_job_id"]), UUID(args["p_invitation_id"]),
                                   UUID(args["p_capsule_id"]), args["p_recipient_email"],
                                   decode_bytea(args["p_kdf_salt"]), decode_bytea(args["p_nonce"]),
                                   decode_bytea(args["p_ciphertext"]))
    assert claim.digest() == decode_bytea(args["p_digest"])
    secret = claim.secret.get_secret_value()
    assert secret not in repr(args) + repr(result) + caplog.text
    assert set(result.model_dump()) == {"id", "unlock_at", "created_at"}
    assert secret.encode() not in decode_bytea(args["p_ciphertext"])
    for wrong_env, email in [(UUID(int=1234), args["p_recipient_email"]), (ENV, "other@example.invalid")]:
        with pytest.raises(ValueError, match="^Invalid encrypted invitation$"):
            decrypt_per_invitation(ROOT, wrong_env, "v1", UUID(args["p_job_id"]), UUID(args["p_invitation_id"]),
                                   UUID(args["p_capsule_id"]), email, decode_bytea(args["p_kdf_salt"]),
                                   decode_bytea(args["p_nonce"]), decode_bytea(args["p_ciphertext"]))


def test_environment_and_rotation_derive_distinct_keys():
    key_id, key = scoped_key(ROOT, ENV, "v1")
    other_id, other_key = scoped_key(ROOT, UUID(int=1234), "v1")
    rotated_id, rotated_key = scoped_key(ROOT, ENV, "v2")
    assert len({key_id, other_id, rotated_id}) == 3
    assert len({key, other_key, rotated_key}) == 3
    with pytest.raises(ValueError):
        scoped_key(ROOT, ENV, "")
    with pytest.raises(ValueError):
        scoped_key(ROOT, UUID(int=0), "v1")
    with pytest.raises(ValueError):
        scoped_key(b"short", ENV, "v1")


def test_encryption_lease_consumed_once_even_concurrently():
    item = lease()
    def consume():
        try:
            item.consume()
            return True
        except InvitationCreationUnavailable:
            return False
    with ThreadPoolExecutor(max_workers=8) as pool:
        assert sum(pool.map(lambda _: consume(), range(16))) == 1
    with pytest.raises(TypeError):
        copy.copy(item)
    with pytest.raises(TypeError):
        copy.deepcopy(item)
    assert ROOT.hex() not in repr(item)


def test_missing_lease_provider_fails_closed_without_rpc():
    calls = []
    with pytest.raises(InvitationCreationUnavailable):
        create_with_outbox(OWNER, capsule(), rpc=successful_rpc(calls))
    assert calls == []
    with pytest.raises(InvitationCreationUnavailable):
        disabled_create(OWNER, capsule(), rpc=successful_rpc(calls))
    assert calls == []


@pytest.mark.parametrize("identity", [None, "", "bad", OWNER.upper(), str(UUID(int=0))])
def test_invalid_identity_does_not_call_rpc(identity):
    calls = []
    with pytest.raises(InvitationCreationUnavailable):
        create_with_outbox(identity, capsule(), encryptor_provider=encryptor, rpc=successful_rpc(calls))
    assert not calls


def test_mutated_or_invalid_capsule_is_rejected_before_lease():
    item = capsule()
    item.body = ""
    calls = []
    with pytest.raises(InvitationCreationUnavailable):
        create_with_outbox(OWNER, item, encryptor_provider=lambda: calls.append(1), rpc=successful_rpc(calls))
    assert not calls


@pytest.mark.parametrize("response", [[], None, [{}], [{"id": "bad"}],
    [{"id": OWNER, "created_at": "2026-01-01T00:00:00Z", "unlock_at": "2026-01-02T00:00:00Z"}]])
def test_invalid_rpc_result_fails_without_retry_or_details(response, caplog):
    calls = []
    def rpc(name, args):
        calls.append(name)
        return response
    with pytest.raises(InvitationCreationUnavailable, match="^Invitation creation unavailable$"):
        create_with_outbox(OWNER, capsule(), encryptor_provider=encryptor, rpc=rpc)
    assert calls == ["aftertime_create_direct_with_outbox"]
    assert "private fixture" not in caplog.text


def test_ambiguous_rpc_failure_is_sanitized_and_lease_remains_spent(caplog):
    item, calls = encryptor(), []
    def rpc(name, args):
        calls.append(name)
        raise TimeoutError("sensitive upstream details")
    for _ in range(2):
        with pytest.raises(InvitationCreationUnavailable, match="^Invitation creation unavailable$") as exc:
            create_with_outbox(OWNER, capsule(), encryptor_provider=lambda: item, rpc=rpc)
        assert "sensitive" not in str(exc.value)
    assert len(calls) == 1
    assert "sensitive upstream details" not in caplog.text


@pytest.mark.parametrize("field", ["id", "unlock_at", "created_at", "extra"])
def test_invalid_success_contract_is_rejected(field):
    def rpc(_, args):
        row = {"id": args["p_capsule_id"], "unlock_at": args["p_unlock_at"],
               "created_at": datetime.now(timezone.utc).isoformat()}
        row[field] = {"id": OWNER, "unlock_at": "2020-01-01T00:00:00Z",
                      "created_at": "2100-01-01T00:00:00Z", "extra": "secret"}[field]
        return [row]
    with pytest.raises(InvitationCreationUnavailable):
        create_with_outbox(OWNER, capsule(), encryptor_provider=encryptor, rpc=rpc)
