# Phase 4 Prompt #014C — security prerequisites for verified-email capsules

**Status: static review and verification plan, not an executable migration.** This document distinguishes repository evidence from proposed behavior and deployed-provider questions. No SQL, server, Supabase or external service was contacted during this review. The previous architecture and 014B schema design remain proposals except for the user's stated MVP rules; their implementation details and numerical limits are not approved merely because they appear in a document.

## 1. Database inventory

### Repository facts

| Area | What migrations 0001–0005 specify |
| --- | --- |
| Capsule | `capsules` stores owner/profile FK, title, body, optional media key, unlock, creation, cancellation and deletion times. Checks enforce nonblank title, body length at most 2,000, future unlock no later than 90 days after creation, and cancellation strictly before unlock. |
| Recipient | `recipients.capsule_id` is unique, so there is at most one recipient per capsule. `intended_email` is nonblank and `lower(btrim(...))`; optional `user_id` references `profiles` with `ON DELETE SET NULL`. Token hash is unique and, if present, 32 bytes. Token expiry/revocation, claim and open timestamps have consistency checks. `(id, capsule_id)` is unique for the notification FK. |
| Invitation constraints | A token hash and `invite_expires_at` must both be null or both nonnull; `invite_revoked_at` requires a token hash; a bound user requires `claimed_at`; a tokenless row requires `claimed_at`. Token-based claim time must be before expiry and revocation. These checks prevent tokenless pending rows and prohibit reusing token expiry/revocation columns directly for them. Migration 0001 did not explicitly name the checks. |
| Profile and deletion | `profiles.id` references `auth.users` with `ON DELETE CASCADE`; capsule owner deletion cascades to owned capsules, while deleting a bound recipient profile sets `recipients.user_id` null. Migration 0002 inserts profiles after Auth-user creation and backfills existing Auth users. The SQL test bootstrap provides a simplified fake `auth.users`, not the real provider implementation. |
| RLS and grants | 0001 enables RLS on all six application tables, creates no client policies, revokes table privileges from `PUBLIC`, `anon` and `authenticated`, and grants table CRUD to `service_role`. Source does not prove effective deployed grants, inherited/default privileges or Storage policies. The service role is a privileged bypass boundary. |
| Self creation | `public.aftertime_create_self_capsule(uuid, text, text, timestamptz)` checks sender `auth.users.email` and `email_confirmed_at`, joins the profile and selects `FOR SHARE OF u, p`; it inserts a capsule and a recipient already bound to the owner. It returns `id, title, unlock_at, created_at`. |
| Self reveal | `public.aftertime_reveal_self_capsule(uuid, uuid)` requires owner and claimed recipient to be the same verified backend-supplied subject, with invitation fields null. It locks capsule then recipient `FOR SHARE`, captures database wall clock after locks, and returns only `id, body` after unlock. |
| Self cancel | `public.aftertime_cancel_self_capsule(uuid, uuid)` locks capsule `FOR UPDATE`, then recipient `FOR SHARE`; requires the same self binding, nondeleted capsule and, for a new cancellation, database time before unlock. Authorized repeats return the original `id, cancelled_at`, including after unlock, subject to its existing checks. |
| Function boundary | The self RPCs are declared postgres-owned `SECURITY DEFINER` with empty `search_path`, explicit revocation from public client roles and EXECUTE granted to `service_role`. The profile trigger function is separately revoked from client roles and service role. The backend supplies a verified JWT subject as a trusted argument; the privileged PostgREST call is not the end user's Auth session. |
| Existing API | FastAPI JWT verification checks ES256/RS256 signature, issuer, audience, expiry and UUID subject. Its dependency returns the subject, not a currently confirmed email. The service repository uses server-only privileged access; owner listing selects metadata and filters cancelled/deleted rows, with no self/direct discriminator. No direct claim or recipient reveal API exists. |

### Proposed constraint and compatibility work

The 014B proposal introduces explicit self/direct discrimination, an independently represented tokenless seven-day pending lifecycle, and type-consistent capsule/recipient relationships. At minimum it must replace the tokenless-must-be-claimed check with a carefully scoped direct-pending exception; it must retain the existing token hash/expiry pair and token revocation checks, using separate direct expiry/revocation fields or another reviewed representation. Preserve all unrelated checks, uniqueness, foreign keys and old self rows. Any check replacement must use names obtained from each target catalog and compare its actual definition first, not guess generated names.

