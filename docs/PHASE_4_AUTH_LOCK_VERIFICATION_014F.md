# Phase 4 Prompt #014F — Auth email-change lock verification design

**Prepared only; not executed.** This is a proposed isolated experiment, not a migration or proof that recipient claiming is safe. It requires separate authorization before any service call, database session, account change or email confirmation. Use only the disposable `aftertime-sql-test` project, ref `wokkxbgbrsmydozvyvkt`; never run it against the original development or beta project. Do not directly update `auth.users` or automatically follow verification links.

## Repository evidence and question

Migration 0003 reads the self-capsule owner's `auth.users.email` and `email_confirmed_at`, joins `public.profiles`, and requests `FOR SHARE OF u, p` before insertion. Migration 0002 provisions a profile via an Auth insert trigger. Migrations 0004/0005 use capsule-then-recipient locks for self reveal and cancellation; they do not implement claiming or lock Auth identity for recipient authorization. FastAPI verifies the JWT and derives its subject UUID but does not establish the current confirmed email.

The user reports one successful supported email change in the isolated project, with the same User B UUID and a completed confirmed state. That observation does **not** show which database rows or transactions were locked, whether every confirmation stage uses the same transaction, or whether a claim-style read is safe during an email change. The local SQL bootstrap is a simplified stub; it cannot prove the managed provider's locks, confirmation behavior, email reassignment, triggers, transaction boundaries or privileges.

The experiment asks whether a lock held on **the exact disposable User B `auth.users` row** overlaps and conflicts with the provider's actual supported email-change request and confirmation stages. An authenticated Auth request is a second concurrent operation, but it is not necessarily a single observable PostgreSQL session; the provider may use multiple transactions, services or asynchronous work. Results demonstrate only the observed operation and configuration, not all provider versions or paths.

## What the locks can and cannot establish

- `FOR SHARE` is a candidate because PostgreSQL row-lock compatibility is expected to make ordinary updates/deletes of the same row wait while the lock is held. Verify the actual conflict in the target database. It does not block ordinary readers and cannot protect a change made elsewhere that does not conflict with that exact row lock.
- `FOR UPDATE` is stronger and may conflict with more row-lock modes, but it is not proof that the Auth workflow uses that row or one transaction, and it can increase contention/deadlock risk. A successful test of it does not prove `FOR SHARE` is sufficient. Run it only as a separately approved variant if needed.
- In both cases, a completed confirmation can involve changes to multiple fields, rows or services; matching current email at a point in time does not prove the same person held the mailbox when an invitation was created. Locks do not hold an email unchanged after the transaction commits or recall metadata already returned.
- The full future claim must also consider profile/FK/recipient/capsule locks, deletion, stale JWTs, pending changes, mailbox reassignment and the real PostgREST transaction boundary. This experiment alone cannot prove those conditions.

## Required environment and preconditions

