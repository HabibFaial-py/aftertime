# Phase 4 #014I-4: local encrypted outbox integration

## Implemented harness

`services/api/tests/test_local_encrypted_outbox.py` is an opt-in, local-only pytest harness. It fixes the connection to `127.0.0.1:55485`, database `aftertime_rpc_test`, role `postgres`, and verifies that the running PostgreSQL data directory is exactly this workspace's `build/outbox014i1-postgres-014i4`. It clears PostgreSQL environment variables before invoking `psql`, disables `psqlrc`, verifies the listen address and database identity, and refuses to set up the fixture if those checks fail. `services/api/tests/sql/setup_local_encrypted_outbox.sql` repeats the local-cluster checks and verifies the real validated 0006 `CHECK (false)` before writing anything.

Each integration case runs in one rollback-only PostgreSQL transaction. The setup uses a synthetic Auth user, fixture-only tables, a restricted test worker role, and a copy of the draft 0010 function redirected to the fixture tables. The fixture invitation table omits the disabling check; the real `public.direct_capsule_invitations` table and its gate are never altered. The copied creation function is executed as the local `service_role`; a separate no-login worker role has only the specific fixture columns required for retrieval. Tests check effective grants and actual denied reads. The transaction rolls back its schema, fixture records, role and Auth user after each case.

The private Python creation seam generates a real random synthetic invitation secret, derives its SHA-256 digest and per-invitation AES-256-GCM ciphertext, and calls a local `psql` test transport exactly once. The transport verifies the adapter argument names against draft 0010's database signature and invokes the copied function with named arguments and explicit PostgreSQL types. The encrypted job is read under the restricted fixture worker role; the test authenticates/decrypts it with a public synthetic key and compares its digest using `hmac.compare_digest`. No mock success response is inserted into an application route. The public creation stub remains fail-closed, direct flag remains default-off, and claim/discovery and email delivery remain unavailable.

The tests exercise wrong key and environment, altered salt, nonce, email/AAD and ciphertext, digest mismatch, nonce and salt collisions, and an outbox job-ID failure after reservation. Failed SQL calls leave capsule, invitation, nonce reservation and job counts unchanged. An ambiguous-result test performs the real SQL statement and then raises a synthetic timeout; it confirms the adapter does not retry and that the row remains visible **inside the still-uncommitted test transaction**. It does not simulate a committed transaction or prove production lost-response behavior. Tests check that the invitation secret is absent from the returned metadata, fixture retrieval, request representation, captured application logs and ciphertext bytes; no real mail is sent.

## Reproducing locally

Use only a new disposable plain PostgreSQL cluster and synthetic data. The harness is disabled in normal pytest runs. For the verified Windows setup, PostgreSQL 18 tools were at `C:\Program Files\PostgreSQL\18\bin`; create the dedicated `build/outbox014i1-postgres-014i4` cluster with `initdb -U postgres -A trust --no-locale`, bind it **only** to `127.0.0.1:55485`, and create the empty database `aftertime_rpc_test`. In that database run `services/api/tests/sql/bootstrap.sql`, add `deleted_at timestamptz` and `banned_until timestamptz` to the local stub `auth.users`, and apply `services/api/migrations/0004_reveal_self_capsule.sql` through `0010_dormant_invitation_outbox.sql` in order with `psql -X -v ON_ERROR_STOP=1`. Bootstrap already applies 0001–0003. Never target Supabase or another database; the fixture refuses an unmatched cluster. Stop the disposable server when finished.

From `services/api`, run the local test explicitly in PowerShell:

```powershell
$env:AFTERTIME_LOCAL_OUTBOX_TEST='1'
..\..\.venv\Scripts\python.exe -m pytest -q tests/test_local_encrypted_outbox.py
Remove-Item Env:AFTERTIME_LOCAL_OUTBOX_TEST
```

Setting the opt-in variable only enables the harness; it does not override its fixed connection and cluster checks. The synthetic constant key in the test file must never be used outside tests.

## Verification results

- Complete backend suite, from `services/api` with the local opt-in set: **277 passed, 2 existing warnings** (Starlette TestClient deprecation and a test-only short HMAC key). The first opt-in focused run passed **12 tests**; the full run includes the final version of those 12. Without the opt-in, the ordinary suite passed **265 tests with 12 local cases skipped**, before the final test-only access/digest assertions were added.
- Disposable local PostgreSQL 18.6 applied migrations 0001–0010 and passed `services/api/tests/sql/test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. The test Auth table is a simplified local stub. A separate post-test query returned true for fixture schema, worker role and synthetic Auth user removal, and for the real 0006 gate remaining validated.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed. Root Git whitespace and separate untracked-file whitespace checks were run; see `docs/STATUS.md`.
- `initdb` reported Windows restricted-token errors while initializing but exited successfully. Sandboxed server startup failed with restricted-token error 87; elevated localhost startup and stop succeeded. The cluster is stopped; its ignored local data and log remain. No hosted Supabase, production credentials, real email, Android changes, commit or push were used.

## Boundaries and remaining blockers

This fixture proves the reviewed Python code and copied SQL function interoperate inside one local PostgreSQL transaction with the specific synthetic roles and simplified Auth schema. It does not validate a committed transaction, production PostgREST JSON encoding, deployed grants/RLS, network failures, real managed Auth behavior or email delivery. Fixture grants and digest verification are test-only; no production worker or delivery authorization has been implemented. Restricting normal representations and checking test logs does not prove all external logs, crash dumps, backups, WAL or process memory are free of secrets.

The scheme still requires managed key provisioning and rotation, entropy and restore/clone safeguards, independent security review, and an idempotency/reconciliation design for ambiguous outcomes. The draft database function trusts the caller to match ciphertext and digest. Delivery must independently validate the digest and recheck cancellation, deletion, expiry, revocation and claim state. The current claim draft does not establish that the recipient account owns the intended email; identity policy and authorization remain activation blockers. The earlier draft 0010 signature is incompatible with the revised local draft; no hosted migration was made.

**Next development task:** independently review the key/entropy and identity policies, then design a dormant worker authorization and atomic lease/retry protocol that rechecks invitation eligibility and verifies the decrypted digest, including cancellation/deletion and ambiguous-delivery tests. Keep the public stub, feature flag, real database gate and delivery disabled pending separate authorization and security review.
