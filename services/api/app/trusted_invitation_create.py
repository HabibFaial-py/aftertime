"""Unwired invitation creation prototype. No production key provider exists.

A trusted caller must supply the verified JWT subject. The injectable
collaborators below are for local testing and future review only.
"""

import re
from datetime import timedelta
from threading import Lock
from uuid import UUID, uuid4

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from app.direct_capsules import CreateDirectCapsule, DirectCapsuleCreated
from app.invitation_outbox import PerInvitationEncryptor


class InvitationCreationUnavailable(RuntimeError):
    def __init__(self):
        super().__init__("Invitation creation unavailable")


def scoped_key(root_key: bytes, environment_id: UUID, key_version: str) -> tuple[str, bytes]:
    """Legacy test primitive; this shared key is not used for new encryption."""
    if (not isinstance(root_key, bytes) or len(root_key) != 32
            or not isinstance(environment_id, UUID) or environment_id.int == 0
            or not isinstance(key_version, str)
            or not re.fullmatch(r"[a-z0-9]{1,31}", key_version)):
        raise ValueError("Invalid encryption configuration")
    key_id = environment_id.hex + "_" + key_version
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=None,
               info=b"aftertime-outbox-key-v1\x00" + environment_id.bytes
               + key_version.encode("ascii")).derive(root_key)
    return key_id, key


class EncryptionLease:
    """Legacy test primitive; not used by the per-invitation creation path."""

    def __init__(self, root_key: bytes, environment_id: UUID, key_version: str, nonce: bytes):
        key_id, key = scoped_key(root_key, environment_id, key_version)
        if not isinstance(nonce, bytes) or len(nonce) != 12:
            raise ValueError("Invalid encryption configuration")
        self._key_id, self._key, self._nonce = key_id, key, nonce
        self._used = False
        self._lock = Lock()

    def __repr__(self):
        return "EncryptionLease(<redacted>)"

    def __copy__(self):
        raise TypeError("Encryption leases cannot be copied")

    def __deepcopy__(self, memo):
        raise TypeError("Encryption leases cannot be copied")

    def consume(self):
        with self._lock:
            if self._used:
                raise InvitationCreationUnavailable()
            self._used = True
            key, self._key = self._key, None
            return self._key_id, key, self._nonce


def create_with_outbox(verified_user_id: str, capsule: CreateDirectCapsule, *,
                       rpc=None) -> DirectCapsuleCreated:
    """Fail closed: key lifecycle and creation integration are not reviewed."""
    raise InvitationCreationUnavailable()


def _create_with_per_invitation_key(verified_user_id: str, capsule: CreateDirectCapsule, *,
                                    encryptor_provider=None, rpc=None) -> DirectCapsuleCreated:
    """Prototype the creation transaction with test-only injected collaborators.

    Neither collaborator has a production implementation here. This private
    seam does not establish a safe key lifecycle and must not be called by routes.
    """
    try:
        if (not isinstance(verified_user_id, str)
                or str(UUID(verified_user_id)) != verified_user_id
                or UUID(verified_user_id).int == 0
                or type(capsule) is not CreateDirectCapsule
                or not callable(encryptor_provider) or not callable(rpc)):
            raise InvitationCreationUnavailable()
        # Revalidate in case a mutable model was changed or constructed unsafely.
        checked = CreateDirectCapsule.model_validate(capsule.model_dump(mode="json"))
        encryptor = encryptor_provider()
        if type(encryptor) is not PerInvitationEncryptor:
            raise InvitationCreationUnavailable()
        capsule_id, invitation_id, job_id = uuid4(), uuid4(), uuid4()
        encrypted = encryptor.encrypt(job_id, invitation_id, capsule_id, checked.recipient_email)
        rows = rpc("aftertime_create_direct_with_outbox", {
            "p_owner_id": verified_user_id, "p_capsule_id": str(capsule_id),
            "p_invitation_id": str(invitation_id), "p_job_id": str(job_id),
            "p_recipient_email": checked.recipient_email, "p_title": checked.title,
            "p_body": checked.body, "p_unlock_at": checked.unlock_at.isoformat(),
            "p_digest": "\\x" + encrypted.digest.hex(), "p_key_id": encrypted.key_id,
            "p_kdf_salt": "\\x" + encrypted.salt.hex(),
            "p_nonce": "\\x" + encrypted.nonce.hex(),
            "p_ciphertext": "\\x" + encrypted.ciphertext.hex(),
        })
        if not isinstance(rows, list) or len(rows) != 1:
            raise InvitationCreationUnavailable()
        result = DirectCapsuleCreated.model_validate(rows[0])
        if (result.id != capsule_id or result.unlock_at != checked.unlock_at
                or result.created_at >= result.unlock_at
                or result.unlock_at - result.created_at > timedelta(days=90)):
            raise InvitationCreationUnavailable()
        return result
    except Exception:
        # RPC outcomes may be ambiguous; never expose details or retry.
        raise InvitationCreationUnavailable() from None
