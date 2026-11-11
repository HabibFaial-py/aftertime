from functools import lru_cache
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient
from jwt.exceptions import PyJWKClientConnectionError, PyJWKClientError, PyJWTError

from app.config import get_settings

bearer = HTTPBearer(auto_error=False)
ALGORITHMS = ("ES256", "RS256")


@lru_cache(maxsize=1)
def jwks_client(url: str) -> PyJWKClient:
    return PyJWKClient(f"{url}/auth/v1/.well-known/jwks.json", timeout=5)


def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer)) -> str:
    unauthorized = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid authentication credentials", headers={"WWW-Authenticate": "Bearer"})
    if credentials is None:
        raise unauthorized
    try:
        settings = get_settings()
    except ValueError:
        raise HTTPException(status_code=503, detail="Authentication is not configured") from None
    try:
        header = jwt.get_unverified_header(credentials.credentials)
        if header.get("alg") not in ALGORITHMS or not isinstance(header.get("kid"), str) or not header["kid"]:
            raise unauthorized
        key = jwks_client(settings.supabase_url).get_signing_key_from_jwt(credentials.credentials)
        claims = jwt.decode(credentials.credentials, key, algorithms=list(ALGORITHMS), issuer=settings.jwt_issuer, audience=settings.jwt_audience, options={"require": ["exp", "iss", "aud", "sub"]})
        subject = claims["sub"]
        if not isinstance(subject, str) or str(UUID(subject)) != subject:
            raise ValueError("Invalid subject")
        return subject
    except PyJWKClientConnectionError:
        raise HTTPException(status_code=503, detail="Authentication keys unavailable") from None
    except (PyJWTError, PyJWKClientError, ValueError, TypeError, KeyError):
        raise unauthorized from None
