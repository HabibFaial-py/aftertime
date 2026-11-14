# AfterTime status

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
