import os
from dataclasses import dataclass
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
