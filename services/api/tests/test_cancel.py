import json
import time
from types import SimpleNamespace

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app import auth, database
from app.main import app

USER = "e3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
OTHER = "a3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
CAPSULE = "f3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
PRIVATE = "confidential-message-marker"
KEY = "sb_" + "secret_" + "fake"
TIMESTAMP = "2026-11-14T10:00:00+00:00"


@pytest.fixture
def setup(monkeypatch):
    for name, value in {
        "SUPABASE_URL": "https://example.supabase.co",
        "SUPABASE_PUBLISHABLE_KEY": "placeholder",
        "SUPABASE_JWT_ISSUER": "https://example.supabase.co/auth/v1",
        "SUPABASE_JWT_AUDIENCE": "authenticated",
        "SUPABASE_SECRET_KEY": KEY,
    }.items():
        monkeypatch.setenv(name, value)
    key = ec.generate_private_key(ec.SECP256R1())
    monkeypatch.setattr(auth, "jwks_client", lambda _: SimpleNamespace(get_signing_key_from_jwt=lambda _: key.public_key()))

    def token(subject=USER, signing_key=key):
        return jwt.encode({"sub": subject, "iss": "https://example.supabase.co/auth/v1", "aud": "authenticated",
                           "exp": int(time.time()) + 300}, signing_key, algorithm="ES256", headers={"kid": "test"})

    state = {"requests": [], "status": 200, "payload": [{"id": CAPSULE, "cancelled_at": TIMESTAMP}],
             "error": None, "raw": None}

    def handler(request):
        state["requests"].append(request)
        if state["error"]:
            raise state["error"]
        if state["raw"] is not None:
            return httpx.Response(state["status"], content=state["raw"])
        return httpx.Response(state["status"], json=state["payload"])

    real_client = httpx.Client

    def factory(**kwargs):
        assert kwargs["follow_redirects"] is False and kwargs["trust_env"] is False and kwargs["timeout"] == 5.0
        return real_client(**kwargs, transport=httpx.MockTransport(handler))

    monkeypatch.setattr(database.httpx, "Client", factory)
    return token, state


def post(token=None, path=CAPSULE, query="", headers=None, **kwargs):
    headers = dict(headers or {})
    if token:
        headers["Authorization"] = "Bearer " + token
    with TestClient(app) as client:
        response = client.post(f"/v1/capsules/{path}/cancel{query}", headers=headers, **kwargs)
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"
    return response


def test_authenticated_cancellation_and_rpc_identity(setup, caplog):
    token, state = setup
    user_token = token()
    response = post(user_token, headers={"X-Requester-Id": OTHER})
    assert response.status_code == 200
    assert response.json() == {"id": CAPSULE, "cancelled_at": "2026-11-14T10:00:00Z"}
    request, = state["requests"]
    assert request.method == "POST" and request.url.path == "/rest/v1/rpc/aftertime_cancel_self_capsule"
    assert request.headers["apikey"] == KEY and request.headers["content-profile"] == "public"
    assert "authorization" not in request.headers
    assert json.loads(request.content) == {"p_capsule_id": CAPSULE, "p_requester_id": USER}
    assert all(item not in response.text + caplog.text for item in (PRIVATE, KEY, user_token, "body", "media_key"))


def test_authentication(setup):
    token, state = setup
    assert post().status_code == 401
    assert post("invalid").status_code == 401
    assert post(token(signing_key=ec.generate_private_key(ec.SECP256R1()))).status_code == 401
    assert not state["requests"]


def test_unavailable_jwks_and_wrong_method_are_not_cached(setup, monkeypatch):
    token, state = setup

    def unavailable(_):
        raise jwt.exceptions.PyJWKClientConnectionError(PRIVATE)

    monkeypatch.setattr(auth, "jwks_client", lambda _: SimpleNamespace(get_signing_key_from_jwt=unavailable))
    assert post(token()).status_code == 503
    with TestClient(app) as client:
        response = client.get(f"/v1/capsules/{CAPSULE}/cancel")
    assert response.status_code == 405 and response.headers["cache-control"] == "no-store"
    assert not state["requests"]


