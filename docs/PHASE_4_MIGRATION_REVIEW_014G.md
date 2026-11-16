# Phase 4 #014G-1: dormant direct-recipient foundation review

## Decision and current scope

Prepared `services/api/migrations/0006_dormant_direct_invitation_foundation.sql` and `services/api/tests/sql/test_dormant_direct_foundation.sql`. **Direct capsules and recipient claims are not implemented or enabled.** The user reports that `FOR SHARE` and `FOR UPDATE` conflicted and released as expected in the isolated project; this is useful PostgreSQL evidence, but does not establish that Supabase Auth's actual email-change and confirmation paths use the same row lock or transaction. The user also reports that a final confirmation link redirected to localhost with no listener; that browser error alone proves neither success nor failure of the Auth change.

Because the authoritative current-confirmed-email boundary is unverified, implementing a usable claim would bypass an unresolved security prerequisite. Migration 0006 therefore creates only a dormant structure and must not be treated as authorization to activate the feature or deploy the migration.

## What the migration adds

- `public.direct_capsule_invitations`, a new table linked one-to-one to `public.capsules` by a unique foreign key, with normalized intended email, creation/expiry timestamps and optional claimant UUID/timestamp. It contains no message body, sender-written title, invitation token or notification data. Sender identity would come from the parent capsule, but no sender operation is provided.
- An exact **168 elapsed hour** relation between creation and pending expiry, finite timestamps, basic email normalization, one invitation per referenced capsule, and consistent binding shape. A claimed record can retain its claim timestamp after profile deletion sets its UUID to null; future code must never treat that historical state as pending.
- A validated `CHECK (false)` named `direct_capsule_invitations_disabled`. It rejects all inserts, including inserts by a privileged table owner, unless a later schema change deliberately removes or changes it. RLS is enabled, no policies are added, and privileges are revoked from `PUBLIC`, `anon`, `authenticated` and `service_role`. The migration creates no RPC or API route and grants no access to the new table. Database owners/superusers can change schema and grants; this is not a defense against a malicious administrator.

These are structural constraints only. `claimed_at` does **not** prove a verified email, reject a currently expired invitation, serialize a claim, revoke an invitation, prevent account enumeration or authorize any response. No pending inbox, direct creation, cancellation, direct reveal, idempotency or abuse control exists. Even a pending tokenless row is intentionally impossible until a separate, reviewed activation migration replaces the disabled constraint and adds the missing controls.

## Compatibility and locking

The migration does not alter existing capsule/recipient columns, recipient checks, self-RPC definitions, return projections or grants. The existing tokenless-pending restriction on `public.recipients` remains intact. Self creation, reveal and cancellation continue to use their existing paths; the new table is empty and inaccessible to the application. Its foreign key may take locks during migration and adds a parent-side referential trigger, so operational lock impact and deployed privileges still need isolated verification.

The existing self reveal/cancel RPCs lock capsule then recipient. No new operation or lock sequence is introduced here. **Before any direct row is enabled**, a later design must enforce an unambiguous self/direct discriminator across capsules, recipients, old self RPCs and the owner-list path. The dormant foreign key by itself can point at a self capsule and does not enforce that distinction. Without those changes, enabling rows could permit unsafe old-path behavior or metadata visibility. Future claim, cancellation and reveal code must use a reviewed capsule-then-recipient lock order, recheck authorization and server time after waits, and test both race orders and rollback.

## Verification performed

- On a temporary PostgreSQL 18 cluster bound only to loopback, the existing test bootstrap applied 0001-0003, followed by local application of 0004, 0005 and this draft 0006. Existing `test_create_self_capsule.sql` and the new dormant-foundation SQL test passed. The cluster was stopped and removed. An initial attempt to start it via `pg_ctl start` failed because Windows rejected its restricted token; direct local server startup succeeded. No hosted database was contacted.
- The new SQL test checks self creation, locked and cross-account denial, eligible self reveal, self cancellation and its repeat behavior; effective privileges and actual read denials for anon/authenticated/service role; RLS and the owner-level disabled constraint; seven-day and binding shape, duplicate capsule rejection, and preservation of historical claim state after claimant profile deletion. Structural tests temporarily drop the disabled check **only inside a rolled-back test transaction** in a disposable local database, then verify it was restored. The guard on database name and role is not sufficient to make it safe on a managed project: **never run this test file against Supabase**.
- The backend suite ran locally: **145 passed**, with two warnings from existing dependencies/tests (Starlette TestClient deprecation and a short synthetic HMAC key). `git diff --check` passed with an LF-to-CRLF warning, and a separate trailing-whitespace check passed for the new files. Local tests use a stub Auth schema and do not prove managed Auth behavior, real deployed grants or live concurrency.

## Security blockers and next steps

1. Finish the real supported Auth initiation and each confirmation-stage concurrency test; clarify pending-email, stale JWT, reassignment and account-deletion behavior. The reported row-lock test and localhost redirect are insufficient to declare this complete.
2. Decide the current-email and mailbox-reassignment policy. Design an atomic trusted identity authority that remains valid through claim commit; otherwise keep claims disabled. Verify service-only RPC privileges and real Auth field access without granting clients privileged access.
3. Design and test capsule type isolation and compatibility with all existing self paths; define direct-recipient cancellation/reveal, safe pending metadata, seven-day expiry at the database clock, revocation, deletion and idempotency. No unclaimed response may include the sender-written title or body, and responses must not disclose account existence or claim state to senders.
4. Add transactional race tests for claim/claim, claim/cancel, claim/email-change, deletion, reveal/cancel and expiration/unlock boundaries, plus actual role/table bypass tests. Define enforceable server-side abuse limits before activation.
5. Review actual target schema, legacy data, inherited grants, default privileges and migration rollback/locking on a disposable project before any separately authorized live migration. A local PostgreSQL stub and catalog assertions do not establish hosted effective privileges or provider guarantees.

No original development database, Supabase project, mobile screen, backend application code, commit or push was modified during this task.
