# AfterTime — Product & Engineering Handoff

**Version:** 1.0 · 10 November 2026  
**Status:** Approved for learning-oriented MVP; implementation not started  
**Working name:** AfterTime (branding and name availability not verified)

## 1. Mission and success criteria

AfterTime is a mobile-first social time-capsule product: write something today, seal it, and reveal it at a chosen future moment. The experience is anticipation followed by an emotional reveal, not ordinary messaging or an AI writing assistant.

The objective is to ship a real product, learn mobile/full-stack engineering with Codex, and recruit 10–12 genuine beta users from university and friend circles. This is not a fundraising or monetization experiment. Keep the beta free, avoid paid acquisition, and prioritize reliability over scale. Success means a deployed app, a working end-to-end capsule flow, real users and documented lessons.

## 2. Product decisions

- Audience: university students, friends and couples; start with one connected circle at FAST.
- Android-first Expo app; responsive web recipient pages so no installation is required to receive a capsule.
- Private self-capsules and one-to-one capsules; text plus one optional image.
- Default presets: 1 day, 7 days, 30 days; custom future date up to 90 days for beta. Use short locks to observe reveals during testing.
- No AI, payments, public feed, followers, chat, video, group capsules or iOS release in MVP. Shared group capsules are the first candidate after beta, not a launch dependency.
- Creator signs in with email; recipient opens an invitation link and verifies the intended email before reading content. Email delivery is the default unlock notification; native push is a later enhancement within the beta if time permits.
- Sender can cancel before reveal; recipient can report/block; users can delete their account and associated content under a documented retention policy. No promise of permanent storage.

## 3. User journey and screens

1. Welcome/sign-in: explain the promise and verify email.
2. Home: sent, received and self capsules; show title, sender, date and locked/open state.
3. Compose: text (max 2,000 characters), optional image (max 5 MB), title, recipient email or self, date/time and confirmation.
4. Seal: validate date, persist capsule, create invitation and share URL. Show confirmation and share sheet.
5. Recipient web page: safe metadata and countdown; no message or image bytes before unlock. Verify email to claim invitation; allow opening in browser.
6. Reveal: server checks access and time, returns message and short-lived media URL; simple reveal animation and create-your-own CTA.
7. Settings: account deletion, notification preferences, block/report and privacy information.

Visual direction: warm, minimal, emotionally expressive; one accent color, generous spacing, accessible contrast, readable countdown and reduced-motion support. Avoid building a design system before core functionality.

## 4. Architecture and stack

| Layer | Choice | Reason |
|---|---|---|
| Mobile | React Native, Expo, TypeScript, Expo Router | Cross-platform learning; Android first |
| Web | Next.js, TypeScript, Tailwind | Shareable recipient pages and landing page |
| API | Python FastAPI, Pydantic, SQLAlchemy | Explicit backend learning and typed contracts |
| Database/auth/storage | Supabase PostgreSQL, Auth, private Storage | Managed infrastructure and relational data |
| Notifications | Scheduled Python worker + transactional email provider | Reliable asynchronous delivery; no push dependency |
| Deployment | Vercel web; Render or Railway API/worker; Supabase | Simple managed hosting; verify current quotas |
| Testing | pytest, Vitest, manual Android E2E | Test core access and timing invariants |
| Version control | GitHub, GitHub Actions | Reviewable commits and automated checks |

Use a modular monolith, not microservices. Mobile/web authenticate with Supabase; API verifies JWT signature, issuer, audience and expiry using supported verification method. API derives user identity from token, never client-supplied owner IDs. Database and storage service credentials remain server-side. Clients must not have direct access to sealed content tables or private storage; use restrictive grants/RLS and test bypass attempts. Use TLS, environment secrets and managed encryption at rest. This is server-enforced time locking, not end-to-end or cryptographic time-lock encryption.

### Repository structure

```
aftertime/
  apps/mobile/          # Expo
  apps/web/             # Next.js
  services/api/
    app/                # routes, auth, services, models, schemas
    tests/
    migrations/
  services/worker/      # due notifications, retries
  docs/                 # product spec, API contract, decisions, test plan
  AGENTS.md             # Codex instructions
  .env.example          # placeholders only
  README.md
```

Keep one migration authority (SQL migrations in services/api/migrations); do not independently modify production schema in dashboard. Pin dependencies and document local startup commands. Use a development Supabase project separate from beta production.

## 5. Data model

All IDs UUID; timestamps UTC timestamptz. Store recipient email normalized, avoid exposing it publicly. Store image object keys, not public URLs.

