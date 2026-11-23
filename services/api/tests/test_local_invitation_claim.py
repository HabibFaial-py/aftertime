"""Authenticated claims against the verified disposable PostgreSQL fixture."""

import os
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest

if os.environ.get("AFTERTIME_LOCAL_DELIVERY_TEST") != "1":
    pytest.skip("explicit local database test opt-in required", allow_module_level=True)

from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.direct_capsules import generate_invitation_secret
from app.invitation_claim import ClaimOutcome, build_invitation_link, claim_invitation, parse_invitation_link
from local_delivery_adapter import (
    CLAIMANT, OWNER, FakeProvider, FixtureConnection, FixtureCursor, LocalDelivery,
    cleanup_fixture, connect_local, create_job, setup_fixture,
)
from test_auth import setup_auth, token


class ClaimCursor(FixtureCursor):
    query = ("SELECT id, created_at, unlock_at FROM "
             "public.aftertime_claim_direct_capsule(%s::uuid,%s::uuid,%s::bytea)")
    role = "service_role"

    def __init__(self, connection, calls):
        super().__init__(connection)
        self.calls = calls

    def execute(self, query, args):
        self.calls.append(args)
        super().execute(query, args)


class ClaimConnection(FixtureConnection):
    def __init__(self, calls, fault=None):
        super().__init__(fault)
        self.calls = calls

    def cursor(self):
        return ClaimCursor(self.conn, self.calls)


@pytest.fixture
def invitation():
    marker = setup_fixture()
    try:
        job, capsule, invitation_id, digest = create_job()
        provider = FakeProvider()
        assert LocalDelivery().process(job, provider) == "sent"
        _, recipient, secret = provider.accepted[0]
        yield capsule, invitation_id, digest, build_invitation_link(capsule, secret), recipient
    finally:
        cleanup_fixture(marker)


@pytest.fixture
def credentials(setup_auth):
    def make(subject=CLAIMANT, scheme="Bearer", **claims):
        return HTTPAuthorizationCredentials(scheme=scheme, credentials=token(setup_auth, sub=str(subject), **claims))

    return make


@pytest.fixture
def other_claimant(invitation):
    user_id = uuid4()
    email = "competing-claimant014j1@example.invalid"
    with connect_local() as connection:
        connection.execute("INSERT INTO auth.users (id,email,email_confirmed_at) VALUES (%s,%s,clock_timestamp())",
                           (user_id, email))
    try:
        yield user_id
    finally:
        with connect_local() as connection:
            row = connection.execute("DELETE FROM auth.users WHERE id=%s AND email=%s RETURNING id",
                                     (user_id, email)).fetchone()
            assert row == (user_id,)


def claim_state(invitation_id):
    with connect_local() as connection:
        return connection.execute(
            "SELECT claimed_user_id, claimed_at, claim_secret_digest FROM fixture014i4.direct_capsule_invitations WHERE id=%s",
            (invitation_id,),
        ).fetchone()


def attempt(link, credentials, calls, fault=None):
    return claim_invitation(link, credentials, confirmed=True, connection_factory=lambda: ClaimConnection(calls, fault))


def test_explicit_claim_binds_verified_subject_even_with_different_email(invitation, credentials, caplog):
    capsule, invitation_id, digest, link, recipient = invitation
    calls = []
    claim_credentials = credentials(email="different-mailbox@example.invalid")
    assert parse_invitation_link(link).capsule_id == capsule and claim_state(invitation_id) == (None, None, digest)
    opening = claim_invitation(link, claim_credentials, connection_factory=lambda: ClaimConnection(calls))
    assert opening.outcome is ClaimOutcome.CONFIRMATION_REQUIRED and calls == []
    assert claim_state(invitation_id) == (None, None, digest)

    result = attempt(link, claim_credentials, calls)
    assert result.outcome is ClaimOutcome.CLAIMED
    assert result.capsule.id == capsule and set(result.capsule.model_dump()) == {"id", "created_at", "unlock_at"}
    assert calls == [(str(capsule), str(CLAIMANT), digest)]
    claimant, claimed_at, stored_digest = claim_state(invitation_id)
    assert claimant == CLAIMANT and claimed_at is not None and stored_digest is None
    secret = parse_invitation_link(link).claim.secret.get_secret_value()
    assert all(value not in repr(result) + repr(calls) + caplog.text for value in (secret, recipient))

    duplicate = attempt(link, claim_credentials, calls)
    assert duplicate.outcome is ClaimOutcome.UNAVAILABLE and duplicate.capsule is None
    assert claim_state(invitation_id) == (CLAIMANT, claimed_at, None)


def test_concurrent_claims_bind_exactly_one_verified_account(invitation, other_claimant, credentials):
    _, invitation_id, _, link, _ = invitation
    users = CLAIMANT, other_claimant
    barrier = Barrier(2)

    def run_claim(user):
        session = credentials(user)
        barrier.wait(timeout=5)
        return attempt(link, session, []).outcome

    with ThreadPoolExecutor(max_workers=2) as pool:
        outcomes = list(pool.map(run_claim, users))
    assert outcomes.count(ClaimOutcome.CLAIMED) == outcomes.count(ClaimOutcome.UNAVAILABLE) == 1
    assert claim_state(invitation_id)[0] == users[outcomes.index(ClaimOutcome.CLAIMED)]