**Compatibility risk:** adding direct rows while old self RPCs and the owner list remain unaware of type can leak direct metadata into the old self UI or make a direct row eligible for a self operation in unexpected states. A safe type discriminator and filters for existing self reveal, cancel and list must be designed and regression-tested before direct records or routes are enabled. Preserve their signatures, self behavior, return projections and privileges. Migration 0003 omits proposed new columns, so defaults and constraints must also preserve self insertion.

### Deployed facts and pre-migration abort conditions

The files are source evidence, not proof of the actual isolated, development or beta catalogs. Only under separate authorization, take a read-only inventory using a least-privilege reviewed procedure that reports aggregate classifications and catalog definitions, never body, raw email or tokens. Confirm migration history, columns/types/defaults, real check names and expressions, unique/FK constraints, indexes, triggers, function signatures/owners/security flags/search paths, RLS policies, grants, role inheritance, extension availability and relevant storage permissions. Compare against the expected migration lineage and the exact proposed migration target.

**Abort rather than silently repair or classify** if there is schema drift, unknown effective client access, unexpected function/trigger definitions, missing prerequisite migrations, conflicting object names, or ambiguous data. Inventory at least: token-backed recipients, tokenless unbound historical claims, rows without recipients, recipients whose binding differs from owner, unknown/manual invitation rows, duplicate/conflicting relationships or nonconforming records. A historical self row with a null `user_id` may be legitimate after deletion; it must not be automatically rebound, discarded or necessarily reclassified as invalid. If a safe classification/backfill policy for any category is not approved, abort. Also abort if constraints are unvalidated, normalization assumptions differ, existing direct/token activity is unknown, or the target is not independently confirmed disposable for the initial test. Investigate anomalies separately; do not print or export private row values.

## 2. Auth identity authority — unresolved provider evidence

**Verified locally:** self creation reads `auth.users.id`, `email`, `email_confirmed_at` and a profile row. `0002` only shows insertion provisioning. Neither this code nor the stub proves how actual Auth email changes, pending confirmation, reconfirmation, account deletion, email reuse or identity-provider flows behave.

**Proposed requirement:** after validating the requester JWT, obtain the requester's **current confirmed email** from an authoritative server-side source, normalize it consistently with intended-email storage, and compare it inside an atomic claim authorization boundary. Never accept email verification, owner/recipient IDs or a stale token's email as a client assertion. Current confirmation of mailbox control is not proof of the same natural person's ownership at invitation creation. A newly reassigned mailbox could satisfy a current-email-only check.

Provider-specific fields and states must be discovered and verified in an isolated project rather than assumed. The investigation must establish the meaning and update order of the current email, confirmation timestamps, pending new/old-email change and confirmation state, identities, and any account-disabled/deletion flags relevant to the deployed Auth version. Verify behavior for email sign-up, already confirmed accounts, pending and completed email changes, unconfirmation, account deletion/recreation, alternate identity providers and email reuse. Do not rely solely on the existence of `email_confirmed_at` or assume that every pending change invalidates an old address.

**Candidate lock, not established guarantee:** a service-only RPC could lock the relevant `auth.users` row, read the authoritative fields, then hold it through pending discovery or claim. Its sufficiency depends on whether **every** relevant Auth email-change, confirmation, identity-reassignment and deletion path updates/locks that same row before making identity effective, with compatible transaction boundaries. Local stubs cannot prove this. Identify actual transactions, constraints, row locks, cascades and provider-supported alternatives in an independently authorized isolated test. If any path is external, asynchronous or does not conflict with the proposed lock, the approach is not proven safe; block activation until a different provider-supported protocol is designed.

The intended guarantee should be stated at a transaction linearization point: the matching confirmed identity and claim are valid when the protected transaction commits. Locks cannot guarantee an email remains unchanged forever after commit, nor prevent a response already authorized from arriving after a subsequent change. Define later access by the bound UUID and separately approved revocation/deletion rules. For discovery, a single consistent transaction is needed; whether it provides the intended identity snapshot must be proved. Avoid claiming an absolute no-leak guarantee across a later Auth state transition.

