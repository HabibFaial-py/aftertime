# AfterTime status

## Phase 4 — Prompt #014I-6D: SQL regression compatibility

- Updated `test_dormant_invitation_worker.sql` for the final 0012 permissions: the worker cannot execute the public caller-token transition, but can execute candidate lookup and the fenced v2 transition. The test checks client/service denials, the no-login/no-inherit worker and direct outbox denial. Its legacy transition grant is limited to a copied synthetic fixture; no migration or production permission changed.
- On the verified disposable PostgreSQL 18.6 cluster at `127.0.0.1:55485`, with 0012 already applied, `psql -X -h 127.0.0.1 -p 55485 -U postgres -d aftertime_rpc_test -v ON_ERROR_STOP=1 -f` passed for `test_dormant_invitation_worker.sql`, `test_dormant_worker_reliability.sql`, `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. The worker tests use committed synthetic fixtures and copied functions; the other checks roll back. Before and after testing, the dedicated data directory, loopback binding, empty fixture state and validated 0006 `CHECK (false)` were verified.
- From `services/api`, with `$env:AFTERTIME_LOCAL_OUTBOX_TEST='1'`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **300 passed, 2 existing warnings**. `..\..\.venv\Scripts\python.exe -m compileall -q app tests` passed. The cluster was stopped after testing; sandboxed start and stop failed with Windows restricted-token/permission errors, while elevated start and stop succeeded. No hosted Supabase or email was used.
- No further 0011/0012 regression incompatibility was observed in these local checks. Fixture copies and a simplified Auth stub do not prove hosted privileges, real-driver behavior or external delivery. Next: review cancellation and identity policy and test a local real DB-driver adapter with commit/disconnect ambiguity and fake-provider reconciliation; keep the worker, direct feature and delivery disabled pending security review.

## Phase 4 — Prompt #014I-6: dormant worker reliability

- Added draft 0012 with database-generated random lease tokens, per-job fencing generations and explicit transition outcomes; revoked the worker's old caller-token RPC. Added an unwired DB-API adapter that returns acknowledgements only after a reported successful commit and treats commit exceptions as unknown. `run_delivery` remains fail-closed; cancellation after a committed prepare can still race with sending. See `docs/PHASE_4_WORKER_RELIABILITY_014I6.md`.
- From `services/api` with `$env:AFTERTIME_LOCAL_OUTBOX_TEST='1'`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **300 passed, 2 existing warnings**; focused worker tests: **23 passed**. `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed. Fake DB-API and provider tests do not prove real-driver or external-delivery behavior.
- Disposable loopback PostgreSQL 18.6 applied 0012 and passed `test_dormant_worker_reliability.sql`, `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. The worker fixture used independent sessions and copied functions for fencing, rollback, cancellation/claim/revocation ordering and late-claim checks. One intermediate SQL assertion failed due to same-statement snapshot visibility; corrected, guarded fixture cleanup completed, and the revised test passed. The real 0006 gate and fixture cleanup were confirmed. Sandboxed startup failed due to Windows restricted-token error; elevated localhost startup/stop succeeded. Server is stopped; no hosted service or email was used.
- Root `git diff --check` passed with line-ending warnings; untracked files were checked separately for trailing whitespace. Next: review cancellation and identity policy and test a local real DB-driver adapter with commit/disconnect ambiguity and fake-provider reconciliation; keep worker, direct feature and delivery disabled pending security review.

## Phase 4 — Prompt #014I-5: dormant delivery-worker foundation

- Added draft 0011 worker lease/eligibility transitions and a no-login, no-table-access worker role, plus an unwired Python AES-GCM/digest verifier. A fake test-only mail transport demonstrates that ambiguous sends can duplicate. The real worker entry point fails closed: token freshness, completion acknowledgements and cancellation-versus-send races remain unresolved. The 0006 gate, default-off direct flag and unavailable public claim/discovery remain. See `docs/PHASE_4_DELIVERY_WORKER_014I5.md`.
- From `services/api`, with `$env:AFTERTIME_LOCAL_OUTBOX_TEST='1'`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **289 passed, 2 existing warnings**; focused worker verification tests: **12 passed**. `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed.
- Disposable loopback PostgreSQL 18.6 applied draft 0011 and passed `test_dormant_invitation_worker.sql` with two real competing connections and synthetic fixtures, plus `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. The initial worker SQL test hit a test-script `CASE` syntax error; corrected, guarded fixture cleanup completed, and the revised test passed twice. Post-test fixture cleanup and the real 0006 gate were confirmed. Sandboxed startup failed with Windows restricted-token error; elevated local startup/stop succeeded. Server is stopped; no hosted Supabase or email used.
- Root `git diff --check` passed with line-ending warnings; untracked files were separately checked for trailing whitespace. Next: redesign completion acknowledgements and fresh fenced lease tokens, decide cancellation/send and ambiguous-outcome semantics, then test a dormant fake-provider adapter. Managed keys, identity and delivery remain activation blockers.

## Phase 4 — Prompt #014I-4: local encrypted invitation fixture

- Added an opt-in loopback-only PostgreSQL harness that passes the real private adapter's encrypted job through the copied 0010 creation function, retrieves it under a restricted synthetic worker role, decrypts it and verifies the digest. Each case rolls back fixture schema, role and synthetic user; the real 0006 `CHECK (false)` remains. Tests cover tampering, digest mismatch, duplicate salt/nonce, late SQL failure, ambiguous response and denied access. See `docs/PHASE_4_LOCAL_OUTBOX_INTEGRATION_014I4.md`.
- From `services/api`, with `$env:AFTERTIME_LOCAL_OUTBOX_TEST='1'`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **277 passed, 2 existing warnings**, including 12 local integration cases. `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed. The fixture uses synthetic keys and a simplified Auth stub; the application and delivery remain unwired.
- A new disposable PostgreSQL 18.6 cluster bound only to `127.0.0.1:55485` applied 0001–0010 and passed `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql`. Post-test checks confirmed fixture schema, worker role and synthetic Auth user rolled back and the gate remained. Sandboxed startup failed due to Windows restricted-token error; elevated startup/stop succeeded. The server is stopped; no hosted Supabase or email was used.
- Root `git diff --check` passed with line-ending warnings; untracked files were checked separately for trailing whitespace. Next: independently review key/entropy and identity policies, then design a dormant worker lease/retry and eligibility-check protocol with cancellation/deletion and ambiguous-delivery tests. No feature activation or delivery is authorized by this work.

## Phase 4 — Prompt #014I-3: per-invitation encryption draft

- Added a dormant one-shot AES-256-GCM helper deriving an invitation-specific key using HKDF-SHA256, a fresh random 256-bit salt, environment/key version and invitation context. Draft 0010 stores salt metadata and rejects committed salt collisions atomically. This probabilistic design avoids a separate nonce allocator only while independent OS randomness and secure key/restore practices hold; SQL checks cannot prevent reuse after rollback, cloning or restore. The public creation stub, default-off direct flag, 0006 gate, claim/discovery and delivery remain disabled. See `docs/PHASE_4_ENCRYPTION_SIMPLIFICATION_014I3.md`.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **265 passed, 2 existing warnings**; focused outbox/creation/encryption tests: **60 passed**; `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed. Tests use synthetic keys and mock RPCs.
- Local PostgreSQL 18.6 only: applied 0001–0010 in a new loopback disposable cluster with a simplified Auth stub. `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql` passed; successful outbox creation used copied fixtures, while the real gate remained. Sandboxed startup failed with Windows restricted-token error; elevated local startup/stop succeeded. Cluster is stopped. No hosted service or email was used.
- Root `git diff --check` passed with line-ending warnings; untracked files were checked separately for trailing whitespace. Next: independently review the construction and define root-key, restore/clone entropy and ambiguous-outcome procedures, then build a local end-to-end encrypted SQL fixture with all gates retained. Identity and delivery safety remain activation blockers.

## Phase 4 — Prompt #014I-2: dormant trusted invitation creation

- Added environment/version-scoped HKDF key derivation, a locally single-use nonce lease and a private, unwired creation prototype that encrypts and digests one secret and makes one RPC call with no retry. The public creation stub always fails closed: no production-safe lease provider exists. Global environment uniqueness, restore-safe nonce allocation and key lifecycle remain external blockers; SQL uniqueness alone is insufficient. The 0006 gate, default-off direct flag and unavailable claim/discovery remain. See `docs/PHASE_4_TRUSTED_INVITATION_CREATE_014I2.md`.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **247 passed, 2 existing warnings**; `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed. Tests use synthetic keys and mocked RPC/leases; no real delivery or hosted services.
- Disposable PostgreSQL 18.6 on `127.0.0.1:55485`: `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql` passed with simplified Auth and copied outbox fixture tables/functions; the real 0006 gate remained active. Sandboxed startup failed with Windows restricted-token error; elevated startup and stop succeeded. The local server is stopped.
- Root `git diff --check` passed with line-ending warnings; untracked files were separately checked for trailing whitespace. Next: design and test a durable external nonce/key authority with environment isolation, restore fencing and rotation, then separately integrate a no-retry transport and local encrypted fixture while keeping all gates closed. Claimant email verification and delivery lifecycle remain activation blockers.

## Phase 4 — Prompt #014I-1R: recovered dormant invitation outbox

- Reviewed the interrupted AES-256-GCM helper, draft migration 0010 and focused tests; preserved #014H-5 work. Added 0007/0009 prerequisite checks to 0010 and a nonce-randomness failure test. Capsule, digest, nonce reservation and job are atomic in the draft SQL, but the trusted application adapter, restore-safe nonce/key lifecycle and delivery remain absent, so the path remains unwired. The 0006 `CHECK (false)`, default-off direct flag and unavailable public claim/discovery remain. See `docs/PHASE_4_SECURE_OUTBOX_014I1.md` for guarantees, limitations and blockers.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **227 passed, 2 existing warnings**; `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed.
- Local PostgreSQL 18.6 only: a dedicated loopback cluster and simplified Auth stub applied 0001–0010; 0010 correctly failed when tried before 0009. `test_dormant_invitation_outbox.sql` and `test_create_self_capsule.sql` passed; successful outbox creation uses copied fixture tables/functions, while the real gate remained active. Sandboxed startup/stop failed due to Windows permissions; elevated startup and stop succeeded, and the cluster is stopped. No hosted Supabase or email was used.
- Root `git diff --check` passed with line-ending warnings; untracked files need separate checking. Next: separately design restore-safe nonce allocation and managed-key lifecycle, then build an unwired trusted creation adapter with local end-to-end mismatch, rollback, retry and leakage tests. Claimant email verification, lifecycle coordination, deployed authorization and other security review remain activation blockers.

