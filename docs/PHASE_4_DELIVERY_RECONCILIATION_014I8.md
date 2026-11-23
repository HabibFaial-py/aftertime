# Phase 4 #014I-8 local delivery reconciliation

## Identity and state

The outbox job UUID is the stable delivery identity within the fixture’s one provider account and environment. The fake uses that UUID as its optional deduplication key. A provider lookup uses the job UUID and the original dispatch generation to identify one provider attempt. The active lease generation can advance while the original attempt is under reconciliation.

Migration 0012 has leases, retries and completions, but it has no durable record that a provider call may have started. The disposable fixture adds a `dispatch_generation` column and records it in the same transaction as the successful `prepare` check. The coordinator can dispatch only after that transaction reports a successful commit. Reclaiming a marked job takes a fresh fenced lease and looks up the existing provider attempt. Reconciliation leases preserve the dispatch attempt count, including at the retry limit. The fixture clears the marker when it commits a retry after confirmed rejection. The existing terminal transitions clear the encrypted payload and lease.

| Provider result | Local action |
| --- | --- |
| Confirmed acceptance | Request a fenced `sent` transition. If a newer lease fences out that write, report `accepted_unrecorded`. |
| Confirmed rejection | Request a fenced `retry` transition. It schedules database-time backoff or reaches the existing attempt limit. A later eligible poll may make a new attempt with the same job ID. |
| Unknown | Keep the reservation and wait for a later lookup. A timeout, missing provider record, or unavailable lookup falls in this category. |

Acceptance and rejection both recheck eligibility in the final database transition. A cancellation, claim, revocation or expiry visible during recovery can make the job terminal even if the provider previously accepted the request. If a newer generation takes over during lookup, the old generation cannot complete or retry the job. `TransitionOutcomeUnknown` means the commit acknowledgement was unavailable. A later worker observes the committed job state or reconciles the same marked attempt.

## Provider requirements and open issues

- Marking dispatch before calling the provider makes recovery conservative. If a worker crashes after marking and before contacting the provider, a missing provider record leaves the job unresolved until its invitation expires or another terminal eligibility check applies. A real recovery workflow needs a policy for that gap.
- Resolving an ambiguous call without resending requires an authoritative status lookup correlated to the original attempt. A confirmed rejection must establish that the attempt was never accepted and that a delayed duplicate of that attempt can no longer be accepted. The fake enforces that rule for rejected attempts. A temporary absence, lookup outage or delivery bounce gives insufficient evidence for that decision.
- Provider-side idempotency is required to deduplicate repeated submissions at the provider boundary. The fake demonstrates both outcomes by injecting a duplicate request directly. Local reconciliation avoids resending unresolved attempts even with fake deduplication turned off. Verify any real provider’s key scope, retention and behavior after timeouts and restore before relying on it.
- The fake provider’s state lives in memory. Worker recovery tests recreate the coordinator while keeping the fake account. The database tests close a real driver connection before commit or inject a lost acknowledgement after commit. They do not intercept PostgreSQL’s wire response. A provider acceptance after the last eligibility check can still race with cancellation or expiry.

Only the guarded PostgreSQL fixture gained the new state. The public schema and migration 0006 gate remain in place. The production worker is fail-closed, `DIRECT_CAPSULES_ENABLED=false` was used for validation, and public claim and discovery remain dormant. The integration uses synthetic keys and the in-memory transport on the disposable loopback database.

## Local verification

Use the verified disposable PostgreSQL 18.6 cluster at `127.0.0.1:55485`, database `aftertime_rpc_test`, with migrations through 0012 and the local Auth stub. Run the pytest and SQL suites sequentially because they share fixture names. The focused run of `tests/test_local_delivery_adapter.py` passed **33 tests**. It covers acceptance followed by a lost acknowledgement, confirmed rejection, timeout and missing status, crash recovery, duplicate submissions, stale lookup fencing, terminal eligibility and commit ambiguity.

Run the backend commands from `services/api` in PowerShell with the pinned local-test dependencies and no inherited `PG*` overrides.

```powershell
$env:DIRECT_CAPSULES_ENABLED = 'false'
$env:AFTERTIME_LOCAL_OUTBOX_TEST = '1'
$env:AFTERTIME_LOCAL_DELIVERY_TEST = '1'
..\..\.venv\Scripts\python.exe -m pytest -q
..\..\.venv\Scripts\python.exe -m compileall -q app tests
```

- The full backend suite passed **333 tests**, including the 33 local delivery cases and 12 encrypted-outbox cases, with the two existing Starlette HTTPX `TestClient` and short test HMAC key warnings. Python compilation passed.
- `psql -X -w -h 127.0.0.1 -p 55485 -U postgres -d aftertime_rpc_test -v ON_ERROR_STOP=1` passed with `-f` for `test_dormant_invitation_worker.sql`, `test_dormant_worker_reliability.sql`, `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql` under `services/api/tests/sql`. The read-only preflight and postflight checked the exact data directory, loopback binding, 0006 gate, empty public invitation and outbox tables, absence of a public dispatch marker and clean fixture state. The already-running cluster was left running.
- Git whitespace checks passed for tracked and untracked files with only Windows line-ending warnings. The existing uncommitted #014I-6 report edit and #014I-7R report and dependency pins were preserved.

## Next development task

Specify and review a dormant database contract for committing a dispatch reservation and resolving the same attempt under the current lease. Define the retry budget, unresolved-job retention and operator actions, and the provider guarantees required before any activation work.
