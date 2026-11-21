# Phase 4 #014H-5: dormant invitation progress

## Session overview

Reviewed the committed #014H-4 claim foundation and added an independently usable, but unwired, invitation-secret generator. Direct capsules and public claiming remain disabled. No Supabase connection, hosted migration, email delivery, Android change, commit or push occurred. The approved policy is a mailbox-delivered bearer secret: possession permits an authenticated account to claim; it does not establish the claimant's identity or current email address.

## Existing 0009 implementation review

- Migration 0009 adds a nullable unique `bytea` digest, constrained to 32 bytes when present, and a revocation timestamp. The 0006 invitation table's validated `CHECK (false)` remains; the 0007 create RPC cannot create an invitation through it and does not issue a secret. The 0008 pending-email index does not enable discovery.
- The draft claim RPC accepts a capsule ID, trusted backend-supplied claimant ID and digest. It locks the eligible Auth row and profile, then the capsule and invitation. It excludes the sender and requires an existing profile and an Auth row that is neither deleted nor currently banned. It does not check that the account email matches the intended mailbox. It checks the digest, unclaimed and unrevoked state, cancellation/deletion, and creation/expiry using database time captured after lock waits. The existing expiry constraint is 168 hours.
- The RPC atomically binds the account, records `claimed_at` and clears the digest. `claimed_at` prevents re-claim after a profile deletion clears the binding. It returns only ID and timestamps. Row locks serialize competing claims and coordinate with the tested cancellation ordering. It is postgres-owned `SECURITY DEFINER` with empty search path; public, anon and authenticated execution are revoked, and service-role execution is granted. It relies on the backend to verify the JWT and supply its subject, not on the RPC to authenticate the caller.
- The existing request model strictly validates canonical unpadded base64url encoding of 32 bytes, masks normal representations, forbids extra fields and hashes decoded bytes with SHA-256. The repository helper is unwired and sends only the digest to the RPC. Its verified-subject and request behavior have mock tests. The public claim route remains unwired: when enabled, it rejects bodies and returns 503 for an authenticated empty request without a database call; the default flag blocks direct routes before authentication. Pending discovery is also unavailable.
- This session's local SQL verifies the real gate and local role denials, but successful claims and races use copied function bodies redirected to separate fixture tables, because the real gate forbids invitation rows. The Auth table is a simplified local stub. These checks do not prove managed Auth lifecycle, session revocation, deployed grants, PostgREST behavior or a successful claim against the real gated table.

## New implementation changes

`generate_invitation_secret` requests exactly 32 bytes from Python's `secrets.token_bytes`, encodes them as canonical unpadded base64url and returns the existing masked `DirectClaimRequest`; its existing `digest()` computes SHA-256 of the raw bytes. It propagates random-source failure without a fallback. It performs no database, network, delivery or logging operation, and is not connected to any route or creation flow. The object contains the secret in process memory and its value can be explicitly retrieved; masking is not encryption or a substitute for careful handling. A future caller must not serialize, log or expose it and must safely handle errors.

Focused tests use a controlled byte source to verify the exact byte count, encoding and digest, and exercise the real random source and failure propagation. A pair of different samples is a smoke check, not proof of entropy quality. Existing claim contract and mocked repository tests remain in place. No dependency or schema changes were made.

## Files created/modified

- `services/api/app/direct_capsules.py` — dormant generation helper.
- `services/api/tests/test_direct_capsules.py` — generation and failure tests.
- `docs/PHASE_4_INVITATION_PROGRESS_014H5.md` — this report.
- `docs/STATUS.md` — session results and next task.

## Test results and limitations

- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **205 passed**, two existing warnings (Starlette TestClient deprecation and test-only short HMAC key).
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q tests/test_direct_capsules.py -k 'claim or invitation_secret'`: **15 passed, 45 deselected**, one existing Starlette warning. HTTP/repository tests use mocks; they are not deployed authorization tests.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed.
- PostgreSQL 18: initialized a new disposable local cluster at `build/claim014h4-postgres-014h5`, bound to `127.0.0.1:55484`, and applied bootstrap and migrations 0001–0009 only there, with `deleted_at` and `banned_until` added to the stub Auth table. `test_create_self_capsule.sql` and `test_dormant_invitation_claim.sql` passed. The latter tests local permissions, gate failure, copied-function claim cases and competing-claim/cancellation/deletion/expiry races. The cluster was stopped; its ignored data and log remain. Initial sandboxed server startup failed due to a Windows restricted-token error; elevated local startup and stop succeeded.
- `git diff --check`: passed; Git does not include untracked files in that check. The new report was also checked for trailing whitespace separately.

## Security status and blockers

The flag still defaults false, the database gate and service-only RPC permissions are unchanged, and public claim/discovery remain unavailable. No plaintext invitation is persisted or sent by this change. Digests are sensitive while valid. Secure delivery requires an encrypted transactional outbox, server-only managed key and authenticated encryption with context, restricted access, retention and key lifecycle; a digest alone cannot deliver the secret. Creation must atomically associate the digest and protected delivery job, and must not return the secret to the sender. Secure link handling, authenticated explicit POST, sanitized errors and logs, rate limits, cancellation/revocation, deletion, abuse controls and monitoring remain required.

Before activation, independently verify managed Auth eligibility and deletion/session races, complete lock ordering, deployed effective grants and direct database/storage denial, RPC/PostgREST transaction boundaries, delivery and leakage behavior, and the other security prerequisites. Local fixtures and mocks do not establish these properties. No activation or hosted migration is authorized by this session.

## Concrete next implementation task

In a separately scoped dormant slice, design and implement atomic creation of a digest and an authenticated-encrypted delivery job using a reviewed server-side key lifecycle, with local mock-delivery and rollback/retry/leakage tests. Keep the helper unwired until that protected path exists; preserve every database, API and mobile gate and do not send email or access hosted services without authorization.