## Phase 4 — Prompt #014H-5: dormant invitation generation

- Reviewed committed 0009: service-only draft claim RPC atomically consumes a digest and binds an eligible account after locks and database-time checks; the public claim and discovery routes remain unavailable, and the 0006 `CHECK (false)` and default-off direct flag remain intact. Claiming follows the approved bearer-secret policy, not current-email matching. See `docs/PHASE_4_INVITATION_PROGRESS_014H5.md` for details and verification limits.
- Added an unwired generator using `secrets.token_bytes(32)`, canonical unpadded base64url and the existing masked claim model/SHA-256 digest. No database storage, issuance, delivery or endpoint was added. Random-source failures propagate; secret values still exist in process memory and must not be logged or exposed.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **205 passed, 2 existing warnings**; focused `..\..\.venv\Scripts\python.exe -m pytest -q tests/test_direct_capsules.py -k 'claim or invitation_secret'`: **15 passed, 45 deselected, 1 existing warning**; `..\..\.venv\Scripts\python.exe -m compileall -q app tests`: passed. Mocks do not prove hosted behavior.
- A fresh loopback-only PostgreSQL 18 cluster with a simplified Auth stub applied migrations 0001–0009 and passed `test_create_self_capsule.sql` and `test_dormant_invitation_claim.sql`. The actual gate stayed intact; successful claim/race cases use copied functions and separate fixture tables. Initial sandboxed server startup failed with a Windows restricted-token error; elevated local startup and stop succeeded. Cluster stopped; ignored local data/log retained. No Supabase contact or hosted migration.
- Root `git diff --check` passed; the new untracked report was separately checked for trailing whitespace. Next: implement a reviewed dormant atomic digest plus authenticated-encrypted outbox path and local delivery/rollback/leakage tests, with managed-key lifecycle and all gates retained. Managed Auth/session, deployed grants, safe delivery, abuse controls and activation verification remain blockers.

## Phase 4 — Prompt #014H-4: dormant invitation claim foundation

- Prepared migration 0009, a masked bearer-secret request model and unwired digest-only claim repository helper; the public endpoint still fails closed and the validated 0006 `CHECK (false)` remains. Local fixture tests cover claim, replay, expiry, revocation, authorization, account/capsule deletion and cancellation races; they use redirected copies of the SQL functions because the actual gate prevents invitation rows. See `docs/PHASE_4_INVITATION_CLAIM_014H4.md` for limits and prerequisites.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **203 passed, two existing warnings**. On disposable loopback PostgreSQL 18, local migrations 0001–0009, the new fixture checks and self-creation SQL regression passed; the local Auth schema was a stub. No hosted database, Supabase, email or mobile integration was used. The local server was stopped.
- Next: separately scope dormant random-secret issuance and encrypted outbox; verify real Auth/session deletion, effective deployed privileges, abuse controls and delivery security before any separately authorized activation.

## Phase 4 — Prompt #014H-3: recipient identity recommendation

- Prepared `docs/PHASE_4_IDENTITY_DECISION_014H3.md`: recommends an explicit mailbox-delivered single-use claim secret, conditional on accepting bearer-possession semantics in place of a current confirmed-email match. It specifies the dormant claim-core implementation slice, delivery and race requirements, and outstanding identity, abuse and deployment blockers. Claiming remains unavailable and activation gates remain intact.
- Documentation review only; no application code, migration execution, backend/SQL tests or Supabase contact. Next: approve the identity semantics and scope before implementing the proposed gated local claim core; activation requires separate security verification and authorization.

## Phase 4 — #014H-2 session report

- Added `docs/PHASE_4_CLAIM_IMPLEMENTATION_014H2.md`, distinguishing the recorded pre-commit review and earlier simulated tests from the #014K-10 mobile review. Claim and discovery remain unavailable; provider identity boundaries and secure claim implementation remain blockers. No application, migration or feature-gate changes and no service contact were made for the report.
- Backend and SQL tests were not rerun for this documentation task. Next: review the report and separately scope isolated identity verification before claim implementation or activation.

## Phase 4 — Prompt #014K-10: dormant Android foundation review

- Reviewed the Send to Someone form, its local time review and UTC serialization, review invalidation, keyboard scrolling and accessibility, the Received presentation states, and navigation guards. The #014K-7, #014K-8 and #014K-9 implementations are present. No concrete locally reproducible problem was found, so no application code or regression tests were changed.
- The direct feature flag defaults off; both direct routes require a session and the flag. The send form validates locally and has no submission action or direct API call. Received always renders unavailable; its other states are presentation-only. Existing self-capsule code was unchanged. Guard and UI tests use mocks and do not establish native deep-link, keyboard or TalkBack behavior.
- From `apps/mobile`: `npm run typecheck` passed; `npm run lint` passed; `npm test` passed **43 tests**. No Android device checks, Supabase contact, backend or migration changes, commit, push or deployment occurred.
- Android checks remain: on a small screen, open each keyboard and reach every input, feedback and the full time review; repeat with large font and display scaling. With TalkBack, check reading order, labels, field errors, announcements and navigation. Review a time, change timezone and clock, background/resume, and verify a fresh review is required. Test back navigation and direct deep links with the flag off and when signed out; use local fixtures to inspect Received loading/error/empty and Retry behavior without implying real data.
- Before direct integration or activation, securely establish recipient identity and claiming, server-enforced access and unlock time, and appropriate cross-account and direct-access tests. Before any future submission, synchronously revalidate the reviewed instant and timezone. Device clock checks are presentation safeguards, not authorization. Next: complete the Android checks and separately scope secure backend integration.

## Phase 4 — Prompt #014K-9: received-capsule presentation states

- Received Capsules now has visible, polite status text for unavailable, loading, error and empty presentations. The decorative loading indicator is hidden from accessibility; the empty presentation distinguishes pending invitations from received capsules. An error shows Retry only when a caller supplies a recovery callback. The live route remains unavailable and direct features remain disabled by default.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed; `npm test` passed **43 tests**. Local component tests cover status semantics, empty wording, retry availability and the unavailable route. No direct API, Supabase, backend or migration changes were made.
- Next: verify transitions, announcements, retry focus, small-screen layout and large font scaling on an Android device using local state fixtures. Before integration, securely implement recipient discovery and claiming; only report both sections empty when both are actually known to be empty.

## Phase 4 — Prompt #014K-8: Android keyboard and small-screen layout

- Send to Someone and Received Capsules use top-aligned scroll content. The send form requests a scroll to the focused input when the keyboard is visible and to the feedback area after checking details, while keeping the shared safe area, keyboard avoidance, handled taps and accessible focus order. No dependency, direct API, Supabase, backend or migration changes were made.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed; `npm test` passed **43 tests**. The new scroll and keyboard-event tests use mocks and do not verify native layout or actual visibility.
- Next: verify on physical Android devices with small screens, large font/display scaling, different keyboards, keyboard open/close transitions and TalkBack. Confirm focused fields, validation feedback and the entire time confirmation can be reached without clipping. Existing time-review and direct-integration limitations remain.

## Phase 4 — Prompt #014K-7: Android form feedback and time review

- Send to Someone now attaches validation guidance to the affected field and uses one polite live region for feedback; the review remains reachable in normal screen-reader order. A review is discarded when the app leaves the foreground and checked while active for timezone, clock and time-window changes. Clock drift checks have a one-second tolerance and run approximately once per second.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed; `npm test` passed **40 tests**. Tests use mocked UI and lifecycle behavior and Node timezones; TalkBack announcements, keyboard behavior, Android timezone/clock updates and lifecycle behavior still require real-device verification. No direct API, Supabase, backend or migration changes were made.
- Next: verify on Android with TalkBack and different keyboard and timezone settings. Before future submission, synchronously revalidate and compare the reviewed instant and timezone, require renewed review after changes, and rely on authoritative server/database time. Identity, claim security and direct-feature activation remain separate work.

## Phase 4 — Prompt #014K-4: direct unlock-time review

- The local-only Send to Someone form now validates the selected local time using the self-capsule parser, rejects invalid and ambiguous clock-change times, and displays the local date, time, timezone, offset and UTC ISO equivalent. The 90-day limit uses elapsed time. Direct features remain disabled by default; no request or simulated creation was added.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed; `npm test` passed **37 tests**. Tests cover calendar and 90-day boundaries, UTC serialization, timezone offsets and DST gaps/folds using Node timezone data. Android device behavior and accessibility were not manually tested.
- Next: before any direct integration, revalidate the selected time and timezone at submission, handle device clock/timezone changes, and enforce the window and reveal using authoritative server/database time. Review recipient normalization, identity and claim/discovery security, abuse controls and activation gates. No backend, migration or Supabase changes were made.

## Phase 4 — Prompt #014K-3: mobile UI commit review

- Reviewed the guarded mobile UI and its tests; the flag defaults off, sending and received-capsule loading remain unavailable, and the reviewed test addresses use the reserved `.invalid` domain. No backend, migration or Supabase operation was made.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed, and `npm test` passed **33 tests**. From the root, `git diff --check` and `git diff --cached --check` passed before staging; staged changes require their own final check.
- Next: manually verify Android navigation and accessibility, then separately address reveal-time confirmation, UTC serialization, normalization and server-side identity and claim security before any integration or activation.

## Phase 4 — Prompt #014K-2: direct form contract review

