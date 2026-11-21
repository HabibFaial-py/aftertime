"""Dormant invitation encryption primitives; no database or delivery access."""

import re
import secrets
from dataclasses import dataclass, field
from threading import Lock
from uuid import UUID

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from app.direct_capsules import DirectClaimRequest, generate_invitation_secret


@dataclass(frozen=True)
class EncryptedInvitation:
    key_id: str
    nonce: bytes = field(repr=False)
    ciphertext: bytes = field(repr=False)
    digest: bytes = field(repr=False)


def _associated_data(job_id: UUID, invitation_id: UUID, capsule_id: UUID,
                     key_id: str, recipient_email: str) -> bytes:
    if not all(isinstance(value, UUID) for value in (job_id, invitation_id, capsule_id)):
        raise ValueError("Invalid invitation context")
    if not isinstance(key_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", key_id):
        raise ValueError("Invalid invitation context")
    if (not isinstance(recipient_email, str) or len(recipient_email) > 254
            or recipient_email != recipient_email.strip().lower()
            or not re.fullmatch(r"[^@\s]+@[^@\s]+", recipient_email)
            or "\x00" in recipient_email):
        raise ValueError("Invalid invitation context")
    try:
        email = recipient_email.encode("utf-8")
    except UnicodeEncodeError:
        raise ValueError("Invalid invitation context") from None
    key_name = key_id.encode("ascii")
    return (b"aftertime-invitation-outbox-v1\x00" + job_id.bytes + invitation_id.bytes
            + capsule_id.bytes + len(key_name).to_bytes(1, "big") + key_name
            + len(email).to_bytes(2, "big") + email)


def _cipher(key: bytes) -> AESGCM:
    if not isinstance(key, bytes) or len(key) != 32:
        raise ValueError("Invalid invitation encryption key")
    return AESGCM(key)


def encrypt_invitation(key: bytes, key_id: str, job_id: UUID, invitation_id: UUID,
                       capsule_id: UUID, recipient_email: str) -> EncryptedInvitation:
    """Legacy test primitive: random nonce alone is not a production lifecycle."""
    nonce = secrets.token_bytes(12)
    return encrypt_invitation_with_nonce(key, key_id, job_id, invitation_id,
                                         capsule_id, recipient_email, nonce)


def encrypt_invitation_with_nonce(key: bytes, key_id: str, job_id: UUID,
                                  invitation_id: UUID, capsule_id: UUID,
                                  recipient_email: str, nonce: bytes) -> EncryptedInvitation:
    """Encrypt with a nonce reserved by a trusted, restore-safe authority."""
    cipher = _cipher(key)
    aad = _associated_data(job_id, invitation_id, capsule_id, key_id, recipient_email)
    if not isinstance(nonce, bytes) or len(nonce) != 12:
        raise ValueError("Invalid encrypted invitation")
    claim = generate_invitation_secret()
    ciphertext = cipher.encrypt(nonce, claim.secret.get_secret_value().encode("ascii"), aad)
    return EncryptedInvitation(key_id, nonce, ciphertext, claim.digest())


def decrypt_invitation(key: bytes, key_id: str, job_id: UUID, invitation_id: UUID,
                       capsule_id: UUID, recipient_email: str, nonce: bytes,
                       ciphertext: bytes) -> DirectClaimRequest:
    """Decrypt for future trusted delivery; never call from a public endpoint."""
    cipher = _cipher(key)
    aad = _associated_data(job_id, invitation_id, capsule_id, key_id, recipient_email)
    if not isinstance(nonce, bytes) or len(nonce) != 12 or not isinstance(ciphertext, bytes) or len(ciphertext) != 59:
        raise ValueError("Invalid encrypted invitation")
    try:
        plaintext = cipher.decrypt(nonce, ciphertext, aad).decode("ascii")
        return DirectClaimRequest(secret=plaintext)
    except (InvalidTag, UnicodeDecodeError, ValueError):
        raise ValueError("Invalid encrypted invitation") from None


@dataclass(frozen=True)
class PerInvitationCiphertext:
    key_id: str
    salt: bytes = field(repr=False)
    nonce: bytes = field(repr=False)
    ciphertext: bytes = field(repr=False)
    digest: bytes = field(repr=False)


def _invitation_key(root_key: bytes, environment_id: UUID, key_version: str,
                    salt: bytes, job_id: UUID, invitation_id: UUID, capsule_id: UUID):
    if (not isinstance(root_key, bytes) or len(root_key) != 32
            or not isinstance(environment_id, UUID) or environment_id.int == 0
            or not isinstance(key_version, str) or not re.fullmatch(r"[a-z0-9]{1,31}", key_version)
            or not isinstance(salt, bytes) or len(salt) != 32
            or not all(isinstance(value, UUID) for value in (job_id, invitation_id, capsule_id))):
        raise ValueError("Invalid encryption configuration")
    key_id = environment_id.hex + "_" + key_version
    info = (b"aftertime-invitation-key-v2\x00" + environment_id.bytes
            + len(key_version).to_bytes(1, "big") + key_version.encode("ascii")
            + job_id.bytes + invitation_id.bytes + capsule_id.bytes)
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=info).derive(root_key)
    return key_id, key


