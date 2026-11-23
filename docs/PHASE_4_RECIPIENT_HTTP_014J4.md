# Phase 4 #014J-4 local authenticated recipient HTTP integration

## Test boundary

`services/api/tests/local_recipient_http.py` builds a separate FastAPI app for in-process HTTP tests. The factory requires `AFTERTIME_LOCAL_DELIVERY_TEST=1`, `AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST=1` and the marker of an active disposable fixture. The existing Psycopg guard checks the exact workspace data directory, fixed loopback address and database, and the validated 0006 `CHECK (false)`. Each request rechecks both opt-ins and the loopback ASGI client address. The normal `app.main:app` startup path has no import or mount for this app, and the test module exposes no ASGI app instance or listener.

| Test request | Contract |
| --- | --- |
| `GET /__local/recipient/capsules` | Returns claimed capsule ID, sender UUID, creation time, unlock time and lock status. The optional `limit` and `offset` follow the 0014 bounds. |
| `POST /__local/recipient/capsules/{capsule_id}/reveal` | An explicit action with no body or query parameters. Returns only ID and body after an authorized, committed reveal. |

The routes reuse the existing bearer dependency and recipient adapters. They derive the subject from the verified JWT. Extra query or body fields are rejected, duplicate pagination is rejected, and identity headers have no effect. A locked or ineligible reveal returns the same `404 Capsule unavailable` as an absent or unbound capsule. Missing and invalid authentication use the existing generic `401` with a bearer challenge. A failed database call or ambiguous commit returns the same `503 Capsule service unavailable`, with no partial result or automatic retry. All test-app responses carry `Cache-Control: no-store` and `Pragma: no-cache`, including errors and disabled responses.

The production application and migrations 0006–0014 were left as they were. Public recipient inbox and direct reveal remain absent, public claim stays dormant, and the default-off direct flag and real invitation gate remain intact.

## Fixture and coverage

`services/api/tests/local_delivery_adapter.py` shares the inbox and reveal connections with the J-3 adapter tests. They run the copied 0014 routines under the fixture service role. `services/api/tests/test_local_recipient_http.py` makes requests through FastAPI `TestClient` and uses synthetic signed JWTs with a mocked JWKS lookup. `services/api/tests/test_recipient_http_isolation.py` checks the opt-ins and confirms the normal API stays isolated even when both opt-ins and the direct flag are forced on.

The live tests check missing and bad JWTs, locked metadata, explicit reveal after database unlock, unclaimed and cross-account denial, cancellation, deletion and revocation, cache protection, and database failures on both sides of commit. Concurrent tests hold an uncommitted ban or deletion, observe the reveal waiting on that account row in PostgreSQL, and verify denial after the account update commits. An inbox snapshot may still reflect the preceding committed account state while the write is pending. Reveal independently rechecks eligibility under its locks.

## Security limits

This boundary ran through an in-process ASGI client against disposable PostgreSQL with an Auth stub. Managed Auth lifecycle and session invalidation, deployed service privileges, actual HTTP transport, and proxy caching and logging remain unverified. The database decision authorizes a reveal at the locked check. A later account or capsule change cannot recall content already returned.

## Local verification

- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q` with `AFTERTIME_LOCAL_OUTBOX_TEST=1`, `AFTERTIME_LOCAL_DELIVERY_TEST=1`, `AFTERTIME_LOCAL_RECIPIENT_HTTP_TEST=1` and `DIRECT_CAPSULES_ENABLED=false` passed **446 tests** with two existing warnings. The focused run passed **25 cases**, including **21 live HTTP/PostgreSQL cases** and **4 isolation and opt-in cases**. Commit ambiguity was simulated by closing a real Psycopg connection before commit or discarding the acknowledgement after commit.
- `psql -X -w -h 127.0.0.1 -p 55485 -U postgres -d aftertime_rpc_test -v ON_ERROR_STOP=1` passed with `-f` for seven SQL regressions under `services/api/tests/sql`. These were `test_dormant_recipient_reads_guard.sql`, `test_dormant_claim_integration_guard.sql`, `test_dormant_dispatch_reservation.sql`, `test_dormant_invitation_worker.sql`, `test_dormant_worker_reliability.sql`, `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. The read-only checks before and after verified PostgreSQL 18.6, the exact workspace data directory, loopback binding, validated 0006 gate, empty public direct tables and outbox, and clean fixture state.
- `..\..\.venv\Scripts\python.exe -m compileall -q app tests` and Git whitespace checks passed. The earlier uncommitted work was preserved, and the already-running disposable database was left running.

## Next development task

Build a presentation-only Android Received prototype using synthetic responses for locked, unlocked, unavailable and explicit reveal states. Keep Android networking and production route wiring outside that slice.
