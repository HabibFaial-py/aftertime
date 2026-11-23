"""In-process HTTP requests against the guarded PostgreSQL recipient fixture."""

import os
from concurrent.futures import ThreadPoolExecutor
from queue import Queue
from time import monotonic, sleep
from uuid import uuid4

import pytest

if (os.environ.get("AFTERTIME_LOCAL_DELIVERY_TEST") != "1"
        or os.environ.get("AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST") != "1"):
    pytest.skip("explicit local recipient HTTP opt-ins required", allow_module_level=True)

from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient

import local_delivery_adapter as local_db
from app.invitation_claim import ClaimOutcome
from local_recipient_http import INBOX_PATH, REVEAL_PATH, create_local_recipient_app
from test_auth import setup_auth, token
from test_local_invitation_claim import credentials
from test_local_recipient_capsules import BODY, claim_fixture, prepare_invitation, recipient_fixture, set_past_unlock


def open_client(marker, host="127.0.0.1"):
    return TestClient(create_local_recipient_app(marker), client=(host, 40000), follow_redirects=False)


def headers(session):
    return {"Authorization": f"{session.scheme} {session.credentials}"}


def reveal_path(capsule_id):
    return REVEAL_PATH.format(capsule_id=capsule_id)


def assert_no_store(response):
    assert response.headers["Cache-Control"] == "no-store"
    assert response.headers["Pragma"] == "no-cache"


def assert_unavailable(response):
    assert_no_store(response)
    assert response.status_code == 404 and response.json() == {"detail": "Capsule unavailable"}


def test_factory_rejects_unverified_marker(recipient_fixture):
    with pytest.raises(RuntimeError, match="^Local recipient HTTP fixture unavailable$"):
        create_local_recipient_app(uuid4())


def test_loopback_scope_and_opt_in_are_checked_for_each_request(recipient_fixture, monkeypatch):
    with open_client(recipient_fixture, host="192.0.2.4") as client:
        nonlocal_response = client.get(INBOX_PATH, headers={"X-Forwarded-For": "127.0.0.1"})
    assert_no_store(nonlocal_response)
    assert nonlocal_response.status_code == 404

    with open_client(recipient_fixture) as client:
        monkeypatch.delenv("AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST")
        disabled_response = client.get(INBOX_PATH)
    assert_no_store(disabled_response)
    assert disabled_response.status_code == 404


@pytest.mark.parametrize("auth_case", ["missing", "malformed", "wrong_signature", "expired", "wrong_audience"])
def test_invalid_auth_is_generic_and_never_opens_service_connection(recipient_fixture, setup_auth, monkeypatch, auth_case):
    def unexpected_read():
        pytest.fail("Unauthenticated request reached the service database connection")

    monkeypatch.setattr(local_db, "InboxConnection", unexpected_read)
    monkeypatch.setattr(local_db, "RevealConnection", unexpected_read)
    if auth_case == "missing":
        auth_headers = {}
    else:
        bad_token = {
            "malformed": lambda: "not-a-jwt",
            "wrong_signature": lambda: token(ec.generate_private_key(ec.SECP256R1()), sub=str(local_db.CLAIMANT)),
            "expired": lambda: token(setup_auth, sub=str(local_db.CLAIMANT), exp=1),
            "wrong_audience": lambda: token(setup_auth, sub=str(local_db.CLAIMANT), aud="wrong"),
        }[auth_case]()
        auth_headers = {"Authorization": f"Bearer {bad_token}"}
    with open_client(recipient_fixture) as client:
        responses = [client.get(INBOX_PATH, headers=auth_headers),
                     client.post(reveal_path(uuid4()), headers=auth_headers)]
    for response in responses:
        assert_no_store(response)
        assert response.status_code == 401
        assert response.headers["WWW-Authenticate"] == "Bearer"
        assert response.json() == {"detail": "Invalid authentication credentials"}