- Added a Title input and passed the actual title into local validation. The API requires nonblank, UTF-8-encodable title and body without NUL, with a 2,000-code-point body limit and no title length limit. Recipient email is required with a 254-code-point raw limit and backend normalization; local validation also checks the normalized length required by the draft SQL. Unlock time must be timezone-aware, future and within 90 days.
- From `apps/mobile`: `npm run typecheck`, `npm run lint` and `npm test` passed; **33 tests passed**. The form remains local-only and the direct flag defaults off. No Supabase operation or backend/migration change was made. Android device testing was not performed.
- Next: before connecting the form, implement exact local-time confirmation and reviewed UTC request serialization; verify Unicode/email normalization differences and rely on server/database time and validation. Auth identity, claim/discovery, abuse controls and activation gates remain unresolved.

## Phase 4 — Prompt #014K-1: mobile direct-capsule UI foundation

- Added authenticated, feature-guarded Send to Someone and Received Capsules routes using the existing mobile styles. `EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED` is false by default. The send screen validates email, message and local reveal date/time without submitting; the received screen defaults to unavailable, with testable loading, error and empty presentations and pending/claimed placeholders. No direct-capsule API, Supabase connection, backend or migration change was made.
- From `apps/mobile`: `npm run typecheck` passed; `npm run lint` passed; `npm test` passed **33 tests**, including six new foundation tests. Android device and real navigation/deep-link behavior were not manually tested. The public flag is a UI switch, not authorization.
- Next: manually review the guarded screens on Android. Before integration, resolve the recipient identity and claim/discovery security blockers, specify how the direct API's required title will be collected, and implement reviewed server-enforced authorization and complete time confirmation. Do not enable the backend or database gate for this UI.

## Phase 4 — Prompt #014H-2: pre-commit review

- Reviewed the dormant direct-capsule implementation, migrations, tests and research. The direct flag defaults off, migration 0006 retains `CHECK (false)`, and claim and pending discovery do not query the database. Existing self-capsule implementation files remain unchanged. Test emails and UUIDs are synthetic; no credentials were found in the reviewed changes.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **200 passed, 2 existing warnings**. From the root, `git diff --check` and `git diff --cached --check` passed with line-ending warnings. No disposable local cluster was identified for this run, so destructive SQL fixtures were not rerun; previous local results are recorded below. No hosted database or Supabase service was contacted.
- Next: resolve verified-email and Auth transaction-boundary questions, implement and test safe claim/discovery and abuse controls, and verify effective deployed privileges before considering separately authorized activation.

## Phase 4 — Prompt #014H-1: claim preparation remains dormant

- Added draft `0008_dormant_claim_preparation.sql`, a guarded pending-lookup index, strict metadata-only API response models and fail-closed tests. The 0006 `CHECK (false)` remains intact; claim and pending-discovery RPCs do not exist, and both API operations remain unavailable even when the direct feature flag is true. See `docs/PHASE_4_CLAIM_PREPARATION_014H1.md`.
- Backend `python -m pytest -q`: 200 passed, two existing warnings. Local PostgreSQL 18 migrations 0001-0008 and regression/gate checks passed, including two concurrent calls to the absent claim RPC; the disposable loopback cluster was stopped and removed. This does not test successful claim, eligibility or claim races. Supabase Auth email-change transaction semantics, verified-identity authorization and abuse controls still block claim implementation and activation. No Supabase request or hosted migration was made.

## Phase 4 — Prompt #014G-2: gated direct-capsule backend draft

- Added separate direct storage, service-only create/cancel/reveal RPC drafts, authenticated API routes and mocked tests. `DIRECT_CAPSULES_ENABLED` defaults to false. Claim and pending discovery remain unavailable, and migration 0006's always-false constraint still blocks creation even if the flag is enabled. Existing self storage and RPCs are unchanged. See `docs/PHASE_4_DIRECT_BACKEND_014G2.md`.
- Backend `python -m pytest -q`: 194 passed, two existing warnings. Local PostgreSQL 18 migration/SQL regression checks and a two-session cancellation-versus-reveal test passed in a disposable loopback-only cluster, which was stopped and removed. Tests used synthetic bindings and a test-only temporary gate removal; no Supabase service or original database was contacted. Auth identity concurrency, safe claiming/discovery, abuse controls and deployed privileges remain blockers to activation.

## Phase 4 — Prompt #014G-1: dormant recipient foundation

- Prepared migration `0006_dormant_direct_invitation_foundation.sql` and a disposable-cluster SQL test. A validated always-false constraint, RLS and revoked application grants keep the new invitation table empty and inaccessible; no direct creation, discovery, claim, cancellation or reveal is enabled. Existing self tables/RPCs remain unchanged. See `docs/PHASE_4_MIGRATION_REVIEW_014G.md` for compatibility and activation gates.
- Local PostgreSQL 18 applied migrations 0001-0006 and passed the existing self-creation and new dormant-foundation SQL checks; its disposable loopback-only cluster was stopped and removed. Backend `python -m pytest -q`: 145 passed, two existing warnings. No live database or Supabase service was contacted. User-reported row-lock conflict is not proof of Auth email-change locking; the localhost confirmation redirect is inconclusive. Next: resolve identity and concurrency blockers before designing activation.

## Phase 4 — Prompt #014F-5F: isolated Auth diagnostic categories

- Updated the ignored temporary email-change script to distinguish sign-in timeout, connection/TLS or other network failure, invalid HTTP/JSON response, HTTP 401/403 rejection and other HTTP statuses without printing exception details or private data. The previous generic `httpx.HTTPError` message did not establish the underlying cause; HTTP status and JSON errors already followed separate paths. The existing HTTPS verification, project check, GUI confirmation and single update attempt remain unchanged.
- Python AST parsing/compilation and static checks for request count, absence of retries, confirmation ordering, HTTP client options and error handlers passed; `git check-ignore -v` confirmed the script is ignored, and `git diff --check` passed with a line-ending warning. No sign-in, email update or Supabase connection was attempted. Next: any live diagnosis requires separate authorization and must preserve disposable-account safeguards.

## Phase 4 — Prompt #014F-3A: psql TLS setup

- Prepared `docs/PHASE_4_TLS_SETUP_014F3A.md` using local PostgreSQL 18.6/OpenSSL inspection and official documentation. The default CA file/directory and libpq root file were absent; a limited offline Windows-root/OpenSSL trust check was inconclusive. The recommended future configuration uses the authenticated Dashboard CA, exact session-pooler hostname and `verify-full`; the real pooler chain remains unverified.
- No project service/database connection, SQL, credentials, installation or project configuration change occurred. Next: separately authorize and verify the isolated TLS connection before session-affinity or Auth-lock testing.

## Phase 4 — Prompt #014F-2: PostgreSQL test setup

- Prepared `docs/PHASE_4_POSTGRES_TEST_SETUP_014F2.md` for a separately authorized isolated lock experiment. PostgreSQL `psql` 18.6 exists outside PATH at the standard PostgreSQL 18 installation; the existing virtual environment has no discoverable psycopg, psycopg2, asyncpg or pg8000. No installation, SQL, connection or service request was performed.
- Next: review TLS, privileges, safe logging, persistent-session affinity, disposable-account recovery and the lock-conflict controls before authorizing a live test. Auth locking and direct recipient claiming remain unverified.

## Phase 4 — Prompt #014F: Auth lock verification design

- Prepared `docs/PHASE_4_AUTH_LOCK_VERIFICATION_014F.md` with an isolated persistent-session lock probe, separate supported Auth request and confirmation stages, safe observations, timeouts and recovery. A matching `auth.users` row lock may conflict with a particular update but is not proof of the whole provider workflow or a safe claim protocol.
- Static repository inspection only; no SQL, Auth operation, concurrency test, migration or service request was run. `psql` was not found on PATH and the checked virtualenv lacks psycopg/psycopg2/asyncpg. Direct claiming remains blocked on verified provider behavior and the other Phase 4 security gates. Next: review and separately authorize an isolated test with a verified persistent connection and disposable accounts.

## Phase 4 — Prompt #014E-2: isolated inventory and Auth observations

- User reports that the isolated inventory matched expected capsule/recipient columns, nullability and catalog-level table RLS/SELECT permissions; no recipient rows were present, three self-RPC permission checks passed, recipient constraints were validated, and `recipients_check3` blocked tokenless pending rows. These are reported results from the isolated project, not independently rerun here or proof of client-role denial.
- User reports email-change confirmation and Secure Email Change were enabled, a supported User B session update returned HTTP 200, confirmation emails arrived, and the change completed. The reported final state was confirmed email, change status zero, no pending change and no deletion marker. No addresses, UUIDs or confirmation links are documented. See `docs/PHASE_4_AUTH_VERIFICATION_014E.md`.
- Auth row-lock and concurrent email-change/claim behavior, direct schema and authorization, and claim/cancel/reveal races remain unverified. Next: review and separately authorize a safe isolated concurrency verification plan before migration design. No direct-capsule feature is implemented.

## Phase 4 — Prompt #014E-1: isolated Auth email-change preparation

- Prepared `.venv/aftertime_update_isolated_user_b_email.py` for a single user-session email update against the fixed isolated project. The paste-friendly GUI masks the publishable key/password, accepts the new address visibly and requires a final confirmation after sign-in. It does not confirm email links, display response bodies or retry requests. The installed Supabase Auth client source was inspected for its authenticated `PUT /user` request shape.
- Python AST syntax parsing passed; `git check-ignore -v` matched `.gitignore:2`, and `git ls-files --` returned no tracked entry. The script was not run and no service was contacted. Next: independently verify User B, key provenance and the project's confirmation settings before a separately authorized manual run; provider settings determine whether confirmation is required, and a request timeout can have an uncertain outcome.

## Phase 4 — Prompt #014D: pre-migration inventory preparation

