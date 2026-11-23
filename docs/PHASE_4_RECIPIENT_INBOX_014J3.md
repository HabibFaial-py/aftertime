# Phase 4 #014J-3 recipient inbox and timed reveal

## Implemented contract

- `services/api/migrations/0014_dormant_recipient_inbox.sql` adds a claimed-binding index and a service-only inbox RPC. It replaces the earlier direct reveal RPC in place so the same function name enforces recipient account eligibility. Both functions use an empty search path and grant execution to `service_role` only. Direct table grants, RLS and migration 0006’s validated `CHECK (false)` stay in place.
- `services/api/app/recipient_capsules.py` provides unwired adapters that derive identity from the existing bearer JWT verifier. Each takes a dedicated non-autocommit service connection, calls a fixed parameterized RPC, validates its projection, and releases data only after commit returns successfully. An ambiguous commit yields a generic unavailable error with no automatic retry or provisional data. The adapter reuses the existing claim metadata validation and `CapsuleReveal` response model.
- `services/api/app/direct_capsules.py` removes the old direct reveal HTTP route, which could reach the earlier RPC when the flag was forced on. Recipient inbox and reveal both return 404 through the public API even with the flag forced on. Public claim and discovery stay dormant, the direct flag stays default-off, and the Android Received screen remains presentation-only.
- `services/api/tests/test_recipient_capsules.py` and `services/api/tests/test_local_recipient_capsules.py` exercise the adapters. The Psycopg tests extend the verified delivery and claim fixture. `services/api/tests/sql/test_dormant_recipient_reads_guard.sql` checks actual permissions and self/direct isolation using rollback-only synthetic self-capsule rows.

## Authorization and timing

The inbox returns the capsule UUID, sender UUID, creation time, unlock time and `locked` or `unlocked`. Sender UUID is the only sender field and is projected only for the bound recipient. The response contains no title, body, email or invitation fields at either status. The inbox uses one database statement snapshot, ordered by creation time then capsule ID descending. Pagination defaults to 50 items, allows up to 100, and caps offsets at 10,000. The inbox omits unclaimed, cancelled, deleted or revoked capsules and returns an empty list for an ineligible verified account.

Reveal checks the verified requester’s active Auth row and profile, a claimed invitation bound to that account, sender exclusion, cancellation, deletion and revocation. The SQL uses the claim lock order of Auth row, profile, capsule and invitation. It reads the database wall clock after the locks and selects only the ID and body when `unlock_at <= now`. Locked capsules, missing bindings, ineligible accounts and other denials all return no row. The read changes no rows but needs a read-write PostgreSQL transaction because it takes row locks.

The original invitation expiry limits the claim window. A binding survives that expiry once claimed. A recorded revocation suppresses the binding from both reads. A binding whose profile was removed remains unavailable. The inbox status is advisory metadata and each reveal independently rechecks eligibility using server time.

## Security limits

The tests use signed synthetic JWTs, mocked JWKS retrieval and the local Auth stub. Copied function definitions run against dedicated synthetic tables while the actual invitation table remains gated. Managed Auth account lifecycle and session invalidation, deployed roles and connection configuration still require verification. Inbox pagination is a sequence of snapshots, and concurrent changes can move items between pages. A reveal is authorized at the locked database check. An authorized response already returned to a client cannot be recalled if the account or capsule changes later.

## Local verification

- Applied 0014 over 0013 on verified disposable PostgreSQL 18.6 at `127.0.0.1:55485`, database `aftertime_rpc_test`. The read-only checks before and after verified the exact workspace data directory, loopback binding, validated 0006 gate, empty public direct tables and outbox, and clean fixture state. The already-running cluster was left running.
- From `services/api`, with `AFTERTIME_LOCAL_OUTBOX_TEST=1`, `AFTERTIME_LOCAL_DELIVERY_TEST=1` and `DIRECT_CAPSULES_ENABLED=false`, `..\..\.venv\Scripts\python.exe -m pytest -q` passed **421 tests** with two existing warnings. The focused run passed **116 tests**, including **15 live Psycopg recipient cases** and **12 recipient adapter cases**. These cover claimed and unclaimed rows, cross-account and sender denial, pagination, safe locked metadata, before/after database unlock, cancellation, deletion, revocation, ineligible accounts, a concurrent uncommitted claim, and both sides of read commit ambiguity.
- `psql -X -w -h 127.0.0.1 -p 55485 -U postgres -d aftertime_rpc_test -v ON_ERROR_STOP=1` passed with `-f` for seven SQL regressions under `services/api/tests/sql`. They were `test_dormant_recipient_reads_guard.sql`, `test_dormant_claim_integration_guard.sql`, `test_dormant_dispatch_reservation.sql`, `test_dormant_invitation_worker.sql`, `test_dormant_worker_reliability.sql`, `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. The new SQL regression checked effective permissions and self reveal before and after unlock, plus self/direct isolation.
- `..\..\.venv\Scripts\python.exe -m compileall -q app tests` and Git whitespace checks passed. Existing 0006–0013 migration files and the Android app were unchanged. Earlier uncommitted claim and web work was preserved.

## Next development task

Define and test a separately scoped local authenticated HTTP boundary for the claimed inbox and explicit reveal. Verify `Cache-Control: no-store`, generic denial, and cross-account isolation through that boundary with all production flags still off. Keep Android API wiring for a later slice.