@pytest.mark.parametrize("case", ["cross-user", "unlocked", "deleted", "missing", "invalid-recipient"])
def test_denials_are_indistinguishable(setup, case):
    token, state = setup
    state["payload"] = []
    response = post(token(OTHER if case == "cross-user" else USER))
    assert response.status_code == 404 and response.json() == {"detail": "Capsule unavailable"}
    assert PRIVATE not in response.text and KEY not in response.text
    assert len(state["requests"]) == 1


def test_repeat_cancellation_preserves_rpc_timestamp(setup):
    token, state = setup
    first = post(token())
    second = post(token())
    assert first.status_code == second.status_code == 200
    assert first.json() == second.json() == {"id": CAPSULE, "cancelled_at": "2026-11-14T10:00:00Z"}
    assert len(state["requests"]) == 2


def test_invalid_id_and_identity_override(setup):
    token, state = setup
    invalid = "not-a-uuid-private-marker"
    response = post(token(), path=invalid)
    assert response.status_code == 422 and invalid not in response.text
    response = post(token(), query="?requester_id=" + OTHER)
    assert response.status_code == 422 and OTHER not in response.text
    response = post(token(), json={"owner_id": OTHER, "requester_id": OTHER, "body": PRIVATE})
    assert response.status_code == 422 and OTHER not in response.text and PRIVATE not in response.text
    assert not state["requests"]


@pytest.mark.parametrize("payload", [
    None, {}, "text", [None], [{"id": CAPSULE}],
    [{"id": "bad", "cancelled_at": TIMESTAMP}],
    [{"id": OTHER, "cancelled_at": TIMESTAMP}],
    [{"id": CAPSULE, "cancelled_at": None}],
    [{"id": CAPSULE, "cancelled_at": 1234567890}],
    [{"id": CAPSULE, "cancelled_at": "1234567890"}],
    [{"id": CAPSULE, "cancelled_at": "2026-11-14T10:00:00"}],
    [{"id": CAPSULE, "cancelled_at": "not-a-date"}],
    [{"id": CAPSULE, "cancelled_at": TIMESTAMP, "body": PRIVATE}],
    [{"id": CAPSULE, "cancelled_at": TIMESTAMP, "media_key": PRIVATE}],
    [{"id": CAPSULE, "cancelled_at": TIMESTAMP}, {"id": CAPSULE, "cancelled_at": TIMESTAMP}],
])
def test_malformed_rpc_response_fails_closed(setup, payload):
    token, state = setup
    state["payload"] = payload
    response = post(token())
    assert response.status_code == 503 and PRIVATE not in response.text and KEY not in response.text
    assert len(state["requests"]) == 1


def test_timestamp_normalized_to_utc(setup):
    token, state = setup
    state["payload"] = [{"id": CAPSULE, "cancelled_at": "2026-11-14T15:00:00+05:00"}]
    assert post(token()).json() == {"id": CAPSULE, "cancelled_at": "2026-11-14T10:00:00Z"}


@pytest.mark.parametrize("mode", ["status", "invalid_json", "network", "configuration", "unexpected"])
def test_failures_are_sanitized_no_retry(setup, monkeypatch, caplog, mode):
    token, state = setup
    if mode == "status":
        state.update(status=500, payload={"detail": PRIVATE + KEY})
    elif mode == "invalid_json":
        state["raw"] = (PRIVATE + KEY).encode()
    elif mode == "network":
        state["error"] = httpx.ConnectError(PRIVATE + KEY)
    elif mode == "configuration":
        monkeypatch.delenv("SUPABASE_SECRET_KEY")
    else:
        state["error"] = RuntimeError(PRIVATE + KEY)
    user_token = token()
    response = post(user_token)
    assert response.status_code == 503 and response.json() == {"detail": "Capsule service unavailable"}
    assert all(item not in response.text + caplog.text for item in (PRIVATE, KEY, user_token))
    assert len(state["requests"]) == (0 if mode == "configuration" else 1)