- Prepared read-only `services/api/tests/sql/inventory_phase4_pre_migration.sql` and `docs/PHASE_4_INVENTORY_014D.md` for the separately confirmed disposable SQL-test project. The script reports catalog metadata, effective-privilege indicators, overlapping aggregate counts and basic drift checks; literals in expressions are redacted, and small counts/catalog identifiers may still be sensitive.
- No SQL was executed and no Supabase service contacted. PostgreSQL parsing and live privileges remain unverified; see the inventory documentation before any separately authorized execution. Direct client-role denial and Auth/concurrency require independent tests.
- Static lexical/structural check passed for 14 SELECT statements, with balanced parentheses and no prohibited statement keywords. No PostgreSQL parser was available, so this is not a PostgreSQL syntax validation. Untracked-file whitespace check and `git diff --check` passed; Git emitted LF-to-CRLF warnings and does not check untracked files.

## Phase 4 — Prompt #014C: security prerequisites

- Prepared `docs/PHASE_4_SECURITY_PREREQUISITES_014C.md` with source-versus-deployed inventory, self-compatibility and abort conditions, current-confirmed-email and Auth locking evidence gaps, two-session race plans, dormant schema-slice assessment and explicitly unapproved operational defaults.
- Static repository review only: no SQL or service requests, executable migration, application code, dependency, commit or push. Auth email-change/reassignment semantics, effective privileges, lock ordering and isolated race outcomes remain unverified; direct-capsule activation is blocked until the documented gates are resolved. Next: review decisions and separately authorize isolated verification.

## Phase 4 — Prompt #014B: direct-capsule schema design

- Prepared `docs/PHASE_4_SCHEMA_DESIGN_014B.md` with proposed tokenless pending-state constraints, seven-day expiry, UUID-bound claims, verified-email authority, lock ordering, service-only RPCs, sender/recipient projections, retry rules, initial abuse budgets and security/race tests. The Auth locking, email reassignment and effective-privilege assumptions remain unverified and block an executable migration until reviewed.
- Inspected the existing migrations, self RPCs, profile provisioning and SQL test patterns. No SQL, migration, live service, application-code or dependency changes were made. Next: approve the design and resolve its listed security decisions before separately scoping executable schema work.

## Phase 3 — mobile integration commit preparation

- Core mobile API integration, list, text-only creation, secure reveal and cancellation are implemented. The latest local verification passed typecheck, lint and **27 mocked mobile tests**. The user reports the core flow works smoothly on a physical Android phone; individual Android edge cases have not been independently verified here.
- Outstanding checks include early-reveal denial, logout/account switching, app-switcher privacy, interrupted cancellation, timezone/DST, accessibility and release-build transport. UI/UX redesign remains pending. Beta and release readiness have not been established. See `docs/PHASE_3_FINAL_REVIEW.md` for the detailed checklist and limitations.

## Phase 3 — Prompt #013G-3: final mobile integration review

- Reviewed the mobile API, auth/navigation, list, creation, reveal, cancellation, tests and candidate documentation. User reports core functionality works smoothly on a physical Android phone; individual scenarios were not independently rerun here. No critical code defect was confirmed, and no application behavior was changed. The current mobile integration slice is ready for a Git commit; this is not a beta/release readiness claim.
- From `apps/mobile`, `npm run typecheck`, `npm run lint` and `npm test` passed; **27 mocked tests passed**. `git diff --check` passed with LF-to-CRLF warnings; a separate scan of then-untracked files found no whitespace issues. A targeted candidate-file secret-pattern scan found no matches; `.env` and temporary `.venv` launchers remain ignored. No live services were contacted.
- `docs/PHASE_3_FINAL_REVIEW.md` lists the commit candidates, missing historical documentation, security/lifecycle limitations and prioritized Android checks. Next: confirm the privacy, account-switch and cancellation interruption cases on Android and separately authorize any commit.

## Phase 3 — Prompt #013G-2B: development Android server launcher

- Prepared `.venv/aftertime_dev_android_server.ps1` to read the five backend settings from root `.env` as data, reject the isolated project, compare development URL and publishable key with the mobile `.env`, check the LAN address and TCP port, and require explicit development-project and startup confirmation. It binds only `192.168.18.155:8002`, passes settings to the child process and disables access logging; no existing process is automatically stopped.
- Read-only checks without displaying values found the root URL was not the isolated project, the URL and public key matched mobile configuration, and URL/issuer/audience/key formats passed. PowerShell parser, dummy project-reference matching and Git-ignore checks passed; the new file is untracked and ignored. The launcher, port check and server were not executed, and no services or records were contacted or changed.
- Next: independently confirm the original development project and use disposable test accounts before manually launching. Matching keys by format cannot prove server-key provenance. The assigned address, port and firewall must be checked at launch; local HTTP exposes bearer tokens on the network.

## Phase 3 — Prompt #013G-2A: isolated Android server launcher

- Prepared `.venv/aftertime_isolated_android_server.ps1`, pinned to isolated project `wokkxbgbrsmydozvyvkt` and LAN address `192.168.18.155:8002`, with explicit confirmation, masked paste-friendly key entry and TCP occupancy checks before and after the dialog. Key type checks cannot establish project provenance; the operator must verify it. Keys are passed to the child process only and not persisted by the script.
- PowerShell `Parser.ParseFile` reported no syntax errors. `git check-ignore -v .venv/aftertime_isolated_android_server.ps1` matched `.gitignore:2`; `git ls-files --` returned no tracked entry. The script, port checks and GUI were not executed, and no server or live service was contacted. Next: separately run the launcher on a trusted network with verified isolated keys and disposable accounts; confirm the LAN IP and firewall policy. HTTP does not encrypt bearer tokens.

## Phase 3 — Prompt #013G-1: Android test preparation

- Prepared `docs/ANDROID_TEST_PLAN_013G.md` with isolated emulator and physical-device setup, safe synthetic fixtures, ordered manual checks and cleanup constraints. Current source uses Expo Go; a development build is not configured. `adb` and `emulator` were not found on PATH; Node, npm, Python, mobile dependencies and the existing virtualenv were present. Several prior audit documents are absent in the current workspace, as recorded in the plan.
- Read-only local inspection only; no servers, Android emulator, live services, migrations or dependencies were started or changed. No Android test has been run. Next: review the plan and run it separately against confirmed disposable accounts and project when ready.
- `git diff --check` passed with LF-to-CRLF warnings; it excludes the untracked test plan.

## Phase 3 — Prompt #013F: mobile cancellation

- Added a confirmed, accessible cancellation action to the protected capsule detail. The controller prevents duplicate requests, clears revealed text and metadata on success, and returns to a fresh list. Uncertain failures prevent further detail actions and ask the user to refresh before trying again; focus/session/route disposal aborts and invalidates pending work.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed; `npm test` passed 27 mocked tests. No live services were contacted. See `docs/MOBILE_CAPSULE_CANCEL_013F.md` for uncertain-outcome and Android verification limitations. Next: validate the full mobile flow with disposable fixtures and hardware/session interruption scenarios.
- From the repository root, `git diff --check` passed with LF-to-CRLF warnings; it does not include untracked files.

## Phase 3 — Prompt #013E: mobile detail and reveal

- Added protected UUID-only detail navigation, metadata lookup across list pages and explicit server-authorized reveal. Focus/session/route cleanup clears private state and aborts or invalidates pending requests; no reveal is automatic or persisted. See `docs/MOBILE_CAPSULE_DETAIL_013E.md` for pagination and native verification limits.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed; `npm test` passed 23 mocked tests. From the repository root, `git diff --check` passed with LF-to-CRLF warnings and excludes untracked files. No live requests were made. Next: validate focus, session changes and server-time reveal on Android using disposable fixtures.

## Phase 3 — Prompt #013D: mobile self-capsule creation

- Added protected text-only creation from the capsule list, manual native-compatible local date/time entry, review with timezone and server-time warning, validation, and uncertain-outcome handling without POST retries. Success clears the message and returns to a fresh list; session changes and unmount abort and invalidate submission. No backend, migration or dependency changes.
- From `apps/mobile`, `npm run typecheck` passed, `npm run lint` passed after an initial JSX lint error was fixed, and `npm test` passed 17 mocked tests. No live requests were made. See `docs/MOBILE_CAPSULE_CREATE_013D.md` for design, timezone limitations and required Android checks. Next: verify create/list, session change, timezone and keyboard behavior on Android using disposable data.
- From the repository root, `git diff --check` passed with LF-to-CRLF warnings; Git excludes untracked files, whose new creation files separately passed a trailing-whitespace check.

## Phase 3 — Prompt #013C: mobile capsule list

- Added a protected read-only list route and Home entry, using the existing capsule service. It displays metadata, local reveal time and the server's last reported status, with loading, empty, retry, pull-to-refresh, pagination and ID deduplication. Session changes remount the list; request abort and generation checks suppress stale results. No capsule data is persisted.
- From `apps/mobile`, `npm run typecheck` passed after fixing an initial FlatList typing error; `npm run lint` passed; `npm test` passed 12 mocked tests. No live service was contacted. See `docs/MOBILE_CAPSULE_LIST_013C.md` for implementation and limitations. Next: manual Android validation and separately scoped creation work.
- From the repository root, `git diff --check` passed with LF-to-CRLF warnings; Git does not check untracked files.

## Phase 3 — Prompt #013B: mobile API foundation

- Added a reusable authenticated request client while retaining Home's `/v1/auth/me` interface, plus typed and validated create/list/reveal/cancel capsule services. No screens, navigation, backend code, migrations or dependencies changed; no automatic requests, caching or POST retries were added.
- From `apps/mobile`, `npm run typecheck` passed; `npm run lint` passed after fixing an initial test-only ESLint global error; `npm test` passed 8 mocked tests using Node's built-in runner and installed TypeScript. No live services were contacted. Backend tests were not rerun because backend code was unchanged.
- From the repository root, `git diff --check` passed with LF-to-CRLF warnings; Git's check excludes untracked files.
- See `docs/MOBILE_API_FOUNDATION_013B.md` for details and limitations. Next: separately implement the capsule list, abort on account changes, and verify on Android. A create timeout may have an uncertain outcome.

## Phase 2 — Prompt #012K: cancellation final review

