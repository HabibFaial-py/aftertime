"""TEST ONLY: Psycopg adapter fixed to a guarded disposable local cluster.

This module is deliberately outside application code. It has no configurable
host, real key provider, real mail transport, or production entry point.
"""

import os
from enum import Enum
from pathlib import Path
from threading import Lock
from uuid import UUID, uuid4

import psycopg

from app.invitation_delivery_worker import (
    DeliveryUnavailable, dispatch_transition_committed, verify_envelope,
)
from app.invitation_outbox import PerInvitationEncryptor


ROOT = bytes(range(32))  # Public synthetic test key only.
ENV = UUID("00000000-0000-4000-8000-000000000172")
OWNER = UUID("00000000-0000-4000-8000-000000000141")
CLAIMANT = UUID("00000000-0000-4000-8000-000000000173")
CLAIMANT_EMAIL = "claimant014i7@example.invalid"
DATA_DIR = Path(__file__).resolve().parents[3] / "build" / "outbox014i1-postgres-014i4"
SETUP = Path(__file__).parent / "sql" / "setup_local_encrypted_outbox.sql"
RPC_QUERY = "SELECT * FROM public.aftertime_invitation_worker_transition_v3(%s::uuid,%s::text,%s::uuid,%s::bigint,%s::bigint)"


def connect_local():
    """Fixed loopback, no inherited libpq configuration or password file."""
    if (os.environ.get("AFTERTIME_LOCAL_DELIVERY_TEST") != "1"
            or any(key.upper().startswith("PG") for key in os.environ)
            or not DATA_DIR.is_dir() or DATA_DIR.resolve() != DATA_DIR):
        raise RuntimeError("Local test database unavailable")
    conn = psycopg.connect(host="127.0.0.1", hostaddr="127.0.0.1", port=55485,
                           dbname="aftertime_rpc_test", user="postgres", passfile=os.devnull,
                           sslmode="disable", gssencmode="disable", connect_timeout=3,
                           options="-c search_path=pg_catalog -c client_encoding=UTF8 "
                                   "-c statement_timeout=5000 -c lock_timeout=2000")
    try:
        with conn.cursor() as cur:
            cur.execute("SET TRANSACTION READ ONLY")
            cur.execute("SELECT current_setting('data_directory'), host(inet_server_addr()), inet_server_port(), "
                        "current_database(), session_user, current_setting('listen_addresses'), EXISTS("
                        "SELECT FROM pg_constraint WHERE conrelid='public.direct_capsule_invitations'::regclass "
                        "AND conname='direct_capsule_invitations_disabled' AND convalidated "
                        "AND pg_get_constraintdef(oid)='CHECK (false)')")
            directory, host, port, db, user, listen, gate = cur.fetchone()
        if (Path(directory).resolve() != DATA_DIR or host != "127.0.0.1" or port != 55485
                or db != "aftertime_rpc_test" or user != "postgres" or listen != "127.0.0.1" or gate is not True):
            raise RuntimeError("Not the dedicated gated local cluster")
        conn.rollback()
        return conn
    except Exception:
        conn.close()
        raise


class FixtureCursor:
    query = RPC_QUERY
    role = "aftertime_invitation_worker"

    def __init__(self, conn):
        self.cursor = conn.cursor()

    def execute(self, query, args):
        if query != self.query:
            raise ValueError("Unexpected test query")
        self.cursor.execute(psycopg.sql.SQL("SET LOCAL ROLE {}").format(psycopg.sql.Identifier(self.role)))
        self.cursor.execute(query.replace("public.", "fixture014i4."), args)

    def fetchall(self):
        return self.cursor.fetchall()

    def fetchmany(self, size):
        return self.cursor.fetchmany(size)

    def close(self):
        self.cursor.close()


class FixtureConnection:
    """Translate only the known worker RPC to the isolated copied function."""

    autocommit = False
    cursor_type = FixtureCursor

    def __init__(self, commit_fault=None):
        self.conn = connect_local()
        self.commit_fault = commit_fault

    def cursor(self):
        return self.cursor_type(self.conn)

    def commit(self):
        if self.commit_fault == "disconnect_before_commit":
            # Closing a real Psycopg connection abandons the open transaction.
            self.conn.close()
        self.conn.commit()
        if self.commit_fault == "lose_commit_ack":
            # Commit really succeeded; simulate losing its acknowledgement to the caller.
            self.conn.close()
            raise TimeoutError("synthetic lost commit response")

    def rollback(self):
        self.conn.rollback()

    def close(self):
        self.conn.close()


class InboxCursor(FixtureCursor):
    role = "service_role"
    query = ("SELECT id, sender_id, created_at, unlock_at, status FROM "
             "public.aftertime_list_received_direct_capsules(%s::uuid,%s::integer,%s::integer)")


