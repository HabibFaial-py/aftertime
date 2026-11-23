"""Dormant recipient reads. No routes or database factory are wired here."""

from contextlib import closing, suppress
from datetime import datetime
from typing import Literal
from uuid import UUID

from fastapi.security import HTTPAuthorizationCredentials

from app.auth import current_user
from app.capsules import CapsuleReveal
from app.direct_capsules import ClaimedDirectCapsuleMetadata


_INBOX_QUERY = (
    "SELECT id, sender_id, created_at, unlock_at, status FROM "
    "public.aftertime_list_received_direct_capsules(%s::uuid,%s::integer,%s::integer)"
)
_REVEAL_QUERY = "SELECT id, body FROM public.aftertime_reveal_direct_capsule(%s::uuid,%s::uuid)"


class RecipientReadUnavailable(RuntimeError):
    def __init__(self):
        super().__init__("Recipient capsules unavailable")


class RecipientReadOutcomeUnknown(RecipientReadUnavailable):
    """The read transaction's commit acknowledgement was unavailable."""


class RecipientInboxItem(ClaimedDirectCapsuleMetadata):
    sender_id: UUID
    status: Literal["locked", "unlocked"]


def _verified_subject(credentials: HTTPAuthorizationCredentials | None) -> str:
    if (not isinstance(credentials, HTTPAuthorizationCredentials) or not isinstance(credentials.scheme, str)
            or credentials.scheme.lower() != "bearer"):
        credentials = None
    return current_user(credentials)


def list_received_capsules(credentials: HTTPAuthorizationCredentials | None, *, connection_factory,
                           limit: int = 50, offset: int = 0) -> list[RecipientInboxItem]:
    """Return safe metadata for the verified recipient from one database snapshot."""
    subject = _verified_subject(credentials)
    if type(limit) is not int or not 1 <= limit <= 100 or type(offset) is not int or not 0 <= offset <= 10000:
        raise RecipientReadUnavailable()

    def parse(rows):
        items = []
        for capsule_id, sender_id, created, unlock, status in rows:
            if (not isinstance(created, datetime) or not isinstance(unlock, datetime)
                    or created.utcoffset() is None or unlock.utcoffset() is None or unlock <= created):
                raise ValueError("Invalid recipient metadata")
            item = RecipientInboxItem(id=capsule_id, sender_id=sender_id, created_at=created.isoformat(),
                                      unlock_at=unlock.isoformat(), status=status)
            if str(item.sender_id) == subject:
                raise ValueError("Invalid recipient metadata")
            items.append(item)
        return items

    return _read_once(connection_factory, _INBOX_QUERY, (subject, limit, offset), limit, parse)


def reveal_received_capsule(capsule_id: UUID, credentials: HTTPAuthorizationCredentials | None, *,
                            connection_factory) -> CapsuleReveal | None:
    """Return the body only after an authorized reveal transaction commits."""
    subject = _verified_subject(credentials)
    if not isinstance(capsule_id, UUID):
        raise RecipientReadUnavailable()

    def parse(rows):
        if not rows:
            return None
        row_id, body = rows[0]
        result = CapsuleReveal(id=row_id, body=body)
        if result.id != capsule_id:
            raise ValueError("Invalid reveal result")
        return result

    return _read_once(connection_factory, _REVEAL_QUERY, (str(capsule_id), subject), 1, parse)


def _read_once(connection_factory, query, args, limit, parse):
    # Each call requires a fresh, non-autocommit service connection. Reveal
    # takes row locks and therefore needs a read-write PostgreSQL transaction.
    connection = None
    commit_started = False
    try:
        connection = connection_factory()
        if connection.autocommit is not False:
            raise RecipientReadUnavailable()
        with closing(connection.cursor()) as cursor:
            cursor.execute(query, args)
            rows = cursor.fetchmany(limit + 1)
        if not isinstance(rows, (list, tuple)) or len(rows) > limit:
            raise ValueError("Invalid recipient result")
        result = parse(rows)
        commit_started = True
        connection.commit()
        return result
    except Exception:
        if connection is not None:
            with suppress(Exception):
                connection.rollback()
        if commit_started:
            raise RecipientReadOutcomeUnknown() from None
        raise RecipientReadUnavailable() from None
    finally:
        if connection is not None:
            with suppress(Exception):
                connection.close()