- User reports migration 0005 applied to isolated and development projects, SQL Editor tests passed, and the isolated FastAPI integration passed cross-account denial, owner cancellation, repeat, reveal denial and no-store checks. User also reports the database timestamp was set and the synthetic fixture was cleaned up with zero rows remaining. These live results were not independently verified here.
- Reviewed the nine uncommitted cancellation-related files. Targeted JWT, Supabase key and private-key pattern scans found no matches; UUID matches were SQL zero placeholders and fixed Python mock fixtures. The temporary `.venv` diagnostic scripts remain ignored and untracked. No application behavior or migrations were changed in this review.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **145 passed, 2 warnings** (Starlette TestClient deprecation and test-only short HMAC key). From root, `git diff --check` passed with LF-to-CRLF warnings; separate checks found no trailing whitespace or missing final newline in the three untracked files.
- Next: review and commit the cancellation slice when authorized. Two-session races and exact-time equality remain unverified; notification/invitation cancellation coordination is required before those flows are enabled.

## Phase 2 — Prompt #012J: cancellation test authentication alignment

- User reports the authentication-order diagnostic returned HTTP 200 for both users in both orders, with authorization headers and nonempty bearer tokens; this was not independently run here. The prior cancellation-test 401 has no confirmed root cause.
- Updated `.venv/aftertime_test_isolated_cancel.py` to import the diagnostic's sign-in logic and fixed isolated project reference, sign in both users before API verification, and retain separate clients and tokens through the cancellation checks. API requests use the diagnostic's explicit request building and send pattern. Both verified identities must pass before any cancellation request. Existing cross-user denial, owner cancellation, repeat, reveal denial and no-store assertions remain.
- Static checks: AST parsing of both scripts passed; `git check-ignore -v` matched `.gitignore:2` for both; `git ls-files --` returned no tracked entries. The test was not executed and no network or credentials were used. Next: user may run `.venv\Scripts\python.exe .venv\aftertime_test_isolated_cancel.py` against the confirmed isolated fixture; live outcome remains unverified.

## Phase 2 — Prompt #012I: isolated authentication order diagnostic

- Prepared `.venv/aftertime_diagnose_isolated_auth_order.py` with paste-friendly credential input and separate HTTP clients and tokens. It signs in both accounts and checks `/v1/auth/me` in A, B, B, A order, printing only the requested safe statuses and header-presence booleans. It makes no capsule requests.
- Code inspection found the cancellation and standalone diagnostics construct sign-in and authentication requests equivalently; the cancellation script uses a separate client and headers per sign-in. The API caches its JWKS client, not a user identity in the inspected authentication code. No cause for the reported 401 is confirmed.
- Static check: `.venv\Scripts\python.exe -c "import ast,pathlib; p=pathlib.Path('.venv/aftertime_diagnose_isolated_auth_order.py'); ast.parse(p.read_text(encoding='utf-8'), filename=str(p)); print('Syntax OK')"` passed. `git check-ignore -v .venv/aftertime_diagnose_isolated_auth_order.py` matched `.gitignore:2`; `git ls-files -- .venv/aftertime_diagnose_isolated_auth_order.py` returned no tracked entry.
- The diagnostic was not executed; no credentials or network were used. Next: user can run `.venv\Scripts\python.exe .venv\aftertime_diagnose_isolated_auth_order.py` and compare the four status lines. Live behavior remains unverified.

Updated: 2026-11-12

## Current phase

Phase 2, Prompt #012C: self-capsule cancellation API implemented and tested with mocked database calls. The user reports migration 0005 applied to development and its isolated SQL Editor tests passed; those live results were not independently checked here. Earlier records are historical.

## Repository inspection

Initially present: `.git/`, `.venv/`, `.gitignore`, and `docs/AfterTime_Project_Report.md`. No application source, root README, package manifests or AGENTS.md existed. The requested `docs/PROJECT_REPORT.md` path was absent; the existing report was read fully and left untouched. Existing `.gitignore` and report were already untracked before this task.

## Completed work

- Created root AGENTS.md with scope, architecture, collaboration and security conventions based on the report.
- Created minimal `apps/mobile` Expo Router/TypeScript source, app configuration, strict typecheck and lint scripts, and startup README.
- Added warm cream/terracotta welcome screen: AfterTime; Write today. Reveal tomorrow. No buttons or extra features.
- Verified SDK 58 Android Expo Go compatibility through official Expo download page and release notes; selected pinned package versions from the official SDK 58 sources (linked in the mobile README).
- Preserved root ignore rules: existing node_modules, .expo, environment, build and log exclusions already cover this scaffold. Git, `.venv` and the report were not changed. No commit, push or deployment.

## Dependency versions

**Installed: none.** These are requested pins, not confirmed installations:

| Package | Version |
| --- | --- |
| expo | 58.0.23 |
| expo-constants | 58.0.15 |
| expo-linking | 58.0.16 |
| expo-router | 58.0.30 |
| expo-status-bar | 58.0.4 |
| react | 19.3.0 |
| react-native | 0.88.1 |
| react-native-safe-area-context | 5.11.1 |
| react-native-screens | 4.30.1 |
| @types/react | 19.3.0 |
| eslint | 9.18.0 |
| eslint-config-expo | 58.0.4 |
| typescript | 6.0.3 |

Environment checked: Node v24.19.0; npm 12.0.2.

## Checks actually executed

| Command/check | Actual result |
| --- | --- |
| `npm view expo version` / template metadata | Failed: EACCES reaching registry.npmjs.org; original default cache also unwritable. |
| `Test-NetConnection registry.npmjs.org -Port 443 -InformationLevel Quiet` | False. |
| `npm install --fetch-retries=0 --fetch-timeout=15000 --cache "$env:TEMP\aftertime-npm-cache"` in apps/mobile | Failed: EACCES fetching @types/react; temporary writable cache did not resolve registry access. No lockfile/install completed. |
| `npm run typecheck` | Failed: missing Expo base config and module declarations; JSX configuration unavailable because dependencies were not installed. A TypeScript executable was available on PATH; project-pinned compiler not installed. |
| `npm run lint` | Failed: eslint executable not found. |
| PowerShell ConvertFrom-Json on package.json and app.json | Passed parsing. |
| `git diff --check` | Exit 0; limited value because created files are untracked. |
| Android visual/runtime check | Not executed; no phone session available and installation failed. |

## Run commands and next steps

Run in an ordinary PowerShell terminal with npm registry access:

```powershell
Set-Location C:\Users\Hp\Desktop\aftertime\apps\mobile
npm install
npx expo install --check
npm run typecheck
npm run lint
npm start
```

Update Android Expo Go to SDK 58 support, use the same Wi-Fi as the PC and scan the terminal QR code in Expo Go. Full instructions: `apps/mobile/README.md`.

Resolve installation first; retain the generated lockfile, inspect dependency/peer compatibility, then rerun all checks and manually verify on Android (including large text). Record actual results here before declaring Part 1 complete. Backend, web, Supabase, auth, capsules, deployment and CI remain outside this task; await the user's next instruction after foundation validation.



## Phase 0 — Part 1: Mobile Scaffold Verification

Status: COMPLETE
Date: November 10, 2026

### Completed
- Expo React Native mobile application scaffolded.
- AGENTS.md and project documentation created.
- npm dependencies installed successfully.
- Expo SDK compatibility check passed.
- TypeScript check passed.
- ESLint check passed.
- AfterTime welcome screen successfully tested on Android using Expo Go.

### Issues resolved
- React/React DOM peer dependency conflict:
  Pinned react-dom to 19.3.0 to match React.
- ESLint version incompatibility:
  Upgraded ESLint from 9.18.0 to 9.39.5.
- ESLint nested configuration error:
  Updated eslint.config.js to use defineConfig().

### Remaining technical debt
- Review 10 moderate npm vulnerabilities.
- Review ESLint deprecation warning.
- Recheck dependency compatibility before production release.

### Next task
Phase 0 — Part 2: Scaffold the FastAPI backend,
implement GET /health, and add a basic automated test.

## Phase 0 — Part 2: FastAPI backend foundation