- profiles: id (auth user ID), display_name, created_at.
- capsules: id, owner_id, title, body, media_key nullable, unlock_at, created_at, cancelled_at nullable, deleted_at nullable. Body is protected server-side; managed encryption at rest is baseline, application-level encryption is optional hardening with managed keys.
- recipients: id, capsule_id, intended_email, user_id nullable, invite_token_hash unique, claimed_at, opened_at. One recipient per capsule in MVP; self uses owner identity. Token is random high-entropy, stored hashed, revocable and exchanged for authenticated access; do not log raw tokens.
- notifications: id, capsule_id, recipient_id, kind, due_at, status, attempts, next_attempt_at, lease_until, sent_at, provider_message_id, last_error. Unique (capsule_id, recipient_id, kind) prevents duplicate logical jobs.
- blocks: blocker_id, blocked_id, created_at; unique pair.
- reports: id, reporter_id, capsule_id, reason, created_at, status.

Indexes: capsules(owner_id, created_at), recipients(user_id), notifications(status, next_attempt_at). Foreign keys and uniqueness constraints enforced in DB. Create capsule and notification record in one transaction. Deletion cancels pending notifications and removes media; document backup expiry.

## 6. API contract (initial)

| Method / route | Behavior |
|---|---|
| POST /v1/capsules | Authenticated create; validate body, date, recipient and media ownership; idempotency key |
| GET /v1/capsules | Authenticated list; metadata only for locked capsules |
| GET /v1/capsules/{id} | Owner/claimed recipient only; metadata before unlock, content after |
| POST /v1/invites/claim | Verify intended email and token; bind recipient atomically |
| GET /v1/invites/{token}/preview | Minimal non-sensitive countdown metadata; no content |
| POST /v1/capsules/{id}/cancel | Owner only before unlock; revoke invite and notification |
| POST /v1/capsules/{id}/opened | Authorized after unlock; record first open idempotently |
| POST /v1/media/upload | Authenticated validated image upload; private object |
| POST /v1/reports | Authenticated abuse report |
| POST /v1/blocks | Block sender; prevent future invitations |
| DELETE /v1/account | Verified account deletion workflow |

Return consistent errors: 401 unauthenticated, 403 unauthorized (or 404 to avoid enumeration), 422 invalid input, 429 rate limit. No sensitive fields in logs, analytics or notification previews. Define OpenAPI schemas before mobile integration.

## 7. Critical engineering rules

### Unlock invariant

Access is decided by authoritative server time: authorized AND not cancelled/deleted AND now >= unlock_at. A capsule does not need a job to change state. Before unlock return only safe metadata. After unlock generate a short-lived signed media URL only after authorization. Never preload content or media into the client. The countdown is cosmetic; device clock changes cannot unlock content. Sender may retain their original text outside the app; do not claim they cannot remember or copy it. Store UTC and display local timezone; confirm exact date/time before sealing.

### Notification reliability

A scheduled worker polls due rows every minute, claims them atomically with a lease (e.g. FOR UPDATE SKIP LOCKED), checks capsule cancellation and sends email. Record provider response, retry transient errors with bounded exponential backoff, recover expired leases and mark permanent failures for manual review. Use provider idempotency where supported; exactly-once external delivery is not guaranteed. Notification failure must never prevent a valid reveal. Avoid leaking message contents in email. Use verified sending domain and consent/opt-out where applicable.

### Security and privacy

Use private buckets; validate MIME and actual image format, size, strip EXIF, reject unsafe files. Rate-limit create/claim/preview and prevent spam. Verify recipient email, expire/revoke invitation tokens, use no-referrer policy and avoid third-party trackers on token URLs. Never expose tokens or service keys in client bundles. Provide report/block, deletion and retention policy; do not collect unnecessary personal data. Restrict beta to consenting adults. Test cross-account access, direct DB/storage access, early reveal, revoked links, clock changes and notification retry. Backup and restore test before beta; do not promise multi-year preservation.

## 8. Build milestones (6–8 weeks, flexible)

| Milestone | Deliverable and acceptance gate |
|---|---|
| 0 — Setup | Repo, AGENTS.md, local env, Expo app, FastAPI health route, CI; all start locally |
| 1 — Auth/data | Email sign-in, migrations, JWT verification; cross-user access tests pass |
| 2 — Core API | Create/list/read/cancel, self capsule, server time gate; before/at/after tests pass |
| 3 — Mobile UI | Compose, home, countdown, reveal, private image; Android end-to-end self capsule works |
| 4 — Sharing | Next.js preview, claim, browser reveal; intended recipient only, no app install required |
| 5 — Delivery | Worker, email, retry and monitoring; simulated failure recovers without blocking reveal |
| 6 — Beta | Deploy, privacy/support pages, deletion/report/block, test matrix, 10–12 invited users |
| 7 — Learn | Review events and feedback, fix top issues, write retrospective; decide whether to add group capsules |

