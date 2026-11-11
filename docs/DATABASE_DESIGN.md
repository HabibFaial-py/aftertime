# Database design

The user reports `0001_initial.sql` applied successfully with RLS and role grants verified. This was not independently checked in the current task. `0002_profile_provisioning.sql` is a local, unexecuted review draft. The sole migration authority is `services/api/migrations`. Migrations assume Supabase's Auth schema and roles; validate new migrations in an isolated matching environment before approval.

## Tables and relationships

- `profiles`: one row per Auth user, keyed by and cascading from `auth.users.id`. Migration 0002 adds automatic provisioning and a backfill; see the provisioning section below.
- `capsules`: owner references a profile. The body, optional private media key and unlock time stay server-side. `timestamptz` represents an instant; the API must accept unambiguous times, use UTC and display local time. Creation requires a future unlock no more than 90 days after `created_at` and limits body length to 2,000 characters. Cancellation and soft deletion have separate timestamps.
- `recipients`: at most one per capsule. Normalized email is lowercase and trimmed; the API must validate email syntax and normalize identically before use. A self capsule uses the owner's verified email and user ID with `claimed_at`, without an invitation hash; a direct capsule uses a random invitation token whose SHA-256 digest alone is stored in the 32-byte hash field. Hash and expiry must appear together; revocation requires a hash; a bound user requires a claim timestamp; opening requires a claim and cannot precede it. A recorded invitation claim must precede expiry and revocation. A claim timestamp may remain after account deletion sets `user_id` to null; it must never by itself authorize access. The database does not enforce creation of a recipient, self ownership, verified email or atomic claim semantics; the API must enforce these transactionally.
- `notifications`: references a recipient and the same capsule through a composite foreign key. The only initial kind is `unlock_email`; adding kinds requires a migration. A unique capsule/recipient/kind identifies a logical job. Leased status requires a lease deadline and no other status permits one; sent status requires `sent_at` and other statuses forbid it; leased, sent and failed jobs require at least one attempt. The worker must atomically lease jobs, increment attempts, clear the lease on transition, recover expired leases, bound retries and check cancellation before sending. Exactly-once delivery is not guaranteed.
- `blocks`: unique directed pair, with self-blocking prohibited.
- `reports`: reporter, capsule, reason and review status. The application must authorize reporting and avoid retaining unnecessary personal data.

UUIDs identify rows; indexes cover owner listings, recipient lookup, job polling and lease recovery, and foreign-key deletion paths. Profile and capsule deletions cascade to related rows; recipient user deletion unlinks claims. Storage objects are outside SQL and must be removed separately before deletion completes. Cascades also remove reports: retention and moderation implications need a decision.

Cancellation must be at or after creation and strictly before unlock; deletion must be at or after creation and cannot precede a recorded cancellation. Both timestamps may coexist. PostgreSQL checks only the stored row values: it does not ensure these timestamps are truthful, prevent later changes, or cancel jobs. The trusted API must use authoritative time and enforce state transitions atomically. PostgreSQL also permits rows without a recipient; creation of the capsule, recipient and job must be transactional. Checks do not verify that a claim actually occurred before expiry or revocation in real time: trusted server logic must check current time and update conditionally under concurrency. Rotation of an invitation after a claim is intentionally unresolved because the stored timestamps refer to one invitation, not a history.

### Recipient states and enforcement

| State | Expected values |
| --- | --- |
| Self | Owner's user ID and claim timestamp; hash, expiry and revocation null. FastAPI verifies the user is the capsule owner. |
| External, unclaimed | Hash and expiry present; user ID and claim timestamp null. Revocation may be null or set. |
| External, claimed | Hash, expiry, user ID and claim timestamp present. Revocation may be recorded after the claim. |
| Account deleted | `user_id` becomes null through `ON DELETE SET NULL`; the claim timestamp may remain. It confers no access. Owner deletion instead cascades through the owned capsule and recipient. |

The database requires either a hash or a claim timestamp, but cannot distinguish self from external recipients or prove identity. A hashless claimed row is therefore not proof of a self capsule. The API must prevent reassignment or a new claim merely because deletion nulled `user_id`, and must implement deletion and retention requirements beyond the foreign key. The migration does not prevent fabricated historical timestamps, token replacement, or deletion of claim data by privileged code.

