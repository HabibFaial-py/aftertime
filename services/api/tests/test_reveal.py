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
BODY = "private message fixture"
KEY = "sb_" + "secret_" + "fake"


@pytest.fixture
def setup(monkeypatch):
    for name, value in {"SUPABASE_URL": "https://example.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "placeholder",
                        "SUPABASE_JWT_ISSUER": "https://example.supabase.co/auth/v1", "SUPABASE_JWT_AUDIENCE": "authenticated",
                        "SUPABASE_SECRET_KEY": KEY}.items():
        monkeypatch.setenv(name, value)
    key = ec.generate_private_key(ec.SECP256R1())
    monkeypatch.setattr(auth, "jwks_client", lambda _: SimpleNamespace(get_signing_key_from_jwt=lambda _: key.public_key()))
    def token(subject=USER, signing_key=key):
        return jwt.encode({"sub": subject, "iss": "https://example.supabase.co/auth/v1", "aud": "authenticated",
                           "exp": int(time.time()) + 300}, signing_key, algorithm="ES256", headers={"kid": "test"})
    state = {"requests": [], "status": 200, "payload": [{"id": CAPSULE, "body": BODY}], "error": None, "raw": None}
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


def get(token=None, path=CAPSULE, query="", headers=None):
    headers = dict(headers or {})
    if token:
        headers["Authorization"] = "Bearer " + token
    with TestClient(app) as client:
        response = client.get(f"/v1/capsules/{path}/reveal{query}", headers=headers)
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"
    return response


def test_authenticated_reveal_and_rpc_identity(setup, caplog):
    token, state = setup
    response = get(token(), headers={"X-Requester-Id": OTHER})
    assert response.status_code == 200
    assert response.json() == {"id": CAPSULE, "body": BODY}
    request, = state["requests"]
    assert request.method == "POST" and request.url.path == "/rest/v1/rpc/aftertime_reveal_self_capsule"
    assert request.headers["apikey"] == KEY and "authorization" not in request.headers
    assert json.loads(request.content) == {"p_capsule_id": CAPSULE, "p_requester_id": USER}
    assert BODY not in caplog.text and KEY not in caplog.text


def test_authentication(setup):
    token, state = setup
    assert get().status_code == 401
    assert get("invalid").status_code == 401
    assert get(token(signing_key=ec.generate_private_key(ec.SECP256R1()))).status_code == 401
    assert not state["requests"]


def test_unavailable_jwks_and_wrong_method_are_not_cached(setup, monkeypatch):
    token, state = setup
    def unavailable(_):
        raise jwt.exceptions.PyJWKClientConnectionError("sensitive detail")
    monkeypatch.setattr(auth, "jwks_client", lambda _: SimpleNamespace(get_signing_key_from_jwt=unavailable))
    assert get(token()).status_code == 503
    with TestClient(app) as client:
        response = client.post(f"/v1/capsules/{CAPSULE}/reveal")
    assert response.status_code == 405 and response.headers["cache-control"] == "no-store"
    assert not state["requests"]


@pytest.mark.parametrize("case", ["locked", "cross-user", "cancelled", "deleted", "missing"])
def test_denials_are_indistinguishable(setup, case):
    token, state = setup
    state["payload"] = []
    response = get(token(OTHER if case == "cross-user" else USER))
    assert response.status_code == 404 and response.json() == {"detail": "Capsule unavailable"}
    assert BODY not in response.text and KEY not in response.text
    assert len(state["requests"]) == 1


def test_invalid_id_and_identity_override(setup):
    token, state = setup
    invalid = "not-a-uuid-private-marker"
    response = get(token(), path=invalid)
    assert response.status_code == 422 and invalid not in response.text
    response = get(token(), query="?requester_id=" + OTHER)
    assert response.status_code == 422 and OTHER not in response.text
    assert not state["requests"]


@pytest.mark.parametrize("payload", [None, {}, "text", [{"id": CAPSULE}],
                                     [{"id": "bad", "body": BODY}], [{"id": CAPSULE, "body": None}],
                                     [{"id": OTHER, "body": BODY}], [{"id": CAPSULE, "body": BODY, "media_key": "private"}],
                                     [{"id": CAPSULE, "body": "x" * 2001}],
                                     [{"id": CAPSULE, "body": BODY}, {"id": CAPSULE, "body": BODY}]])
def test_malformed_rpc_response_fails_closed(setup, payload):
    token, state = setup
    state["payload"] = payload
    response = get(token())
    assert response.status_code == 503 and BODY not in response.text and "private" not in response.text
    assert len(state["requests"]) == 1


@pytest.mark.parametrize("mode", ["status", "invalid_json", "network", "configuration", "unexpected"])
def test_failures_are_sanitized_no_retry(setup, monkeypatch, caplog, mode):
    token, state = setup
    if mode == "status":
        state.update(status=500, payload={"detail": BODY + KEY})
    elif mode == "invalid_json":
        state["raw"] = b"not-json"
    elif mode == "network":
        state["error"] = httpx.ConnectError(BODY + KEY)
    elif mode == "configuration":
        monkeypatch.delenv("SUPABASE_SECRET_KEY")
    else:
        state["error"] = RuntimeError(BODY + KEY)
    response = get(token())
    assert response.status_code == 503
    assert response.json() == {"detail": "Capsule service unavailable"}
    assert BODY not in response.text + caplog.text and KEY not in response.text + caplog.text
    assert len(state["requests"]) == (0 if mode == "configuration" else 1)
