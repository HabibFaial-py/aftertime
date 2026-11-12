"""Server-only Data API repository. Never accept user tokens or request headers.

The secret bypasses RLS. Future user-specific methods must be preceded by
explicit authorization using identity from app.auth.current_user.
"""

import httpx

from app.config import get_database_settings


class DatabaseUnavailableError(RuntimeError):
    def __init__(self) -> None:
        super().__init__("Database connectivity check failed")


class DatabaseRepository:
    def __init__(self) -> None:
        self._settings = get_database_settings()

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
