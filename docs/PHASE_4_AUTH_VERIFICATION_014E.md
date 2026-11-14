# Phase 4 Auth verification — Prompt #014E

## Scope and evidence

The user reports the observations below from the disposable `aftertime-sql-test` project. They were not independently rerun or verified during this documentation task. No account identifiers, addresses, credentials, confirmation links or tokens are recorded here.

## Email-change observation

- Before the change, disposable User B was reported as email-confirmed, with `email_change_confirm_status = 0`, no pending email change, no change request and no deletion marker.
- Email-change confirmation and Secure Email Change were reported enabled in the isolated project's Auth configuration.
- The user reports a supported, authenticated user-session email-change request returned HTTP 200, confirmation emails arrived, and the email change completed through normal verification. The confirmation links were not recorded here. HTTP 200 by itself would not prove that verification or the change completed; the completed state below is a separate user-reported observation.
- Afterward, the reported safe state was email-confirmed, `email_change_confirm_status = 0`, no pending change and no deletion marker. This is one observed completed flow under that project's configuration, not evidence for all providers, versions, settings or intermediate states.

## Related inventory observations

The user reports that capsule and recipient columns/nullability matched the expected inventory, no recipient records existed in the latest isolated inventory, table RLS and SELECT grants matched the expected catalog-level checks, three self-capsule RPC permission checks passed, and the recipient constraints were validated. The user reports `recipients_check3` blocks tokenless pending rows in that project. Constraint names and deployed data may differ elsewhere; do not infer development or production state from this isolated observation. Catalog checks are not a substitute for direct client-role denial tests and effective privilege verification.

## Remaining blockers

- Auth email-change row-lock behavior, all intermediate confirmation states, reassignment and account-deletion interactions remain unverified. A completed email change does not establish that a proposed database lock serializes every Auth update path.
- Concurrent claim versus email change, claim versus cancellation, and cancellation versus reveal have not been verified with two independent sessions. Exact expiry/unlock boundary behavior remains to be tested.
- Direct-capsule schema migration, claim authorization, recipient access, self-capsule compatibility and direct client-role bypass checks are not implemented or verified. No claim is made that the direct-capsule feature exists.
- Rate limiting, idempotency, pending metadata policy, account deletion/reassignment semantics and operational access boundaries require approval and verification before activation. See `docs/PHASE_4_SECURITY_PREREQUISITES_014C.md` and `docs/PHASE_4_SCHEMA_DESIGN_014B.md`.

## Next checkpoint

Review the reported results and approve a safe isolated two-session verification plan for Auth changes, deletion and claim-like locking before designing an executable migration. Preserve the current self-capsule paths and verify real effective grants and provider transaction behavior. Any live experiment requires separate authorization, dedicated disposable accounts, safe logging and a reviewed cleanup procedure. No SQL, migration or live Supabase request was executed during this documentation task.