- Added a minimal FastAPI app and `GET /health`, plus a test for its status and JSON response.
- Installed into the existing root `.venv` using Python 3.11.9. Direct pins: FastAPI 0.162.3, Uvicorn 0.54.0, pytest 9.2.0, HTTPX 0.28.1. `services/api/requirements-lock.txt` records resolved dependencies.
- From the repository root, `.\.venv\Scripts\python.exe -m pip install -r services/api/requirements.txt` succeeded with network access after the sandboxed attempt failed with WinError 10013.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest` passed: 1 test, 1 warning. Starlette warns that HTTPX-based TestClient is deprecated in favor of httpx2; review when updating dependencies.
- From the repository root, `.\.venv\Scripts\python.exe -m pip check` passed: no broken requirements.
- No remaining blocker for this slice. Server startup was not manually exercised; install, startup, and test commands are documented in `services/api/README.md`.
- Next task: choose the next Phase 0 slice; web and CI remain planned and were not implemented here.

## Phase 0 — Part 3: Next.js web foundation

- Added a responsive landing page and Next.js App Router, TypeScript, Tailwind and ESLint configuration under `apps/web`.
- Requested pins: Next.js and eslint-config-next 16.4.6, React and React DOM 19.3.0, Tailwind and @tailwindcss/postcss 4.1.18, PostCSS 8.5.6, TypeScript 5.9.3, ESLint 9.39.2, @types/node 24.10.1, @types/react 19.2.7 and @types/react-dom 19.2.3. Installation did not finish, so compatibility of the full set is unverified and no lockfile was produced. npm warned ESLint 9.39.2 is no longer supported.
- Node 24.19.0 and npm 12.0.2 are installed. Next.js documentation specifies Node 20.9 or newer.
- `npm install --fetch-retries=0 --fetch-timeout=15000` failed with EACCES reaching the npm registry and writing the default cache log. A network-approved `npm install` downloaded packages but was interrupted after several minutes without completion.
- Checks attempted from `apps/web` after the incomplete installation: `npm run typecheck` failed with TS2614 for Next's Metadata export; `npm run lint` failed because eslint was not found; `npm run build` failed because next was not found. These are not successful validation results. No browser or responsive visual check was performed.
- Blocker: complete installation and resolve any dependency or check errors. From the repository root run `Set-Location apps/web`, `npm install`, `npm run typecheck`, `npm run lint`, and `npm run build`. Start locally with `npm run dev`.
- Next task: finish and verify the web foundation before selecting the next Phase 0 milestone.

## Phase 1 — Part 1: database design

- Drafted `services/api/migrations/0001_initial.sql` and `docs/DATABASE_DESIGN.md` with six tables, constraints, indexes and default-deny client access.
- Reviewed SQL and security design statically; no SQL was executed, no database connection was made, and no PostgreSQL, migration or RLS tests were run. No credentials were configured.
- Blockers before application: human review, decisions and isolated database validation described in the design. The backend privileged role and migration runner are not provisioned.
- Next task: obtain approval and resolve open decisions, then test the migration and access controls in an isolated environment before any cloud application.

## Phase 1 — migration review

- Reviewed and strengthened invitation, capsule timestamp and notification state constraints, and documented the database/backend boundary and access alternatives.
- Reviewed SQL ordering and permissions statically. No SQL was executed, no database was contacted, and no PostgreSQL or RLS tests were run. `git diff --check` is a whitespace check only.
- Next: review open design decisions and, with authorization, test the draft on an isolated Supabase-compatible database before considering cloud application. Backend access and migration tooling remain unprovisioned.

## Phase 1 — recipient and server-access review

- Added a recipient state check allowing historical claims after `ON DELETE SET NULL`, documented self and external states, expiry/revocation responsibilities, privileged-client grant requirements and a minimal isolated test plan.
- Static review only; no SQL was executed, no Supabase connection was made and no database tests were run. Server access method, invitation rotation and post-claim revocation policy remain decisions.
- Next: review decisions and obtain authorization for isolated testing; do not apply to Supabase yet.

## Phase 1 — authentication foundation Part A

- Added environment configuration, asymmetric JWKS token verification and `GET /v1/auth/me`; preserved `/health`. Added placeholder-only root `.env.example` and setup documentation.
- Added PyJWT 2.15.1 with cryptography 50.0.2, cffi 2.1.1 and pycparser 3.12 to the lockfile. Installation into root `.venv` succeeded after a sandboxed pip attempt could not find the package and a network-enabled retry succeeded.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest`: 11 passed, 2 warnings (existing Starlette HTTPX deprecation and test-only short HMAC key warning). From root, `.\.venv\Scripts\python.exe -m pip check`: no broken requirements.
- Tests use local keys and mocked key lookup; no live Supabase token or project configuration was tested. Confirm actual signing algorithm, issuer and audience. HS256 is intentionally unsupported; Supabase recommends Auth server verification for legacy symmetric tokens, which remains future work if needed.
- Next: verify development project signing configuration and plan the appropriate integration and cross-account authorization tests before building auth-dependent features.

## Phase 1 — profile provisioning design

- Added `services/api/migrations/0002_profile_provisioning.sql`: restricted SECURITY DEFINER trigger, explicit postgres ownership, revoked client execution and idempotent missing-profile backfill. Existing RLS and table grants are unchanged; 0001 was not edited.
- Updated `docs/DATABASE_DESIGN.md` with privilege assumptions, signup rollback behavior, verification SQL and the dedicated-owner alternative. The postgres-owned function follows Supabase's minimal trigger pattern but retains a privileged owner; that tradeoff requires review.
- Static review only; no migration, SQL verification queries, PostgreSQL or Auth signup tests executed. No secrets, application changes, commits or deployment.
- `git diff --check` completed without whitespace errors (line-ending warnings only); `git diff -- services/api/migrations/0001_initial.sql` was empty. These are file checks, not database validation.
- Next: review migration ownership and failure behavior, then authorize isolated tests for backfill, new signups, duplicates, client denials, concurrent inserts and failure rollback before migration approval.

## Phase 1 — Expo mobile authentication

- Added welcome actions, sign-in/signup, email confirmation instructions/resend, protected home and local logout. Added Supabase client, SecureStore adapter, session restoration/listener, foreground refresh and expiry handling. No table queries.
- Installed exact @supabase/supabase-js 2.119.0, react-native-url-polyfill 4.0.0 and expo-secure-store 58.0.2 with lockfile; retained existing Expo/Router/React Native versions.
- Added mobile .env.example. `git check-ignore -v apps/mobile/.env` confirmed root ignore rule line 10; no ignore changes.
- From apps/mobile: `npx expo install --check` passed after network-approved retry of EACCES; `npm run typecheck` and `npm run lint` passed after initial AppState type and effect-state lint fixes. npm reported 10 moderate vulnerabilities; no force fixes performed.
- No live credentials, Android, signup/email, refresh or native storage tests were used/run. README provides manual cases, including storage errors and offline logout limits.
- Configure mobile public env values, enabled email confirmation and trusted reachable Supabase Site URL. Browser confirmation followed by manual app sign-in is supported; automatic deep-link return is not implemented for Expo Go.
- Next: complete manual Android authentication acceptance and review dependency advisories before the next milestone.

## Phase 1 — mobile-to-FastAPI integration

- Added an authenticated client for `/v1/auth/me`, a Home connection status and retry, and the public API URL environment placeholder. Tokens remain in the existing session storage and are not logged. Requests use a configurable 10-second default deadline and cancellation, and production builds require HTTPS; private LAN HTTP is allowed in development only.
- From `apps/mobile`, `npm run typecheck` and `npm run lint` passed after fixing the initial nullable-client and effect lint failures. `npx expo install --check` initially failed with EACCES; the network-enabled retry completed but exited 1 because Expo now recommends patch updates: expo 58.0.24, expo-constants 58.0.16, expo-linking 58.0.17, expo-router 58.0.31, expo-secure-store 58.0.3 and expo-status-bar 58.0.5. Existing versions were preserved; no dependencies were added or updated.
- No live backend request or Android integration test was run in this task. Configure the mobile API URL with the laptop's current LAN IP and port; the README documents setup, HTTPS requirement and manual tests.
- Next: run the Android connection, failure, retry and logout tests; review Expo patch updates separately.

## Phase 2 — Part 1: secure Supabase data access

- Added lazy, independent database configuration for `SUPABASE_URL` and server-only `SUPABASE_SECRET_KEY`; preserved all authentication variables and the JWT verifier. Added a placeholder to root `.env.example`.
- Added `app/database.py` with a small repository using existing pinned HTTPX 0.28.1 against the Supabase Data API. Current Python SDK docs support secret keys; the full SDK was not needed or installed. Documentation links and tradeoffs are in `services/api/README.md`. No dependency or lockfile changes.
- Added local operator command `python -m app.check_database`: bounded HEAD read against `public.profiles`, no row body/count returned, fixed success/failure output and exit codes. No database API endpoint. Private client sends only an apikey secret, never a user JWT; redirects and environment proxies disabled, five-second HTTP operation timeouts, deterministic client cleanup.
- Added mocked tests for missing/invalid secrets and URLs, success, provider denials/failures, redirects, network failures/timeouts, sanitized errors/logging and independent health/API behavior. Existing authentication success test now explicitly runs without a database secret.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **43 passed, 2 warnings**. Warnings are the existing Starlette HTTPX TestClient deprecation and test-only short HMAC key. From root, `.\.venv\Scripts\python.exe -m pip check`: **No broken requirements found**. `git diff --check` passed with line-ending warnings only.
- No live Supabase connection, real credentials, schema/migration/RLS edits, mobile/web edits, capsule logic, workers, commits, pushes or deployment. No live connectivity success is claimed.
- No implementation blocker. Compatibility limits: HTTPS default/443 origins and new `sb_secret_*` keys only; hosted project Data API exposure, effective schema/table grants and key validity remain untested here. Existing TestClient deprecation should be reviewed during a separate dependency update.
- Next task: after authorization, run the README's masked-input PowerShell connectivity command against development only and record its actual result. Then separately scope the next core API slice with explicit per-user authorization and atomic transaction design.

## Test fixture push-protection cleanup

- Replaced secret-shaped test literals with clearly fake runtime-constructed placeholders while preserving valid and invalid credential cases; application behavior is unchanged.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: 43 passed, 2 existing warnings (Starlette TestClient deprecation and short test HMAC key). From root, `git diff --check`: passed, with line-ending warnings only.
- No real environment secrets were accessed or changed. No Git history changes or push were performed. Next: review the fix and decide separately how to address the already-existing rejected commit.

## Phase 2 — Prompt #009: atomicity gate

- Read the required report, design, status, backend source, migrations, tests and README. The repository has only a read-only Data API check; no creation RPC or direct database transaction infrastructure exists. Separate capsule/recipient HTTP inserts can leave partial data, and compensating deletion is not atomic.
- Confirmed title has no database maximum; body is limited to 2,000 characters but currently allows empty text. Self-recipient requires owner profile ID, claim timestamp and normalized nonempty intended_email, with null invitation fields. Profiles contain no email and the verifier returns only a verified UUID.
- Documented the exact proposed `0003_create_self_capsule.sql` RPC, access restrictions, server-derived email and timestamps, safe response projection, API contract and verification requirements in `services/api/README.md`. No migration file was created and no capsule code or tests were implemented, following the user's explicit stop-before-writes instruction.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **43 passed, 2 existing warnings** (Starlette HTTPX TestClient deprecation and test-only short HMAC key). This is baseline regression coverage, not capsule or transaction validation. No live project access or real credentials used.
- Only README and STATUS changed. No application, existing migration, schema, mobile/web, dependency, Git history, commit, push or deployment changes.
- `git diff --check`: passed with line-ending warnings only.
- Next: obtain approval for the narrow server-only RPC migration proposal, then implement and validate rollback/role restrictions in an isolated database before enabling capsule writes. Timeouts after commit still need an explicit idempotency/retry policy; do not automatically retry creation.

## Phase 2 — Prompt #009A: atomic self-capsule RPC migration

