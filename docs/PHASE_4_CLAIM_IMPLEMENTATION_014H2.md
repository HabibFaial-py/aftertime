# Phase 4 claim implementation: #014H-2 session report

## Session overview

The repository records Prompt #014H-2 as a pre-commit review of the dormant direct-capsule implementation, migrations, tests and research. The original prompt text is not available in this session, so its objective is described from that recorded review rather than reconstructed as a verbatim instruction. The review checked the disabled gates, unavailable claim and discovery paths, self-capsule isolation and test results. It did not implement a working claim.

The outcome remains **blocked for activation**. This report was requested following the #014K-10 Android foundation review. It summarizes existing repository evidence and that local review; it does not represent a new backend implementation or a fresh backend or SQL test run. The direct mobile interface is dormant, and Received Capsules remains unavailable.

## Implementation details

### Files and scope

This reporting task creates this document and updates `docs/STATUS.md`. No application code, tests, migrations, dependencies or activation gates were changed by this reporting task. The preceding #014K-10 review updated `docs/STATUS.md` and found no locally reproducible application defect requiring a fix.

Previously prepared relevant artifacts include:

- `services/api/migrations/0006_dormant_direct_invitation_foundation.sql`, `0007_direct_capsule_draft.sql` and `0008_dormant_claim_preparation.sql`.
- `services/api/app/direct_capsules.py` and `services/api/app/main.py`, with backend tests in `services/api/tests/test_direct_capsules.py` and local SQL checks in `services/api/tests/sql/`.
- `docs/PHASE_4_CLAIM_PREPARATION_014H1.md` and `docs/PHASE_4_DIRECT_BACKEND_014G2.md`, which record the earlier design and local testing.
- Mobile routes `apps/mobile/app/send-to-someone.tsx` and `apps/mobile/app/received-capsules.tsx`, their supporting components and validation modules, and mobile tests. These were prepared after the recorded #014H-2 review.

These artifacts span earlier prompts; the available record does not establish that #014H-2 itself created each file.

### Database migrations and RPCs

Migration 0006 contains a validated `CHECK (false)` gate on direct invitations. Migration 0007 defines separate direct-capsule storage and draft service-only create, cancel and reveal RPCs; its create operation is blocked by the retained invitation gate. Migration 0008 checks the gate and other prerequisites and prepares a partial pending-lookup index. It adds no claim or discovery RPC, policy or grant, and does not enable lookup. The index is a candidate requiring review against any future query and privacy policy.

There is no implemented claim or pending-discovery RPC in these drafts. Successful direct creation and recipient reveal were previously exercised only with synthetic local bindings and a test-only gate removal; those simulations do not establish a secure recipient claim. Deployed schema and effective privileges have not been verified in this reporting task.

### FastAPI and authorization

The direct API flag defaults disabled. The recorded implementation returns a generic 404 before authentication or database access when disabled. With the flag enabled, authenticated claim and pending-discovery endpoints return 503 and do not query the database. The proposed metadata models restrict fields; they are not evidence of a working discovery operation. The direct routes use the existing verified-token identity mechanism for their implemented operations. The database RPCs trust identity supplied by the backend, so their service-only execution boundary matters.

The mobile flag also defaults disabled, and the direct routes are guarded by a session and that flag. Send to Someone validates and reviews details locally with no submission action or direct API call. Received Capsules always renders unavailable; loading, error and empty states are presentation-only. These client-side guards are not server authorization. Existing self-capsule implementation was not changed in the #014K-10 review.

## Test results

| Evidence | Result and limits |
| --- | --- |
| #014H-2 backend, recorded in `docs/STATUS.md` | `..\..\.venv\Scripts\python.exe -m pytest -q` from `services/api`: **200 passed**, two existing warnings. Not rerun for this report. |
| #014H-2 SQL | No disposable local cluster was identified for that review; SQL fixtures were **not rerun**. |
| Earlier #014H-1 local SQL, recorded in its report | PostgreSQL 18 migrations 0001–0008 and local regression/gate checks passed on a disposable loopback cluster. Concurrent calls to the absent claim function failed as expected. This tested the dormant gate, not successful claim eligibility, real claim races or managed Auth. Some earlier direct tests temporarily removed the gate in the disposable environment. |
| Earlier static checks | #014H-2 records `git diff --check` and `git diff --cached --check` passing with line-ending warnings. #014H-1 records Python syntax and Git whitespace checks passing. These are historical results, not fresh checks for this report. |
| #014K-10 mobile review | `npm run typecheck` and `npm run lint` passed; `npm test` passed **43 tests**. `git diff --check` passed with a line-ending warning. Component and guard tests use mocks. |

No backend or SQL tests were run for this reporting task. No successful claim, real provider identity transaction, hosted migration, deployed grant, live bypass or Android device behavior was tested here. No Supabase service was contacted during the #014K-10 review or this reporting task.

## Security status

**Locally supported observations:** repository code contains the default-disabled API and mobile flags, the independent database gate, and fail-closed claim/discovery endpoints. Earlier mocked backend and disposable local SQL tests support those specific behaviors in their test environments. The current mobile review confirmed the route guards and unavailable Received route in source; its tests do not prove native deep-link handling. None of these observations establishes deployed security.

**Unverified assumptions:** current confirmed identity must remain authoritative through the entire claim transaction, including provider email changes, confirmation, deletion and reassignment. A previously recorded row-lock conflict and local Auth stub do not prove the managed provider's transaction boundaries. Actual role inheritance, grants, RLS, direct access and provider behavior in a deployed environment remain unverified. Recipient normalization and mailbox reassignment also require a reviewed policy.

**Critical blockers:** no safe atomic claim or discovery implementation exists; claim eligibility and races have not been tested; abuse limits, idempotency and revocation policy remain unresolved; deployed privilege and direct-access checks remain outstanding. The direct creation and reveal simulations do not prove recipient authorization.

**Claiming is not safe to activate.** Preserve all existing feature and database gates until the identity protocol, implementation, tests and security review are complete and activation is separately authorized.

## Next steps

1. Review an isolated provider verification plan and obtain separate authorization before any live service or database operation. Verify supported identity-change and confirmation stages, pending changes, deletion, reassignment, effective privileges and transaction/locking behavior through claim commit. If the provider cannot support the required boundary, agree on another identity design before implementation.
2. Design and implement service-only atomic claim and discovery using verified backend identity, authoritative current confirmed recipient identity, database time, reviewed lock ordering and minimal metadata. Define expiry, cancellation/deletion, terminal history and same-user retry behavior; deny competing claimants. Add abuse controls, idempotency and revocation policies.
3. In a disposable local database, test successful and denied claims, expiry boundaries, duplicates, cross-account and direct-access denial, and claim/claim, claim/cancel, claim/identity-change and deletion races in both orders. Separately verify managed-provider behavior and effective privileges in an authorized isolated environment. Preserve self-capsule regressions.
4. Complete the Android device checklist recorded in `docs/STATUS.md`, including keyboard, scaling, TalkBack, clock/timezone and deep-link checks. Before any future mobile submission, synchronously revalidate the reviewed instant and timezone and rely on server enforcement.

**Recommended next Codex prompt:** “Review the existing Phase 4 identity and locking research and prepare a concrete, non-executing verification plan for current confirmed recipient identity across supported Auth change and confirmation transactions. Identify prerequisites, safe disposable fixtures, lock ordering, observations and cleanup. Preserve all direct feature gates; do not contact a service, apply migrations or implement claiming without separate authorization.”
