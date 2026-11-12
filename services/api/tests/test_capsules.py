import json
import time
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app import auth, database
from app.main import app

USER = "e3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
CAPSULE = "f3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
PRIVATE = "private test body"
FAKE_KEY = "sb_" + "secret_" + "fake"


@pytest.fixture
def setup(monkeypatch):
    for name, value in {"SUPABASE_URL": "https://example.supabase.co",
                        "SUPABASE_PUBLISHABLE_KEY": "placeholder",
                        "SUPABASE_JWT_ISSUER": "https://example.supabase.co/auth/v1",
                        "SUPABASE_JWT_AUDIENCE": "authenticated",
                        "SUPABASE_SECRET_KEY": FAKE_KEY}.items():
        monkeypatch.setenv(name, value)
    key = ec.generate_private_key(ec.SECP256R1())
    monkeypatch.setattr(auth, "jwks_client", lambda url: SimpleNamespace(get_signing_key_from_jwt=lambda _: key.public_key()))
    token = jwt.encode({"sub": USER, "iss": "https://example.supabase.co/auth/v1",
                        "aud": "authenticated", "exp": int(time.time()) + 300}, key,
                       algorithm="ES256", headers={"kid": "local"})
    requests = []
    state = {"status": 200, "error": None, "payload": None}
    def handler(request):
        requests.append(request)
        if state["error"]:
            raise state["error"]
        sent = json.loads(request.content)
        payload = state["payload"] if state["payload"] is not None else [{
            "id": CAPSULE, "title": sent["p_title"], "unlock_at": sent["p_unlock_at"],
            "created_at": datetime.now(timezone.utc).isoformat(), "body": PRIVATE,
            "media_key": "private-media", "invite_token_hash": "private-hash"}]
        return httpx.Response(state["status"], json=payload)
    real_client = httpx.Client
    def factory(**kwargs):
        assert kwargs["follow_redirects"] is False and kwargs["trust_env"] is False
        return real_client(**kwargs, transport=httpx.MockTransport(handler))
    monkeypatch.setattr(database.httpx, "Client", factory)
    return token, requests, state


def valid():
    return {"title": "A title", "body": PRIVATE,
            "unlock_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()}


def post(data, token=None):
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    with TestClient(app) as client:
        return client.post("/v1/capsules", json=data, headers=headers)


def test_success_uses_verified_owner_and_safe_metadata(setup):
    token, requests, _ = setup
    data = valid()
    data["unlock_at"] = (datetime.now(timezone(timedelta(hours=5))) + timedelta(days=1)).isoformat()
    response = post(data, token)
    assert response.status_code == 201
    assert set(response.json()) == {"id", "title", "created_at", "unlock_at"}
    assert PRIVATE not in response.text and "private-media" not in response.text
    assert len(requests) == 1
    request = requests[0]
    assert request.method == "POST" and request.url.path == "/rest/v1/rpc/aftertime_create_self_capsule"
    assert request.headers["apikey"] == FAKE_KEY and "authorization" not in request.headers
    sent = json.loads(request.content)
    assert sent == {"p_owner_id": USER, "p_title": data["title"], "p_body": PRIVATE,
                    "p_unlock_at": datetime.fromisoformat(data["unlock_at"]).astimezone(timezone.utc).isoformat()}
    assert datetime.fromisoformat(response.json()["unlock_at"].replace("Z", "+00:00")).utcoffset() == timedelta(0)


def test_authentication_fails_closed(setup):
    _, requests, _ = setup
    assert post(valid()).status_code == 401
    assert post(valid(), "not-a-jwt").status_code == 401
    other_key = ec.generate_private_key(ec.SECP256R1())
    invalid = jwt.encode({"sub": USER, "iss": "https://example.supabase.co/auth/v1",
                          "aud": "authenticated", "exp": int(time.time()) + 300}, other_key,
                         algorithm="ES256", headers={"kid": "local"})
    assert post(valid(), invalid).status_code == 401
    assert requests == []


@pytest.mark.parametrize("changes", [
    {"title": ""}, {"title": " \t"}, {"title": 1}, {"title": None},
    {"body": ""}, {"body": "  "}, {"body": "x" * 2001}, {"body": None},
    {"unlock_at": "2027-01-01T00:00:00"}, {"unlock_at": "bad"}, {"unlock_at": 42},
    {"unlock_at": (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()},
    {"unlock_at": (datetime.now(timezone.utc) + timedelta(days=91)).isoformat()},
    {"owner_id": "another-user"}, {"recipient_id": "another-user"}, {"email": "test@example.invalid"},
])
def test_invalid_requests_never_query_or_echo_input(setup, changes):
    token, requests, _ = setup
    data = valid()
    data.update(changes)
    response = post(data, token)
    assert response.status_code == 422
    assert response.json() == {"detail": "Invalid capsule request"}
    assert PRIVATE not in response.text
    assert requests == []


@pytest.mark.parametrize("missing", ["title", "body", "unlock_at"])
def test_missing_fields(setup, missing):
    token, requests, _ = setup
    data = valid()
    del data[missing]
    assert post(data, token).status_code == 422
    assert not requests


@pytest.mark.parametrize("status,code,expected", [(400, "22023", 422), (403, "42501", 403),
                                                  (500, "XX000", 503), (401, "bad", 503)])
def test_rpc_errors_are_sanitized(setup, status, code, expected, caplog):
    token, requests, state = setup
    state.update(status=status, payload={"code": code, "message": PRIVATE + FAKE_KEY})
    response = post(valid(), token)
    assert response.status_code == expected
    assert PRIVATE not in response.text + caplog.text and FAKE_KEY not in response.text + caplog.text
    assert len(requests) == 1


@pytest.mark.parametrize("payload", [[], {}, [{"id": "bad"}], [{"id": CAPSULE}, {"id": CAPSULE}]])
def test_bad_database_result_fails_closed(setup, payload):
    token, _, state = setup
    state["payload"] = payload
    response = post(valid(), token)
    assert response.status_code == 503
    assert PRIVATE not in response.text


def test_network_failure_no_retry(setup, caplog):
    token, requests, state = setup
    state["error"] = httpx.ConnectError(PRIVATE + FAKE_KEY)
    response = post(valid(), token)
    assert response.status_code == 503 and len(requests) == 1
    assert PRIVATE not in response.text + caplog.text and FAKE_KEY not in response.text + caplog.text


def test_missing_database_configuration(setup, monkeypatch):
    token, requests, _ = setup
    monkeypatch.delenv("SUPABASE_SECRET_KEY")
    response = post(valid(), token)
    assert response.status_code == 503
    assert response.json() == {"detail": "Capsule service unavailable"}
    assert not requests


def test_maximum_body_allowed(setup):
    token, requests, _ = setup
    data = valid()
    data["body"] = "x" * 2000
    response = post(data, token)
    assert response.status_code == 201
    assert "x" * 2000 not in response.text
    assert len(requests) == 1
