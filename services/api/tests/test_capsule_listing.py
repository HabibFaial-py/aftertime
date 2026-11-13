import time
from datetime import datetime, timezone
from types import SimpleNamespace

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

from app import auth, database
import app.main as main

USER = "e3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
OTHER = "f3216d4c-9b6e-4f8b-8493-7e3a3ac7da80"
KEY = "sb_" + "secret_" + "fake"
NOW = datetime(2026, 11, 13, 12, tzinfo=timezone.utc)


@pytest.fixture
def fixture(monkeypatch):
    for name, value in {"SUPABASE_URL": "https://example.supabase.co", "SUPABASE_PUBLISHABLE_KEY": "test",
                        "SUPABASE_SECRET_KEY": KEY, "SUPABASE_JWT_ISSUER": "https://example.supabase.co/auth/v1",
                        "SUPABASE_JWT_AUDIENCE": "authenticated"}.items():
        monkeypatch.setenv(name, value)
    key = ec.generate_private_key(ec.SECP256R1())
    monkeypatch.setattr(auth, "jwks_client", lambda url: SimpleNamespace(get_signing_key_from_jwt=lambda _: key.public_key()))
    token = jwt.encode({"sub": USER, "iss": "https://example.supabase.co/auth/v1", "aud": "authenticated",
                        "exp": int(time.time()) + 300}, key, algorithm="ES256", headers={"kid": "test"})
    class Clock(datetime):
        @classmethod
        def now(cls, tz=None):
            return NOW
    monkeypatch.setattr(main, "datetime", Clock)
    rows = [
        {"id": f"00000000-0000-4000-8000-{i:012d}", "owner_id": owner,
         "title": f"title-{i}", "created_at": "2026-11-12T12:00:00Z",
         "unlock_at": unlock, "deleted_at": deleted, "cancelled_at": cancelled,
         "body": "private-body", "media_key": "private-media"}
        for i, owner, unlock, deleted, cancelled in [
            (1, USER, "2026-11-13T11:59:59Z", None, None),
            (2, USER, "2026-11-13T12:00:00Z", None, None),
            (3, USER, "2026-11-13T12:00:01Z", None, None),
            (4, OTHER, "2026-11-13T11:00:00Z", None, None),
            (5, USER, "2026-11-13T11:00:00Z", "2026-11-12T12:00:00Z", None),
            (6, USER, "2026-11-13T11:00:00Z", None, "2026-11-12T13:00:00Z"),
        ]]
    state = {"requests": [], "rows": rows, "status": 200, "payload": None, "error": None}
    def handler(request):
        state["requests"].append(request)
        if state["error"]:
            raise state["error"]
        if state["payload"] is not None:
            return httpx.Response(state["status"], json=state["payload"])
        params = request.url.params
        filtered = [r for r in state["rows"] if params.get("owner_id") == "eq." + r["owner_id"]
                    and (params.get("deleted_at") != "is.null" or r["deleted_at"] is None)
                    and (params.get("cancelled_at") != "is.null" or r["cancelled_at"] is None)]
        filtered.sort(key=lambda r: (r["created_at"], r["id"]), reverse=True)
        offset, limit = int(params["offset"]), int(params["limit"])
        selected = params["select"].split(",")
        return httpx.Response(state["status"], json=[{k: r[k] for k in selected} for r in filtered[offset:offset + limit]])
    real_client = httpx.Client
    def factory(**kwargs):
        assert kwargs["follow_redirects"] is False and kwargs["trust_env"] is False
        return real_client(**kwargs, transport=httpx.MockTransport(handler))
    monkeypatch.setattr(database.httpx, "Client", factory)
    return token, state


def get(token=None, query=""):
    with TestClient(main.app) as client:
        return client.get("/v1/capsules" + query, headers={"Authorization": "Bearer " + token} if token else {})


def test_authentication(fixture):
    _, state = fixture
    assert get().status_code == 401
    assert get("invalid-jwt").status_code == 401
    assert state["requests"] == []


def test_only_owned_nondeleted_safe_metadata_and_status(fixture):
    token, state = fixture
    response = get(token, "?owner_id=" + OTHER)
    assert response.status_code == 200
    items = response.json()
    assert [item["title"] for item in items] == ["title-3", "title-2", "title-1"]
    assert [item["status"] for item in items] == ["locked", "unlocked", "unlocked"]
    assert all(set(item) == {"id", "title", "created_at", "unlock_at", "status"} for item in items)
    assert "private-body" not in response.text and "private-media" not in response.text
    request, = state["requests"]
    assert request.method == "GET" and request.url.path == "/rest/v1/capsules"
    assert dict(request.url.params) == {"select": "id,title,created_at,unlock_at", "owner_id": "eq." + USER,
                                        "deleted_at": "is.null", "cancelled_at": "is.null",
                                        "order": "created_at.desc,id.desc", "limit": "50", "offset": "0"}
    assert request.headers["apikey"] == KEY and "authorization" not in request.headers


def test_pagination_and_empty(fixture):
    token, state = fixture
    assert [x["title"] for x in get(token, "?limit=2&offset=0").json()] == ["title-3", "title-2"]
    assert [x["title"] for x in get(token, "?limit=2&offset=2").json()] == ["title-1"]
    assert get(token, "?offset=3").json() == []
    assert len(state["requests"]) == 3


@pytest.mark.parametrize("query", ["?limit=0", "?limit=51", "?offset=-1", "?offset=10001", "?limit=bad"])
def test_invalid_page(fixture, query):
    token, state = fixture
    assert get(token, query).status_code == 422
    assert state["requests"] == []


@pytest.mark.parametrize("payload", [{"private": "detail"}, [{"id": "bad"}],
                                     [{"id": "00000000-0000-4000-8000-000000000001", "title": "x",
                                       "created_at": "2026-11-13T12:00:00", "unlock_at": "2026-11-13T13:00:00Z"}]])
def test_bad_response_fails_closed(fixture, payload):
    token, state = fixture
    state["payload"] = payload
    assert get(token).status_code == 503


def test_defense_in_depth_response_fields(fixture):
    token, state = fixture
    state["payload"] = [{"id": "00000000-0000-4000-8000-000000000001", "title": "safe",
                         "created_at": "2026-11-13T12:00:00Z", "unlock_at": "2026-11-14T12:00:00Z",
                         "body": "private-body", "invite_token_hash": "private-hash"}]
    response = get(token)
    assert response.status_code == 200
    assert "private-body" not in response.text and "private-hash" not in response.text


@pytest.mark.parametrize("failure", ["status", "network"])
def test_database_failure_is_sanitized(fixture, caplog, failure):
    token, state = fixture
    if failure == "status":
        state.update(status=500, payload={"message": "private detail " + KEY})
    else:
        state["error"] = httpx.ConnectError("private detail " + KEY)
    response = get(token)
    assert response.status_code == 503
    assert response.json() == {"detail": "Capsule service unavailable"}
    assert KEY not in response.text + caplog.text and "private detail" not in response.text + caplog.text


def test_missing_database_config(fixture, monkeypatch):
    token, state = fixture
    monkeypatch.delenv("SUPABASE_SECRET_KEY")
    assert get(token).status_code == 503
    assert not state["requests"]