**Privileges:** investigate whether a postgres-owned SECURITY DEFINER can minimally read and acquire the needed Auth locks in the deployed platform, the effect of Auth schema grants and RLS, SECURITY DEFINER ownership, `search_path`, schema USAGE, `EXECUTE` ACLs and role inheritance. Do not grant client roles `auth.users` or broad access to bypass a failed design. A server-side service key can bypass RLS and accepts backend-asserted requester UUIDs; its isolation and backend authorization remain essential. Privilege adequacy, unsupported managed-schema modifications and upgrade behavior are unverified blockers.

## 3. Concurrency and lock-order analysis

The 014B candidate order is admission → Auth identity → profile → capsule → recipient → future job. This is a **hypothesis**, not a demonstrated global order. The repository proves only: 0003 selects Auth and profile `FOR SHARE OF u, p` in a joined query; it does not document a guaranteed global acquisition order for those two relations. 0004 locks capsule `FOR SHARE` then recipient `FOR SHARE`; 0005 locks capsule `FOR UPDATE` then recipient `FOR SHARE`. 0002's Auth insert trigger writes a profile. FK enforcement, owner cascade, recipient `SET NULL`, notification cascade, account deletion and Supabase Auth's own transactions can acquire additional locks. An Auth → profile → capsule → recipient order can still conflict with a reverse-order trigger, FK or provider path. Do not assert absence of deadlocks or assume grant/lock behavior from the simplified bootstrap.

After separate authorization, use **two independent database sessions** and dedicated disposable users/fixtures; use controlled transactions and bounded lock timeouts. Observe safe state/results only, never reveal body or email in logs. Repeat both commit orders and rollback, and classify timeouts, deadlocks or serialization errors as fail-closed outcomes:

1. **Claim vs claim:** same invitation by same and distinct verified users; only the intended verified UUID can bind, at most once; repeats follow the approved idempotency rule.
2. **Claim vs cancellation:** hold capsule or recipient locks in each order; cancellation committed first denies claim; a prior claim does not prevent eligible owner cancellation. Test rollback and seven-day expiry while waiting.
3. **Claim/discovery vs email change:** exercise the actual Auth-supported change and confirmation paths, in both orders, including pending change and a stale JWT. Prove whether the candidate Auth lock conflicts through commit. Do not simulate a row update and assume it represents all provider paths.
4. **Claim vs account deletion:** exercise actual user/profile deletion and relevant FK cascades in both orders. Ensure no rebinding of a historical null `user_id`, no metadata/body after committed deletion, and no unexpected lock inversion. Test sender deletion separately.
5. **Reveal vs cancellation/deletion:** verify common capsule-then-recipient locking and database time after waits. Cancellation committed first prevents subsequent reveal; a reveal already committed cannot recall bytes. A new cancellation cannot commit at/after unlock.
6. **Boundaries:** before, at and after `direct_expires_at` and `unlock_at`, including a transaction blocked across each boundary. Exact equality needs an independently reviewed deterministic database-side method, not a client-provided clock. Test actual timezone configuration for the seven-day duration.

Also test claim versus revocation, profile/Auth creation and removal, two rate-limit admissions, idempotency-key collisions and legacy self operations under concurrency. A test using `clock_timestamp()` followed by a later statement demonstrates at-or-after, not exact microsecond equality. No race was executed here.

## 4. Scope and activation gates

### Can be designed and locally tested later

Review named constraints, discriminator logic, self-route compatibility, state transitions, response projections, rate-limit and idempotency behavior. A future local PostgreSQL test environment could run synthetic constraint and transaction tests with mocked Auth fields and compare current self-capsule regression suites. Local stubs are useful for SQL mechanics, but they cannot establish actual Supabase Auth behavior, deployed grants, PostgREST semantics or real email reassignment. No such test was executed in this task.

### Requires separately authorized isolated Supabase verification

Inventory actual catalogs and rows; verify Auth confirmation/change/deletion behavior and effective locks with real provider operations; inspect effective roles/RLS/privileges and service-only RPC routing; verify PostgREST transaction behavior, time boundaries and two-session races; and rerun self regressions with isolated synthetic fixtures. This may involve changes to disposable test accounts and rows, so requires explicit authorization and a reviewed cleanup plan. Do not use development or production records as fixtures.

### Must block direct-capsule activation

