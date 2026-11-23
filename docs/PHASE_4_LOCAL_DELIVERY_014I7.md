# Phase 4 #014I-7R local delivery integration

## Recovery and implementation

The interrupted session left a Psycopg adapter, an in-memory fake provider, 12 opt-in tests and pinned local-test dependencies. The branch tip was `1669077`, which aligns the legacy worker SQL regression with migration 0012. The existing uncommitted edit to the #014I-6 report was preserved. The first recovered run stopped at the database guard because PostgreSQL returned `127.0.0.1/32` for the text cast of its `inet` address. The guard now checks `host(inet_server_addr())`. All 12 recovered cases passed after that fix.

The adapter lives under `services/api/tests`. It requires an explicit opt-in, rejects inherited `PG*` settings and redirected data paths, and checks the fixed loopback address, port, database, role, exact workspace data directory and validated invitation gate in a read-only transaction before any fixture write. Tests reuse the #014I-4 synthetic setup. Fixture creation, worker and actor calls use copied functions, and separate connections can see the committed fixture. The worker executes those calls as the existing `NOLOGIN` worker role. Fixture teardown checks its run marker and synthetic user identities in one transaction.

The test coordinator looks up candidate IDs, leases one job, and uses the lease token and generation for `prepare` and each subsequent transition. It waits for the committed `prepare` acknowledgement and closes the database connection before decrypting the AES-GCM envelope, checking its SHA-256 digest and dispatching to the in-memory fake. A confirmed acceptance leads to `sent`, a definite rejection schedules `retry`, and invalid ciphertext or digest leads to terminal `failed`. A fake provider timeout leaves the lease in place without resending during that invocation. The existing production `run_delivery()` remains fail-closed. The direct flag stayed false for validation, the public claim and discovery routes stayed dormant, and the real 0006 gate stayed validated.

## Transaction and delivery behavior

- The integration tests close a real Psycopg connection before commit to exercise rollback, and close it after a real commit and inject a timeout to simulate a lost caller acknowledgement. These are controlled faults around commit. Both raise `TransitionOutcomeUnknown`. The tests independently read the database to distinguish the two outcomes for `lease`, `prepare` and `sent`. At `lease` and `prepare` no dispatch follows. At `sent` the fake has already accepted once, and the invocation issues no second send or completion attempt.
- Cancellation, claim and revocation before `prepare` block dispatch and clear the outbox ciphertext. A cancellation committed after `prepare` can still allow fake acceptance, while the copied claim RPC denies the late claim. If a newer generation leases the job before stale completion, the old worker cannot record `sent`. It reports `accepted_unrecorded` if the fake accepted and the completion RPC returned no row.
- Explicitly running the job again after a simulated provider timeout and lease expiry can submit the same logical job twice. An in-memory fake configured to deduplicate by job ID accepts it once. The fake with deduplication disabled accepts both sends. Fake provider state lives only within the test process.

## Local verification

The disposable PostgreSQL 18.6 server was already running before recovery at `127.0.0.1:55485`, database `aftertime_rpc_test`, data directory `build/outbox014i1-postgres-014i4`. Use an idle copy of that verified cluster with migrations through 0012 and the existing local Auth stub. Run the pytest and SQL suites sequentially because they reuse fixture names. To run pytest, use the existing backend virtual environment with the optional pins from `services/api/requirements-local-test-lock.txt` and no `PG*` overrides. The installed Psycopg 3.3.9 binary, typing extensions 4.16.0 and tzdata 2026.6 matched the recovered lock on Windows with Python 3.11.

Run these commands from `services/api` in PowerShell.

```powershell
$env:DIRECT_CAPSULES_ENABLED = 'false'
$env:AFTERTIME_LOCAL_OUTBOX_TEST = '1'
$env:AFTERTIME_LOCAL_DELIVERY_TEST = '1'
..\..\.venv\Scripts\python.exe -m pytest -q
..\..\.venv\Scripts\python.exe -m compileall -q app tests
```

- Full backend pytest passed **319 tests**, including the **19** local delivery cases and **12** encrypted-outbox cases. The two existing warnings are the Starlette HTTPX `TestClient` deprecation and the short HMAC key in an auth test. Python compilation passed.
- `psql -X -w -h 127.0.0.1 -p 55485 -U postgres -d aftertime_rpc_test -v ON_ERROR_STOP=1` passed with `-f` for `test_dormant_invitation_worker.sql`, `test_dormant_worker_reliability.sql`, `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql` under `services/api/tests/sql`. A read-only check in that session verified the cluster before those scripts and confirmed the 0006 gate, empty public invitation and outbox tables, and removal of the temporary schema, user fixtures, role and `dblink` afterward.
- Git whitespace checks covered tracked edits and untracked #014I-7 files. The tracked and untracked checks emitted only Windows line-ending warnings. The attempted `pg_ctl start` was denied access to the log and did not start a new server. The verified cluster was already running and was left running.

## Remaining limits and next step

The copied functions and local Auth stub cover the driver transaction boundary and database fencing. The tests simulate acknowledgement loss above the driver and do not intercept the PostgreSQL wire response. Production role provisioning, managed Auth identity and session behavior, key lifecycle and restore fencing still need verification. Cancellation and lease expiry can race with acceptance after the final check. Fake deduplication supplies no evidence about a real provider’s acceptance, persistence, or idempotency guarantees.

The next development step is to implement and test a local reconciliation policy that checks status by stable job ID after an ambiguous send or completion. Give it explicit outcomes for confirmed acceptance, confirmed rejection and unresolved delivery. Review that policy together with the intended-recipient identity and cancellation rules before wiring a production worker.