def test_claimed_inbox_and_explicit_reveal_before_and_after_unlock(recipient_fixture, credentials, caplog):
    capsule, _, link = prepare_invitation()
    _, unclaimed, _, _ = local_db.create_job()
    session = credentials()
    session_headers = headers(session)
    set_past_unlock(unclaimed)
    with open_client(recipient_fixture) as client:
        unbound = client.post(reveal_path(unclaimed), headers=session_headers)
        assert_unavailable(unbound)
        empty = client.get(INBOX_PATH, headers=session_headers)
        assert_no_store(empty)
        assert empty.status_code == 200 and empty.json() == []

        assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED
        locked = client.get(INBOX_PATH, params={"limit": 1, "offset": 0}, headers=session_headers)
        assert_no_store(locked)
        assert locked.status_code == 200
        item, = locked.json()
        assert set(item) == {"id", "sender_id", "created_at", "unlock_at", "status"}
        assert item["id"] == str(capsule) and item["sender_id"] == str(local_db.OWNER) and item["status"] == "locked"
        assert BODY not in locked.text
        assert_unavailable(client.post(reveal_path(capsule), headers=session_headers))

        set_past_unlock(capsule)
        metadata = client.get(INBOX_PATH, headers=session_headers)
        assert_no_store(metadata)
        assert metadata.status_code == 200 and metadata.json()[0]["status"] == "unlocked"
        assert BODY not in metadata.text
        prefetched = client.get(reveal_path(capsule), headers=session_headers)
        assert_no_store(prefetched)
        assert prefetched.status_code == 405 and BODY not in prefetched.text
        revealed = client.post(reveal_path(capsule), headers=session_headers)
        assert_no_store(revealed)
        assert revealed.status_code == 200 and revealed.json() == {"id": str(capsule), "body": BODY}
    assert BODY not in caplog.text


@pytest.fixture
def other_account(recipient_fixture):
    subject = uuid4()
    email = "recipient-http-isolation014j4@example.invalid"
    with local_db.connect_local() as connection:
        connection.execute("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES (%s,%s,clock_timestamp())",
                           (subject, email))
    try:
        yield subject
    finally:
        with local_db.connect_local() as connection:
            deleted = connection.execute("DELETE FROM auth.users WHERE id=%s AND email=%s RETURNING id",
                                         (subject, email)).fetchone()
            assert deleted == (subject,)


def test_other_account_and_sender_cannot_override_verified_subject(recipient_fixture, other_account, credentials):
    capsule, _, link = prepare_invitation()
    assert claim_fixture(link, credentials()).outcome is ClaimOutcome.CLAIMED
    set_past_unlock(capsule)
    with open_client(recipient_fixture) as client:
        for subject in (local_db.OWNER, other_account):
            forged_headers = {**headers(credentials(subject)), "X-User-ID": str(local_db.CLAIMANT)}
            result = client.get(INBOX_PATH, headers=forged_headers)
            assert_no_store(result)
            assert result.status_code == 200 and result.json() == []
            assert_unavailable(client.post(reveal_path(capsule), headers=forged_headers))

        other_headers = headers(credentials(other_account))
        override = {"user_id": str(local_db.CLAIMANT)}
        for response in (client.get(INBOX_PATH, params=override, headers=other_headers),
                         client.post(reveal_path(capsule), params=override, headers=other_headers),
                         client.post(reveal_path(capsule), json=override, headers=other_headers)):
            assert_no_store(response)
            assert response.status_code == 422 and response.json() == {"detail": "Invalid recipient request"}


def test_invalid_inputs_are_not_echoed_and_receive_no_store(recipient_fixture, credentials):
    session_headers = headers(credentials())
    with open_client(recipient_fixture) as client:
        responses = [client.get(INBOX_PATH, params={"limit": "private-value"}, headers=session_headers),
                     client.get(INBOX_PATH, params=[("limit", 1), ("limit", 2)], headers=session_headers),
                     client.post(reveal_path("private-value"), headers=session_headers)]
    for response in responses:
        assert_no_store(response)
        assert response.status_code == 422 and response.json() == {"detail": "Invalid recipient request"}