class RevealCursor(FixtureCursor):
    role = "service_role"
    query = "SELECT id, body FROM public.aftertime_reveal_direct_capsule(%s::uuid,%s::uuid)"


class InboxConnection(FixtureConnection):
    cursor_type = InboxCursor


class RevealConnection(FixtureConnection):
    cursor_type = RevealCursor


class FakeProviderTimeout(Exception):
    pass


class FakeProviderRetryable(Exception):
    pass


class ProviderOutcome(Enum):
    ACCEPTED = "accepted"
    REJECTED = "rejected"
    UNKNOWN = "unknown"


def synthetic_key_provider(key_id):
    if key_id != ENV.hex + "_v1":
        raise DeliveryUnavailable()
    return ROOT, ENV, "v1"


class FakeProvider:
    """An in-memory provider account scoped to one fixture environment."""

    def __init__(self, *, deduplicate=True, timeout_after_accept=False, reject_before_accept=False,
                 lookup_available=True, timeout_without_outcome=False):
        self.deduplicate = deduplicate
        self.timeout_after_accept = timeout_after_accept
        self.reject_before_accept = reject_before_accept
        self.lookup_available = lookup_available
        self.timeout_without_outcome = timeout_without_outcome
        self.requests = 0
        self.accepted = []
        self.lookups = []
        self._outcomes = {}
        self._lock = Lock()

    def __repr__(self):
        return "FakeProvider(<redacted>)"

    def send(self, job_id, dispatch_generation, recipient, secret):
        with self._lock:
            self.requests += 1
            attempt = (job_id, dispatch_generation)
            previous = self._outcomes.get(attempt)
            if (previous is ProviderOutcome.REJECTED
                    or (previous is None and self.reject_before_accept)):
                self._outcomes[attempt] = ProviderOutcome.REJECTED
                raise FakeProviderRetryable("Synthetic rejection before acceptance")
            if self.timeout_without_outcome:
                raise FakeProviderTimeout("Synthetic outcome unknown")
            item = (job_id, recipient, secret)
            if not self.deduplicate or not any(previous[0] == job_id for previous in self.accepted):
                self.accepted.append(item)
            self._outcomes[attempt] = ProviderOutcome.ACCEPTED
            if self.timeout_after_accept:
                self.timeout_after_accept = False
                raise FakeProviderTimeout("Synthetic outcome unknown")
            return ProviderOutcome.ACCEPTED

    def lookup(self, job_id, dispatch_generation):
        with self._lock:
            attempt = (job_id, dispatch_generation)
            self.lookups.append(attempt)
            if not self.lookup_available:
                return ProviderOutcome.UNKNOWN
            return self._outcomes.get(attempt, ProviderOutcome.UNKNOWN)


class LocalDelivery:
    """The only dispatch target is exactly FakeProvider, never a network client."""

    def candidates(self):
        with connect_local() as conn:
            with conn.cursor() as cur:
                cur.execute("SET LOCAL ROLE aftertime_invitation_worker")
                cur.execute("SELECT job_id FROM fixture014i4.aftertime_invitation_worker_candidates()")
                rows = cur.fetchall()
            conn.commit()
        return [row[0] for row in rows]

    def process(self, job_id, provider, *, before_prepare=None, commit_fault=None):
        if type(provider) is not FakeProvider:
            raise ValueError("Only the local fake provider is permitted")

        def transition(action, token=None, generation=None, dispatch=None):
            fault = commit_fault[1] if commit_fault and commit_fault[0] == action else None
            return dispatch_transition_committed(lambda: FixtureConnection(fault), job_id, action, token, generation, dispatch)

        lease = transition("lease")
        if lease is None:
            return "unavailable"
        if lease.outcome != "leased":
            return lease.outcome
        if before_prepare is not None:
            before_prepare()
        token, generation = lease.lease_token, lease.lease_generation
        ready = transition("prepare", token, generation)
        if ready is None or ready.outcome not in {"prepared", "reconcile"}:
            return "ineligible"
        if ready.outcome == "prepared":
            envelope = ready.envelope
            try:
                root, environment, version = synthetic_key_provider(envelope.key_id)
                claim = verify_envelope(envelope, root, environment, version)
            except DeliveryUnavailable:
                result = transition("fail", token, generation)
                return result.outcome if result else "unavailable"
            ready = transition("reserve", token, generation)
            if ready is None or ready.outcome not in {"reserved", "reconcile"}:
                return "ineligible"

        dispatch_generation = ready.dispatch_generation
        if ready.outcome == "reconcile":
            outcome = provider.lookup(job_id, dispatch_generation)
        else:
            try:
                outcome = provider.send(job_id, dispatch_generation, envelope.intended_email, claim.secret.get_secret_value())
            except FakeProviderRetryable:
                outcome = ProviderOutcome.REJECTED
            except FakeProviderTimeout:
                outcome = ProviderOutcome.UNKNOWN

        if outcome is ProviderOutcome.ACCEPTED:
            result = transition("accept", token, generation, dispatch_generation)
            return result.outcome if result else "accepted_unrecorded"
        if outcome is ProviderOutcome.REJECTED:
            result = transition("reject", token, generation, dispatch_generation)
            return result.outcome if result else "unavailable"
        return "send_unknown"


