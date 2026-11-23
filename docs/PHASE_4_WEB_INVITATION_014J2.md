# Phase 4 #014J-2 secure web invitation handoff

## Local prototype

The existing Next.js app serves a standalone invitation document at `/invite/<capsule-uuid>#<secret>` in development with an explicit opt-in and a loopback Host check. The local browser origin is `http://127.0.0.1:3100`. J-1’s reserved HTTPS origin supplies the link format, while this prototype replaces that origin for loopback testing. Run the server from `apps/web` with an explicit loopback bind.

```powershell
$env:AFTERTIME_LOCAL_WEB_INVITE = '1'
$env:NEXT_TELEMETRY_DISABLED = '1'
npm run dev -- --hostname 127.0.0.1 --port 3100
```

The synthetic capsule UUID ending in `0201` is `00000000-0000-4000-8000-000000000201`. Use 43 uppercase `A` characters in its fragment to try the success case. The suffixes `0202`, `0203` and `0204` simulate expiry, replay and an uncertain outcome. Use a test session, then press **Claim invitation**. Simulating a sign-in redirect discards the secret and sends the browser to a fragment-free page. Reopen the original link in a new tab to resume the local demonstration.

The first script reads the fragment and calls `history.replaceState` before the stylesheet or document body. The path and fragment must use the canonical lowercase UUID and 43-character unpadded base64url format from J-1. The script explicitly clears the history state object, and only the clean path is used for navigation. The fragment is held in a function closure and discarded on claim, page exit or history navigation, including restoration from the back-forward cache. Reloading the scrubbed URL leaves no secret to recover. The fake runs in the document with no claim request or storage writes. Opening, prefetching and simulated sign-in perform no claim. Malformed, expired, unavailable and already-claimed invitations use the same denial. Uncertainty has a generic message and leaves the claim control unavailable.

## Response and deployment boundary

`apps/web/app/invite/[[...capsule]]/route.ts` serves the standalone HTML, and `apps/web/app/invite/handoff-script.mjs` handles the interaction. The response uses `Cache-Control: no-store`, `Referrer-Policy: no-referrer`, and a CSP permitting only its nonce-matched script and stylesheet. The policy blocks external resources, programmatic network connections, framing, form submission and changes to the base URL. The page bypasses the application layout, so it loads no third-party scripts, analytics or pixels. `apps/web/next.config.ts` excludes invitation paths from normal development request logging and retains the repository’s existing agent instructions by disabling generated Next.js agent files. The tests live in `apps/web/tests/invitation-handoff.test.mjs` and run with Node’s built-in test runner.

This prototype uses a synthetic session and fixed synthetic input. Browser JavaScript is required to scrub the fragment, and an in-memory reference can be discarded without proving physical memory erasure. The localhost Host check complements the explicit loopback bind. A future deployed handoff needs an approved HTTPS origin, review of browser history and proxies, production authentication continuity and a review of the logging and security headers at the deployment boundary. Backend claim and discovery remain dormant with migration 0006’s `CHECK (false)` and default-off direct capsules.

## Local verification

- From `apps/web`, `npm test` passed **17 tests** covering early scrubbing, canonical validation, explicit confirmation, authentication interruption, refresh and history, no persistence, and generic outcomes. `npm run lint`, `npm run typecheck`, and `npm run build` passed on the existing pinned Next.js install without dependency changes.
- Headless Chromium on the loopback development server verified the real fragment scrub, clean history state, explicit fake claim, reload, back navigation, sign-in interruption, and malformed and uncertain outcomes. The page issued only loopback GET requests. The DOM, observed request paths and queries, cookies, Web Storage and IndexedDB contained no synthetic invitation token. The responsive page was checked at a 390-pixel viewport. The Windows sandbox blocked Chromium’s renderer startup. The local smoke test passed outside that sandbox with an isolated browser profile.
- HTTP probes confirmed `no-store`, `no-referrer`, fresh CSP nonces, one nonce-matched script, POST denial, and rejection of a nonmatching Host. The synthetic audit query marker and token were absent from the captured development server log. The route returned 404 in development without the opt-in and in the production build with the opt-in set.
- From `services/api` with `DIRECT_CAPSULES_ENABLED=false`, `..\..\.venv\Scripts\python.exe -m pytest -q tests/test_invitation_claim.py tests/test_direct_capsules.py tests/test_auth.py tests/test_invitation_delivery_worker.py` passed **107 tests** with two existing warnings. Git whitespace and protected-file checks passed for the package lock, backend migrations and Android app.

## Next development task

Design the real web authentication interruption and safe reopen flow without carrying the fragment through redirects or persistent state. Verify it in an isolated HTTPS environment with the claim feature still gated before reviewing any backend route wiring.