- No proven authoritative current-email protocol and race-safe identity boundary, including pending changes and deletion.
- No approved policy for mailbox reassignment; matching currently verified email cannot identify the same human across transfers.
- No tested self/direct discriminator and proof that old list/self RPCs cannot authorize direct content or change existing self behavior.
- Unresolved deployed schema drift, legacy token/unbound rows, unexpected effective grants or untested rollback/restore.
- No shared server-enforced admission controls, idempotency strategy and minimum abuse/block/report policy for the intended audience.
- Unverified direct claim/cancel/reveal races, client table/storage bypasses or early-content protection.
- No separately authorized deployment, safe test/cleanup plan or data separation.

### Is schema-only 0006 safer?

An **additive, dormant schema-only slice** can reduce review size: inventory first, add only explicitly approved constrained structures with restrictive grants, create no direct rows or endpoints, and retain self regression behavior. A new isolated table with no data access may avoid changing old self predicates initially; whether that is preferable to the 014B discriminator/composite-FK proposal is unresolved. Even additive changes can alter permissions, lock duration, deployment or rollback behavior. A schema-only migration that relaxes an existing recipient check or creates direct rows while old self/list functions ignore kind is **not automatically safe**. Do not add an externally writable state until compatibility guards and effective access are proven; a feature flag alone is not a database security boundary.

Recommendation: complete the evidence gates and approve a concrete split first. Then, if justified, prepare a separately reviewed dormant schema migration and local tests, followed by isolated verification. Add identity-backed claim, cancellation and reveal only after the provider/locking gate passes, together with the API and server-enforced abuse controls needed before activation. This document does not authorize or create migration 0006.

## 5. Unapproved proposed defaults and decisions

The user proposed seven-day pending expiry, current confirmed-email matching, UUID-bound claims, no sender reveal, sender cancellation before unlock, no pending title/body, and no token/delivery in this MVP. Those are design inputs; implementation and deployment remain unapproved. The following are **proposals requiring explicit approval**, not completed security guarantees:

- **Email reassignment:** fail closed when provider identity state is uncertain; decide whether current verified mailbox control at claim time is acceptable despite reassignment risk, or require stronger proof. Never automatically rebind a claimed historical row after account deletion.
- **Expiry/terminal state:** seven days as 168 elapsed hours from authoritative creation; pending claim denied at exact expiry; successful UUID-bound claim survives the pending deadline. Expired/revoked/cancelled/historical invitations are terminal; reissue requires a new approved flow.
- **Rate limiting and abuse:** 014B suggests initial per-sender create budgets, privacy-preserving target budgets, and authenticated discovery/claim budgets, implemented by atomic shared server-side admission with fail-closed behavior. Exact numbers, HMAC key handling/rotation, transaction accounting, 429 privacy, block/report and adult-consent requirements are **unapproved**; no limiter infrastructure exists in this repository.
- **Idempotency:** no automatic POST retries; design sender-scoped, unique create keys and keyed canonical-request digests in a separately reviewed transaction. Claim repeats may succeed only for the same already-bound subject; define behavior after identity change. Cancellation repeats may preserve the original timestamp for an eligible owner while all new cancellations remain before unlock. Retention and privacy of keys/digests are unapproved.
- **Pending visibility:** verified current-email recipient sees only invitation ID and safe timestamps, no sender-written title, body, recipient email, token or user-controlled sender display name. A claimed title policy needs approval. Sender must not learn whether an address exists or claims; generic responses reduce but cannot eliminate timing inference.
- **Access:** owner creates/lists/cancels eligible direct capsules but cannot reveal; only the bound recipient can reveal after database-authoritative unlock and no cancellation/deletion. Decide account liveness/revocation policy after a UUID-bound claim, and preserve all self-capsule contracts.

## 6. Next implementation sequence

1. Review these assumptions, approve identity/reassignment and state semantics, then separately authorize a read-only isolated inventory and controlled Auth/lock tests. Record provider version, environment and results without credentials or personal data.
2. Resolve actual deployed data and effective-role findings; design a concrete dormant schema split, rollback and self compatibility tests. Only then separately authorize preparing an executable migration and local synthetic tests.
3. Verify the dormant slice and self regressions in an isolated project, then implement/verify current-email claim, direct reveal/cancellation and atomic abuse/idempotency controls in reviewable increments.
4. Add API and mobile routes only after the database security boundary is established; verify cross-account access, direct-table denials, no early disclosure, races and failure behavior before any activation.

This task performed static repository inspection only. No SQL, migrations, services, dependencies, application code, commit or push were changed or executed.
