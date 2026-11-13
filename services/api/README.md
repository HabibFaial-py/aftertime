# AfterTime API

The API exposes `GET /health`, `GET /v1/auth/me`, `GET`/`POST /v1/capsules`,
and `GET /v1/capsules/{capsule_id}/reveal`.
Use Python 3.11 and the existing virtual environment at the repository root.
Run these commands in PowerShell from the repository root:

```powershell
.\.venv\Scripts\python.exe -m pip install -r services/api/requirements-lock.txt
Set-Location services/api
..\..\.venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

Visit http://127.0.0.1:8000/health. Stop the server with Ctrl+C.
To run the test, from the repository root:

```powershell
Set-Location services/api
..\..\.venv\Scripts\python.exe -m pytest
```

`requirements.txt` lists the direct dependencies; the lock file pins their
resolved dependencies for reproducible installation.

## Authentication

`GET /v1/auth/me` accepts a Supabase user access token in a Bearer header and returns only `{"id": "<verified subject>"}`. The API reads process environment variables; it does not automatically load `.env` files. Set these in the PowerShell session before starting the server, using your own development project values:

```powershell
$env:SUPABASE_URL = 'https://your-project.supabase.co'
$env:SUPABASE_PUBLISHABLE_KEY = 'your-publishable-key'
$env:SUPABASE_JWT_ISSUER = 'https://your-project.supabase.co/auth/v1'
$env:SUPABASE_JWT_AUDIENCE = 'authenticated'
```

Confirm the issuer and audience against your project configuration. The URL must be HTTPS and the issuer must match its `/auth/v1` path. The publishable key is required configuration but is not used by the JWKS verification path. Do not put service credentials in these variables or commit local values. `/health` works without auth configuration.

The verifier accepts ES256 and RS256 only, fetching the project's public keys from `/auth/v1/.well-known/jwks.json`; it verifies signature, issuer, audience, expiry and UUID subject. Key sets are cached in process for five minutes by PyJWT, in addition to Supabase's edge cache, so revoked keys may remain usable until caches expire. Unknown keys trigger a refresh subject to PyJWT's cooldown. Key-service failures return 503; invalid tokens return 401. This verifies a token locally and does not check whether a session has since been revoked or a user deleted.

Check the project's actual signing algorithm and key configuration before using this endpoint. Legacy HS256 tokens are rejected: Supabase recommends verifying those via its Auth server `/auth/v1/user`, which this slice does not implement. Never use the publishable key as a JWT signing secret. See [Supabase JWT verification](https://supabase.com/docs/guides/auth/jwts) and [signing-key caching](https://supabase.com/docs/guides/auth/signing-keys).

## Server-only database access (Phase 2, Part 1)

`app/database.py` contains a minimal `DatabaseRepository` for Supabase's PostgreSQL
Data API. It reuses pinned HTTPX 0.28.1; no dependencies or lockfile changes were
needed. This is HTTPS/PostgREST access, not a direct PostgreSQL/SQLAlchemy connection.
It provides a read-only connectivity check, owner-filtered listing, and self-capsule creation and reveal RPC calls.

Compatibility review (2026-11-12): the current [Python initialization reference](https://supabase.com/docs/reference/python/initializing)
accepts a project URL and key, and the [Python server example](https://supabase.com/docs/reference/python/admin-api)
explicitly uses a secret key with session persistence and refresh disabled.
The full SDK supports this approach, but is unnecessary for this bounded read.
We use the existing HTTPX client directly, following [Supabase key guidance](https://supabase.com/docs/guides/getting-started/api-keys):
send `sb_secret_*` in `apikey`, not as a Bearer JWT. No SDK version is installed or
claimed tested. Legacy service-role JWTs and publishable keys are rejected by our
database configuration. No fallback to a weaker credential is attempted.

`get_database_settings()` reads `SUPABASE_URL` and `SUPABASE_SECRET_KEY` only when
the repository is constructed. Authentication settings and `app/auth.py` remain
independent. The URL must be an HTTPS origin on the default/443 port without
userinfo, path, query or fragment. Validation checks key type and header-safe
syntax; it cannot prove that a key exists, is unrevoked or belongs to the project.
The secret is excluded from the settings representation. `.env.example` contains
only a deliberately invalid placeholder, and `.env` files are not auto-loaded.

The repository creates and closes its own HTTP client, accepts no user JWTs or
incoming request headers, and has no sign-in/session API. It uses TLS validation,
five-second HTTP operation timeouts, no redirects, no retries and no environment
proxies. `/health` and `/v1/auth/me` never construct this client. No unrestricted
query proxy is exposed.

### Create a self-capsule

`POST /v1/capsules` requires the same verified Bearer JWT as `/v1/auth/me`.
Send JSON with exactly `title`, `body`, and `unlock_at`; unknown fields including
owner, recipient and email are rejected. Text must be nonblank, body is limited
to 2,000 Unicode characters, and the timestamp must be an ISO 8601 string with
seconds and `Z` or a numeric `+/-HH:MM` offset. The API converts it to UTC and
checks it is in the next 90 days using server time. The RPC repeats its checks
using database time, which is authoritative; close boundary requests can fail
as time passes or clocks differ. No title maximum exists in the schema.

The verified JWT subject is the sole owner argument sent to the one atomic RPC;
no user token is forwarded into the privileged client. On success, HTTP 201
returns only `id`, `title`, `unlock_at`, and `created_at` (timestamps in UTC).
Invalid input is 422 with a fixed response, missing/invalid authentication is
401, an ineligible owner reported by the RPC is 403, and unavailable/malformed
database responses are 503. Errors omit request values and provider details.
`/health` remains independent of database configuration. An unconfirmed or
missing Auth user/profile is ineligible under the RPC.

No automatic retry is performed. A timeout can happen after the transaction
committed, so a caller may not know if a capsule was created; idempotency and
rate limiting are not implemented and need separate design before beta. This
endpoint does not return capsule bodies or implement read/reveal/notifications.
Do not enable HTTP body or credential logging. Existing tests mock the Data API;
they do not validate a live creation or transactional behavior.

The read-only check sends `HEAD /rest/v1/profiles?select=id&limit=1` with
`Accept-Profile: public`. It checks access to an existing table even if empty,
requests no row body or count, and returns no records. Only HTTP 200/206 is success;
permission errors, revoked keys, redirects and outages fail with a fixed message.
Provider error bodies and exception details are never printed or logged by this
code. Do not add request/header dumps, environment dumps or credential-bearing
tracing to privileged operations.

Secret keys run as `service_role` and bypass RLS. Existing schema/table grants
are still required. All future user-specific repository calls must enforce
authorization explicitly using the identity from the FastAPI JWT verifier before
retrieving data. This check does not prove RLS isolation, cross-account safety,
write privileges, transaction behavior or reveal authorization. Future atomic
capsule/job creation needs a separately designed transaction boundary; several
Data API requests are not one transaction. Migrations and RLS remain unchanged.

### Offline verification

From the repository root in PowerShell:

```powershell
Set-Location services/api
..\..\.venv\Scripts\python.exe -m pytest -q
..\..\.venv\Scripts\python.exe -m pip check
```

Database tests replace HTTP transport with mocks and use dummy keys. They cover
missing/invalid config, successful reads, permission/provider failures, redirects,
connection failures/timeouts, sanitized output, resource cleanup and independent
API behavior. No live database connection is made by these tests.

### Safe live connectivity test (manual, not run in this task)

After separate authorization, use the development project only. Confirm that
the existing `SUPABASE_URL` points to that project, the Data API exposes `public`,
and `service_role` has schema usage and SELECT on `public.profiles`. Do not change
RLS or grants to make the check pass. Obtain an existing server secret through
your trusted project settings; never paste it into chat, source files or a shell
command. Keep the existing Auth environment variables as configured above.

In a dedicated backend PowerShell terminal, run these commands from the repository
root. The secure prompt keeps the key out of terminal echo and command history;
the backend process inherits it from that terminal. Do not run with debug tracing or
environment capture enabled.

```powershell
Set-Location services/api
$databaseSecretInput = Read-Host 'Development Supabase server secret' -AsSecureString
$databaseSecretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($databaseSecretInput)
try {
    $env:SUPABASE_SECRET_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($databaseSecretPointer)
    ..\..\.venv\Scripts\python.exe -m app.check_database
    Write-Output "Connectivity command exit code: $LASTEXITCODE"
} finally {
    Remove-Item Env:SUPABASE_SECRET_KEY -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($databaseSecretPointer)
    $databaseSecretInput.Dispose()
}
```

Exit 0 prints `Database connectivity check passed.`; exit 1 prints only
`Database connectivity check failed.`; exit 2 reports missing/invalid configuration.
For failures, privately verify the project URL, key type/revocation, Data API/schema
settings, grants and network availability; do not print the key or raw provider
response. Record the actual result in STATUS. Live connectivity has not been
tested as part of this implementation.

### List owned capsules

`GET /v1/capsules` requires a verified Bearer JWT and returns a JSON array. Each
item has exactly `id`, `title`, `created_at`, `unlock_at`, and `status`. UTC
timestamps use ISO 8601. Status is `locked` before `unlock_at` and `unlocked`
at or after it, calculated once per request using the API server clock. An
unlocked status does not itself authorize content access.

The privileged repository filters by the verified JWT subject (`owner_id`),
requires `deleted_at` and `cancelled_at` to be null, and selects only
`id,title,created_at,unlock_at`. Cancellation is not an API operation yet;
cancelled rows are omitted so they cannot be mislabeled as unlocked. The query
does not fetch body, media, email, invitation or token data. No client-supplied
owner parameter is used, and no user JWT is forwarded to the privileged client.
RLS and grants are unchanged. Provider failures return a fixed 503.

Optional query parameters: `limit` (1–50, default 50) and `offset` (0–10000,
default 0). Ordering is `created_at` descending, then `id` descending. An empty
page returns `[]`; a full page does not guarantee a next page. Offset pagination
is not a snapshot: inserts/deletes between requests can shift items, and offsets
past 10000 are rejected. Malformed parameters return 422. Client clocks never
determine status, but the API host clock must be maintained accurately. Future
reveal must independently enforce server time, authorization, cancellation and
deletion. Mock tests verify the query and filtering behavior; they do not prove
live PostgREST or cross-account security. See [PostgREST filtering and ordering](https://docs.postgrest.org/en/stable/references/api/tables_views.html).

## Prompt #009A: atomic self-capsule migration

`POST /v1/capsules` is implemented. Migration 0003 defines the approved
creation RPC. The user reports migrations 0001-0003 applied to a disposable
Supabase test project; they have not been applied or executed by this agent.
The current repository uses
the Data API, where each request has its own transaction. Two inserts followed
by a compensating delete cannot guarantee atomicity: the recipient insert or
cleanup could fail after the capsule commits. See [PostgREST transactions](https://docs.postgrest.org/en/stable/references/transactions.html).

The existing schema requires a nonblank title but specifies no title maximum.
It permits an empty body, so the new operation must additionally enforce nonblank
body text and the existing 2,000-character maximum. Unlock time must be greater
than created time and at most 90 days later. Self-recipients require the owner's
profile ID, a non-null claim timestamp, and a normalized nonempty intended email;
invitation hash, expiry and revocation stay null. Profiles do not store email,
and `current_user` returns only the verified UUID subject.

New migration: `services/api/migrations/0003_create_self_capsule.sql`.
It leaves 0001 and 0002, all table definitions, table grants and RLS unchanged.
It adds only a narrowly scoped
`public.aftertime_create_self_capsule(p_owner_id uuid, p_title text, p_body text,
p_unlock_at timestamptz)` function and its execution permissions:

1. Use a VOLATILE PL/pgSQL function, SECURITY DEFINER owned by postgres,
   `search_path = ''`, fully qualified references and UTC timezone. Revoke
   EXECUTE from PUBLIC, anon and authenticated; grant it only to service_role
   (apart from the administrative owner). Apply creation and permission changes
   within the migration transaction. This follows the existing trigger's owner
   convention but retains a powerful owner; the static function body and narrow
   execution permission need explicit review. No dynamic SQL or arbitrary table
   or column arguments. See [Supabase function security](https://supabase.com/docs/guides/database/functions).
2. FastAPI supplies `p_owner_id` exclusively from `current_user`, never from
   request JSON. The RPC trusts this backend assertion; the privileged request
   does not carry the end-user JWT, so `auth.uid()` is not the user's identity.
   Read the matching `auth.users` row and existing profile; fail closed if absent
   or if email is missing/unconfirmed. Use `lower(btrim(auth.users.email))` for
   intended_email, checking `email_confirmed_at`; never accept an email argument
   or read user-editable metadata. Hold an appropriate row lock while using the
   Auth row so concurrent updates/deletion cannot invalidate this check mid-write.
3. Validate nonblank title/body, body length and non-null finite unlock time.
   Capture database `clock_timestamp()` once after identity checks, enforce
   `now < unlock_at <= now + interval '90 days'` in UTC, and use that same instant
   for capsule created_at and recipient claimed_at. API validation must reject
   naive timestamps before converting to UTC; timestamptz alone cannot detect
   that the original input omitted an offset.
4. Insert the capsule with the verified owner and null media, cancellation and
   deletion fields. Insert exactly one recipient with the new capsule ID,
   user_id equal to owner_id, normalized email and claimed_at; leave all invite
   fields and opened_at null. Let any failure abort the whole RPC transaction.
   Do not catch an error and return success after only one insert. No notifications.
5. Return an explicit table projection of only capsule ID, title, unlock_at and
   created_at. Never return a capsule row/composite type, body, email or tokens.
   Call it with one privileged POST from the repository, with no automatic retry.

Public contract: authenticated `POST /v1/capsules`
accepts only `title`, `body`, and an offset-aware `unlock_at`; extra properties
including owner/recipient IDs are rejected. Return 201 with `id`, `title`,
`unlock_at` and `created_at` in UTC. Validation errors must omit echoed input
values (including body), and database failures must use fixed safe messages.
Validation/authentication remain separate from repository HTTP calls.

Isolated database tests and separate application approval are required before enabling writes: prove
both rows roll back on an injected recipient failure, deny direct anon and
authenticated RPC execution, verify missing/unconfirmed identity handling, and
test time boundaries alongside the requested API tests. Mock HTTP tests alone
cannot prove PostgreSQL rollback. A timeout after commit can still leave the
caller uncertain whether creation succeeded; atomicity does not give retry
idempotency. Do not retry automatically or promise duplicate prevention without
a separately reviewed idempotency design.

### Disposable PostgreSQL verification

No PostgreSQL runtime was available in this session: `psql`, `postgres` and
`pg_ctl` were absent from PATH, and Docker context inspection failed because its
configuration was inaccessible. The SQL below is supplied for execution later;
it has not passed a PostgreSQL parser or runtime test here.

Run from the repository root on a machine with Docker running. These commands
create a new disposable **plain PostgreSQL** container, with no host ports,
external network or volumes. Local container connections use trust authentication;
no credentials or API keys are needed. Do not point these tests at Supabase or any
existing database. `docker run` deliberately fails if the container name exists.
The image must be available locally (download `postgres:17` separately if needed).

```powershell
docker run --pull=never --name aftertime-rpc-test --network none -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_DB=aftertime_rpc_test -d postgres:17
docker exec aftertime-rpc-test pg_isready -U postgres -d aftertime_rpc_test
# Wait until pg_isready reports accepting connections before continuing.
docker cp services/api aftertime-rpc-test:/work
docker exec aftertime-rpc-test psql -X -v ON_ERROR_STOP=1 -U postgres -d aftertime_rpc_test -f /work/tests/sql/bootstrap.sql
docker exec aftertime-rpc-test psql -X -v ON_ERROR_STOP=1 -U postgres -d aftertime_rpc_test -f /work/tests/sql/test_create_self_capsule.sql
# After inspecting results, remove only this disposable container:
docker rm -f aftertime-rpc-test
```

Check each command's exit code before proceeding. `bootstrap.sql` requires an
empty database named `aftertime_rpc_test`, creates minimal test-only Auth columns
and roles, and applies migrations 0001 through 0003. It is not a replacement for
Supabase's managed Auth schema. Do not rerun bootstrap in the same database.

`test_create_self_capsule.sql` wraps fixture changes in a transaction and rolls
them back. It checks a successful call as service_role with a 2,000-character body
and a near-90-day unlock, exact safe result keys, owner/recipient association,
email normalization, null invitation/media fields, and no notifications. Negative
cases include missing/unconfirmed owners, absent profiles/emails, null/empty/blank
title/body, oversized body, null/infinite/past/present/over-90-day unlock times.
A temporary trigger proves the capsule insert occurred before forcing the
recipient insert to fail, then checks both table counts are unchanged. It also
checks function ownership/settings, effective and explicit EXECUTE ACLs, actual
anon/authenticated call denials, and retained RLS flags. Expected exceptions are
caught inside test subtransactions; unexpected outcomes stop the script.

The SQLSTATEs for explicit validation are `22023` (invalid input) and `42501`
(ineligible owner), with fixed messages and no supplied values. Other database
errors may contain private PostgreSQL details: the eventual API must sanitize
them and must not echo validation inputs or log RPC arguments. A timestamptz
argument represents an instant but cannot identify whether its original input
was naive; offset requirements remain a future API responsibility. The function
sets UTC for interval calculation; timestamp display still follows the caller's
session timezone after it returns.

Before deployment, repeat privilege and transaction checks in a disposable
Supabase-compatible environment, including Auth row update/deletion contention
and PostgREST schema-cache visibility. The postgres SECURITY DEFINER owner retains
broad authority (as in migration 0002); administrative owners/superusers cannot
be excluded by an EXECUTE revoke. The only ordinary role explicitly granted
execution is service_role. Review inherited/default grants in the target project.

### Supabase Dashboard SQL Editor verification

For the separate disposable Supabase project with migrations 0001-0003 already
applied, copy **`services/api/tests/sql/test_create_self_capsule_sql_editor.sql`**
into the SQL Editor. Do not copy bootstrap.sql or the original psql test script.
This alternative has been reviewed statically only; it has not been executed here.

Original script compatibility review:

- `bootstrap.sql` uses psql-only `\set` and `\ir`, creates roles that already exist
  in Supabase, creates a mock `auth` schema/table, and assumes an empty database
  named `aftertime_rpc_test`. Its included migrations contain BEGIN/COMMIT and
  would attempt to recreate existing objects. It must never run on Supabase.
- `test_create_self_capsule.sql` uses psql-only `\set` and `\echo`, the same database
  name assumption, fixed user UUIDs, and direct writes to the simplified Auth
  table. Its profile DELETE can cascade through application data if adapted
  carelessly. It uses global row counts and assumes notifications are empty.
  Its failure trigger rejects every recipient insert while installed; the DROP
  statements remove that helper/trigger. BEGIN/ROLLBACK and SET LOCAL ROLE are
  valid PostgreSQL, but the file is designed to run as one psql session after
  bootstrap, not as separately selected SQL Editor fragments.
- Migration 0003 contains valid PostgreSQL SQL and no psql commands. Do not rerun
  it for this test: it deliberately uses CREATE, and it is already applied.

Preparation and expected results:

1. Confirm the selected project is the **disposable test project**, and use an
   idle project during the run. The script cannot infer whether a project is
   production. No SQL database-name check can establish that on hosted Supabase.
2. Through Supabase Auth/Dashboard, prepare one dedicated, confirmed email test
   user with its automatically provisioned profile. Do not use a real person's
   account. The script does not fabricate, modify or delete managed Auth rows.
   Set `v_owner` and `v_expected_email` at the top to that user's UUID and exact
   email. These are test identifiers, not credentials; no API key is required.
3. Select the **postgres** SQL Editor role. Copy and execute the **entire file**
   as one query. It is one DO statement; there are no psql commands, file includes,
   role creation, migration application, explicit commits, or DELETE cleanup.
4. Expect successful completion with no returned rows. If the UI exposes NOTICE
   messages, the final notice starts `PASS: creation, safe metadata, validation,
   privileges, atomic rollback and cleanup.` Any ERROR means failure or a blocked
   prerequisite; do not change grants to make a failing test pass.

The test checks real service_role creation, exactly four safe response fields,
the self-recipient relationship, scoped notification absence, input/time/owner
validation, ACLs and actual anon/authenticated denials. All writes are inside a
PL/pgSQL exception subtransaction: successful tests deliberately raise/catch a
private cleanup signal to roll back their changes. Unexpected errors abort the
DO statement. The script verifies that its successful capsule and unique helper
objects no longer exist before reporting PASS. The pre-existing test Auth user
and profile are retained; there is no cleanup DELETE against them or other users.

To test second-insert failure, it briefly creates a randomly named, uncommitted
helper function and a trigger on `public.recipients`, restricted to the dedicated
test owner's UUID. Both disappear through rollback. No existing function is
replaced, no table/RLS definition or grants are weakened, and other users' records
are not targets. Trigger DDL still takes a table lock: the test sets a three-second
lock timeout and restores it, but can briefly block concurrent writers. Run only
on the idle disposable project and rerun later if a lock timeout occurs.

Limitations: this checks PostgreSQL behavior, not JWT verification, HTTP error
sanitization, PostgREST routing/schema-cache behavior, or retry idempotency. It
does not create missing-email/unconfirmed-user fixtures or mutate managed Auth
to exercise those branches; the original isolated mock-Auth suite covers them.
It checks safely separated time cases, not a deterministic exact 90-day boundary.
No credentials or database connections were accessed to prepare this script.

### Reveal a self-capsule

`GET /v1/capsules/{capsule_id}/reveal` requires the existing verified Bearer JWT
and a UUID path. It accepts no query parameters. On success it returns exactly
`{"id": "<uuid>", "body": "<text>"}`. The repository makes one privileged POST
to migration 0004's RPC with the verified subject and capsule ID; the user JWT
is not forwarded, and no capsule table/body query or API-clock unlock decision
is made. The RPC checks owner, self-recipient, cancellation, deletion and database
time. No automatic retry is performed.

Missing/invalid authentication returns 401; malformed IDs and query parameters
return fixed 422 errors. Locked, missing, cross-user, cancelled, deleted and
non-self capsules all return `404 {"detail":"Capsule unavailable"}`. Database
configuration, network or malformed/unexpected RPC responses return a fixed 503.
All reveal responses, including errors, carry `Cache-Control: no-store` and
`Pragma: no-cache`. Never log request authorization, response bodies, RPC
payloads or provider errors; configure reverse proxies and monitoring accordingly.

The user reports migration 0004 was tested in a disposable project and applied to
development. Mock tests here do not verify the live RPC, locking or effective
database privileges. The verified backend subject is trusted by the server-role
RPC; a leaked privileged key or other privileged code can bypass this boundary.
The JWT verifier does not immediately detect revoked sessions. Race behavior,
live before/at/after unlock checks, cache behavior through intermediaries and
rate limiting still require verification before broader use.

## Prompt #011B: self-capsule reveal RPC

Migration `0004_reveal_self_capsule.sql` adds
`public.aftertime_reveal_self_capsule(p_capsule_id uuid, p_requester_id uuid)`.
It returns zero rows for missing, cross-owner, locked, cancelled, deleted, or
non-self capsules, and exactly `id, body` for an eligible self capsule. It does
not expose title, media, email, recipient or invitation fields. This is a
database function. The user reports 0004 tested in a disposable Supabase project
and applied to development; these live results were not independently verified here.

The backend must derive `p_requester_id` from the verified JWT, never client
input, and pass it over the separate service-role client without forwarding a
user JWT. The function trusts that assertion. PostgreSQL verifies matching owner
and a bound, claimed recipient with null invitation hash/expiry/revocation. A
hashless claimed row is not independently proof of self-creation: privileged
writers must preserve this invariant. The first query locks only capsule metadata
with `FOR SHARE`; the second locks the matching recipient. It captures
`clock_timestamp()` **after** lock acquisition and reads body only after all
checks, permitting equality at the unlock instant. Both locks survive until the
transaction ends. New cancellation, deletion and recipient writers must lock in
the same order: capsule, then recipient. Under READ COMMITTED a locking read that
waits on a concurrent update re-evaluates the row; stronger isolation may instead
raise a serialization failure. Either must fail closed. These guarantees end when
the transaction commits; a subsequent deletion cannot recall content already sent.

The function is VOLATILE, SECURITY DEFINER, owned by postgres with an empty
search_path; PUBLIC, anon and authenticated lose EXECUTE and service_role gets
EXECUTE. As in 0003, the postgres owner is broad and can bypass RLS. Existing
service_role table grants also permit privileged direct reads; this function
cannot contain a compromised key or another backend code path. Never pass user
tokens into the privileged client, expose the key, log bodies/arguments/provider
errors, or cache reveal results. The future FastAPI endpoint should validate
UUIDs, map all no-row denials to the same 404, sanitize database/UUID errors,
and use `Cache-Control: no-store`. A malformed SQL UUID cast can itself produce
an error; HTTP validation and sanitization remain the future API's responsibility.

The row locks require a read-write PostgreSQL transaction. The future public
endpoint is GET and calls this VOLATILE RPC with a backend **POST** to
PostgREST: a GET RPC runs in a read-only transaction. Do not forward a client
authorization header. See [PostgREST transactions](https://docs.postgrest.org/en/stable/references/transactions.html)
and [PostgreSQL row locks](https://www.postgresql.org/docs/current/explicit-locking.html).

### Disposable Supabase SQL Editor test

Only after review, in the separate **idle disposable SQL-test project**, apply
0004 as postgres once; do not run it against the development or production
project as part of these tests. Then copy the entire file
`services/api/tests/sql/test_reveal_self_capsule_sql_editor.sql` into the SQL
Editor. Select postgres and replace `v_owner` and `v_other` with UUIDs of two
distinct dedicated test users with provisioned profiles. The script cannot detect
whether a project is disposable. It creates synthetic capsule and recipient
fixtures inside a rollback-only subtransaction; it never changes Auth users and
no fixture is committed. Expected: success/no rows, and a PASS notice if the UI
shows notices. Any error is a failure. Do not paste only a selection of the DO
block. The test obtains row locks; the project should have no concurrent traffic.

The script checks permitted response and exact output keys, wrong owner, locked,
cancelled, deleted, missing capsule/recipient, unbound historical claim,
invitation-backed recipient, null arguments, and at-or-after unlock. It checks
effective EXECUTE grants, ownership/security settings, all six RLS flags,
direct client body SELECT denial and actual anon/authenticated RPC denials.
Fixtures are rolled back even on success. It sets an unlock to the current clock
and then calls immediately: this demonstrates at-or-after, not exact-microsecond
equality. Its cases do not prove live PostgREST transport or concurrency.

### Required two-session concurrency checks

In that same isolated test project, prepare an eligible self-capsule fixture
owned by a dedicated test account; use **only that disposable fixture**. Replace
`<CAPSULE_UUID>` and `<OWNER_UUID>` below with its IDs. Use two independent
trusted SQL sessions (for example two separate `psql` connections, not two
requests whose session affinity is unknown). Use synthetic body text only. The
fixture must already be committed and unlocked, with no cancellation/deletion.
Do not print or save the function result. These tests need real concurrent
connections; a single SQL Editor DO block does not provide that guarantee.

1. In session A, run the following and keep the transaction open:

   ```sql
   BEGIN;
   SET LOCAL ROLE service_role;
   SELECT count(*) FROM public.aftertime_reveal_self_capsule('<CAPSULE_UUID>'::uuid, '<OWNER_UUID>'::uuid);
   -- Expect 1; keep the transaction open so its row locks remain held.
   ```

   While A is open, in session B run:

   ```sql
   BEGIN;
   SET LOCAL lock_timeout = '2s';
   UPDATE public.capsules SET deleted_at = clock_timestamp() WHERE id = '<CAPSULE_UUID>'::uuid;
   -- Expect lock timeout; ROLLBACK the failed transaction.
   ROLLBACK;
   ```

   Afterward issue `ROLLBACK` in A. Repeat with a recipient update/delete to
   verify its row lock, then repeat with cancellation using a still-locked
   fixture and a timestamp satisfying 0001's constraints. For that locked
   fixture the RPC returns zero rows but still holds both locks until A ends.
   Never commit those updates. A failed transaction must be rolled back before reuse.

2. Reverse the order with an eligible, synthetic fixture: in session B start a
   transaction and update its `deleted_at`; keep B open. In A begin, set the
   same two-second local lock timeout and call the RPC as service_role. Expect a
   timeout and no result/body. Roll back A and B. Repeat with a recipient
   unbinding and a still-locked cancellation fixture. For a writer-commits-first
   check, commit only the synthetic fixture's deletion in B in the disposable
   project, then call the RPC in A and expect zero rows; remove the synthetic
   fixture later using that environment's approved cleanup procedure. Test
   concurrent unlock-time updates as well. Under stronger isolation, record a
   serialization failure as a fail-closed outcome, not as a successful reveal.

These scripts were not executed in this task. SQL errors, timeouts, exact
microsecond boundary behavior, live PostgREST role/transport, effective inherited
grants, SQL statement logging, and concurrent races require real isolated
verification before implementation or deployment of reveal. The previous
creation and listing API tests do not prove these properties.