def _invitation_aad(job_id, invitation_id, capsule_id, key_id, recipient_email, salt):
    return b"aftertime-per-invitation-v2\x00" + _associated_data(
        job_id, invitation_id, capsule_id, key_id, recipient_email) + salt


class PerInvitationEncryptor:
    """One encryption attempt per instance, including failures; never copy it."""

    def __init__(self, root_key: bytes, environment_id: UUID, key_version: str):
        # Validate configuration without consuming random bytes or exposing key material.
        _invitation_key(root_key, environment_id, key_version, bytes(32), UUID(int=1), UUID(int=2), UUID(int=3))
        self._root_key, self._environment_id, self._key_version = root_key, environment_id, key_version
        self._used = False
        self._lock = Lock()

    def __repr__(self):
        return "PerInvitationEncryptor(<redacted>)"

    def __copy__(self):
        raise TypeError("Encryptors cannot be copied")

    def __deepcopy__(self, memo):
        raise TypeError("Encryptors cannot be copied")

    def encrypt(self, job_id: UUID, invitation_id: UUID, capsule_id: UUID,
                recipient_email: str) -> PerInvitationCiphertext:
        with self._lock:
            if self._used:
                raise ValueError("Encryption already attempted")
            self._used = True
            root_key, self._root_key = self._root_key, None
        # A fresh CSPRNG salt gives each attempt a new key with overwhelming
        # probability. A random nonce is independent defense in depth.
        salt, nonce = secrets.token_bytes(32), secrets.token_bytes(12)
        if len(salt) != 32 or len(nonce) != 12:
            raise ValueError("Invalid encryption randomness")
        key_id, key = _invitation_key(root_key, self._environment_id, self._key_version,
                                      salt, job_id, invitation_id, capsule_id)
        aad = _invitation_aad(job_id, invitation_id, capsule_id, key_id, recipient_email, salt)
        claim = generate_invitation_secret()
        ciphertext = AESGCM(key).encrypt(nonce, claim.secret.get_secret_value().encode("ascii"), aad)
        return PerInvitationCiphertext(key_id, salt, nonce, ciphertext, claim.digest())


def decrypt_per_invitation(root_key: bytes, environment_id: UUID, key_version: str,
                           job_id: UUID, invitation_id: UUID, capsule_id: UUID,
                           recipient_email: str, salt: bytes, nonce: bytes,
                           ciphertext: bytes) -> DirectClaimRequest:
    """Test/future trusted delivery only; caller must also verify the digest."""
    try:
        key_id, key = _invitation_key(root_key, environment_id, key_version, salt,
                                      job_id, invitation_id, capsule_id)
        aad = _invitation_aad(job_id, invitation_id, capsule_id, key_id, recipient_email, salt)
        if not isinstance(nonce, bytes) or len(nonce) != 12 or not isinstance(ciphertext, bytes) or len(ciphertext) != 59:
            raise ValueError("Invalid encrypted invitation")
        return DirectClaimRequest(secret=AESGCM(key).decrypt(nonce, ciphertext, aad).decode("ascii"))
    except (InvalidTag, UnicodeDecodeError, ValueError, TypeError):
        raise ValueError("Invalid encrypted invitation") from None