@pytest.mark.parametrize("case", ["cancelled", "deleted", "revoked"])
def test_capsule_ineligibility_uses_same_http_denial(recipient_fixture, credentials, case):
    capsule, invitation, link = prepare_invitation()
    session = credentials()
    assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED
    set_past_unlock(capsule)
    query, target = {
        "cancelled": ("UPDATE fixture014i4.direct_capsules SET cancelled_at=unlock_at-interval '1 second' WHERE id=%s", capsule),
        "deleted": ("UPDATE fixture014i4.direct_capsules SET deleted_at=clock_timestamp() WHERE id=%s", capsule),
        "revoked": ("UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=%s", invitation),
    }[case]
    with local_db.connect_local() as connection:
        connection.execute(query, (target,))
    with open_client(recipient_fixture) as client:
        assert_unavailable(client.post(reveal_path(capsule), headers=headers(session)))
        result = client.get(INBOX_PATH, headers=headers(session))
        assert_no_store(result)
        assert result.status_code == 200 and result.json() == []


@pytest.mark.parametrize("state", ["banned", "deleted"])
def test_reveal_rechecks_concurrent_account_change_after_wait(recipient_fixture, credentials, monkeypatch, state):
    capsule, _, link = prepare_invitation()
    session = credentials()
    assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED
    set_past_unlock(capsule)
    session_headers = headers(session)
    readers = Queue()

    class ObservedRevealConnection(local_db.RevealConnection):
        def __init__(self):
            super().__init__()
            self.conn.execute("SET LOCAL lock_timeout = '4s'")
            readers.put(self.conn.info.backend_pid)

    monkeypatch.setattr(local_db, "RevealConnection", ObservedRevealConnection)
    with open_client(recipient_fixture) as client, ThreadPoolExecutor(max_workers=1) as pool:
        with local_db.connect_local() as writer:
            if state == "banned":
                writer.execute("UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 day' WHERE id=%s",
                               (local_db.CLAIMANT,))
            else:
                writer.execute("UPDATE auth.users SET deleted_at=clock_timestamp() WHERE id=%s", (local_db.CLAIMANT,))

            snapshot = client.get(INBOX_PATH, headers=session_headers)
            assert_no_store(snapshot)
            assert snapshot.status_code == 200 and snapshot.json()[0]["id"] == str(capsule)

            pending = pool.submit(client.post, reveal_path(capsule), headers=session_headers)
            reader = readers.get(timeout=6)
            with local_db.connect_local() as observer:
                deadline = monotonic() + 2
                while not observer.execute("SELECT %s = ANY(pg_blocking_pids(%s))",
                                           (writer.info.backend_pid, reader)).fetchone()[0]:
                    assert monotonic() < deadline, "Reveal did not wait on the account lock"
                    sleep(0.025)
                assert not pending.done()
        assert_unavailable(pending.result(timeout=6))
        updated = client.get(INBOX_PATH, headers=session_headers)
        assert_no_store(updated)
        assert updated.status_code == 200 and updated.json() == []


@pytest.mark.parametrize("fault", ["connect_failure", "disconnect_before_commit", "lose_commit_ack"])
@pytest.mark.parametrize("operation", ["inbox", "reveal"])
def test_http_withholds_provisional_data_on_database_failure(recipient_fixture, credentials, monkeypatch, caplog,
                                                           operation, fault):
    capsule, _, link = prepare_invitation()
    session = credentials()
    assert claim_fixture(link, session).outcome is ClaimOutcome.CLAIMED
    set_past_unlock(capsule)
    connection_name = "InboxConnection" if operation == "inbox" else "RevealConnection"
    connection_type = getattr(local_db, connection_name)
    attempts = []

    def connect():
        attempts.append(True)
        if fault == "connect_failure":
            raise RuntimeError(BODY)
        return connection_type(fault)

    monkeypatch.setattr(local_db, connection_name, connect)
    with open_client(recipient_fixture) as client:
        if operation == "inbox":
            result = client.get(INBOX_PATH, headers=headers(session))
        else:
            result = client.post(reveal_path(capsule), headers=headers(session))
    assert_no_store(result)
    assert attempts == [True] and result.status_code == 503
    assert result.json() == {"detail": "Capsule service unavailable"}
    assert BODY not in result.text + caplog.text and str(capsule) not in result.text
