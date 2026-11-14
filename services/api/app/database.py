"""Server-only Data API repository. Never accept user tokens or request headers.

The secret bypasses RLS. Future user-specific methods must be preceded by
explicit authorization using identity from app.auth.current_user.
"""

import httpx
from pydantic import ValidationError

from app.config import get_database_settings
from app.capsules import CapsuleCancellation, CapsuleMetadata, CapsuleReveal, CreateCapsule
from uuid import UUID


class DatabaseUnavailableError(RuntimeError):
    def __init__(self) -> None:
        super().__init__("Database connectivity check failed")


class DatabaseInputError(Exception):
    pass


class DatabaseOwnerError(Exception):
    pass


class DatabaseRepository:
    def __init__(self) -> None:
        self._settings = get_database_settings()

    def cancel_self_capsule(self, capsule_id: UUID, requester_id: str) -> CapsuleCancellation | None:
        """The database RPC enforces authorization, time and repeat cancellation."""
        try:
            with httpx.Client(
                base_url=f"{self._settings.supabase_url}/rest/v1/",
                headers={"apikey": self._settings.secret_key, "Content-Profile": "public"},
                timeout=5.0, follow_redirects=False, trust_env=False,
            ) as client:
                response = client.post("rpc/aftertime_cancel_self_capsule", json={
                    "p_capsule_id": str(capsule_id), "p_requester_id": requester_id,
                })
                if response.status_code != 200:
                    raise DatabaseUnavailableError()
                rows = response.json()
                if not isinstance(rows, list) or len(rows) > 1:
                    raise DatabaseUnavailableError()
                if not rows:
                    return None
                cancellation = CapsuleCancellation.model_validate(rows[0])
                if cancellation.id != capsule_id:
                    raise DatabaseUnavailableError()
                return cancellation
        except (httpx.HTTPError, ValueError, ValidationError):
            raise DatabaseUnavailableError() from None

    def reveal_self_capsule(self, capsule_id: UUID, requester_id: str) -> CapsuleReveal | None:
        """The RPC, not the API clock or a separate table read, decides eligibility."""
        try:
            with httpx.Client(
                base_url=f"{self._settings.supabase_url}/rest/v1/",
                headers={"apikey": self._settings.secret_key, "Content-Profile": "public"},
                timeout=5.0, follow_redirects=False, trust_env=False,
            ) as client:
                response = client.post("rpc/aftertime_reveal_self_capsule", json={
                    "p_capsule_id": str(capsule_id), "p_requester_id": requester_id,
                })
                if response.status_code != 200:
                    raise DatabaseUnavailableError()
                rows = response.json()
                if not isinstance(rows, list) or len(rows) > 1:
                    raise DatabaseUnavailableError()
                if not rows:
                    return None
                reveal = CapsuleReveal.model_validate(rows[0])
                if reveal.id != capsule_id:
                    raise DatabaseUnavailableError()
                return reveal
        except (httpx.HTTPError, ValueError, ValidationError):
            raise DatabaseUnavailableError() from None

    def create_self_capsule(self, owner_id: str, capsule: CreateCapsule) -> CapsuleMetadata:
        try:
            with httpx.Client(
                base_url=f"{self._settings.supabase_url}/rest/v1/",
                headers={"apikey": self._settings.secret_key, "Content-Profile": "public"},
                timeout=5.0, follow_redirects=False, trust_env=False,
            ) as client:
                response = client.post("rpc/aftertime_create_self_capsule", json={
                    "p_owner_id": owner_id, "p_title": capsule.title,
                    "p_body": capsule.body, "p_unlock_at": capsule.unlock_at.isoformat(),
                })
                if response.status_code != 200:
                    try:
                        code = response.json().get("code")
                    except (ValueError, AttributeError):
                        code = None
                    if response.status_code == 400 and code == "22023":
                        raise DatabaseInputError() from None
                    if response.status_code == 403 and code == "42501":
                        raise DatabaseOwnerError() from None
                    raise DatabaseUnavailableError() from None
                rows = response.json()
                if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict):
                    raise DatabaseUnavailableError() from None
                return CapsuleMetadata.model_validate(rows[0])
        except (httpx.HTTPError, ValueError, ValidationError):
            raise DatabaseUnavailableError() from None

    def list_owned_capsules(self, owner_id: str, limit: int, offset: int) -> list[CapsuleMetadata]:
        """Select only safe fields, with ownership enforced by PostgreSQL."""
        try:
            with httpx.Client(
                base_url=f"{self._settings.supabase_url}/rest/v1/",
                headers={"apikey": self._settings.secret_key, "Accept-Profile": "public"},
                timeout=5.0, follow_redirects=False, trust_env=False,
            ) as client:
                response = client.get("capsules", params={
                    "select": "id,title,created_at,unlock_at",
                    "owner_id": f"eq.{owner_id}",
                    "deleted_at": "is.null",
                    "cancelled_at": "is.null",
                    "order": "created_at.desc,id.desc",
                    "limit": str(limit), "offset": str(offset),
                })
                if response.status_code not in (200, 206):
                    raise DatabaseUnavailableError()
                rows = response.json()
                if not isinstance(rows, list) or len(rows) > limit:
                    raise DatabaseUnavailableError()
                return [CapsuleMetadata.model_validate(row) for row in rows]
        except (httpx.HTTPError, ValueError, ValidationError):
            raise DatabaseUnavailableError() from None

    def check_connection(self) -> None:
        """Exercise SELECT permission on public.profiles without fetching rows."""
        try:
            # A private, short-lived client has no Auth session, incoming headers,
            # environment proxy, or redirect path that could forward the secret.
            with httpx.Client(
                base_url=f"{self._settings.supabase_url}/rest/v1/",
                headers={"apikey": self._settings.secret_key,
                         "Accept-Profile": "public"},
                timeout=5.0,
                follow_redirects=False,
                trust_env=False,
            ) as client:
                response = client.head("profiles", params={"select": "id", "limit": "1"})
                if response.status_code not in (200, 206):
                    raise DatabaseUnavailableError()
        except httpx.HTTPError:
            # Never propagate provider bodies, headers, URLs or exception text.
            raise DatabaseUnavailableError() from None