1. Independently verify the selected isolated project reference in the Dashboard and that no other testing or real users are active. Use dedicated disposable User B, with a stable UUID already recorded privately, and two controlled disposable inboxes appropriate for the project's enabled confirmation mode. A second dedicated account may be used only for independently approved control tests; do not use or change a real user's account.
2. Record only safe booleans and timestamps/status categories: baseline confirmed state, pending-change flags and deletion marker, project confirmation settings, provider/project configuration and UUID **stability as a boolean**. The user previously reported confirmed email, zero change status, no pending change and the same UUID. Reconfirm baseline safely before a later run; do not display email values, UUIDs, passwords, tokens, confirmation URLs, SQL connection strings or provider response bodies.
3. Ensure email-change confirmation and Secure Email Change settings are known. The actual number and order of approvals depend on provider settings. Have access to all required test inboxes, a user-approved recovery plan, a stop condition and an operator who can release the database lock immediately. Do not disable verification to make the test easier.
4. A **persistent trusted PostgreSQL connection** with appropriate, narrowly scoped privileges is required for session A. Confirm the endpoint and TLS/connection configuration privately without printing credentials or query parameters. `FOR SHARE`/`FOR UPDATE` can require more privilege than ordinary SELECT; verify applicable managed-role permissions separately. Do not grant client roles Auth-table access. Avoid SQL statement/parameter and HTTP header/body logging; if the environment logs IDs or Auth data and cannot be made safe, stop.
5. A second path is the real supported Auth email-change operation, authenticated as disposable User B. The existing ignored `.venv/aftertime_update_isolated_user_b_email.py` signs in and asks for final confirmation before its one `PUT /auth/v1/user`; it has a 15-second HTTP timeout and no automatic retry. Inspect it and verify its target/configuration before any later use. Prepare its final confirmation dialog **before** session A takes the lock, so the operator can act promptly. Do not put credentials in shell commands, logs or the database. The operator manually completes any normal email confirmations.
6. Local inspection found no `psql` command on PATH and no `psycopg`, `psycopg2` or `asyncpg` in the existing virtual environment. A verified persistent client must be supplied separately; this task does not install one. Supabase SQL Editor request-to-request session affinity is not established. Do **not** assume that separate Editor submissions share a transaction; a GUI that cannot prove one persistent connection cannot safely implement this test. A single bounded Editor request might overlap an Auth operation, but its timeout, cancellation and transaction cleanup must first be independently established and it is not a substitute for a controlled persistent session.

## Proposed controlled sequence

Use a no-lock control and separate fresh attempts for the request and confirmation phases. No actual claim or new database object is created. The SQL below is an illustrative later `psql` session using a **private, process-local** `AFTERTIME_B_UUID` value. Set that variable through a separately reviewed secure input mechanism before starting the client; do not echo it, embed it in a committed file or place it in a command line. `\getenv` reads the value locally, but psql substitution sends an identifier in the SQL statement: database statement/parameter logging and client history must be disabled or safely controlled before use. Never publish transcripts. This query deliberately selects only a count and confirmation boolean; it does not select the email, pending email, token or user ID as output. It is a lock probe, **not** a complete verified-email claim check.

```text
\getenv aftertime_b_uuid AFTERTIME_B_UUID
BEGIN;
SET LOCAL idle_in_transaction_session_timeout = '60s';
SET LOCAL statement_timeout = '10s';
SELECT count(*) AS matching_confirmed_rows
FROM (
  SELECT 1 FROM auth.users AS u
  WHERE u.id = :'aftertime_b_uuid'::uuid
    AND u.email_confirmed_at IS NOT NULL
  FOR SHARE OF u
) AS locked_user;
```

**Do not execute this snippet as part of preparation.** Require exactly one row counted and no error before starting the concurrent Auth action. A zero count, unexpected result, permission failure, logging concern, wrong project or lost session means `ROLLBACK` and stop. The count confirms only the selected row and a non-null confirmation timestamp; it does not establish that the current email is the intended one or that no change is pending. Verify transaction/lock ownership using an independently reviewed safe method; an SQL Editor success message without proven session persistence is insufficient.

### Control and request-phase overlap

1. With **no database lock**, perform a separately authorized supported email-change request on a disposable account and record only safe status, stage, elapsed time and confirmation-state booleans. Complete or safely resolve it before the lock variant; do not leave a second pending change. This control establishes only that the operation works under that test configuration.
2. Prepare a **new, distinct** authorized change. Bring the Auth client's final confirmation to the foreground without sending the update. Start session A, take the shown `FOR SHARE` lock and confirm the count is one. Keep the same connection and transaction open. Use a stopwatch and a second operator or coordinated windows; do not hold the lock longer than the smallest safely usable interval. The 60-second idle timeout is a fallback, not the primary release mechanism.
3. Immediately approve the supported user-session update. Observe only whether the Auth request completes, remains pending or times out while A demonstrably holds the lock. Release A with `ROLLBACK;` within a few seconds, before the client's 15-second timeout whenever feasible; then observe the request outcome. Do not infer the database write or email delivery from the button press alone.
4. Compare with the no-lock control and inspect only safe state booleans afterward using a separately reviewed read-only check. If the request waits while the exact row lock is held and proceeds promptly after release, that supports a conflict for **that initiation path**. If it completes while the lock is demonstrably held, the lock did not serialize the entire observed initiation path; do not use it as a claim-security guarantee. If the client times out, the provider may still be processing or may commit later: **outcome uncertain**, not a passing conflict test. Do not automatically retry.

