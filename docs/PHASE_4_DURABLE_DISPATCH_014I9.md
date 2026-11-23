# Phase 4 #014I-9 durable dispatch reconciliation

Migration [0013](../services/api/migrations/0013_dormant_dispatch_reservation.sql) adds `dispatch_generation` to the dormant outbox. It requires the validated 0006 `CHECK (false)` and an empty outbox so the upgrade cannot treat an older ambiguous delivery as fresh. It grants the existing `NOLOGIN` worker role access to the v3 transition and revokes its v2 access. The Python adapter exposes acknowledgements after commit. The production `run_delivery()` still fails closed, and direct capsules, public claim and discovery remain disabled.

## Dispatch contract

| Operation | Result and effect |
| --- | --- |
| `lease` | Acquires a 60-second database-time lease with a fresh token and increasing generation. It consumes an attempt only for a job without a dispatch marker. |
| `prepare` | Rechecks eligibility and returns the encrypted envelope for an unreserved job. A marked job returns `reconcile` with the original dispatch generation and no envelope. |
| `reserve` | After local decryption and digest verification, rechecks eligibility and records the active generation as the dispatch attempt. `reserved` authorizes one submission after a successful commit. The transaction requests synchronous commit. A repeated reservation returns `reconcile` and does not authorize another submission. |
| `accept` | Records `sent` for a confirmed acceptance of the exact reserved attempt. |
| `reject` | Clears the reservation and schedules database-time backoff after a confirmed rejection. The delay is 30, 60, 120 or 240 seconds. Confirmed rejection of the fifth attempt makes the job `failed`. |
| `fail` | Allows terminal failure for invalid payload or another local failure before a dispatch reservation. |

The outbox UUID is the stable job identity. The provider attempt is identified by this UUID and its original dispatch generation, scoped to the provider account and environment. To resolve it, a worker supplies that dispatch generation as well as the current lease token and generation. A stale worker cannot record a result after lease expiry or takeover. Results are provisional until the transaction commits. A missing acknowledgement raises `TransitionOutcomeUnknown` and leads to no immediate provider call or retry. Only `prepare` for an unreserved job returns the encrypted envelope. The SQL contract never takes a plaintext invitation secret.

The transition retains capsule, invitation, then outbox lock order, using `SKIP LOCKED` and database time after the locks. Committed cancellation, soft deletion, claim or revocation makes a pending job `cancelled` at the next eligible check. Invitation expiry makes it `expired`. Terminal results clear ciphertext and the lease. Hard deletion cascades to the outbox through its invitation foreign key. A competing actor transaction can temporarily make a transition inapplicable, and a later check sees the committed state. Neither the locks nor the lease cover external provider contact after the reservation commits.

## Recovery and limits

- A crash before reservation leaves the job eligible for a fresh lease while the attempt budget lasts. A crash after reservation and before provider contact can leave the job unresolved because a missing provider record is inconclusive.
- After provider acceptance with a lost response, a replacement worker can use authoritative lookup for the original attempt and record `sent`. An unavailable lookup or provider timeout leaves the marker in place. The worker can look up the marked attempt again after lease expiry without spending another dispatch attempt or resending. A fifth attempt can still reconcile. An unreserved job with no attempts left becomes `failed`.
- SQL relies on the trusted caller to supply accurate provider outcomes. A provider rejection must establish that the attempt was never accepted and that a delayed submission of it cannot be accepted. Provider-side idempotency is necessary to deduplicate submissions at the provider boundary. The fake models both capabilities with in-memory state, and its outcomes do not establish a real provider’s guarantees.
- Cancellation or expiry can race with a send after the reservation transaction commits. An accepted email cannot be recalled. Clearing ciphertext from a row does not remove copies in WAL or backups. Storage durability, restore fencing, managed Auth and provider key scope and retention require independent review.

## Local verification

- Applied 0013 over 0012 on the verified disposable PostgreSQL 18.6 cluster at `127.0.0.1:55485`, database `aftertime_rpc_test`. A read-only preflight checked the exact workspace data directory, loopback binding, validated 0006 gate, empty public outbox and clean fixture state. The postflight confirmed the gate and fixture cleanup, and the already-running cluster was left running.
- From the root, `psql -X -w -h 127.0.0.1 -p 55485 -U postgres -d aftertime_rpc_test -v ON_ERROR_STOP=1` passed with `-f` for 0013 and five regressions under `services/api/tests/sql`. The regressions were `test_dormant_dispatch_reservation.sql`, `test_dormant_invitation_worker.sql`, `test_dormant_worker_reliability.sql`, `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. The new SQL regression checks the real constraint and effective permissions, including the denied legacy transition. The older regression scripts keep testing copied legacy functions and check grants appropriate to the installed migration.
- From `services/api`, with `AFTERTIME_LOCAL_OUTBOX_TEST=1`, `AFTERTIME_LOCAL_DELIVERY_TEST=1` and `DIRECT_CAPSULES_ENABLED=false`, `..\..\.venv\Scripts\python.exe -m pytest -q` passed **348 tests**, including **44** real-driver delivery cases and **12** encrypted-outbox cases. The two existing warnings concern Starlette HTTPX `TestClient` and a short test HMAC key. The Psycopg tests run the installed v3 definition against synthetic fixture tables through the restricted role. They check reservation commit visibility, sync commit configuration, duplicate reservation, stale transitions, actor locks, deleted jobs, the fifth attempt, and both sides of commit ambiguity. They also verify that reservation and recovery results exclude the envelope and that the synthetic secret is absent from captured application logs.
- `..\..\.venv\Scripts\python.exe -m compileall -q app tests` passed. Git whitespace checks passed for tracked and untracked files with Windows line-ending warnings only.

## Next development task

Define the operator workflow for unresolved attempts, including retention, alerting and the evidence required to resolve or abandon an attempt. Before any production wiring, validate a candidate provider’s attempt lookup and idempotency guarantees against that workflow and review the remaining cancellation and identity requirements.
