"""Dormant invitation-link and authenticated claim helpers. No route is wired here."""

from contextlib import closing, suppress
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from uuid import UUID

from fastapi.security import HTTPAuthorizationCredentials
from pydantic import SecretStr, ValidationError

from app.auth import current_user
from app.direct_capsules import ClaimedDirectCapsuleMetadata, DirectClaimRequest


_LINK_PREFIX = "https://aftertime.example.invalid/invite/"
_SECRET_LENGTH = 43
_CLAIM_QUERY = (
    "SELECT id, created_at, unlock_at FROM "
    "public.aftertime_claim_direct_capsule(%s::uuid,%s::uuid,%s::bytea)"
)


class InvalidInvitation(ValueError):
    def __init__(self):
        super().__init__("Invalid invitation")


@dataclass(frozen=True)
class InvitationLink:
    capsule_id: UUID
    claim: DirectClaimRequest = field(repr=False)


def _validated_secret(value: str | SecretStr) -> DirectClaimRequest:
    text = value.get_secret_value() if isinstance(value, SecretStr) else value
    if type(text) is not str or len(text) != _SECRET_LENGTH:
        raise InvalidInvitation()
    try:
        return DirectClaimRequest(secret=text)
    except ValidationError:
        raise InvalidInvitation() from None


def build_invitation_link(capsule_id: UUID, secret: str | SecretStr) -> SecretStr:
    """Build a masked link for the reserved local-test origin."""
    if not isinstance(capsule_id, UUID):
        raise InvalidInvitation()
    claim = _validated_secret(secret)
    return SecretStr(f"{_LINK_PREFIX}{capsule_id}#{claim.secret.get_secret_value()}")


def parse_invitation_link(link: str | SecretStr) -> InvitationLink:
    """Parse a canonical link without authentication, network access, or claiming."""
    text = link.get_secret_value() if isinstance(link, SecretStr) else link
    if (type(text) is not str or len(text) != len(_LINK_PREFIX) + 36 + 1 + _SECRET_LENGTH
            or not text.startswith(_LINK_PREFIX)):
        raise InvalidInvitation()
    capsule_text, _, secret = text[len(_LINK_PREFIX):].partition("#")
    try:
        capsule_id = UUID(capsule_text)
    except ValueError:
        raise InvalidInvitation() from None
    if capsule_text != str(capsule_id):
        raise InvalidInvitation()
    return InvitationLink(capsule_id, _validated_secret(secret))


class ClaimOutcome(Enum):
    CONFIRMATION_REQUIRED = "confirmation_required"
    UNAVAILABLE = "unavailable"
    SERVICE_UNAVAILABLE = "service_unavailable"
    OUTCOME_UNKNOWN = "outcome_unknown"
    CLAIMED = "claimed"


@dataclass(frozen=True)
class ClaimResult:
    outcome: ClaimOutcome
    capsule: ClaimedDirectCapsuleMetadata | None = None


def claim_invitation(
    link: str | SecretStr,
    credentials: HTTPAuthorizationCredentials | None,
    *,
    confirmed: bool = False,
    connection_factory,
) -> ClaimResult:
    """Claim on explicit action using a verified JWT and a dedicated service transaction.

    The factory must supply a fresh, non-autocommit DB-API connection with
    server-side claim privileges. No production connection factory is wired.
    """
    if confirmed is not True:
        return ClaimResult(ClaimOutcome.CONFIRMATION_REQUIRED)
    if (not isinstance(credentials, HTTPAuthorizationCredentials) or not isinstance(credentials.scheme, str)
            or credentials.scheme.lower() != "bearer"):
        credentials = None
    subject = current_user(credentials)
    try:
        invitation = parse_invitation_link(link)
    except InvalidInvitation:
        return ClaimResult(ClaimOutcome.UNAVAILABLE)
    return _claim_once(invitation.capsule_id, subject, invitation.claim.digest(), connection_factory)


def _claim_once(capsule_id: UUID, subject: str, digest: bytes, connection_factory) -> ClaimResult:
    connection = None
    commit_started = False
    try:
        connection = connection_factory()
        if connection.autocommit is not False:
            return ClaimResult(ClaimOutcome.SERVICE_UNAVAILABLE)
        with closing(connection.cursor()) as cursor:
            cursor.execute(_CLAIM_QUERY, (str(capsule_id), subject, digest))
            rows = cursor.fetchmany(2)
        if not isinstance(rows, (list, tuple)) or len(rows) > 1:
            raise ValueError("Invalid claim result")
        if rows:
            claimed_id, created, unlock = rows[0]
            if (not isinstance(created, datetime) or not isinstance(unlock, datetime)
                    or created.tzinfo is None or unlock.tzinfo is None or unlock <= created):
                raise ValueError("Invalid claim result")
            metadata = ClaimedDirectCapsuleMetadata(
                id=claimed_id, created_at=created.isoformat(), unlock_at=unlock.isoformat(),
            )
            if metadata.id != capsule_id:
                raise ValueError("Invalid claim result")
            result = ClaimResult(ClaimOutcome.CLAIMED, metadata)
        else:
            result = ClaimResult(ClaimOutcome.UNAVAILABLE)
        commit_started = True
        connection.commit()
        return result
    except Exception:
        if connection is not None:
            with suppress(Exception):
                connection.rollback()
        return ClaimResult(ClaimOutcome.OUTCOME_UNKNOWN if commit_started else ClaimOutcome.SERVICE_UNAVAILABLE)
    finally:
        if connection is not None:
            with suppress(Exception):
                connection.close()