- Added `services/api/migrations/0003_create_self_capsule.sql`: `public.aftertime_create_self_capsule(uuid, text, text, timestamptz)`, explicit four-column safe return type, postgres-owned SECURITY DEFINER, empty search_path, UTC and service_role execution grant. PUBLIC/anon/authenticated execution explicitly revoked. Migrations 0001/0002, table definitions, table grants and RLS unchanged.
- Validates nonblank title/body, body <= 2,000 characters, finite unlock time in `(database now, database now + 90 days]`. Locks the confirmed Auth user and existing profile, derives normalized email internally, and uses one captured database clock instant for creation/claim timestamps. Inserts capsule and self-recipient in one call without swallowing failures. No media, invitation or notification operations.
- Added `services/api/tests/sql/bootstrap.sql` and `test_create_self_capsule.sql` for a fresh disposable plain PostgreSQL cluster, with minimal simulated Auth columns and roles. Supplied exact Docker/psql commands in README. SQL cases cover valid creation, safe projection, recipient-failure rollback, invalid inputs/owners, execution restrictions and RLS retention. No real or secret-shaped credentials added.
- Environment discovery: `Get-Command psql,postgres,pg_ctl,docker -ErrorAction SilentlyContinue` found only Docker. `docker context ls` exited 1 with access denied reading Docker configuration/context metadata. No usable local PostgreSQL test environment established; no SQL, Docker container or live Supabase operation executed. No credentials read or configured.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **43 passed, 2 existing warnings** (Starlette HTTPX TestClient deprecation and test-only short HMAC key). These tests validate unchanged Python behavior, not this migration. `git diff --check` passed with line-ending warnings only. Diff for migrations 0001/0002 was empty.
- README/STATUS already had uncommitted Prompt #009 documentation at task start; preserved and extended it. No endpoint, mobile/web, dependency, commit, push or deployment changes.
- Blocker before use: execute the supplied SQL in disposable PostgreSQL, then validate against Supabase's actual Auth schema, effective role memberships/default grants, concurrent Auth updates/deletion and Data API function visibility. The broad postgres owner and trusted backend owner_id assertion are explicit security boundaries. API input/error sanitization and naive-time rejection remain future work; RPC atomicity does not provide retry idempotency.
- Next: isolated database validation and review, then separately authorize any migration application and endpoint implementation. Stop at Prompt #009A.

## Supabase SQL Editor test-script review

- Reviewed bootstrap.sql, test_create_self_capsule.sql and migration 0003. Original scripts are for an empty plain PostgreSQL database and psql: backslash commands, role/mock Auth creation, fixed database/user IDs, a cascading profile deletion, global counts and an unscoped failure trigger make them unsuitable for direct SQL Editor use. Migration 0003 remains unchanged and must not be reapplied for testing.
- Added `services/api/tests/sql/test_create_self_capsule_sql_editor.sql`: one DO statement using an existing dedicated confirmed test Auth user/profile, supplied explicitly by UUID and matching email. Tests success as service_role, exact safe output fields, self-recipient consistency, validation, role privileges/denials, RLS and forced second-insert rollback. It uses unique helper names and an owner-scoped trigger, then rolls back all test writes/DDL even on success. No Auth mutations or cleanup DELETEs. A three-second lock timeout bounds waiting for trigger DDL locks; use an idle disposable project.
- Updated README with incompatibilities, exact file to copy, prerequisites, expected successful completion/optional PASS notice, cleanup semantics and limitations. The existing test user/profile remain untouched; SQL Editor tests do not cover HTTP/JWT behavior, managed Auth failure fixtures, concurrency or exact time boundaries.
- Verification is static review and whitespace checking only. No SQL tests, backend tests, credentials, database connections, migration execution, commit, push or deployment performed in this task, as requested.
- `git diff --check` passed with line-ending warnings only.
- Next: user runs the entire SQL Editor script as postgres in the disposable project after replacing the two test-identity placeholders, then records actual results. Runtime correctness is not claimed before that execution.

## Phase 2 — Prompt #009B: self-capsule creation API

- Added authenticated `POST /v1/capsules`, strict request validation and a four-field safe metadata response. Identity comes only from the existing verified JWT subject. Extra request fields are rejected; request-validation responses never echo input. Times require an explicit offset, are normalized to UTC, and checked against API server time; migration 0003's database clock and checks remain authoritative.
- Added one repository RPC call with only the verified owner, title, body and unlock time. The server-only key remains in the apikey header, no user JWT is forwarded, no redirects or automatic retries occur, and fixed 422/403/503 messages hide provider errors. No direct table inserts, migration/RLS changes or new dependencies.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **75 passed, 2 warnings** (existing Starlette HTTPX TestClient deprecation and test-only short HMAC key). Tests use generated JWT signing keys and mocked HTTP; no real credentials or live DB operations. From root, `git diff --check` passed with line-ending warnings only.
- No mobile/web changes, commit, push or deploy. Prior uncommitted migration and SQL test files were preserved. An uncertain timeout can follow a successful commit; idempotency and rate limiting remain future work. API clock validation can reject near-boundary requests; database validation makes the final decision. `/health` and `/v1/auth/me` remain covered.
- Next: independently review and test the endpoint in a disposable environment when separately authorized, then plan idempotency/rate limits and the next capsule operation.

## Local self-capsule integration script

- Prepared `.venv/aftertime_test_capsule.py` in the existing gitignored virtualenv directory. It authenticates a designated development test account using environment variables or prompts, then makes at most one local creation request, checking the four safe response fields. No secrets, JWTs or response bodies are printed; failures after the POST report an uncertain outcome and prohibit blind retries.
- Confirmed `git check-ignore -v .venv/aftertime_test_capsule.py` matches `.gitignore:2`; `git ls-files -- .venv/aftertime_test_capsule.py` returned no tracked entry. Parsed the script with Python `ast.parse`: `Syntax OK`. No script execution, live requests or credentials were used. No application or migration changes.
- Next: the user can run the script once after confirming the development project and designated account; record the actual outcome, and inspect the database before considering another attempt if the result is uncertain.

## Phase 2 — Prompt #010: authenticated capsule listing

- Added `GET /v1/capsules` using the existing JWT verifier and privileged repository. The database query filters by the verified owner UUID, excludes deleted and cancelled rows, and selects only ID, title, creation and unlock timestamps. Results add locked/unlocked status using one API server clock reading. Cancelled rows are excluded to avoid reporting them as unlocked; no cancellation feature was implemented.
- Added bounded limit (1–50, default 50) and offset (0–10000, default 0), with deterministic created_at DESC/id DESC ordering. Offset pagination is not a stable snapshot under concurrent writes; no total count is returned.
- Mocked tests cover authentication, cross-user/deleted/cancelled filtering, private-field projection, empty pages, pagination/ties, before/at/after unlock status, malformed database responses and sanitized failures. Mock database filtering proves the request shape and response handling, not actual database/RLS enforcement. No real credentials or live database used.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **90 passed, 2 existing warnings** (Starlette HTTPX TestClient deprecation and test-only short HMAC key). No schema, migration, mobile/web, dependency, commit, push or deployment changes.
- From the repository root, `git diff --check` passed with line-ending warnings only.
- Next: with separate authorization, verify the owner filters and pagination against a disposable Supabase project with distinct test users. Independently design reveal authorization and authoritative time checks; listing status does not grant content access. Review pagination snapshot behavior and rate limits before beta.

## Phase 2 — Prompt #010A: listing integration script

- Prepared `.venv/aftertime_test_listing.py` under the existing gitignored directory. It signs in to the designated development test account, makes one GET request to the local listing API, validates the five-field schema and searches the first page for the earlier integration-test title. It prints only PASS/FAIL, the count and whether the expected title was found; credentials and returned records are not printed.
- Static verification only: Python AST parsing and Git ignore checks. The script was not run; no credentials, live authentication or database were accessed. No application, migrations, mobile/web, commit, push or deployment changes.
- Next: run the script manually against the confirmed development project/account, record its actual result, and separately validate cross-account isolation and pagination in a disposable environment.

## Phase 2 — Prompt #010B: cross-account isolation script

- Prepared `.venv/aftertime_test_isolation.py` for the designated development project and User B. It compares User B's verified `/v1/auth/me` identity to a separately supplied User A owner UUID, then requests the first capsule page and checks its metadata and User A capsule UUID. Empty results pass this specific check; a nonempty page without User A's capsule is inconclusive because listing responses contain no owner IDs.
- Static verification only: AST parsing and Git ignore checks. No integration script run, credentials accessed, or live requests made. No application code, migration or backend test changes. Next: manually run the script with confirmed development account/project and known IDs, then record the actual result; independently verify nonempty results and broader isolation in a disposable environment.

## Phase 2 — Prompt #011B: reveal RPC migration

- Added `services/api/migrations/0004_reveal_self_capsule.sql`: `public.aftertime_reveal_self_capsule(p_capsule_id uuid, p_requester_id uuid)` returns only `id, body` after checking verified-backend-supplied owner, noncancelled/nondeleted capsule and claimed self-recipient with null invitation fields. Denials return no rows. A `FOR SHARE` capsule lock precedes a recipient lock; database `clock_timestamp()` is captured afterward, and body is selected only when `unlock_at <=` that time. VOLATILE SECURITY DEFINER, empty search_path, postgres owner, service_role EXECUTE, explicit PUBLIC/anon/authenticated revoke. No changes to 0001–0003, tables, RLS or grants.
- Added `services/api/tests/sql/test_reveal_self_capsule_sql_editor.sql`: disposable-project-only single DO block with synthetic fixtures and rollback, two existing test profile UUID placeholders, owner and cross-owner, locked/cancelled/deleted/missing/invitation/unbound cases, null and invalid UUIDs, safe projection, actual client-role denials and RLS/ACL inspection. The at-or-after check cannot force exact microsecond equality. README documents exact execution prerequisites and two-session race procedures; SQL and races have not been run.
- No `psql`, `postgres`, or `pg_ctl` on PATH; Python environment has neither pglast nor sqlparse. No local PostgreSQL runtime or parser verified. No credentials, live database, SQL execution, migration application, new dependencies, endpoint, commit, push or deployment. User's disposable Supabase project was not accessed.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **90 passed, 2 existing warnings** (Starlette TestClient deprecation and test-only short HMAC key). These are existing Python regressions, not SQL tests. `git diff --check` passed with line-ending warnings; migrations 0001–0003 had no diff.
- Blockers before use: run SQL Editor tests and two-session concurrency scenarios in the disposable project, verify role inheritance/ACLs and PostgREST POST transaction behavior, review postgres SECURITY DEFINER exposure and backend-only identity trust, and test exact time boundary. The future API must sanitize invalid UUID and database errors, prohibit caching and independently verify JWT. Reveal-before-delete may complete even if deletion follows its committed transaction; returned bytes cannot be recalled.
- Next: review and authorize isolated application/test of 0004 only; record actual results before separately scoping the FastAPI reveal endpoint.

