from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.main import app
from local_recipient_http import INBOX_PATH, REVEAL_PATH, create_local_recipient_app
from test_auth import setup_auth, token


@pytest.mark.parametrize("missing", ["AFTERTIME_LOCAL_DELIVERY_TEST", "AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST"])
def test_test_app_requires_both_opt_ins(monkeypatch, missing):
    monkeypatch.setenv("AFTERTIME_LOCAL_DELIVERY_TEST", "1")
    monkeypatch.setenv("AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST", "1")
    monkeypatch.delenv(missing, raising=False)
    with pytest.raises(RuntimeError, match="^Local recipient HTTP tests are disabled$"):
        create_local_recipient_app(uuid4())


@pytest.mark.parametrize("direct_flag", ["false", "true"])
def test_normal_api_cannot_mount_local_boundary_even_with_all_flags(setup_auth, monkeypatch, direct_flag):
    monkeypatch.setenv("AFTERTIME_LOCAL_DELIVERY_TEST", "1")
    monkeypatch.setenv("AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST", "1")
    monkeypatch.setenv("DIRECT_CAPSULES_ENABLED", direct_flag)
    capsule = uuid4()
    headers = {"Authorization": f"Bearer {token(setup_auth)}"}
    with TestClient(app, client=("127.0.0.1", 40000)) as client:
        assert client.get(INBOX_PATH, headers=headers).status_code == 404
        assert client.post(REVEAL_PATH.format(capsule_id=capsule), headers=headers).status_code == 404
        assert client.get("/v1/direct-capsules/received", headers=headers).status_code == 404
        assert client.get(f"/v1/direct-capsules/{capsule}/reveal", headers=headers).status_code == 404
        claim = client.post(f"/v1/direct-capsules/{capsule}/claim", headers=headers)
        assert claim.status_code == (503 if direct_flag == "true" else 404)

    assert all(not path.startswith("/__local/") for path in app.openapi()["paths"])
