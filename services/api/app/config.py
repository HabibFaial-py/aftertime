import os
from dataclasses import dataclass, field
import re
from urllib.parse import urlsplit


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    publishable_key: str
    jwt_issuer: str
    jwt_audience: str


def get_settings() -> Settings:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
    issuer = os.environ.get("SUPABASE_JWT_ISSUER", "")
    audience = os.environ.get("SUPABASE_JWT_AUDIENCE", "")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or
            parsed.password or parsed.query or parsed.fragment or parsed.path or
            not key or issuer != f"{url}/auth/v1" or not audience):
        raise ValueError("Invalid or missing Supabase configuration")
    return Settings(url, key, issuer, audience)


class DatabaseConfigurationError(ValueError):
    def __init__(self) -> None:
        super().__init__("Privileged database configuration is missing or invalid")


@dataclass(frozen=True)
class DatabaseSettings:
    supabase_url: str
    secret_key: str = field(repr=False)


def get_database_settings() -> DatabaseSettings:
    """Read lazily, independently of Auth; never include input in errors."""
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    secret = os.environ.get("SUPABASE_SECRET_KEY", "")
    try:
        parsed = urlsplit(url)
        valid_url = (
            parsed.scheme == "https"
            and parsed.hostname
            and re.fullmatch(r"[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)*", parsed.hostname)
            and parsed.port in (None, 443)
            and not any((parsed.username, parsed.password, parsed.path,
                         parsed.query, parsed.fragment))
            and not any(character.isspace() for character in url)
            and "?" not in url and "#" not in url
        )
    except ValueError:
        raise DatabaseConfigurationError() from None
    # Check key type/header safety, not validity with Supabase. Revoked or wrong
    # project keys can only be detected by an explicitly requested connection.
    if not valid_url or not re.fullmatch(r"sb_secret_[A-Za-z0-9_-]+", secret):
        raise DatabaseConfigurationError()
    return DatabaseSettings(url, secret)
