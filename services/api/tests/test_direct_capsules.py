import json
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app import auth, direct_capsules
from app.main import app

USER = "00000000-0000-4000-8000-000000000011"
OTHER = "00000000-0000-4000-8000-000000000012"
CAPSULE = "00000000-0000-4000-8000-000000000013"
BODY = "synthetic private body"
EMAIL = "recipient@example.invalid"
KEY = "sb_" + "secret_" + "fake"
STAMP = "2026-11-14T10:00:00Z"


@pytest.fixture
def setup(monkeypatch):
    for name, value in {
        "SUPABASE_URL": "https://example.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "placeholder",
        "SUPABASE_JWT_ISSUER": "https://example.supabase.co/auth/v1", "SUPABASE_JWT_AUDIENCE": "authenticated",
        "SUPABASE_SECRET_KEY": KEY,
    }.items():
        monkeypatch.setenv(name, value)
    monkeypatch.delenv("DIRECT_CAPSULES_ENABLED", raising=False)
    key = ec.generate_private_key(ec.SECP256R1())
    monkeypatch.setattr(auth, "jwks_client", lambda _: SimpleNamespace(get_signing_key_from_jwt=lambda _: key.public_key()))

    def token(user=USER, email_claim=None):
        claims = {"sub": user, "iss": "https://example.supabase.co/auth/v1", "aud": "authenticated",
                  "exp": int(time.time()) + 300}
        if email_claim is not None:
            claims["email"] = email_claim
        return jwt.encode(claims, key, algorithm="ES256", headers={"kid": "test"})

    state = {"requests": [], "status": 200, "payload": [{"id": CAPSULE, "unlock_at": STAMP, "created_at": STAMP}],
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
        assert kwargs["timeout"] == 5.0 and not kwargs["follow_redirects"] and not kwargs["trust_env"]
        return real_client(**kwargs, transport=httpx.MockTransport(handler))

    monkeypatch.setattr(direct_capsules.httpx, "Client", factory)
    return token, state


def data():
    return {"title": "synthetic title", "body": BODY, "recipient_email": EMAIL,
            "unlock_at": (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()}


def request(method, path, token=None, **kwargs):
    headers = {"Authorization": "Bearer " + token} if token else {}
    with TestClient(app) as client:
        response = client.request(method, path, headers=headers, **kwargs)
    assert response.headers["cache-control"] == "no-store"
    return response


@pytest.mark.parametrize("flag", [None, "false", "1", "yes", "invalid"])
@pytest.mark.parametrize("method,path", [
    ("POST", "/v1/direct-capsules"), ("GET", "/v1/direct-capsules/invitations"),
    ("POST", f"/v1/direct-capsules/{CAPSULE}/claim"),
    ("POST", f"/v1/direct-capsules/{CAPSULE}/cancel"),
    ("GET", f"/v1/direct-capsules/{CAPSULE}/reveal"),
])
def test_disabled_fails_before_auth_or_db(setup, monkeypatch, flag, method, path):
    _, state = setup
    if flag is not None:
        monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", flag)
    response = request(method, path, json={"body": BODY})
    assert response.status_code == 404 and BODY not in response.text
    assert not state["requests"]


def test_enabled_create_uses_authenticated_identity_and_safe_projection(setup, monkeypatch, caplog):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    payload = data()
    payload["recipient_email"] = " Recipient@Example.Invalid "
    response = request("POST", "/v1/direct-capsules", token(), json=payload)
    assert response.status_code == 201
    assert set(response.json()) == {"id", "created_at", "unlock_at"}
    sent, = state["requests"]
    assert sent.url.path.endswith("/rpc/aftertime_create_direct_capsule")
    fields = json.loads(sent.content)
    assert fields["p_owner_id"] == USER and fields["p_recipient_email"] == EMAIL and fields["p_body"] == BODY
    assert "authorization" not in sent.headers
    assert all(v not in response.text + caplog.text for v in (BODY, EMAIL, KEY))


@pytest.mark.parametrize("bad", ["", "bad", "a@b@c", "a b@example.invalid", "a@b\x00"])
def test_invalid_recipient_is_sanitized(setup, monkeypatch, bad):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    payload = data()
    payload["recipient_email"] = bad
    response = request("POST", "/v1/direct-capsules", token(), json=payload)
    assert response.status_code == 422 and response.json() == {"detail": "Invalid capsule request"}
    assert BODY not in response.text and not state["requests"]


def test_enabled_auth_and_identity_override(setup, monkeypatch):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    assert request("POST", "/v1/direct-capsules", json=data()).status_code == 401
    payload = data()
    payload["owner_id"] = OTHER
    response = request("POST", "/v1/direct-capsules", token(), json=payload)
    assert response.status_code == 422 and OTHER not in response.text and not state["requests"]


@pytest.mark.parametrize("path,method", [("/v1/direct-capsules/invitations", "GET"),
                                          (f"/v1/direct-capsules/{CAPSULE}/claim", "POST")])
def test_claim_and_discovery_remain_unavailable_when_enabled(setup, monkeypatch, path, method):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    response = request(method, path, token())
    assert response.status_code == 503 and BODY not in response.text and not state["requests"]
    assert request(method, path, token()).status_code == 503 and not state["requests"]


@pytest.mark.parametrize("path,method,rpc,payload", [
    (f"/v1/direct-capsules/{CAPSULE}/cancel", "POST", "aftertime_cancel_direct_capsule",
     {"id": CAPSULE, "cancelled_at": STAMP}),
    (f"/v1/direct-capsules/{CAPSULE}/reveal", "GET", "aftertime_reveal_direct_capsule",
     {"id": CAPSULE, "body": BODY}),
])
def test_cancel_reveal_success_and_generic_denial(setup, monkeypatch, path, method, rpc, payload):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    state["payload"] = [payload]
    response = request(method, path, token())
    assert response.status_code == 200 and response.json() == payload
    sent, = state["requests"]
    assert sent.url.path.endswith("/rpc/" + rpc)
    assert json.loads(sent.content) == {"p_capsule_id": CAPSULE, "p_requester_id": USER}
    state["payload"] = []
    response = request(method, path, token(OTHER))
    assert response.status_code == 404 and response.json() == {"detail": "Capsule unavailable"}


@pytest.mark.parametrize("status,payload,expected", [
    (400, {"code": "22023"}, 422), (403, {"code": "42501"}, 403),
    (400, {"code": "23514"}, 503),
    (500, {"detail": BODY}, 503), (200, [], 503),
    (200, [{"id": CAPSULE, "created_at": STAMP, "unlock_at": STAMP, "body": BODY}], 503),
    (200, [{"id": CAPSULE, "created_at": 123, "unlock_at": STAMP}], 503),
])
def test_create_rpc_failures_are_safe_and_not_retried(setup, monkeypatch, caplog, status, payload, expected):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    state.update(status=status, payload=payload)
    response = request("POST", "/v1/direct-capsules", token(), json=data())
    assert response.status_code == expected and len(state["requests"]) == 1
    assert all(v not in response.text + caplog.text for v in (BODY, EMAIL, KEY))


def test_transport_failure_is_sanitized(setup, monkeypatch, caplog):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    state["error"] = httpx.ConnectError(BODY + KEY)
    response = request("POST", "/v1/direct-capsules", token(), json=data())
    assert response.status_code == 503 and len(state["requests"]) == 1
    assert BODY not in response.text + caplog.text and KEY not in response.text + caplog.text


@pytest.mark.parametrize("payload", [
    [{"id": OTHER, "body": BODY}], [{"id": CAPSULE, "body": BODY, "title": "unexpected"}],
    [{"id": CAPSULE, "body": None}], [{"id": CAPSULE, "body": BODY}] * 2,
])
def test_reveal_rejects_invalid_rpc_payloads(setup, monkeypatch, payload):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    state["payload"] = payload
    response = request("GET", f"/v1/direct-capsules/{CAPSULE}/reveal", token())
    assert response.status_code == 503 and BODY not in response.text and len(state["requests"]) == 1


def test_cancel_rejects_extra_request_data(setup, monkeypatch):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    response = request("POST", f"/v1/direct-capsules/{CAPSULE}/cancel", token(), json={"body": BODY})
    assert response.status_code == 422 and BODY not in response.text and not state["requests"]


@pytest.mark.parametrize("model", [direct_capsules.PendingDirectCapsuleMetadata,
                                   direct_capsules.ClaimedDirectCapsuleMetadata])
def test_prepared_recipient_metadata_rejects_private_or_untrusted_fields(model):
    safe = {"id": CAPSULE, "created_at": STAMP, "unlock_at": STAMP}
    assert set(model.model_validate(safe).model_dump()) == {"id", "created_at", "unlock_at"}
    for key, value in [("body", BODY), ("title", "sender input"), ("recipient_email", EMAIL),
                       ("sender_name", "sender input")]:
        with pytest.raises(ValidationError):
            model.model_validate({**safe, key: value})


@pytest.mark.parametrize("method,path", [
    ("GET", "/v1/direct-capsules/invitations?email=secret"),
    ("POST", f"/v1/direct-capsules/{CAPSULE}/claim?requester_id={OTHER}"),
])
def test_unavailable_paths_reject_identity_overrides(setup, monkeypatch, method, path):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    response = request(method, path, token())
    assert response.status_code == 422 and OTHER not in response.text and not state["requests"]


def test_concurrent_claim_requests_remain_unavailable(setup, monkeypatch):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    tokens = [token(USER), token(OTHER)]
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda t: request("POST", f"/v1/direct-capsules/{CAPSULE}/claim", t), tokens))
    assert all(response.status_code == 503 and BODY not in response.text for response in responses)
    assert not state["requests"]


def test_claim_rejects_body_and_does_not_trust_jwt_email(setup, monkeypatch):
    token, state = setup
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", "true")
    user_token = token(USER, email_claim=EMAIL)
    path = f"/v1/direct-capsules/{CAPSULE}/claim"
    response = request("POST", path, user_token, json={"email": EMAIL, "user_id": OTHER})
    assert response.status_code == 422 and EMAIL not in response.text and OTHER not in response.text
    response = request("POST", path, user_token)
    assert response.status_code == 503 and EMAIL not in response.text and not state["requests"]