Both layers have a role in expiry and revocation: CHECK constraints compare stored claim, expiry and revocation timestamps for consistency, without consulting current time or another row. FastAPI must use authoritative server time to require `now < invite_expires_at`, require `invite_revoked_at IS NULL`, validate the hash and verified intended email, and atomically claim only an eligible unclaimed row. Serialize claim and revocation (and deletion/cancellation) so concurrent operations cannot bypass those checks. A later revocation satisfies the stored ordering check but blocks future token use; whether it also revokes an already claimed user's access is an unresolved product decision. These constraints do not decide that policy.

## Access control and assumptions

All six tables enable RLS with **no client policies** and revoke table privileges from `PUBLIC`, `anon` and `authenticated`. Thus normal client roles cannot directly read or write even profiles or safe metadata. Migration 0002 adds only an internal trigger function, with no client execution grants. Verify effective role memberships, inherited/column grants, default privileges, exposed schemas and Storage policies in the target environment; RLS does not protect roles with bypass privileges or table owners. See [Supabase RLS documentation](https://supabase.com/docs/guides/database/postgres/row-level-security) and [PostgreSQL row security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html).

FastAPI verifies JWTs and derives identity from the verified subject; future database operations must apply authorization themselves. The current 0001 file explicitly grants SELECT, INSERT, UPDATE and DELETE on the six tables to `service_role`. A server-only Supabase secret credential uses this role and bypasses RLS; actual connection configuration and authorization tests remain separate work. A dedicated direct PostgreSQL role with explicit privileges and server-role RLS policies is an alternative requiring separate provisioning. Never put database or secret/service credentials in frontend bundles, Git or logs. See [Supabase Data API security](https://supabase.com/docs/guides/api/securing-your-api).

For a Supabase privileged client, the Data API must expose the schema and `service_role` needs schema usage as well as the table grants in 0001. RLS bypass does not itself grant SQL privileges. Verify effective privileges rather than relying on project defaults. Use a separate server-only client without a user session or user Authorization token; Supabase documents that a request carrying a user access token runs under that user's RLS policies even when initialized with a secret key. Verify the user token independently, never forward it into the privileged client, and enforce every user's authorization in FastAPI. See [Supabase RLS bypass](https://supabase.com/docs/guides/database/postgres/row-level-security) and [explicit Data API grants](https://supabase.com/docs/guides/api/securing-your-api).

Before returning body or signing a short-lived private media URL, the API must verify authorization, no cancellation/deletion, and authoritative server time at or after unlock. Never load locked content into a client, and never treat device time or notification delivery as authorization. Verify intended email before claiming, enforce expiration/revocation and block rules, rate limits, image ownership/type/size and EXIF stripping. Creation and job insertion must share a transaction. Enforce concurrent cancellation/reveal and claim rules in transactions. The database constraints alone do not implement these guarantees. Do not log raw tokens, capsule content or sensitive provider errors.

## Profile provisioning: migration 0002

Run after 0001, once, through a trusted `postgres` migration session. The function and trigger deliberately use `CREATE`, not `CREATE OR REPLACE`: a name collision fails for review rather than silently replacing an existing hook. Only the backfill is repeatable. No changes to 0001, table grants, RLS flags or policies are made.

The `AFTER INSERT` row trigger on `auth.users` creates a profile using only `NEW.id`. It runs for every new Auth record, including users whose email is not yet confirmed. A profile's existence is not proof of email confirmation, authentication, consent or access rights. Neither email nor editable user metadata is copied. `display_name` remains null; `created_at` records profile provisioning time, including for backfilled accounts. Existing profiles and names are preserved by `ON CONFLICT (id) DO NOTHING`. The primary key prevents duplicates, including concurrent inserts. The trigger is installed before the backfill, in the same transaction. Auth inserts may briefly wait for migration DDL locks; test concurrent signup behavior in isolation.

### Security and failure behavior

The function is `SECURITY DEFINER`, explicitly owned by `postgres`, uses `search_path = ''`, and references `public.profiles` by its full name. No dynamic SQL, user metadata or client arguments are used. `EXECUTE` is revoked from PUBLIC, anon, authenticated and service_role within the migration transaction. The owner can still administer it; this is an internal trigger, not a supported RPC. Ordinary clients gain no privileges on tables or functions, and no extra profile grants are given to `supabase_auth_admin`. The privileged function owner performs the insert through RLS. Check effective function grants and actual Auth execution in the target-compatible test environment.

This follows the [Supabase user-provisioning pattern](https://supabase.com/docs/guides/auth/managing-user-data). It minimizes new grants, but **the function owner is not a least-privilege role**: `postgres` has broad authority. Its tightly scoped, static body and restricted execution are therefore part of the security boundary. A dedicated NOLOGIN owner with column-level privileges and specific RLS policies is an alternative if stricter owner isolation is required; that needs additional role/policy provisioning and tests and is not introduced in this minimal migration. Do not allow untrusted roles to replace this function or create triggers using it. See [PostgreSQL trigger privileges](https://www.postgresql.org/docs/current/sql-createtrigger.html).

There is no blanket exception handler. Errors other than the handled duplicate ID abort the Auth insert transaction, so signup fails rather than leaving an Auth user without a profile. Supabase may report a generic database signup error; inspect restricted Auth/Postgres logs, fix the trigger and retry. Backfill errors abort the whole migration. Test this failure path before approval. Email confirmation is a later update and does not create a second profile. Deleting an Auth user continues to cascade through the existing foreign key. Deleting only a profile does not cause the INSERT trigger to repair it; use a separately approved backfill if needed.

If a future rollback is needed, first review its effect on signups, then remove only `aftertime_auth_user_created` and its function in a transaction. Preserve existing profiles, their foreign key, and RLS. Do not delete backfilled rows to undo provisioning. Disabling provisioning temporarily permits missing profiles and requires a later reconciliation.

### Verification SQL (not executed)

Use only after approval in a disposable Supabase-compatible environment. Run administrator queries as the trusted migration owner. Keep identity results private. First verify backfill coverage (expected zero) and duplicates (expected no rows):

```sql
SELECT count(*) AS missing_profiles
FROM auth.users AS u
LEFT JOIN public.profiles AS p ON p.id = u.id
WHERE p.id IS NULL;

SELECT id, count(*) FROM public.profiles GROUP BY id HAVING count(*) > 1;
```

Create a disposable test user using the normal Supabase Auth signup flow, not a handcrafted insert into the managed Auth table. Replace the UUID placeholder below with that user's ID; expect one matching profile even before email confirmation. After confirmation, rerun and expect the same profile and timestamp.

```sql
SELECT u.id, p.id AS profile_id, p.display_name, p.created_at
FROM auth.users AS u
LEFT JOIN public.profiles AS p ON p.id = u.id
WHERE u.id = '<test-user-uuid>'::uuid;
```

Repeat the backfill under a rollback-only transaction; expect zero returned rows after successful migration. Confirm no existing profile values changed. This checks idempotence and the duplicate-conflict path; the primary key remains the hard duplicate constraint.

```sql
BEGIN;
INSERT INTO public.profiles (id)
SELECT id FROM auth.users
ON CONFLICT (id) DO NOTHING
RETURNING id;
ROLLBACK;
```

Check owner, security mode, search path and trigger binding (expect postgres, true, an empty search_path setting, and the enabled AFTER INSERT trigger on auth.users):

```sql
SELECT pg_get_userbyid(p.proowner) AS owner, p.prosecdef, p.proconfig
FROM pg_proc AS p
WHERE p.oid = 'public.aftertime_provision_profile()'::regprocedure;

SELECT t.tgenabled, pg_get_triggerdef(t.oid)
FROM pg_trigger AS t
WHERE t.tgrelid = 'auth.users'::regclass
  AND t.tgname = 'aftertime_auth_user_created';

SELECT r.role_name,
       has_function_privilege(r.role_name, 'public.aftertime_provision_profile()', 'EXECUTE') AS can_execute
FROM (VALUES ('anon'), ('authenticated'), ('service_role')) AS r(role_name);
-- All can_execute values must be false.

SELECT r.role_name, v.privilege,
       has_table_privilege(r.role_name, 'public.profiles', v.privilege) AS allowed
FROM (VALUES ('anon'), ('authenticated')) AS r(role_name)
CROSS JOIN (VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) AS v(privilege);
-- All allowed values must be false; also inspect any column grants.

SELECT relrowsecurity FROM pg_class WHERE oid = 'public.profiles'::regclass;
-- Must remain true.
```

As an administrator allowed to assume these roles, run each denial probe separately; the expected permission error aborts its transaction, so issue ROLLBACK afterward. Repeat both probes with `authenticated` instead of `anon`. Verify client table writes and direct function access also fail; do not interpret a trigger-function context error alone as proof of revoked EXECUTE.

```sql
BEGIN;
SET LOCAL ROLE anon;
SELECT id FROM public.profiles LIMIT 1; -- Expected permission denied.
ROLLBACK;

BEGIN;
SET LOCAL ROLE anon;
INSERT INTO public.profiles (id) VALUES ('<test-user-uuid>'::uuid);
-- Expected permission denied, not duplicate key.
ROLLBACK;
```

Before approval, also verify signup failure rolls back the Auth record when profile insertion is intentionally made to fail in a disposable environment, existing-profile conflicts preserve display names, concurrent signup/backfill produces no gaps, and deleting the test Auth user removes its profile. None of these PostgreSQL/Auth tests has been run here.

## Migration and rollback

Do not apply this draft until approved. Review and test it first against a disposable Supabase-compatible PostgreSQL instance, then apply versioned migrations in order through a chosen migration runner, with separate development and beta production projects and backups. No runner is selected yet. Inspect grants, RLS, indexes and existing objects before applying; a transaction is included for atomic DDL. Migration history and deployment credentials must be managed by the eventual runner.

Rollback is destructive: dropping these tables removes capsule data and cascades dependent records, and does not remove storage objects or undo external notifications. Prefer a reviewed forward migration; if rollback is unavoidable, stop writers, back up and verify restoration, handle storage and jobs, and drop dependent tables in reverse order. Never drop `auth.users`. No rollback SQL is supplied.

## Review and open decisions

Static review considered table dependency order, transaction boundaries, primary and foreign keys, uniqueness, nullable CHECK behavior, indexes, default-deny RLS and revoked client grants. This is not a PostgreSQL parser or execution test. **No SQL was executed and no database or access-control tests passed or were run.** The draft is ready for isolated compatibility testing, not cloud application. Test null and boundary cases, deletion with claimed recipients, each notification state, invalid cross-capsule jobs, effective role/column grants and memberships, client bypass attempts, cross-account access, before/at/after unlock, revoked links, clock changes, concurrent operations, retries, storage access and restore.

Decide the migration runner and version tracking, backend connection setup, email normalization and verified-email change behavior, invitation expiry and rotation, whether self capsules need email notifications, job lease fencing and retry limits, and report/deletion retention. Review the profile trigger owner tradeoff in 0002 before approval. Confirm the server-controlled creation/unlock timestamps cannot be manipulated by privileged application paths. Define storage deletion and backup expiry before beta. This design is server-enforced time locking, not end-to-end encryption or permanent preservation.

### Minimal isolated database test plan

After separate authorization, use a disposable Supabase-compatible environment with no real user data:

1. Apply the migration once and verify all six tables, constraints, indexes and RLS settings exist; check the transaction fails cleanly on an intentional error in a disposable run.
2. Insert valid self, unclaimed external and claimed external fixtures; reject hash/expiry mismatches, missing claim for a bound user, invalid claim ordering, duplicate recipients and invalid foreign keys. Delete an external claimed profile and verify `user_id` becomes null without violating checks; delete an owner and verify its capsule and recipient cascade. Verify null claim history alone never authorizes a user in later API tests.
3. As `anon`, attempt SELECT and writes on all six tables and verify access is denied; inspect effective inherited and column grants.
4. Repeat as `authenticated` with two distinct user identities, including attempts to read capsule bodies and recipient fields; verify direct reads and writes are denied.
5. Once the server access strategy and grants are provisioned in the disposable environment, exercise only the needed operations as that server role or via a separate privileged Supabase client. Confirm the secret-key request uses `service_role`, required grants exist, RLS is bypassed for that request, and the same request carrying a user token is denied under client policies. For a dedicated direct role instead, verify its explicit grants and policies. These checks establish database access only; subsequent FastAPI tests must prove per-user and time authorization.
