# Phase 4 — Person-to-person capsule architecture audit

This document separates **verified repository findings** from **proposals**. It is a design review, not an implementation or an authorization to change schema, code or infrastructure. The review inspected migrations 0001–0005, the current FastAPI and mobile integration, existing tests and project status. No SQL was executed and no Supabase project was contacted.

## 1. Verified current data model

Migration `services/api/migrations/0001_initial.sql` defines:

- `profiles`: UUID primary key referencing `auth.users`, optional display name and creation timestamp. Deleting the Auth user cascades to its profile.
- `capsules`: UUID, required `owner_id` referencing a profile with cascading deletion, nonblank title, body of at most 2,000 characters, optional `media_key`, `unlock_at`, `created_at`, and optional `cancelled_at` and `deleted_at`. Unlock must be after creation and no more than 90 days later. Cancellation must be at or after creation and strictly before unlock. Deletion cannot precede creation or an existing cancellation.
- `recipients`: UUID, **one row per capsule** through unique `capsule_id`, normalized nonblank `intended_email` (`lower(btrim(...))`), optional `user_id` referencing a profile with `ON DELETE SET NULL`, optional unique 32-byte `invite_token_hash`, `invite_expires_at`, `invite_revoked_at`, `claimed_at` and `opened_at`. The table also has unique `(id, capsule_id)` to support the notifications foreign key.
- Invitation hash and expiry must be both null or both nonnull; revocation requires a hash. A bound `user_id` requires `claimed_at`; a tokenless row also requires `claimed_at`. `opened_at` requires a claim and cannot precede it. For token-backed rows, a claim must be before expiry and any revocation. The schema deliberately permits a historical claim with a null `user_id` after a profile is deleted; that row is not sufficient authorization.
- `notifications` has a composite foreign key to its recipient/capsule pair, a constrained status/lease model and uniqueness on `(capsule_id, recipient_id, kind)`. `blocks` and `reports` exist as tables. Their presence does not mean an abuse-handling API or notification worker has been implemented.

There is an owner/creation index for capsules and a recipient-user index. No pending-recipient email lookup index is defined by 0001. The reviewed migrations do not establish a private Storage bucket or Storage policies; actual deployed grants and bucket configuration were not inspected.

## 2. Verified access controls and self-capsule assumptions

Migration 0001 enables RLS on all six public application tables, creates no client policies and revokes table privileges from `PUBLIC`, `anon` and `authenticated`. It grants `service_role` table SELECT/INSERT/UPDATE/DELETE. The server key is therefore privileged and bypassing the intended backend is a critical risk; source declarations alone do not prove effective grants in a deployed project.

Migration 0002 provisions a profile after an Auth user insert and backfills missing profiles. Migration 0003 creates a self-capsule and a recipient in one transaction, using the verified backend-supplied owner ID to find a confirmed Auth email and binding that same owner as recipient. Its function is `SECURITY DEFINER`, postgres-owned with an empty search path, and executable by `service_role` rather than client roles.

Migration 0004 self-reveal requires the requester to be the owner **and** the claimed, bound recipient, with all invitation fields null. It locks the capsule and then recipient, checks cancellation/deletion, captures database wall-clock time after locks and only then selects `id, body` if the unlock time has arrived. Migration 0005 self-cancellation makes the same self-recipient assumptions, locks capsule then recipient, checks the database clock, and returns an authorized repeat's original cancellation timestamp. Both use the trusted backend's verified JWT subject; they do not trust a client-supplied owner ID.

FastAPI `current_user` verifies JWT signature, issuer, audience, expiry and UUID subject, but returns only the subject ID; it does **not** establish a current confirmed email for claiming. The repository lists owner-filtered metadata only and excludes cancelled/deleted rows. Existing create, reveal and cancel routes invoke self-specific RPCs. The mobile service, list, creation and detail flows assume self-capsules. Existing backend mocked tests and SQL Editor scripts cover self paths, including denial and safe projections; they do not implement recipient claims or prove direct-capsule concurrency.

