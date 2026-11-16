# Phase 4 #014G-2: direct-capsule backend draft

## Current behavior and safety gates

This is an implementation for local review, **not an activated feature**. `DIRECT_CAPSULES_ENABLED` defaults to false; only the case-insensitive string `true` enables the direct HTTP routes. When disabled, they return a generic 404 with `Cache-Control: no-store` before authentication, input validation or database access. No mobile code was changed.

There is a second independent database gate: migration 0006's validated `direct_capsule_invitations_disabled CHECK (false)` remains in place. Therefore, even with the HTTP flag true and migrations 0006/0007 installed, direct creation fails atomically and returns 503. **Do not remove this gate or deploy these drafts** until the identity, abuse and compatibility prerequisites below are resolved. The API flag alone does not enforce database access for trusted service-role callers.

Claim and pending-inbox endpoints always return 503 after authentication, including with the flag enabled; they perform no recipient lookup and there is no claim or discovery RPC. This avoids accepting a JWT email or a non-atomic identity check as authoritative. No active invitation rows can be created under the draft migrations. Consequently, create/cancel/reveal success was verified only in a disposable local database after a test-only, explicitly documented removal of the gate and synthetic binding; those checks do not prove a real claim is authorized.

## Storage and RPCs

Draft migration `0007_direct_capsule_draft.sql` adds a separate RLS-protected `direct_capsules` table. It changes the empty 0006 invitation table's foreign key to point to that table while retaining its disabled constraint. This separate storage keeps the existing self table, owner-list query, recipient constraints, self RPC signatures and response contracts unchanged. The sender's direct text is never stored in the self-capsule table. Both direct tables have no client or service-role table grants; the three `SECURITY DEFINER` RPCs are restricted to service-role execution. Effective privileges and role inheritance in a deployed project remain unverified.

- `aftertime_create_direct_capsule` validates the sender and input, checks server time, creates a direct capsule and its 168-hour tokenless invitation atomically, and returns only ID and timestamps. It never checks whether the recipient email has an account. The retained 0006 constraint rolls back both inserts in the real draft.
- `aftertime_cancel_direct_capsule` requires the sender, locks capsule then invitation, checks server time after waiting, and preserves the first cancellation timestamp for authorized repeats. Cancellation is denied for a new request at or after unlock.
- `aftertime_reveal_direct_capsule` locks capsule then invitation, rejects the sender and anyone other than an already-bound recipient, checks cancellation/deletion and database time, and only then reads the body. An already-bound recipient is not expired merely because the pending invitation's seven days have elapsed. There is no implementation that establishes a valid binding yet.

All RPC identity parameters are trusted backend assertions derived from a verified JWT, not direct request-supplied user IDs. Existing self operations remain in their original tables and functions. Structural expiry constraints are not a complete pending-expiry, revocation or claim implementation. Email normalization across Python, PostgreSQL collations and the Auth provider needs separate verification.

## HTTP routes

All direct routes use the existing JWT verification, generic errors, safe response validation, no-store headers and server-only database credentials. Request validation errors do not echo the body or recipient email. RPC calls do not automatically retry.

| Method and path | Enabled-flag behavior under current migration drafts |
| --- | --- |
| `POST /v1/direct-capsules` | Validates text, timezone and recipient; attempts the create RPC once. Database gate makes this return 503. |
| `GET /v1/direct-capsules/invitations` | 503; no query or unclaimed title/body is returned. |
| `POST /v1/direct-capsules/{id}/claim` | 503; no claim RPC exists. |
| `POST /v1/direct-capsules/{id}/cancel` | Calls the service-only cancellation RPC; unavailable records return generic 404. |
| `GET /v1/direct-capsules/{id}/reveal` | Calls the service-only reveal RPC; unavailable records return generic 404. |

The cancellation/reveal paths have no real eligible direct rows while the gate is intact. `DIRECT_CAPSULES_ENABLED` is a server environment option, not a credential or authorization decision; it must not be exposed as a client-side bypass.

## Tests and limitations

- Backend: `python -m pytest -q` from `services/api` passed **194 tests**, with the existing Starlette TestClient deprecation and synthetic short-HMAC-key warnings. New mocked tests cover flag behavior, authentication, safe projections, request validation, disabled claim/discovery, cancellation/reveal RPC construction and denial, and sanitized failures without retries. An existing route-inventory assertion was updated for the new routes.
- SQL: on a disposable loopback-only PostgreSQL 18 cluster, applied bootstrap/0001-0006, ran the 0006 foundation test, applied 0007, and ran the existing self-creation test plus `test_direct_capsule_draft.sql` and `test_direct_capsule_race.sql`. All passed; the cluster was stopped and removed. The local Auth schema was a stub. The 0006 test must run **before** 0007 because 0007 changes the invitation FK.
- The draft SQL test checks the intact gate, atomic rollback, isolated tables, effective grants/RLS, no claim/discovery RPC, self/direct separation, synthetic recipient-only reveal, sender denial, cancellation and repeat behavior, and bound-recipient behavior after pending expiry. It removes the gate only within a rolled-back local transaction.
- The race test uses two independent local sessions through the locally installed `dblink` extension. It holds a valid pre-unlock cancellation open, starts reveal, passes the unlock boundary, commits cancellation and verifies reveal remains denied. This is one cancellation/reveal ordering, not proof of all races. **The race file commits fixtures and temporarily drops the disabled constraint. Never execute either direct SQL test against Supabase or any shared database.** Its database-name/role guard alone cannot ensure safety.
- Python AST compilation and `git diff --check` were run; no backend linter is configured or installed. No live Supabase request or migration was executed, and no original database was changed.

## Activation blockers

1. Prove the authoritative current-confirmed-email check and actual Supabase Auth email-change, confirmation, deletion and reassignment transaction boundaries. The previously reported row-lock conflict does not prove those provider paths. The localhost confirmation redirect is not proof of success or failure.
2. Design and test atomic claim and safe pending discovery, duplicate claims, pending expiry, cancellation/claim and claim/email-change races, revocation and account-deletion behavior. Do not infer claim status or account existence in sender responses.
3. Add and verify server-enforced abuse limits, a reviewed idempotency policy, recipient normalization and any required report/block controls. Test effective deployed RPC/table privileges, default privileges, direct-table bypasses, race orderings and self regressions in an isolated project before any activation.
4. Review migration 0006/0007 dependencies, catalog drift and operational locks, then separately authorize any isolated live migration. No commit, push or deployment was performed.