Each milestone is a separate branch/PR or small commits. No new feature until its acceptance gate passes. Prefer vertical slices over generating the entire codebase in one prompt.

## 9. Beta launch and marketing

Recruit 10–12 consenting adults through friends, university classmates and one small group. Invite them personally with a demo link; no paid ads. Ask each to create a 1–7 day capsule and share with one person. Run a 2–3 week beta with a reveal event in week one. Offer an optional second capsule; do not pressure users to share private content.

Launch copy: “Write something today. Open it when the moment is right. AfterTime lets you seal a message or photo for your future self or someone you care about. Try the free private beta.”

Track events without message content: signup_completed, capsule_created, invite_shared (explicit share action, not delivery), invite_claimed, capsule_opened, second_capsule_created, notification_failed. Measure counts and denominators, not statistically meaningful market rates. Suggested learning goals: 10–12 unique activated testers, at least 8 creators, at least 6 eligible capsules opened, at least 3 voluntary repeat creators, zero known early-content leaks. These are internal targets, not industry benchmarks. Record delivery latency, failed jobs and user feedback. Ask: What did you feel at reveal? Would you send another? What was confusing? What would make it worth returning?

## 10. Budget and risks

Aim for free-tier development and a small beta; budget $0–30/month plus optional domain and distribution fees. Verify actual provider limits, email quotas and current Android distribution requirements before deployment. Start with direct/internal Android testing or web access; public Play Store release is optional. A public release may require account verification and testing prerequisites. No paid marketing or subscriptions. Main risks: weak repeat usage, notification failure, privacy breach, forgotten accounts and scope creep. Mitigate with short beta locks, browser access, security tests, backups, clear deletion and milestone gates.

## 11. Codex collaboration protocol

ChatGPT is product/architecture mentor; Codex implements in the repository; the user owns decisions, runs tests and reviews changes. Neither chat automatically knows the other's repository state. Keep docs/STATUS.md updated with current milestone, completed work, commands, test results, blockers and next task. Paste relevant diffs/errors or share files when asking for help. Do not paste secrets. Codex should inspect existing files before edits, propose a small plan, implement only the requested slice, run tests/lint, and report changed files and failures. Never claim tests passed without running them. Ask before changing stack, schema, dependencies or scope. Use mock email and local fixtures in tests. Do not deploy or incur charges without approval.

### First Codex task (copy into Codex)

Read AfterTime_Project_Report.md and create AGENTS.md summarizing the collaboration and security rules. Implement Milestone 0 only: scaffold the monorepo with Expo TypeScript mobile app, Next.js TypeScript web app and FastAPI health endpoint; add README local setup, .env.example, .gitignore and minimal CI checks. Inspect available tools and existing files first. Do not implement auth, database schema, capsule logic or deployment yet. Use current compatible dependencies, document versions and commands, run available checks, and report exact changed files, results and blockers. Create docs/STATUS.md with next milestone. Do not commit secrets or invent successful test results.

### New ChatGPT conversation starter

I am building AfterTime, a time-locked social capsule app, as a real learning project with 10–12 beta users. The attached AfterTime_Project_Report.md is our source of truth. I will use Codex to implement while you act as my product and engineering mentor. Work milestone by milestone; explain architecture and tradeoffs, give focused Codex prompts, help review code and debug errors, and maintain scope. Do not assume code exists until I share Codex output or repo files. Start with Milestone 0: setup, repository structure and the first Codex task. Ask only for essential missing information. Keep it practical and free-first.

## 12. Decisions and open questions

Finalized for planning: Android-first, browser recipients, free private beta, text/photo, self/direct capsules, server-side time gate, email notifications, no AI. Working assumptions selected for this report: name AfterTime, 90-day cap, email identity, 2,000-character/5 MB limits, 6–8 week schedule, stack and beta targets. User may revise these before implementation. Open items: name/domain availability, actual hosting/email provider and quotas, local development environment, production privacy/retention wording and distribution channel. No code, deployment, user recruitment or market validation has been performed yet.

Source basis: supplied Time-Locked Social App product evaluation report and subsequent conversation; architecture and constraints above are implementation recommendations, not externally verified market claims.