@pytest.mark.parametrize("case", ["wrong_secret", "unknown_capsule", "malformed", "tampered_host"])
def test_invalid_invitations_share_one_outcome(invitation, credentials, case):
    capsule, invitation_id, digest, link, _ = invitation
    if case == "wrong_secret":
        bad_link = build_invitation_link(capsule, generate_invitation_secret().secret)
    elif case == "unknown_capsule":
        bad_link = build_invitation_link(uuid4(), parse_invitation_link(link).claim.secret)
    elif case == "malformed":
        bad_link = link.get_secret_value() + "="
    else:
        bad_link = link.get_secret_value().replace("aftertime.example.invalid", "other.example.invalid")
    calls = []
    result = attempt(bad_link, credentials(), calls)
    assert result.outcome is ClaimOutcome.UNAVAILABLE and result.capsule is None
    assert len(calls) == int(case in {"wrong_secret", "unknown_capsule"})
    assert claim_state(invitation_id) == (None, None, digest)


@pytest.mark.parametrize("case", ["expired", "cancelled", "revoked", "banned", "deleted_account", "missing_profile", "sender"])
def test_ineligible_claims_share_one_outcome(invitation, credentials, case):
    capsule, invitation_id, digest, link, _ = invitation
    with connect_local() as connection:
        if case == "expired":
            connection.execute("UPDATE fixture014i4.direct_capsule_invitations SET "
                               "created_at=statement_timestamp()-interval '169 hours', "
                               "expires_at=statement_timestamp()-interval '1 hour' WHERE id=%s", (invitation_id,))
        elif case == "cancelled":
            connection.execute("SET LOCAL ROLE service_role")
            assert connection.execute("SELECT * FROM fixture014i4.aftertime_cancel_direct_capsule(%s,%s)",
                                      (capsule, OWNER)).fetchone() is not None
        elif case == "revoked":
            connection.execute("UPDATE fixture014i4.direct_capsule_invitations SET revoked_at=clock_timestamp() WHERE id=%s",
                               (invitation_id,))
        elif case == "banned":
            connection.execute("UPDATE auth.users SET banned_until=clock_timestamp()+interval '1 day' WHERE id=%s", (CLAIMANT,))
        elif case == "deleted_account":
            connection.execute("UPDATE auth.users SET deleted_at=clock_timestamp() WHERE id=%s", (CLAIMANT,))
        elif case == "missing_profile":
            connection.execute("DELETE FROM public.profiles WHERE id=%s", (CLAIMANT,))
    result = attempt(link, credentials(OWNER if case == "sender" else CLAIMANT), [])
    assert result.outcome is ClaimOutcome.UNAVAILABLE and result.capsule is None
    assert claim_state(invitation_id) == (None, None, digest)


@pytest.mark.parametrize("case", ["no_credentials", "raw_subject", "wrong_scheme", "bad_signature", "expired",
                                  "wrong_audience", "wrong_issuer"])
def test_invalid_auth_never_opens_claim_transaction(invitation, credentials, case):
    _, invitation_id, digest, link, _ = invitation
    session = credentials()
    if case == "no_credentials":
        session = None
    elif case == "raw_subject":
        session = str(CLAIMANT)
    elif case == "wrong_scheme":
        session = credentials(scheme="Basic")
    elif case == "bad_signature":
        header, payload, _ = session.credentials.split(".")
        session.credentials = f"{header}.{payload}.{'A' * 86}"
    elif case == "expired":
        session = credentials(exp=1)
    elif case == "wrong_audience":
        session = credentials(aud="anon")
    else:
        session = credentials(iss="https://another.example.invalid/auth/v1")

    def unexpected_connection():
        pytest.fail("Invalid authentication reached the database")

    with pytest.raises(HTTPException) as exc:
        claim_invitation(link, session, confirmed=True, connection_factory=unexpected_connection)
    assert exc.value.status_code == 401 and exc.value.detail == "Invalid authentication credentials"
    assert claim_state(invitation_id) == (None, None, digest)


@pytest.mark.parametrize("fault", ["disconnect_before_commit", "lose_commit_ack"])
def test_commit_ambiguity_never_returns_success_or_retries(invitation, credentials, fault, caplog):
    _, invitation_id, digest, link, _ = invitation
    calls = []
    session = credentials()
    result = attempt(link, session, calls, fault)
    assert result.outcome is ClaimOutcome.OUTCOME_UNKNOWN and result.capsule is None and len(calls) == 1
    assert parse_invitation_link(link).claim.secret.get_secret_value() not in repr(result) + caplog.text
    if fault == "lose_commit_ack":
        assert claim_state(invitation_id)[0] == CLAIMANT and claim_state(invitation_id)[2] is None
        assert attempt(link, session, []).outcome is ClaimOutcome.UNAVAILABLE
    else:
        assert claim_state(invitation_id) == (None, None, digest)
        assert attempt(link, session, []).outcome is ClaimOutcome.CLAIMED


@pytest.mark.parametrize("bad_result", ["wrong_capsule", "fetch_error"])
def test_invalid_database_result_rolls_back_the_claim(invitation, credentials, caplog, bad_result):
    _, invitation_id, digest, link, _ = invitation
    secret = parse_invitation_link(link).claim.secret.get_secret_value()
    calls = []

    class BadResultCursor(ClaimCursor):
        def fetchmany(self, size):
            rows = super().fetchmany(size)
            assert len(rows) == 1
            if bad_result == "fetch_error":
                raise ValueError(secret)
            return [(uuid4(), *rows[0][1:])]

    class BadResultConnection(ClaimConnection):
        def cursor(self):
            return BadResultCursor(self.conn, self.calls)

    result = claim_invitation(link, credentials(), confirmed=True,
                              connection_factory=lambda: BadResultConnection(calls))
    assert result.outcome is ClaimOutcome.SERVICE_UNAVAILABLE and result.capsule is None
    assert len(calls) == 1 and claim_state(invitation_id) == (None, None, digest)
    assert secret not in repr(result) + caplog.text