## 3. Proposal: smallest verified-email MVP

Use an in-app, explicit claim for a recipient with a registered account and a **currently confirmed intended email**. A sender enters a recipient email and seals a text-only direct capsule. The recipient learns to open AfterTime through an existing out-of-band channel, signs in, sees a minimal pending invitation after verified-email authorization, and explicitly claims it. No link token or new email-delivery worker is required for the first slice. Existing Supabase email confirmation remains an operational dependency; the design does not eliminate the need for a working verification channel.

The backend must derive the requester UUID from a verified JWT and obtain the current confirmed email through an authoritative server-side Auth source. Never accept the recipient user ID or verified-email assertion from the client. Claim must recheck the current confirmed email in the same protected transaction or use another reviewed mechanism that closes email-change races. The exact Supabase Auth data and locking semantics must be independently verified before implementation; a signed but stale email claim alone is insufficient.

**Alternative for later:** expiring, single-use invitation tokens enable shareable links but add generation, storage, lifecycle and leak risks. Even with a token, the claimant must verify the intended email. Use cryptographically random high-entropy tokens, store only hashes, enforce single use and expiry atomically, never log raw tokens, and use a no-referrer policy and no third-party tracking on token pages. Do not build this extra path until separately approved.

## 4. Proposed schema and RPC changes

Keep migrations 0001–0005 as history; design a subsequent migration under `services/api/migrations` after approval. Existing `recipients` checks prevent a pending invitation with both `invite_token_hash` and `claimed_at` null, and couple `invite_expires_at` to token presence. A tokenless pending-recipient state therefore requires deliberate constraint and lifecycle changes, not merely a new API route.

Review an explicit self/direct distinction and constrained pending, claimed and revoked/expired state representation; a separate pending expiry field may be clearer than weakening the existing token-pair invariant. Decide whether expiry is stored or derived, how to preserve the existing hashless claimed self rows and historical unbound rows, and how to avoid giving a deleted account's former recipient row to a new account. Add an appropriately scoped index for verified pending lookup only after reviewing privacy and performance. Preserve one-recipient-per-capsule, existing self behavior, RLS and restrictive grants.

Introduce separate service-only direct-capsule RPCs or equivalent narrowly scoped operations. Proposed responsibilities:

1. **Create direct:** derive sender from verified backend identity; validate text, time and recipient address; atomically create the capsule and pending recipient; do not query or report whether the address has an account. Return sender-safe metadata only.
2. **Pending inbox:** obtain only minimal metadata for the requester's currently confirmed matching email and eligible pending invitations. This is a trusted, backend-mediated operation; never expose the email lookup to anonymous callers.
3. **Claim:** atomically verify current confirmed email and bind the verified requester only if the invitation is pending, not expired or revoked, and its capsule is neither cancelled nor deleted. Return metadata only; a repeated claim policy must be specified and tested.
4. **Recipient list/reveal:** return metadata only for authorized claimed rows; select body only inside a server-authoritative reveal check after access, cancellation/deletion and unlock conditions pass.
5. **Sender list/cancel:** select only sender-authorized metadata; cancel an eligible direct capsule and invalidate any outstanding claim in the same transaction. Do not infer eligibility from the client clock.

The self RPCs must remain callable with their current contracts. Separate direct RPCs and route contracts avoid accidentally broadening self checks. Keep SQL migration authority in `services/api/migrations`; no implementation is authorized by this document.

## 5. Proposed HTTP contracts

Names and payloads below are provisional design contracts, **not existing endpoints**. All require an authenticated subject; response/error details and pagination need review before implementation.

