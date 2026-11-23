from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.recipient_capsules import RecipientReadUnavailable, list_received_capsules, reveal_received_capsule
from test_auth import USER, setup_auth, token


CAPSULE = UUID("fd8d21ed-18dc-4310-a46a-3e8dd8a3fef3")
BODY = "synthetic private content"


@pytest.fixture
def session(setup_auth):
    return HTTPAuthorizationCredentials(scheme="Bearer", credentials=token(setup_auth))


def unexpected_connection():
    pytest.fail("Request reached the database")


@pytest.mark.parametrize("operation", ["inbox", "reveal"])
def test_caller_supplied_subject_is_not_identity(operation):
    with pytest.raises(HTTPException) as exc:
        if operation == "inbox":
            list_received_capsules(USER, connection_factory=unexpected_connection)
        else:
            reveal_received_capsule(CAPSULE, USER, connection_factory=unexpected_connection)
    assert exc.value.status_code == 401


@pytest.mark.parametrize("pagination", [{"limit": 0}, {"limit": 101}, {"limit": True}, {"offset": -1}, {"offset": 10001}])
def test_invalid_pagination_is_unavailable(session, pagination):
    with pytest.raises(RecipientReadUnavailable, match="^Recipient capsules unavailable$"):
        list_received_capsules(session, connection_factory=unexpected_connection, **pagination)


class BrokenCursor:
    def __init__(self, rows):
        self.rows = rows

    def execute(self, _query, _params):
        pass

    def fetchmany(self, _size):
        return self.rows

    def close(self):
        pass


class BrokenConnection:
    autocommit = False

    def __init__(self, rows):
        self.rows = rows
        self.rolled_back = False

    def cursor(self):
        return BrokenCursor(self.rows)

    def commit(self):
        pytest.fail("Malformed data reached commit")

    def rollback(self):
        self.rolled_back = True

    def close(self):
        pass


@pytest.mark.parametrize("rows", [[(uuid4(), BODY)], [(CAPSULE, BODY, "extra")], [(CAPSULE, None)], [(CAPSULE, BODY)] * 2])
def test_malformed_reveal_result_is_sanitized_and_rolled_back(session, rows, caplog):
    connection = BrokenConnection(rows)
    with pytest.raises(RecipientReadUnavailable, match="^Recipient capsules unavailable$") as exc:
        reveal_received_capsule(CAPSULE, session, connection_factory=lambda: connection)
    assert connection.rolled_back and BODY not in repr(exc.value) + caplog.text


def test_inbox_rejects_extra_columns_even_if_the_row_would_otherwise_be_valid(session, caplog):
    created = datetime.now(timezone.utc)
    connection = BrokenConnection([(CAPSULE, uuid4(), created, created + timedelta(days=1), "locked", BODY)])
    with pytest.raises(RecipientReadUnavailable, match="^Recipient capsules unavailable$") as exc:
        list_received_capsules(session, connection_factory=lambda: connection)
    assert connection.rolled_back and BODY not in repr(exc.value) + caplog.text
