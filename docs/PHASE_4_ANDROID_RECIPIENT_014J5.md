# Phase 4 #014J-5 Android Received Capsules presentation

## Implementation

- `apps/mobile/app/received-capsules.tsx` keeps the existing Received route, home action, and signed-in feature gate. The local preview appears only in development when `EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED` is exactly `true`. A release build with a session and the flag forced on shows the unavailable state. The flag still defaults to false.
- `apps/mobile/components/received-capsules.tsx` presents loading, empty, unavailable, retryable error, and account interruption states. Claimed cards show lock status, local creation and reveal times, and sender UUID. They use the existing `Screen`, `Action`, typography and accessibility patterns. The successful message is rendered in a separate panel, with a live-region heading and readable message text.
- `apps/mobile/lib/received-capsules.ts` defines the `id`, `sender_id`, `created_at`, `unlock_at`, and `status` inbox shape from J-4. The controller explicitly projects those fields and handles reveal results separately. Inbox status is a snapshot. Only an unlocked card offers **Reveal message**, and the controller matches the response ID before showing its body. It suppresses duplicate taps and clears the message on refresh, blur, scenario change, or a replaced or missing session. An aborted or superseded request cannot publish a late result.
- `apps/mobile/lib/received-preview.ts` generates synthetic timestamps and UUIDs. It supplies message text only through a successful reveal response. Cancellation, deletion and revocation share the unavailable outcome. In that scenario the next refresh drops the withdrawn card. An ambiguous reveal shows a generic message and requires refresh and another explicit action. An account interruption clears the list and message and waits for a fresh preview controller.
- `apps/mobile/tests/received-capsules.test.cjs` exercises fixture shape, presentation, controller behavior and screen lifecycle with the existing Node test setup. `apps/mobile/tests/direct-foundation.test.cjs` keeps the direct route and home navigation checks and leaves Received-specific assertions to the new suite.

## Local preview

Open **Received Capsules** from the existing authenticated home navigation in an opted-in development build. The default synthetic inbox has one locked and one unlocked card. Press **Local preview states** to choose an empty or unavailable inbox, a load error that recovers on **Retry**, an unavailable or uncertain reveal, or a simulated sign-in interruption. The preview uses local promises and synthetic results. It makes no recipient API calls and stores no messages or session data.

## Local verification

- From `apps/mobile`, `npm test` passed **56 tests**, including **14 Received-specific cases**. They cover the metadata-only projection, advisory locked status, explicit reveal and separate message rendering, duplicate requests, unavailable and ambiguous outcomes, stale responses, refresh, blur, auth interruption, accessibility announcements, and the navigation and release gates.
- `npm run lint` and `npm run typecheck` passed. Git whitespace checks passed for tracked and untracked files with only Windows line-ending warnings. The mobile dependency lockfile, existing flag defaults and migration 0006 were unchanged. No shared backend code changed in this slice, so the backend suite was not rerun. Prior uncommitted work was preserved.

## Remaining limits

The preview uses a mock data source and the automated tests use mocked native components and sessions. Android rendering, TalkBack, large-text layout, and real session lifecycle behavior still need a device pass. In a future connected flow authorization and the database clock remain authoritative. The default-off direct flag and migration 0006’s `CHECK (false)` remain intact.

## Next development task

Run an Android emulator or device acceptance pass with a synthetic session. Verify TalkBack can announce status and read the explicitly revealed message, check large-text and small-screen layouts, and confirm that rapid taps, refresh, back navigation and reauthentication discard stale results.