| Endpoint | Request | Proposed safe response |
| --- | --- | --- |
| `POST /v1/direct-capsules` | `{title, body, unlock_at, recipient_email}` | `201` sender-safe `{id, title, created_at, unlock_at}`; same public outcome for existing and nonexisting addresses |
| `GET /v1/direct-capsules/sent` | Bounded pagination | Sender's safe metadata only; no body, token, recipient-existence or claim-status signal by default |
| `GET /v1/direct-capsules/inbox` | Bounded pagination | Minimal eligible pending or claimed metadata for the authenticated verified recipient; no body or token |
| `POST /v1/direct-capsules/{id}/claim` | No client identity or email assertion | Claimed metadata only; generic unavailable response for unauthorized, expired, revoked or missing invitations |
| `GET /v1/direct-capsules/{id}/reveal` | No client clock or identity override | `{id, body}` only after all recipient and database-time checks; otherwise generic unavailable |
| `POST /v1/direct-capsules/{id}/cancel` | No client identity override | `{id, cancelled_at}` on eligible sender cancellation; otherwise generic unavailable |

Avoid returning raw database/provider errors, email addresses, token hashes, message text or private fields in list/error responses. Apply no-store to sensitive responses and error paths. Define create idempotency separately before automatic retry; a timeout can follow a committed creation.

## 6. Authorization and metadata visibility

**Sender:** can create for a syntactically valid recipient address without learning whether it is registered, list sender-safe metadata, and request cancellation before database unlock. Whether a sender may reveal a direct capsule is a product/security decision, not an assumption; recipient authorization must not automatically imply sender access. Do not disclose claim status to the sender by default because it can reveal recipient account or activity information.

**Recipient:** an unclaimed invitation can appear only to an authenticated user whose **current confirmed email** matches the intended address through a server-authoritative check. Pending metadata should be the minimum needed to decide whether to claim: capsule ID, a safe sender indication if approved, title and unlock time. Title is sender-controlled and may itself contain sensitive or abusive content; review whether title or sender identity should be withheld until claim. No body, image bytes, recipient email, token or privileged internal fields may be exposed. A claimed capsule is listed only to its bound verified user. Reveal requires bound-user authorization, no cancellation/deletion and database time at or after unlock. A UUID, device clock or list status never grants access.

**Other users and clients:** generic unavailable responses must not distinguish missing, locked, wrong-user, cancelled or deleted capsules where that distinction could leak information. Client roles must remain unable to read bodies or recipient tables directly; storage must remain private with separately verified restrictive policies before media is enabled. Never expose service keys to mobile clients.

## 7. Expiration, revocation and email changes

**Proposal:** pending invitations have a finite lifetime and are ineligible for discovery or claim after expiry or revocation. Expiry should govern the pending claim, not silently revoke a valid already-claimed recipient; exact semantics require approval. Cancellation invalidates an outstanding invitation immediately and must override any prior claim for reveal. Reissue, sender-initiated revocation, post-claim revocation and deletion behavior require explicit design.

The system must not silently transfer an invitation or claimed capsule when an email is changed, becomes unconfirmed, is reassigned, or an account/profile is deleted. Define how current email confirmation and ownership are proven at discovery and claim; define whether a previously claimed capsule remains bound to the original user ID after email change. Review Auth email-change confirmation behavior and concurrency with claims. Do not assume `email_confirmed_at` alone resolves every provider-specific email-change case. Lock or otherwise serialize against changes using a verified approach; if identity state is uncertain, fail closed. Account deletion's existing `ON DELETE SET NULL` leaves historical rows and must never trigger automatic rebinding.

## 8. Concurrency and cancellation

All operations touching the same direct capsule and recipient must use a documented **capsule-then-recipient lock order**, compatible with the current self functions. Claim, revoke, cancellation, deletion and reveal must recheck authorization and state after lock waits and use authoritative database time inside their transaction. Define and test which committed operation wins: cancellation committed first denies a later claim/reveal; claim committed first does not prevent an otherwise eligible sender cancellation; a reveal completed before a later cancellation cannot recall bytes already returned. A new cancellation at or after unlock is denied; if authorized repeats are supported, specify their exact semantics.

