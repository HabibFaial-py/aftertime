"""Opt-in, rollback-only PostgreSQL integration. Never connect to hosted services.

Run only against the dedicated test cluster described in the phase 014I-4 report.
The adapter receives a real SQL result through a local psql test transport; no
production route, transport, key provider, or email delivery is implemented.
"""

import hmac
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import threading
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest

from app.direct_capsules import CreateDirectCapsule
from app.invitation_outbox import PerInvitationEncryptor, decrypt_per_invitation
from app.trusted_invitation_create import InvitationCreationUnavailable, _create_with_per_invitation_key


pytestmark = pytest.mark.skipif(os.environ.get("AFTERTIME_LOCAL_OUTBOX_TEST") != "1",
                                reason="explicit local PostgreSQL opt-in required")
ROOT = bytes(range(32))  # Public synthetic fixture key, never a production key.
ENV = UUID("00000000-0000-4000-8000-000000000142")
OWNER = "00000000-0000-4000-8000-000000000141"
REPOSITORY = Path(__file__).resolve().parents[3]
DATA_DIR = (REPOSITORY / "build" / "outbox014i1-postgres-014i4").resolve()
SETUP = Path(__file__).parent / "sql" / "setup_local_encrypted_outbox.sql"
ARGUMENTS = (
    "p_owner_id", "p_capsule_id", "p_invitation_id", "p_job_id", "p_recipient_email",
    "p_title", "p_body", "p_unlock_at", "p_digest", "p_key_id", "p_nonce", "p_kdf_salt", "p_ciphertext",
)


class SqlError(Exception):
    pass


