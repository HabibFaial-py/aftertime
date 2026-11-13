# AfterTime status

Updated: 2026-11-12

## Current phase

Phase 2, Prompt #010: authenticated owner-only capsule listing implemented and mock-tested. The user reports live self-capsule creation verified and prior work pushed to main; these live results were not independently rechecked here. Earlier records are historical.

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
