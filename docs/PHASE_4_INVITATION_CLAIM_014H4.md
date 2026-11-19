# Phase 4 #014H-4: dormant invitation claim foundation

## Outcome and scope

Prepared a draft, gated claim foundation for the approved mailbox-delivered bearer-secret policy. Possession is sufficient to claim into an authenticated account; it does not prove the claimant is the sender's intended person or that the mailbox remains under that person's control. The public claim endpoint remains unavailable, the direct flags were not activated, and the validated 0006 `CHECK (false)` gate remains intact. There is no invitation issuance or delivery, outbox, landing page or mobile integration in this slice. No real invitation or secret was generated or delivered.

Changed files for this slice:

- `services/api/migrations/0009_dormant_invitation_claim.sql` — new draft columns, uniqueness/length checks and service-only claim RPC.
- `services/api/app/direct_capsules.py` and `services/api/tests/test_direct_capsules.py` — dormant request contract and unwired repository call, with mocked tests.
- `services/api/tests/sql/test_dormant_invitation_claim.sql` — guarded disposable-local SQL and race fixture checks.
- `docs/STATUS.md` and this report — results and remaining work.

Existing self-capsule code, migrations 0001–0008, feature gates and earlier uncommitted reports were not modified by this slice.

## Database and API behavior

The proposed invitation secret is 32 cryptographically random bytes, encoded as canonical unpadded base64url; issuance is not implemented. The request model validates encoding and derives a SHA-256 digest of the decoded bytes. The draft migration stores an optional unique 32-byte digest and optional revocation time; the existing 168-hour expiry constraint remains. Claim captures the database clock after locks and requires an unexpired, unrevoked, never-claimed invitation and a noncancelled, nondeleted capsule. It excludes the sender, requires an existing nondeleted/nonbanned Auth row and profile, clears the digest and binds the claimant atomically. A historical `claimed_at` remains terminal after account deletion clears the profile binding. An email change does not update that binding.

The function locks the Auth row, profile, capsule and invitation in that order, retaining capsule-before-invitation ordering. It returns only capsule ID, creation time and unlock time. It is `SECURITY DEFINER`, has an empty search path, revokes public/client execution, and grants execution only to the service role. The trusted backend must supply the verified session subject; the function cannot verify a JWT itself. Managed Auth fields, deletion behavior, privilege inheritance and complete cross-operation lock ordering are not proven by the local Auth stub.

The dormant FastAPI request model rejects extra identity fields and masks its secret representation; its internal repository helper takes a trusted verified subject and sends only the digest to the RPC. A mocked test exercises that helper using the existing JWT verifier. Neither is wired into the public endpoint: with the direct flag enabled, that endpoint still rejects request bodies and returns unavailable for an otherwise valid empty request, with no database call. The disabled middleware gate remains unchanged. No successful public claim is implemented. Hashes are also sensitive while valid; future logging configuration and intermediary handling require review.

## Verification

- Complete backend suite, from `services/api`: `..\..\.venv\Scripts\python.exe -m pytest -q` — **203 passed**, two existing warnings (Starlette TestClient deprecation and a test-only short HMAC key).
- Local PostgreSQL 18: migrations 0001–0009 were applied to a new loopback-only disposable database with a simplified local Auth stub. The 0009 migration succeeded with the real gate intact. The existing `test_create_self_capsule.sql` passed after 0009.
- `test_dormant_invitation_claim.sql` passed locally. It checks actual gated-table insertion failure, RLS/ACL metadata and actual client-role denials. Because the real gate forbids all invitation rows, it copies the claim, cancel and reveal function definitions with table references redirected to separate fixture tables. Those tests cover valid and invalid digest, replay, expired/revoked invitation, cancellation/deletion, sender and ineligible accounts, terminal history, email-change binding, metadata projection, early reveal denial, competing claims, both cancellation orderings, account-deletion orderings, simulated capsule soft-deletion orderings and expiry while waiting for a lock. The fixture contains a matching seven-day expiry check. It is not a successful claim against the actual gated table, and its simplified tables and Auth stub do not establish deployed behavior.
- `git diff --check` passed with line-ending warnings. The SQL test's local-only guards and disposable-cluster setup are not proof that a hosted environment is safe; do not run the SQL fixture against a hosted or shared database.

The loopback database server was stopped after testing; its ignored disposable data directory remains under `build/`. No Supabase connection, hosted migration, Android test or real email delivery was performed. No managed Auth concurrency/session revocation or production role/RLS/storage bypass test was performed. Local synthetic soft-deletion is not a test of an implemented production deletion endpoint, which does not yet exist for direct capsules.

## Remaining blockers and next task

Keep all gates in place. Before any activation, independently verify managed Auth active/deleted/banned account and stale-session behavior, effective deployed privileges, direct table/storage denial, locking and transaction boundaries. Design and implement safe creation and cryptographically random issuance, encrypted transactional outbox and delivery, a protected authenticated claim handoff, rate limits and abuse controls, revocation/deletion and retention policies, and tests for delivery, retries, leakage and real service behavior in a separately authorized isolated environment. A secret or its digest can be copied or stolen; a claimed account remains the recipient even if its email later changes. No mailbox-person identity guarantee is provided.

Recommended next implementation task: prepare a separately scoped **dormant issuance and encrypted transactional outbox** draft with generated random secrets, digest-only invitation storage, a server-key-encrypted delivery payload and local mock delivery tests. Preserve the database/HTTP/mobile gates; do not send email or connect to a hosted service in that slice.
