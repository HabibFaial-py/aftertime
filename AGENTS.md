# AfterTime implementation conventions

## Source of truth and scope
- Read `docs/AfterTime_Project_Report.md` fully before changes. This is the existing report; `docs/PROJECT_REPORT.md` does not exist. Do not modify the report without explicit instruction.
- Read `docs/STATUS.md`, inspect existing files, and present a small plan before editing.
- Implement only the requested milestone slice. The current task is Phase 0 Part 1: mobile foundation only. No API, web, auth, database, capsule logic, CI or deployment in this slice.
- Keep code simple, readable and learning friendly. Explain meaningful choices. Avoid speculative abstractions and unnecessary dependencies.
- Ask before stack, schema, dependency or scope changes unless already authorized by the current task. Verify current compatibility; use stable packages and pin versions with a lockfile after successful installation.
- Never recreate Git, the root folder or `.venv`. Preserve existing user work and ignore rules. Do not commit, push, deploy or incur charges without authorization.
- Run appropriate available checks; never invent passing results. Update STATUS with commands, actual results, blockers and the next task.

## Architecture
- Android-first React Native + Expo + TypeScript + Expo Router in `apps/mobile`.
- Planned only: Next.js/TypeScript/Tailwind in `apps/web`; FastAPI/Pydantic/SQLAlchemy in `services/api`; Python scheduled notification worker in `services/worker`; Supabase PostgreSQL/Auth/private Storage.
- Use a modular monolith. One SQL migration authority: `services/api/migrations`. Separate development and beta production data.
- Mobile routes belong in `apps/mobile/app`; keep routes small. Use strict TypeScript, accessible contrast, readable text, generous spacing, one warm accent and reduced-motion support for any future animation.
- MVP: private self and one-to-one capsules, text and one optional image. No AI, payments, feed, followers, chat, video, groups or iOS release.

## Security requirements for future implementation
- Reveal requires authorized access AND no cancellation/deletion AND authoritative server time >= unlock time. Device countdown is cosmetic. Never preload locked body or image bytes.
- Store UTC timestamps; display local time and confirm exact reveal time before sealing. Notifications must never gate reveal.
- Verify JWT signature, issuer, audience and expiry. Derive identity from the verified token, never client owner IDs. Verify intended recipient email before claiming an invitation.
- Keep service keys server-side and secrets out of Git, client bundles, logs and analytics. Environment examples contain placeholders only.
- Deny direct client access to sealed content and private storage with restrictive grants/RLS. Generate short-lived signed media URLs only after time/access checks.
- Use random high-entropy revocable invitation tokens, store hashes, avoid raw-token logging, use no-referrer policy and no third-party tracking on token pages.
- Validate image ownership, actual format/MIME and 5 MB limit; strip EXIF. Text limit is 2,000 characters; beta unlock cap is 90 days. Rate-limit create/claim/preview and prevent spam.
- Create capsules and notification jobs transactionally. Workers use atomic leases, bounded retries and logical-job uniqueness; do not promise exactly-once external delivery. Email previews contain no message content.
- Support cancellation, report/block, account deletion and documented retention; deletion removes media and cancels pending jobs. Restrict beta to consenting adults. Avoid unnecessary personal data.
- Test cross-account access, direct DB/storage bypasses, before/at/after unlock, clock changes, revoked links and notification failures. Use mock email/local fixtures. Test restore before beta.
- Describe this as server-enforced time locking, never end-to-end encryption or guaranteed permanent preservation.