### Confirmation-phase overlap

The request that initiates an email change and the later act of confirming it may use different transactions. On another fresh, explicitly authorized test, initiate the normal supported change **without a lock** and wait until the required confirmation email(s) arrive. Do not automatically open or print their links, tokens or addresses. Prepare the appropriate normal confirmation step in a private browser, take the same bounded lock in persistent session A, then manually complete **one** confirmation step while it is held. Release A promptly and record only the safe stage/status/timing and state booleans. If secure email change requires multiple confirmation steps, test each separately with fresh, valid provider state; do not infer the final step from an earlier one. Never log confirmation URLs or browser history in a shared artifact.

Run `FOR UPDATE` only as an additional separately approved variant after assessing contention, using the same structure and replacing the lock clause. Do not run either variant on another person's row or on development data. Reverse-order claim/email-change tests require a future real claim implementation or a separately reviewed non-mutating test harness; this probe cannot establish their outcome.

## Interpretation, abort and recovery

- **Positive observation:** a lock conflict observed with a verified held lock, bounded timing and a no-lock control is evidence for the tested stage, account, settings and provider version. It does not prove other stages, other email/identity providers, asynchronous updates, account deletion/reassignment, or all Auth writes use that row/lock. Verify the actual lock modes and transaction boundaries through supported safe diagnostics if available.
- **Negative observation:** an Auth phase completing while the row lock is provably held, or state changing in an uncoordinated path, defeats the proposed assumption for that phase. A delayed confirmation email alone is not evidence of a blocked database write.
- **Inconclusive:** no confirmed lock ownership, ambiguous timing, a short server timeout, no comparable control, lost connection, a blocked network/email path, partial confirmation, an expired link, unexplained failure or rate limit. Stop; do not convert an absence of evidence into a pass.
- **Always release:** run `ROLLBACK;` in the same session on completion or error. If that session disconnects, verify through a separately reviewed safe administrative method that its transaction ended; the idle timeout is only a fallback. Never kill another user's backend or session. No direct `UPDATE`, `DELETE`, schema change or fabricated confirmation is part of this test.
- **After interruption:** the Auth request may have committed or may still complete after an HTTP timeout or lock release. Inspect safe confirmation/pending/deletion booleans through a reviewed private method and use the provider's normal supported recovery flow. Do not blindly resubmit, follow an old link automatically, revert by SQL, or delete an account to clean up. Restore or replace the disposable account/inboxes only through a separately authorized supported flow, then confirm the final safe state and record a sanitized result. If recovery cannot be established, stop and keep that account out of further tests.

## If persistent overlap cannot be established

Do not infer safety from sequential SQL Editor requests, local mock schemas or a normal successful Auth email change. Keep direct-capsule claiming disabled until a supported, provider-backed identity protocol and its race boundaries are reviewed and verified. A possible alternative requiring a **separate product/security decision** is a server-issued, short-lived one-time challenge delivered to the intended mailbox, consumed atomically and bound to the signed-in UUID and invitation; tokens must be high entropy, hashed at rest, revocable and protected from logs/referrers. This introduces delivery infrastructure and mailbox-reassignment risks. It does not automatically prove the existing rule that the account's **current confirmed email** matches at claim time, nor does calling an Auth `getUser` endpoint immediately before a separate database write make that check atomic. Retain the blocker until the required identity semantics, transaction boundary and tests are proven or the product rule is explicitly changed.

## Before any real test

Obtain approval for the exact accounts, project, supported Auth operations, durable-session tool, evidence capture and recovery; verify no logging exposes private data; review timeouts and concurrent operator steps. No live test, SQL, migration, server or network operation was performed while preparing this document.