## Phase 2 — Prompt #011C: FastAPI self-capsule reveal

- Added `GET /v1/capsules/{capsule_id}/reveal`, using the existing verified JWT subject, UUID validation, no query parameters, and a single POST to the privileged 0004 RPC. No direct body query or application-clock authorization. Empty RPC results for locked, cross-user, cancelled, deleted, missing or non-self capsules map to one generic 404.
- Added strict id/body-only response validation, matching requested UUID, sanitized 422/503 errors, no retries and no-store/no-cache response headers including authentication, validation, method and unexpected-error paths. No application logging of bodies, tokens or provider responses. Secret role remains separate from user JWTs.
- Mock tests cover ES256 authentication, correct RPC arguments, query/header identity overrides, denials, response shape and UUID mismatches, bad JSON/HTTP/network/JWKS/configuration failures, unexpected exceptions, safe response/log contents and cache headers. From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **114 passed, 2 existing warnings** (Starlette HTTPX TestClient deprecation and test-only short HMAC key). No real credentials or live DB used.
- No migration, mobile/web, dependency, commit, push or deployment changes; pre-existing uncommitted 0004 and SQL test artifacts preserved. SQL test outcome, concurrency and live application reported by the user are not independently verified in this task.
- `git diff --check` passed with line-ending warnings only.
- Next: separately review and test the full endpoint using disposable accounts and database fixtures, including before/at/after unlock, concurrency, direct-access grants and intermediary cache/log configuration. Rate limiting and immediate JWT revocation checks remain future work.

## Phase 2 — Prompt #011D: locked reveal integration script

- Prepared `.venv/aftertime_test_locked_reveal.py`, a gitignored one-shot script using masked credentials/UUID, owner-visible metadata and at most one reveal GET. It requires a fixed generic 404 and no-store header for PASS; an already-unlocked capsule, missing first-page metadata or a 200 reveal is INCONCLUSIVE. It never prints records or credentials and does not read a successful reveal body.
- Static verification only: Python AST parse and Git-ignore check. The script was not run and no live authentication, credentials, API request, database change or migration operation was performed. No application code, migrations, commit, push or deployment changes.
- Next: after confirming the development project and owner account, manually run once while the test capsule is still locked. The metadata/API and client clocks are not authoritative for reveal; the RPC database clock decides eligibility. A 404 is generic and does not independently prove denial was due to time.

## Phase 2 — Prompt #011E: cross-account reveal test script

- Prepared gitignored `.venv/aftertime_test_cross_reveal.py` using masked User B credentials and User A owner/capsule UUID prompts. It checks the verified User B subject via `/v1/auth/me`, then makes one reveal GET and requires the exact generic 404 and no-store header. No record creation or modification, retries, or response/credential output.
- Static verification only: AST parsing and Git-ignore check. No integration script execution, live requests, credentials, database changes, application/migration/test changes, commit, push or deployment. User reports an owner locked-capsule denial; this was not independently verified here.
- Next: manually run the script after confirming the original development project and identities; a generic 404 on a locked/missing capsule cannot independently prove the owner check. Verify cross-account denial for an independently confirmed unlocked test capsule in an isolated environment.

## Phase 2 — Prompt #011G: isolated unlocked-reveal infrastructure

- Prepared four gitignored `.venv` files: `aftertime_isolated_server.ps1`, `aftertime_isolated_fixture_create.sql`, `aftertime_isolated_fixture_cleanup.sql`, and `aftertime_test_isolated_reveal.py`. The server derives URL/issuer from the isolated project reference and accepts both keys through masked prompts; the operator must confirm their provenance because opaque keys do not encode a verifiable project reference. No development `.env` changes.
- SQL creates one uniquely marked synthetic historical fixture with a self-recipient; cleanup matches owner, fixture UUID, marker and body, locks both rows, and refuses unexpected recipients, notifications or reports. Neither script creates/deletes Auth users or profiles. SQL Editor user must independently confirm the isolated project before either operation.
- The client authenticates two isolated users with masked prompts, verifies both identities through the separate API on port 8002, and checks one authorized synthetic-body reveal and one generic cross-user denial with no-store. It prints only PASS/FAIL and has no retries.
- Syntax and ignore checks only; no SQL execution, server startup, network requests or credentials. No application/migration changes, commits, pushes or deployment. SQL compatibility, live key provenance, isolation, security behavior and cleanup remain unverified until a separately authorized test.

## Isolated launcher paste support

- Updated gitignored `.venv/aftertime_isolated_server.ps1` to use two masked Windows Forms text boxes that accept paste. Project reference and ISOLATED confirmation remain; URL/issuer/audience and loopback port are unchanged. Configuration is placed only in the spawned server process, with dialog fields, local key references and process-start configuration cleared on normal/error cleanup.
- PowerShell parser and isolated key-prefix function checks with dummy strings passed; `git check-ignore` confirmed the launcher remains ignored, and `git diff --check` passed with line-ending warnings. The GUI and FastAPI server were not started; no real keys or network were used. Windows Forms/PowerShell managed strings cannot guarantee immediate in-memory erasure; clipboard content remains under user control.
- Next: manually use the isolated launcher and verify paste and project/key provenance during the separately authorized test.

## Phase 2 — Prompt #012B: self-capsule cancellation RPC

- Added `services/api/migrations/0005_cancel_self_capsule.sql`: `public.aftertime_cancel_self_capsule(p_capsule_id uuid, p_requester_id uuid)` returns only `id, cancelled_at`. It checks owner and nondeleted capsule, locks capsule FOR UPDATE then claimed/self recipient FOR SHARE, and captures database wall clock after locks. A new cancellation requires `created_at <= now < unlock_at`; denials return no rows. Authorized repeats return the original timestamp, even after unlock; deletion or recipient changes deny repeats. Catchable SQL errors are reraised as a fixed generic error. The trusted backend must derive requester from verified JWT.
- Function is postgres-owned SECURITY DEFINER with empty search_path, explicitly revokes PUBLIC/anon/authenticated and grants service_role EXECUTE. No existing migration, table grant, RLS, application, mobile/web, dependency, commit, push or deployment changes. The postgres owner and direct service_role grants remain privileged boundaries.
- Added SQL Editor script `services/api/tests/sql/test_cancel_self_capsule_sql_editor.sql`, with random synthetic rollback-only fixtures, dedicated test-user placeholders, safe projection, owner/cross-user/recipient/deleted/unlocked checks, idempotency, reveal-after-cancel, direct role denials, ACL/RLS checks and scoped injected-error/DDL rollback. README includes isolated execution and two-session race procedures. Neither script has been run or parsed by PostgreSQL.
- Local availability check found no `psql`, `postgres`, `pg_ctl` or `sqlfluff` on PATH; pglast and sqlparse were absent. Standard-library structural checks cover balanced dollar tags and trailing whitespace only, not SQL syntax or semantics. From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **114 passed, 2 existing warnings** (Starlette HTTPX TestClient deprecation and test-only short HMAC key). Existing backend tests do not cover this SQL. No credentials, live database or SQL requests used.
- `git diff --check` passed with line-ending warnings only; new untracked SQL files were separately checked for trailing whitespace and balanced dollar tags.
- Remaining verification: run the SQL Editor and two-session concurrency checks only in an idle disposable project; verify actual effective grants, generic errors, direct-client denials and PostgREST read-write invocation. Exact-microsecond unlock equality is not forced by the prepared test. No cancellation endpoint exists. The migration does not cancel notification jobs or revoke invitations; do not treat it as sufficient once those flows are enabled without atomic coordination and worker rechecks.
- Next: review and validate 0005 in the isolated project, record actual results, then separately scope application and API work.

## Phase 2 — Prompt #012C: FastAPI self-capsule cancellation

- Added `POST /v1/capsules/{capsule_id}/cancel`: verified JWT subject and validated capsule UUID go to the server-only 0005 RPC as `p_requester_id` and `p_capsule_id`; no direct update, body read or API-clock eligibility check. Query parameters and request bodies are rejected. A successful response contains only ID and UTC cancellation timestamp. Empty results use the same generic 404; malformed results and database failures fail closed with a fixed 503. All route responses use no-store/no-cache, including authentication and validation failures.
- The RPC's reported authorized repeat behavior returns the original timestamp even after unlock, unless deletion or a changed recipient disqualifies it. No automatic retries occur. User reports 0005 applied to development and isolated SQL Editor tests passed; this task did not independently access either project or verify those results.
- From `services/api`, `..\..\.venv\Scripts\python.exe -m pytest -q`: **145 passed, 2 warnings** (existing Starlette TestClient deprecation and test-only short HMAC key). Mocked tests exercise authentication, requester isolation, RPC arguments, generic denials, response shape, repeat handling, cache headers and sanitized failures; they do not prove database enforcement, concurrency or real PostgREST behavior. No real credentials or live requests were used.
- From the repository root, `git diff --check` passed with line-ending warnings. Git does not include untracked files in that check.
- No migration, RLS, mobile/web, dependency, commit, push or deployment changes. Existing uncommitted 0005 and SQL test files were preserved.
- Next: after separate authorization, test only dedicated disposable fixtures: owner cancellation and repeat, cross-account and unlocked denials, reveal after cancellation, real grants, exact unlock boundary and cancellation/reveal races. Before enabling invitations or notifications, coordinate their revocation and worker checks transactionally; rate limits and immediate session revocation remain future work.