The current self-cancellation RPC does not cancel notification jobs or revoke direct invitations. Before notifications or invitations are enabled, design atomic revocation and job cancellation plus worker rechecks under the shared locking protocol, including leased or already-dispatched jobs. External email cannot be recalled and exactly-once delivery is not guaranteed. Do not imply that this table/RPC audit proves those flows are implemented.

## 9. Abuse and enumeration controls

Creating or listing a sent capsule must not reveal whether the address exists, is confirmed, has an account or has claimed the invitation. Use consistent public response shapes and comparable processing paths; do not claim timing can be made perfectly indistinguishable. Limit metadata and avoid observable delivery/claim-status signals. Rate-limit and monitor create, pending discovery and claim by authenticated actor and suitable privacy-preserving target/IP controls, with bounded payloads, spam prevention and operational thresholds. Decide minimum block/report and adult-consent protections before broader beta use. Do not use a client-supplied identity, log bodies, emails unnecessarily, raw invitation tokens or request headers.

## 10. Required verification

- **SQL and privileges:** isolated tests for constraints, pending/claimed/expired/revoked states, exact return projections, self compatibility, effective grants and role inheritance, actual client-role RPC/table denial, RLS bypass attempts, and direct Storage denial before any media feature. Test Auth/profile deletion and unbound historical rows.
- **Claim identity:** confirmed matching email, wrong/other account, unconfirmed or changed email, stale verified state, malformed identity, expired/revoked invitation, simultaneous claims and retry behavior. Verify no client-selected user ID or email can override the verified subject.
- **Reveal and cancellation:** sender and recipient matrix, claimed versus unclaimed, locked, before/at/after authoritative unlock, cancellation, deletion, expiration and revoked state; assert no early body or image bytes and identical generic denials where intended.
- **Concurrency:** two-session claim versus cancel, claim versus email change/deletion, revoke versus claim, reveal versus cancel/deletion, expiry across lock waits and both commit/rollback orders. Verify lock order, fail-closed errors and the documented winner. Exact boundary tests need a deterministic database-side strategy rather than trusting a client clock.
- **FastAPI/mobile:** mocked contract, validation, identity, error sanitization, no-store, rate-limit and no sensitive-log tests; cross-account live integration only with separately authorized disposable fixtures. Test session changes and stale responses. Existing self-capsule regression tests must continue to pass.
- **Operations:** real effective grants, role inheritance, PostgREST transaction behavior, email confirmation/change semantics and backup/restore before beta. SQL Editor and mocked HTTP tests alone do not prove these properties.

## 11. Recommended implementation order

1. Approve the schema/security design, identity authority, lifecycle, lock protocol and abuse controls before coding.
2. Prepare isolated SQL security tests and a migration for direct pending-recipient representation and transactional creation/claim; preserve and regression-test self-capsules.
3. Add direct recipient listing, reveal and sender cancellation RPCs with concurrency and cross-account tests. Validate with disposable-project tests only after separate authorization.
4. Add FastAPI request/response contracts and mocked tests, then separately authorized live integration tests. Add mobile direct-capsule UX after backend gates pass.
5. Consider expiring share tokens, browser links and delivery only as later separately scoped work; implement required transactional notification and invitation coordination first.

## 12. Decisions required before coding

- Pending invitation lifetime, reissue and expiration semantics; whether claim remains valid after the pending deadline.
- Current verified-email authority, email normalization and handling of email change, unconfirmation, account deletion and reassignment.
- Whether and when a sender can reveal their own direct capsule; exactly which metadata pending recipients may see.
- Sender-facing claim-status visibility, including its enumeration and privacy tradeoff.
- Required creation/claim/discovery rate limits, blocking/reporting and adult-consent controls before use.
- Cancellation/revocation and retry behavior, including concurrency and future notification jobs.
- Whether token links, browser claiming or delivery are needed now; this audit recommends deferring them.

No schema or application changes were implemented, no tests or migrations were executed, and deployed database state was not independently verified during this audit.
