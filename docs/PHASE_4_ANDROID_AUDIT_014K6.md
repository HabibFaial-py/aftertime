# Phase 4 Android accessibility and device-readiness audit — #014K-6

This was a static, read-only audit; no Android device was used. The Send to Someone and Received Capsules screens have a scrollable safe-area layout, labeled inputs, button roles and minimum 52 dp button heights. The main readiness gaps are feedback accessibility and behavior when the keyboard or device timezone changes.

## Critical findings

None identified in the current disabled, local-only flow.

## Important findings

- **Validation and confirmation may be missed by TalkBack.** Errors appear below “Check details” without focus moving to the error or an association with the affected field. The newly displayed confirmation also does not receive focus; only the separate feedback text is in a live region. Test announcements and add accessible field-level guidance and a clear way to reach the confirmation. See [Send to Someone](../apps/mobile/app/send-to-someone.tsx).
- **A reviewed time can become stale.** The confirmation is cleared on text edits, but remains visible if the device timezone or clock changes, or the selected time passes. Before any future submission, revalidate and require review again when the instant or timezone changes. See [Send to Someone](../apps/mobile/app/send-to-someone.tsx).
- **Keyboard behavior needs device verification.** The shared screen uses Android `KeyboardAvoidingView` height behavior inside a safe area and scroll view. It has no explicit focused-field scrolling; on some devices or keyboard configurations, fields, errors or the confirmation could be obscured. See [shared layout](../apps/mobile/components/ui.tsx).
- **Received states are placeholders.** The route currently always displays “unavailable.” Loading, error and empty presentations exist, but cannot be reached through this screen; loading has no visible text and error has no retry action. Review their announcements and recovery behavior when connected to a service. See [Received Capsules screen](../apps/mobile/app/received-capsules.tsx) and [received content](../apps/mobile/components/received-capsules.tsx).

## Optional improvements

- Date and time require exact typed punctuation, and the generic clock-change error does not identify the field or suggest a replacement time. Consider clearer format hints and recovery guidance. See [unlock-time validation](../apps/mobile/lib/direct-unlock-time.ts).
- The app explicitly requests a light interface and uses fixed light colors. Test dark system mode for readable system bars, keyboard and inputs; a dark app theme is not currently implemented. See [app configuration](../apps/mobile/app.json) and [shared styles](../apps/mobile/components/ui.tsx).

## Navigation and feature flag

Navigation is guarded by both an authenticated session and the direct feature flag, which defaults off. The flag is a UI gate, not authorization; actual deep-link and Android Back behavior still need device testing. See [navigation setup](../apps/mobile/app/_layout.tsx), [home navigation](../apps/mobile/app/home.tsx) and [feature flag](../apps/mobile/lib/direct-feature.ts).

## Manual Android testing checklist

1. In an isolated test setup with a mock session, verify the default-off flag hides both links and blocks their deep links; test Back navigation and signed-out access.
2. With the UI flag enabled only in that setup, test a small screen, large font and display scaling, and gesture navigation. Reach every input and action while the keyboard is open.
3. With TalkBack, navigate both screens; check labels, focus order, errors, confirmation and button announcements.
4. Check invalid dates, past times, the 90-day boundary and a DST gap or fold. Verify the displayed local time, offset and UTC value; edit a field and confirm the review disappears.
5. Change the device timezone or clock after review and observe the stale confirmation. Test light and dark system settings, keyboard and system-bar contrast.
6. In a fixture or preview capable of selecting received states, inspect unavailable, loading, error and empty states, including screen-reader announcements.