def setup_fixture(*, recipient_reads=False):
    """Create a uniquely marked fixture only after independent cluster checks."""
    marker = uuid4()
    service_functions = ["aftertime_claim_direct_capsule(uuid,uuid,bytea)",
                         "aftertime_cancel_direct_capsule(uuid,uuid)"]
    if recipient_reads:
        service_functions += ["aftertime_list_received_direct_capsules(uuid,integer,integer)",
                              "aftertime_reveal_direct_capsule(uuid,uuid)"]
    with connect_local() as conn:
        with conn.cursor() as cur:
            cur.execute(SETUP.read_text(encoding="utf-8"))
            cur.execute("CREATE TABLE fixture014i4.test_marker(id uuid PRIMARY KEY)")
            cur.execute("INSERT INTO fixture014i4.test_marker VALUES (%s)", (marker,))
            for signature in ("aftertime_invitation_worker_candidates()",
                              "aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint)",
                              *service_functions):
                cur.execute("SELECT pg_get_functiondef(%s::regprocedure)", ("public." + signature,))
                definition = cur.fetchone()[0].replace("FUNCTION public.", "FUNCTION fixture014i4.")
                for table in ("direct_capsules", "direct_capsule_invitations", "invitation_delivery_outbox"):
                    definition = definition.replace("public." + table, "fixture014i4." + table)
                cur.execute(definition)
            cur.execute("REVOKE ALL ON ALL FUNCTIONS IN SCHEMA fixture014i4 FROM PUBLIC")
            cur.execute("GRANT USAGE ON SCHEMA fixture014i4 TO aftertime_invitation_worker")
            cur.execute("GRANT EXECUTE ON FUNCTION fixture014i4.aftertime_invitation_worker_candidates(), "
                        "fixture014i4.aftertime_invitation_worker_transition_v3(uuid,text,uuid,bigint,bigint) TO aftertime_invitation_worker")
            functions = ", ".join("fixture014i4." + signature for signature in service_functions)
            cur.execute(f"GRANT EXECUTE ON FUNCTION {functions} TO service_role")
            cur.execute("INSERT INTO auth.users(id,email,email_confirmed_at) VALUES (%s,%s,clock_timestamp())",
                        (CLAIMANT, CLAIMANT_EMAIL))
    return marker


def cleanup_fixture(marker):
    """Remove only our matching fixture, after re-verifying the cluster."""
    with connect_local() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM fixture014i4.test_marker")
            if cur.fetchall() != [(marker,)]:
                raise RuntimeError("Fixture marker mismatch; refusing cleanup")
            cur.execute("DELETE FROM auth.users WHERE (id, email) IN ((%s, %s), (%s, %s)) RETURNING id",
                        (OWNER, "owner014i4@example.invalid", CLAIMANT, CLAIMANT_EMAIL))
            if {row[0] for row in cur.fetchall()} != {OWNER, CLAIMANT}:
                raise RuntimeError("Fixture users mismatch; refusing cleanup")
            cur.execute("DROP SCHEMA fixture014i4 CASCADE")
            cur.execute("DROP ROLE aftertime_fixture_worker_014i4")


def create_job():
    capsule_id, invitation_id, job_id = uuid4(), uuid4(), uuid4()
    item = PerInvitationEncryptor(ROOT, ENV, "v1").encrypt(job_id, invitation_id, capsule_id,
                                                            "recipient014i7@example.invalid")
    with connect_local() as conn:
        with conn.cursor() as cur:
            cur.execute("SET LOCAL ROLE service_role")
            cur.execute("SELECT * FROM fixture014i4.aftertime_create_direct_with_outbox("
                        "%s,%s,%s,%s,%s,%s,%s,clock_timestamp()+interval '1 day',%s,%s,%s,%s,%s)",
                        (OWNER, capsule_id, invitation_id, job_id, "recipient014i7@example.invalid",
                         "synthetic", "synthetic body", item.digest, item.key_id, item.nonce, item.salt, item.ciphertext))
            if len(cur.fetchall()) != 1:
                raise RuntimeError("Local fixture creation failed")
    return job_id, capsule_id, invitation_id, item.digest
