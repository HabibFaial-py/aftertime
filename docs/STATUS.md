# AfterTime status

Updated: 2026-11-11

## Current phase

Phase 1, profile provisioning design. The user reports the initial migration applied and real Supabase ES256 authentication verified. Migration 0002 is a local review draft only; no database connection or execution occurred in this task. Earlier records are historical.

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
