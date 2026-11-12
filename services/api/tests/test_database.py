import logging

import httpx
import pytest
from fastapi.testclient import TestClient

from app import check_database, database
from app.config import DatabaseConfigurationError, get_database_settings
from app.main import app


SECRET_PREFIX = "sb_" + "secret_"
SECRET = SECRET_PREFIX + "fake"
SENSITIVE = "private-provider-detail private-profile-name"


@pytest.fixture(autouse=True)
def isolated_database(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_SECRET_KEY", SECRET)
    state = {"requests": [], "status": 200, "failure": None, "clients": []}

    def handler(request):
        state["requests"].append(request)
        if state["failure"]:
            raise state["failure"]
        return httpx.Response(state["status"], text=SENSITIVE,
                              headers={"Location": "https://other.invalid/"})

    real_client = httpx.Client

    def client_factory(**kwargs):
        assert kwargs["follow_redirects"] is False
        assert kwargs["trust_env"] is False
        assert kwargs["timeout"] == 5.0
        client = real_client(**kwargs, transport=httpx.MockTransport(handler))
        state["clients"].append(client)
        return client

    monkeypatch.setattr(database.httpx, "Client", client_factory)
    return state


@pytest.mark.parametrize("secret", [None, "", "sb_" + "publishable_" + "fake", "ey" + "Jlegacy",
                                    SECRET_PREFIX, SECRET_PREFIX + "bad\r\nheader"])
def test_missing_or_invalid_secret(monkeypatch, isolated_database, secret):
    if secret is None:
        monkeypatch.delenv("SUPABASE_SECRET_KEY")
    else:
        monkeypatch.setenv("SUPABASE_SECRET_KEY", secret)
    with pytest.raises(DatabaseConfigurationError, match="missing or invalid"):
        database.DatabaseRepository()
    assert isolated_database["requests"] == []


@pytest.mark.parametrize("url", ["", "http://example.supabase.co", "https://user:pass@host",
                                 "https://host/rest/v1", "https://host?secret=value",
                                 "https://host#fragment", "https://host:bad", "https://[",
                                 "https://bad host", "https://host:8443"])
def test_invalid_url(monkeypatch, isolated_database, url):
    monkeypatch.setenv("SUPABASE_URL", url)
    with pytest.raises(DatabaseConfigurationError):
        database.DatabaseRepository()
    assert isolated_database["requests"] == []


@pytest.mark.parametrize("status", [200, 206])
def test_read_only_success_without_records(isolated_database, status):
    isolated_database["status"] = status
    assert database.DatabaseRepository().check_connection() is None
    request, = isolated_database["requests"]
    assert request.method == "HEAD"
    assert str(request.url) == "https://example.supabase.co/rest/v1/profiles?select=id&limit=1"
    assert request.headers["apikey"] == SECRET
    assert request.headers["Accept-Profile"] == "public"
    assert "authorization" not in request.headers
    assert request.content == b""
    assert isolated_database["clients"][0].is_closed
    assert SECRET not in repr(get_database_settings())


@pytest.mark.parametrize("status", [301, 401, 403, 404, 429, 500, 503])
def test_provider_errors_are_sanitized(isolated_database, capsys, caplog, status):
    caplog.set_level(logging.DEBUG)
    isolated_database["status"] = status
    assert check_database.main() == 1
    output = capsys.readouterr()
    assert output.out == ""
    assert output.err == "Database connectivity check failed.\n"
    assert SECRET not in caplog.text + output.err
    assert SENSITIVE not in caplog.text + output.err
    assert len(isolated_database["requests"]) == 1  # No retries or redirects.
    assert isolated_database["clients"][0].is_closed


@pytest.mark.parametrize("error", [httpx.ConnectError, httpx.ReadTimeout])
def test_database_unavailable(isolated_database, caplog, capsys, error):
    isolated_database["failure"] = error(f"{SECRET} {SENSITIVE}")
    assert check_database.main() == 1
    output = capsys.readouterr()
    assert output.err == "Database connectivity check failed.\n"
    assert SECRET not in caplog.text + output.err
    assert SENSITIVE not in caplog.text + output.err
    assert isolated_database["clients"][0].is_closed


def test_command_configuration_failure(monkeypatch, capsys, isolated_database):
    monkeypatch.delenv("SUPABASE_SECRET_KEY")
    assert check_database.main() == 2
    assert capsys.readouterr().err == "Database configuration is missing or invalid.\n"
    assert isolated_database["requests"] == []


def test_command_success(capsys):
    assert check_database.main() == 0
    assert capsys.readouterr().out == "Database connectivity check passed.\n"


@pytest.mark.parametrize("secret", ["", "invalid", SECRET])
def test_api_is_independent(monkeypatch, isolated_database, caplog, secret):
    monkeypatch.setenv("SUPABASE_SECRET_KEY", secret)
    isolated_database["failure"] = httpx.ConnectError(SENSITIVE)
    with TestClient(app) as client:
        health = client.get("/health")
        unauthorized = client.get("/v1/auth/me")
    assert health.status_code == 200
    assert health.json() == {"status": "ok"}
    assert unauthorized.status_code == 401
    assert unauthorized.json() == {"detail": "Invalid authentication credentials"}
    assert SECRET not in health.text + unauthorized.text + caplog.text
    assert SENSITIVE not in health.text + unauthorized.text + caplog.text
    assert isolated_database["requests"] == []
    assert {route.path for route in app.routes if route.path.startswith("/v1/")} == {"/v1/auth/me", "/v1/capsules"}
