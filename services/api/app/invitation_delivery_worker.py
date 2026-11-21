"""Dormant delivery verification primitives. No worker loop or real transport."""

import hmac
from dataclasses import dataclass, field
from datetime import datetime
from uuid import UUID

from app.direct_capsules import DirectClaimRequest
from app.invitation_outbox import decrypt_per_invitation


class DeliveryUnavailable(RuntimeError):
    def __init__(self):
        super().__init__("Invitation delivery unavailable")


class TransitionOutcomeUnknown(DeliveryUnavailable):
    def __init__(self):
        RuntimeError.__init__(self, "Invitation transition outcome unknown")


@dataclass(frozen=True, repr=False)
class DeliveryEnvelope:
    job_id: UUID
    capsule_id: UUID
    invitation_id: UUID
    intended_email: str = field(repr=False)
    key_id: str
    nonce: bytes = field(repr=False)
    salt: bytes = field(repr=False)
    ciphertext: bytes = field(repr=False)
    digest: bytes = field(repr=False)

    def __repr__(self):
        return "DeliveryEnvelope(<redacted>)"


def verify_envelope(envelope: DeliveryEnvelope, root_key: bytes, environment_id: UUID,
                    key_version: str) -> DirectClaimRequest:
    """Authenticate encrypted data and compare its digest, without dispatch."""
    try:
        if (type(envelope) is not DeliveryEnvelope or not isinstance(environment_id, UUID)
                or not isinstance(key_version, str)
                or envelope.key_id != environment_id.hex + "_" + key_version
                or not isinstance(envelope.digest, bytes) or len(envelope.digest) != 32):
            raise DeliveryUnavailable()
        claim = decrypt_per_invitation(
            root_key, environment_id, key_version, envelope.job_id, envelope.invitation_id,
            envelope.capsule_id, envelope.intended_email, envelope.salt,
            envelope.nonce, envelope.ciphertext)
        if not hmac.compare_digest(claim.digest(), envelope.digest):
            raise DeliveryUnavailable()
        return claim
    except Exception:
        raise DeliveryUnavailable() from None


@dataclass(frozen=True, repr=False)
class CommittedTransition:
    outcome: str
    job_id: UUID
    lease_token: UUID | None = field(repr=False)
    lease_generation: int
    lease_until: datetime | None
    envelope: DeliveryEnvelope | None = field(repr=False)

    def __repr__(self):
        return f"CommittedTransition(outcome={self.outcome!r}, <redacted>)"


def _parse_transition(row, job_id: UUID, action: str) -> CommittedTransition:
    if not isinstance(row, (tuple, list)) or len(row) != 13:
        raise ValueError("Invalid transition")
    outcome, row_job, token, generation, until, capsule, invitation, email, key_id, nonce, salt, ciphertext, digest = row
    allowed = {"lease": {"leased", "cancelled", "expired", "failed"},
               "prepare": {"prepared", "cancelled", "expired"},
               "sent": {"sent", "cancelled", "expired"},
               "retry": {"retry", "failed", "cancelled", "expired"},
               "fail": {"failed", "cancelled", "expired"}}
    if (outcome not in allowed[action] or UUID(str(row_job)) != job_id
            or type(generation) is not int or generation < 0):
        raise ValueError("Invalid transition")
    envelope = None
    if outcome in {"leased", "prepared"}:
        token = UUID(str(token))
        if generation < 1 or not isinstance(until, datetime) or until.tzinfo is None or until.utcoffset() is None:
            raise ValueError("Invalid transition")
        if outcome == "prepared":
            if (not isinstance(email, str) or not isinstance(key_id, str)
                    or not all(isinstance(value, (bytes, memoryview)) for value in (nonce, salt, ciphertext, digest))):
                raise ValueError("Invalid transition")
            envelope = DeliveryEnvelope(job_id, UUID(str(capsule)), UUID(str(invitation)), email, key_id,
                                        bytes(nonce), bytes(salt), bytes(ciphertext), bytes(digest))
        elif any(value is not None for value in (capsule, invitation, email, key_id, nonce, salt, ciphertext, digest)):
            raise ValueError("Invalid transition")
    elif any(value is not None for value in (token, until, capsule, invitation, email, key_id, nonce, salt, ciphertext, digest)):
        raise ValueError("Invalid transition")
    return CommittedTransition(outcome, job_id, token, generation, until, envelope)


def transition_committed(connection_factory, job_id: UUID, action: str,
                         token: UUID | None = None, generation: int | None = None) -> CommittedTransition | None:
    """Use a fresh dedicated DB-API connection; expose results only after commit.

    A factory must open a new non-autocommit transaction and not share it. No
    production factory is configured; this function never performs a send.
    """
    connection = cursor = None
    commit_started = False
    try:
        if (not callable(connection_factory) or not isinstance(job_id, UUID)
                or action not in {"lease", "prepare", "sent", "retry", "fail"}
                or (action == "lease" and (token is not None or generation is not None))
                or (action != "lease" and (not isinstance(token, UUID) or type(generation) is not int or generation < 1))):
            raise DeliveryUnavailable()
        connection = connection_factory()
        if connection.autocommit is not False:
            raise DeliveryUnavailable()
        cursor = connection.cursor()
        cursor.execute("SELECT * FROM public.aftertime_invitation_worker_transition_v2(%s::uuid,%s::text,%s::uuid,%s::bigint)",
                       (str(job_id), action, str(token) if token else None, generation))
        rows = cursor.fetchall()
        if not isinstance(rows, (tuple, list)) or len(rows) > 1:
            raise DeliveryUnavailable()
        result = _parse_transition(rows[0], job_id, action) if rows else None
        if (result is not None and action != "lease"
                and (result.lease_generation != generation
                     or (result.outcome == "prepared" and result.lease_token != token))):
            raise DeliveryUnavailable()
        commit_started = True
        connection.commit()
        return result
    except Exception:
        if connection is not None:
            try:
                connection.rollback()
            except Exception:
                pass
        if commit_started:
            raise TransitionOutcomeUnknown() from None
        raise DeliveryUnavailable() from None
    finally:
        for resource in (cursor, connection):
            if resource is not None:
                try:
                    resource.close()
                except Exception:
                    pass


def run_delivery() -> None:
    """Fail closed until dispatch and lifecycle authorization are reviewed."""
    raise DeliveryUnavailable()