class LocalSession:
    """Fixed loopback connection; diagnostics are intentionally not echoed."""

    def __init__(self):
        windows_psql = Path("C:/Program Files/PostgreSQL/18/bin/psql.exe")
        psql = str(windows_psql) if windows_psql.is_file() else shutil.which("psql")
        if not psql or not DATA_DIR.is_dir():
            raise RuntimeError("Dedicated local cluster or psql unavailable")
        env = {key: value for key, value in os.environ.items() if not key.upper().startswith("PG")}
        env.update(PGCONNECT_TIMEOUT="3", PGCLIENTENCODING="UTF8")
        self.proc = subprocess.Popen(
            [psql, "-X", "-q", "-A", "-t", "-h", "127.0.0.1", "-p", "55485", "-U", "postgres",
             "-d", "aftertime_rpc_test", "-v", "ON_ERROR_STOP=0", "-v", "ON_ERROR_ROLLBACK=on"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", bufsize=1, env=env,
        )
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.calls = []
        try:
            identity = self.json("SELECT json_build_object('directory',current_setting('data_directory'),"
                                 "'port',current_setting('port'),'listen',current_setting('listen_addresses'),"
                                 "'database',current_database(),'role',current_user);")
            if (Path(identity["directory"]).resolve() != DATA_DIR or identity["port"] != "55485"
                    or identity["listen"] != "127.0.0.1" or identity["database"] != "aftertime_rpc_test"
                    or identity["role"] != "postgres"):
                raise RuntimeError("Not the dedicated local test cluster")
            self.execute("BEGIN;")
            self.execute(SETUP.read_text(encoding="utf-8"))
        except Exception:
            self.close()
            raise

    def _read(self):
        for line in self.proc.stdout:
            self.lines.put(line.rstrip("\r\n"))
        self.lines.put(None)

    def execute(self, sql):
        marker = "AFTERTIME_END_" + uuid4().hex
        self.proc.stdin.write(sql + "\n\\echo " + marker + "\n")
        self.proc.stdin.flush()
        lines = []
        while True:
            try:
                line = self.lines.get(timeout=20)
            except queue.Empty:
                raise RuntimeError("Local PostgreSQL test timed out") from None
            if line is None:
                raise RuntimeError("Local PostgreSQL test connection closed")
            if line == marker:
                break
            lines.append(line)
        if any("ERROR:" in line or "FATAL:" in line for line in lines):
            raise SqlError("Local SQL operation failed")
        return [line for line in lines if line]

    def json(self, sql):
        lines = self.execute(sql)
        if len(lines) != 1:
            raise RuntimeError("Unexpected local SQL response")
        return json.loads(lines[0])

    def rpc(self, name, args):
        self.calls.append((name, dict(args)))
        if name != "aftertime_create_direct_with_outbox" or set(args) != set(ARGUMENTS):
            raise ValueError("Unexpected RPC arguments")
        # Only hex is interpolated into SQL. Fixture values are decoded by PostgreSQL.
        payload = json.dumps(args, ensure_ascii=True).encode("utf-8").hex()
        values = []
        for arg in ARGUMENTS:
            cast = ("uuid" if arg in ARGUMENTS[:4] else "timestamptz" if arg == "p_unlock_at"
                    else "bytea" if arg in {"p_digest", "p_nonce", "p_kdf_salt", "p_ciphertext"} else "text")
            values.append(f"{arg} => (j.value->>'{arg}')::{cast}")
        sql = ("SET LOCAL ROLE service_role; SELECT COALESCE(json_agg(row_to_json(result)), '[]'::json) "
               "FROM (SELECT convert_from(decode('" + payload + "','hex'),'UTF8')::jsonb AS value) j "
               "CROSS JOIN LATERAL fixture014i4.aftertime_create_direct_with_outbox("
               + ",".join(values) + ") result; RESET ROLE;")
        return self.json(sql)

    def read_job(self, job_id):
        # Worker has only the columns required by this local fixture.
        query = ("SET LOCAL ROLE aftertime_fixture_worker_014i4; SELECT json_build_object("
                 "'job_id',o.id,'invitation_id',i.id,'capsule_id',i.capsule_id,"
                 "'email',i.intended_email,'key_id',o.key_id,'nonce',encode(o.nonce,'hex'),"
                 "'salt',encode(o.kdf_salt,'hex'),'ciphertext',encode(o.ciphertext,'hex'),"
                 "'digest',encode(i.claim_secret_digest,'hex')) "
                 "FROM fixture014i4.invitation_delivery_outbox o JOIN fixture014i4.direct_capsule_invitations i "
                 "ON i.id=o.invitation_id WHERE o.id='" + str(UUID(job_id)) + "'::uuid; RESET ROLE;")
        return self.json(query)

    def close(self):
        if self.proc.poll() is None:
            try:
                self.proc.stdin.write("ROLLBACK;\n\\q\n")
                self.proc.stdin.flush()
                self.proc.wait(timeout=10)
            except (OSError, subprocess.TimeoutExpired):
                self.proc.kill()
                self.proc.wait(timeout=10)


@pytest.fixture
def local():
    session = LocalSession()
    try:
        yield session
    finally:
        session.close()


def create(local, rpc=None):
    capsule = CreateDirectCapsule(title="synthetic title", body="synthetic fixture body",
                                  recipient_email="recipient014i4@example.invalid",
                                  unlock_at=(datetime.now(timezone.utc) + timedelta(days=1)).isoformat())
    return _create_with_per_invitation_key(
        OWNER, capsule, encryptor_provider=lambda: PerInvitationEncryptor(ROOT, ENV, "v1"),
        rpc=rpc or local.rpc)


def decrypt(job, **changes):
    values = dict(root_key=ROOT, environment_id=ENV, key_version="v1", job_id=UUID(job["job_id"]),
                  invitation_id=UUID(job["invitation_id"]), capsule_id=UUID(job["capsule_id"]),
                  recipient_email=job["email"], salt=bytes.fromhex(job["salt"]),
                  nonce=bytes.fromhex(job["nonce"]), ciphertext=bytes.fromhex(job["ciphertext"]))
    values.update(changes)
    return decrypt_per_invitation(**values)


def verified_claim(job):
    claim = decrypt(job)
    if not hmac.compare_digest(claim.digest(), bytes.fromhex(job["digest"])):
        raise ValueError("Invitation digest mismatch")
    return claim


def count_rows(local):
    return local.json("SELECT json_build_array((SELECT count(*) FROM fixture014i4.direct_capsules),"
                      "(SELECT count(*) FROM fixture014i4.direct_capsule_invitations),"
                      "(SELECT count(*) FROM fixture014i4.invitation_outbox_nonces),"
                      "(SELECT count(*) FROM fixture014i4.invitation_delivery_outbox));")


def test_real_adapter_sql_round_trip_and_restricted_worker(local, caplog):
    signature = local.json("SELECT array_to_json(proargnames[1:pronargs]) FROM pg_proc WHERE oid = "
                           "'public.aftertime_create_direct_with_outbox(uuid,uuid,uuid,uuid,text,text,text,timestamptz,bytea,text,bytea,bytea,bytea)'::regprocedure;")
    assert signature == list(ARGUMENTS)
    result = create(local)
    assert len(local.calls) == 1 and set(local.calls[0][1]) == set(ARGUMENTS)
    args = local.calls[0][1]
    assert str(result.id) == args["p_capsule_id"] and count_rows(local) == [1, 1, 1, 1]
    job = local.read_job(args["p_job_id"])
    claim = verified_claim(job)
    secret = claim.secret.get_secret_value()
    assert secret not in json.dumps(job) + repr(args) + repr(result) + caplog.text
    assert secret.encode("ascii") not in bytes.fromhex(job["ciphertext"])
    assert "synthetic fixture body" not in json.dumps(job)
    privileges = local.json("SELECT json_build_array("
        "has_schema_privilege('anon','fixture014i4','USAGE'),"
        "has_schema_privilege('authenticated','fixture014i4','USAGE'),"
        "has_table_privilege('service_role','fixture014i4.invitation_delivery_outbox','SELECT'),"
        "has_column_privilege('aftertime_fixture_worker_014i4','fixture014i4.invitation_delivery_outbox','ciphertext','SELECT'),"
        "has_table_privilege('aftertime_fixture_worker_014i4','fixture014i4.direct_capsules','SELECT')); ")
    assert privileges == [False, False, False, True, False]
    with pytest.raises(SqlError):
        local.execute("SET LOCAL ROLE anon; SELECT ciphertext FROM fixture014i4.invitation_delivery_outbox; RESET ROLE;")
    with pytest.raises(SqlError):
        local.execute("SET LOCAL ROLE aftertime_fixture_worker_014i4; SELECT body FROM fixture014i4.direct_capsules; RESET ROLE;")


@pytest.mark.parametrize("field", ["root_key", "environment_id", "salt", "nonce", "recipient_email", "ciphertext"])
def test_stored_encrypted_job_rejects_tampering(local, field):
    create(local)
    job = local.read_job(local.calls[0][1]["p_job_id"])
    changes = {"root_key": b"x" * 32, "environment_id": UUID(int=42), "salt": b"s" * 32,
               "nonce": b"n" * 12, "recipient_email": "other@example.invalid", "ciphertext": b"c" * 59}
    with pytest.raises(ValueError, match="^Invalid encrypted invitation$"):
        decrypt(job, **{field: changes[field]})


def test_digest_mismatch_is_detected_after_authentication(local):
    create(local)
    job = local.read_job(local.calls[0][1]["p_job_id"])
    wrong_digest = bytes([bytes.fromhex(job["digest"])[0] ^ 1]) + bytes.fromhex(job["digest"])[1:]
    job["digest"] = wrong_digest.hex()
    with pytest.raises(ValueError, match="^Invitation digest mismatch$"):
        verified_claim(job)


@pytest.mark.parametrize("collision", ["nonce", "salt", "job"])
def test_collision_and_post_reservation_failure_roll_back_atomically(local, collision):
    create(local)
    original = local.calls[0][1]
    params = dict(original, p_capsule_id=str(uuid4()), p_invitation_id=str(uuid4()), p_job_id=str(uuid4()),
                  p_digest="\\x" + os.urandom(32).hex(), p_nonce="\\x" + os.urandom(12).hex(),
                  p_kdf_salt="\\x" + os.urandom(32).hex())
    if collision == "nonce":
        params["p_nonce"] = original["p_nonce"]
    elif collision == "salt":
        params["p_kdf_salt"] = original["p_kdf_salt"]
    else:
        params["p_job_id"] = original["p_job_id"]
    with pytest.raises(SqlError):
        local.rpc("aftertime_create_direct_with_outbox", params)
    assert count_rows(local) == [1, 1, 1, 1]


def test_ambiguous_response_after_real_sql_is_not_retried(local):
    def ambiguous(name, args):
        local.rpc(name, args)
        raise TimeoutError("synthetic uncertain response")
    with pytest.raises(InvitationCreationUnavailable, match="^Invitation creation unavailable$"):
        create(local, rpc=ambiguous)
    assert len(local.calls) == 1 and count_rows(local) == [1, 1, 1, 1]
