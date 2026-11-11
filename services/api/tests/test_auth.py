import time
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app import auth
from app.main import app

USER = "e3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
ISSUER = "https://example.supabase.co/auth/v1"


@pytest.fixture
def setup_auth(monkeypatch):
    for name, value in {"SUPABASE_URL": "https://example.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "placeholder", "SUPABASE_JWT_ISSUER": ISSUER, "SUPABASE_JWT_AUDIENCE": "authenticated"}.items():
        monkeypatch.setenv(name, value)
    private_key = ec.generate_private_key(ec.SECP256R1())
    monkeypatch.setattr(auth, "jwks_client", lambda url: SimpleNamespace(get_signing_key_from_jwt=lambda token: private_key.public_key()))
    return private_key


def token(key, **overrides):
    claims = {"sub": USER, "iss": ISSUER, "aud": "authenticated", "exp": int(time.time()) + 300}
    claims.update(overrides)
    return jwt.encode(claims, key, algorithm="ES256", headers={"kid": "test"})


def request(value):
    with TestClient(app) as client:
        return client.get("/v1/auth/me", headers={"Authorization": f"Bearer {value}"})


def test_valid_token(setup_auth):
    response = request(token(setup_auth))
    assert response.status_code == 200
    assert response.json() == {"id": USER}


@pytest.mark.parametrize("claims", [{"iss": "https://wrong"}, {"aud": "wrong"}, {"exp": 1}, {"sub": "invalid"}, {"sub": None}])
def test_invalid_claims(setup_auth, claims):
    assert request(token(setup_auth, **claims)).status_code == 401


def test_bad_signature(setup_auth):
    assert request(token(ec.generate_private_key(ec.SECP256R1()))).status_code == 401


def test_unsupported_and_malformed(setup_auth):
    assert request(jwt.encode({"sub": USER}, "not-a-real-secret", algorithm="HS256", headers={"kid": "test"})).status_code == 401
    assert request("not-a-jwt").status_code == 401
    with TestClient(app) as client:
        assert client.get("/v1/auth/me").status_code == 401
        assert client.get("/v1/auth/me", headers={"Authorization": "Basic abc"}).status_code == 401


def test_missing_config(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    assert request("anything").status_code == 503


def test_key_service_unavailable(setup_auth, monkeypatch):
    def unavailable(token):
        raise jwt.exceptions.PyJWKClientConnectionError("offline")
    monkeypatch.setattr(auth, "jwks_client", lambda url: SimpleNamespace(get_signing_key_from_jwt=unavailable))
    assert request(token(setup_auth)).status_code == 503
