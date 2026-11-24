# Phase 4 #014J-6 Android recipient acceptance

## Android runtime

The Windows workspace has Android Studio, platform-tools and the emulator executable in the SDK at `%LOCALAPPDATA%\Android\Sdk`. ADB was available directly at `platform-tools/adb.exe` and reported version 37.0.0. `adb devices -l` returned an empty list. `emulator -list-avds` returned no virtual devices, and the SDK has no installed `system-images` directory. The installed `android-36.1` platform supplies development files. An emulator requires a system image and a configured virtual device.

Device acceptance is blocked on an Android target. The existing Received route requires a session and the development opt-in. No device launch or native UI check took place.

## Coverage

| Area | Automated evidence | Android device check |
| --- | --- | --- |
| Locked and unlocked cards, explicit reveal | Tests verify metadata-only cards, the unlocked action, and a separate message panel after success. | Pending |
| Loading, empty, unavailable, error and retry | Tests verify the synthetic scenarios, generic messages, loading indicator state, and recovery on retry. | Pending |
| Repeated taps | Controller tests verify that rapid requests produce one reveal and stale results are ignored. | Pending |
| Refresh and back navigation | Tests verify message clearing on refresh, abort on mocked blur, and the Back to home route action. | Pending, including Android system Back |
| Session interruption | Tests verify clearing data for a synthetic Auth interruption, session-key remount and sign-out hiding the screen. | Pending |
| Small screen and large text | Reviewed the existing scroll container and wrapping text structure. Native layout and font scaling were not exercised. | Pending |
| TalkBack | Tests assert roles, live-region labels and separate message text in the rendered component tree. Spoken output and focus order were not exercised. | Pending |

No UI or accessibility defect was confirmed by the checks above. Application code and regression tests stayed as they were. The direct-capsule flag still defaults off and the database gates remain in place.

## Local verification

- From `apps/mobile`, `npm test` passed **56 tests**, including **14 Received cases**. `npm run lint` and `npm run typecheck` passed.
- The opted-in Android development bundle exported successfully to the ignored `build/aftertime-014j6-android` directory. From `apps/mobile`, the command was `expo export --platform android --dev --no-bytecode --max-workers 2 --output-dir <workspace>/build/aftertime-014j6-android` using the installed CLI. The export process set `EXPO_OFFLINE=1`, `EXPO_NO_TELEMETRY=1`, `EXPO_NO_DOTENV=1` and `EXPO_PUBLIC_DIRECT_CAPSULES_ENABLED=true`, and cleared the inherited mobile Auth and API settings. This verified Metro bundling only. No APK was built or run.
- Git whitespace checks passed. The existing untracked API requirements file was preserved. The device pass remains pending per the decision to continue offline.

## Next development task

Attach a USB-debugging-authorized Android device or start a configured emulator. Use an isolated synthetic session to open the existing opted-in Received route. Verify TalkBack announcements and message reading, small-screen and large-font scrolling, then exercise rapid reveal, refresh, Android Back and session interruption. Add a targeted regression only for a reproduced defect.
