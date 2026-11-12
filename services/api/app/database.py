"""Server-only Data API repository. Never accept user tokens or request headers.

The secret bypasses RLS. Future user-specific methods must be preceded by
explicit authorization using identity from app.auth.current_user.
"""

import httpx
from pydantic import ValidationError

from app.config import get_database_settings
from app.capsules import CapsuleMetadata, CreateCapsule


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
