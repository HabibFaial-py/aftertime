# Android end-to-end test preparation — Prompt #013G

## Recommendation and scope

Start with an Android emulator and the existing isolated `aftertime-sql-test` project and dedicated test accounts. Use Expo Go compatible with the installed Expo SDK 58. The existing isolated launcher binds FastAPI to the host loopback interface, which the Android emulator can normally reach through `10.0.2.2`. Then repeat on a physical Android device after arranging a reachable API address and checking cleartext restrictions. Neither path has been run or verified in this preparation.

This plan creates and cancels real rows when executed. Use only consenting dedicated test accounts, synthetic text, distinct fixture titles and a separately confirmed disposable project. Never use real private content. The mobile app currently supports text-only self-capsules. A successful cancellation is permanent. Do not apply migrations, alter timestamps or change the server time gate to perform this test.

## Configuration and local findings

- `apps/mobile/package.json` pins the Expo SDK 58 family; the installed `expo` package reports 58.0.24. `npm start` runs `expo start --go`, and `npm run android` runs Expo Go's Android launch path. Expo Go compatibility with the actual emulator/device and its installed Expo Go version remains unverified.
- `app.json` includes Android and Expo Router. `expo-secure-store` persists sessions; the root Stack protects Home, list, create and detail. Session expiry or logout removes access. Tests below must verify actual native behavior.
- The existing mobile `.env` is present; its contents were not read or changed. It needs `EXPO_PUBLIC_SUPABASE_URL`, `EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, and `EXPO_PUBLIC_API_BASE_URL`. Ensure the first two point to the same disposable project used by FastAPI. These `EXPO_PUBLIC_` values are embedded in the app: never put a server secret there. Restart Metro/reload after changing configuration. Use a process-local API URL override as below; do not overwrite existing credentials or `.env` files.
- FastAPI reads process environment, not `.env` automatically. It needs the isolated `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, matching `SUPABASE_JWT_ISSUER`, `SUPABASE_JWT_AUDIENCE`, and server-only `SUPABASE_SECRET_KEY`. The existing isolated launcher accepts both keys in masked paste-friendly fields and sets them only on its child process. Independently confirm their project provenance. The test accounts need confirmed email and existing eligible profiles; the isolated project must already have migrations 0001–0005. Do not apply migrations as part of this plan.
- `apps/mobile/node_modules` and `.venv/Scripts/python.exe` exist. Local versions observed: Node 24.19.0, npm 12.0.2 and Python 3.11.9. `adb` and `emulator` were not found on PATH; this does not prove Android SDK tools are absent elsewhere. No emulator, device, GUI, server or network was started or checked.
- The earlier `docs/MOBILE_ARCHITECTURE_AUDIT.md`, `docs/MOBILE_CAPSULE_LIST_013C.md` and `docs/MOBILE_CAPSULE_DETAIL_013E.md` files referenced in earlier records are absent in the current workspace. This plan uses the current source, available documents and status records; it does not recreate or modify those files.

## Connectivity and startup

Run the two processes in separate PowerShell windows from the repository root. Do not print credentials, JWTs, full request headers, private bodies or server environment variables. Stop each process after testing. The backend requires network access to the same isolated Supabase project's Auth/JWKS and Data API; Expo Go also needs to reach Metro. The `/health` endpoint alone does not prove authentication or database connectivity.

### Emulator — preferred first run

1. Ensure an Android emulator and compatible SDK 58 Expo Go are installed and running. Android SDK/AVD installation is outside this preparation; `adb` and `emulator` were not on PATH here. The host emulator alias is normally `10.0.2.2`; `127.0.0.1` and `localhost` inside Android point to Android itself.
2. In PowerShell window A, run the existing isolated launcher; it prompts for the project reference and masked keys. Verify the reference and both keys are from the disposable project. It starts FastAPI at host `127.0.0.1:8002` and waits for it to exit:

   ```powershell
   Set-Location C:\Users\Hp\Desktop\aftertime
   powershell -NoProfile -File .\.venv\aftertime_isolated_server.ps1
   ```

3. In window B, use the emulator's host alias for the mobile API origin and start the existing Expo Go script. This changes only that window's process environment, not stored credentials:

   ```powershell
   Set-Location C:\Users\Hp\Desktop\aftertime\apps\mobile
   $env:EXPO_PUBLIC_API_BASE_URL = 'http://10.0.2.2:8002'
   npm start
   ```

4. Open the project in the running emulator's compatible Expo Go using Expo's terminal instructions; the `a` shortcut requires the Android tooling to be available. Verify Metro and API connectivity independently. The app permits private IPv4 HTTP only in development, but Android/Expo Go can still block cleartext. If blocked, use a suitable trusted HTTPS setup rather than assuming this HTTP path works. Do not bypass the restriction by putting secrets in the client.

### Physical Android device

The existing isolated launcher is **loopback-only**; a physical phone cannot reach its `127.0.0.1:8002` listener. A separately configured isolated FastAPI process must listen on a phone-reachable interface, using the same existing isolated credentials in its process environment. Do not edit the launcher or copy credentials into the mobile app. The operator must supply those already-managed server values through a trusted local method before starting window A. With that environment already present, the command is:

```powershell
Set-Location C:\Users\Hp\Desktop\aftertime\services\api
..\..\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8002
```

In window B, find the host's private LAN IPv4 address with `ipconfig`. Replace the placeholder below locally; do not include angle brackets in the value. Use the same trusted network and a private firewall rule limited to the test device/network if required. Binding `0.0.0.0` exposes the service to reachable network interfaces, so stop it after testing. HTTP sends bearer tokens without transport encryption; use only a trusted development network, or use a trusted HTTPS endpoint. Guest Wi-Fi/client isolation, VPNs, changing IPs, firewall rules and Expo Go/Android cleartext policy may prevent access.

```powershell
Set-Location C:\Users\Hp\Desktop\aftertime\apps\mobile
$env:EXPO_PUBLIC_API_BASE_URL = 'http://<host-private-lan-ip>:8002'
npm start
```

Open the Metro QR code with a compatible Expo Go on the phone. The phone must reach both Metro and FastAPI. If the local API origin or project configuration is wrong, the Home connectivity check may fail; do not share diagnostic tokens or raw headers.

### Development builds

This checkout is configured for Expo Go, not a ready-to-run development build: `expo-dev-client` is not declared, no `eas.json` or Android native project is present, and no development-build profile or cleartext network configuration was found. A development build would require a separately scoped setup and Android toolchain; no installation or build was performed. Cleartext and HTTPS behavior must be verified for the actual build. Do not assume Expo Go results prove release-build networking or security.

## Disposable data and time setup

Use a new or known-empty dedicated account A for the empty state and a separate account B for isolation checks. Avoid deleting or altering existing accounts or data. Name synthetic fixtures distinctly, for example `Android reveal test` and `Android cancel test`, and use harmless synthetic text. Record only test outcomes and non-sensitive fixture labels, not messages or credentials.

For a fast reveal, create the reveal fixture through the app with a valid future local minute a few minutes away, allowing time to test the locked response before the deadline. The app takes `YYYY-MM-DD` and 24-hour `HH:MM`; confirm its displayed timezone and exact local time. Wait for the real database-authoritative unlock time and explicitly retry reveal afterward. A 404 before unlock is generic and alone does not prove the cause; the later successful reveal of the same fixture provides additional evidence. No production gate is weakened and no server/device clock is advanced. Use a separate fixture with a comfortably later unlock for cancellation.

Creation has no idempotency key: a timeout or network failure can occur after a commit. Do not blindly resubmit; refresh the list and inspect only the dedicated fixture. The same uncertainty applies to interrupted cancellation. There is currently no mobile delete/cleanup feature. After testing, leave synthetic fixtures in the disposable project until an independently reviewed, specifically authorized cleanup is available; do not improvise broad deletion.

## Ordered manual checklist

Record pass/fail, device or emulator, OS and Expo Go versions, local timezone, and relevant safe status messages. Never record body text, account credentials or tokens.

1. **Start and sign in:** confirm Home loads and backend authentication changes to Connected for account A. Sign out and sign back in as needed. Force-close and reopen Expo Go; confirm session restoration without exposing another user's screen. Test an expired session when safely feasible.
2. **List and empty state:** open View capsules. With an independently known-empty test account, verify the empty state; otherwise record it as not tested. Verify loading, pull-to-refresh and pagination if enough synthetic records already exist. Do not remove existing data just to make the list empty.
3. **Create reveal fixture:** choose Create a capsule, enter a distinctive synthetic title and synthetic message, and a valid future local minute a few minutes away. Review the date, timezone and warning, then seal once. Verify the list returns and refreshes with the title and metadata; the body must not appear in the list. If the outcome is uncertain, refresh before any further attempt.
4. **Locked detail:** open that fixture. Check its title, localized unlock time and server-reported locked status. Explicitly press Reveal message before the chosen time; expect a generic unavailable message and no body. The generic denial does not by itself establish why access was denied.
5. **Eligible reveal:** wait until the real unlock time has passed. Refresh or reopen the detail, then explicitly press Reveal message. Confirm the synthetic message appears only after successful server authorization. Leave the screen and return; it must not appear again until explicitly revealed. Observe that list status is a snapshot, not authorization.
6. **Create and cancel a separate locked fixture:** choose a later future unlock, seal once and open it while still locked. Press Cancel capsule, read the permanent-cancellation warning, choose Keep capsule and verify no cancellation occurred. Then choose Cancel capsule again and explicitly confirm. Verify return to a refreshed list and that the fixture no longer appears. If the result is uncertain, refresh and inspect the disposable fixture before another attempt.
7. **Offline and retry:** with test account A signed in, interrupt connectivity or stop only the local API. Verify safe error and manual retry for the list/detail; restore connectivity and retry. Avoid submitting create or cancel during disconnect unless deliberately testing an uncertain outcome with a dedicated fixture; never automatically repeat an uncertain POST.
8. **Logout and account switch:** while viewing detail, log out, then use hardware back and direct navigation where possible; protected content must not reappear. Sign in as B and verify A's metadata and revealed content do not appear. Switch back to A and confirm the correct list. Avoid assuming that an empty first page proves all possible cross-account checks.
9. **Hardware back and lifecycle:** navigate from list to detail, reveal an eligible synthetic fixture, press hardware back and return; text must be cleared until a new explicit reveal. Check background/resume, rotation if available, logout/account switch during pending requests, and back during cancellation. If interrupted after submission, refresh the list because the server outcome can be unknown.
10. **Accessibility and finish:** inspect large text, screen reader labels, contrast, keyboard entry and timezone/DST handling. Stop Metro and FastAPI. Record limitations and fixture labels. Do not perform destructive cleanup without a reviewed, separately authorized procedure.

## Known blockers and limits

No native Android run, Expo Go version check, LAN/firewall check or live project access was performed for this plan. Android SDK tools were not on PATH; SDK/AVD and matching Expo Go availability are unverified. A LAN-bound server needs correctly provisioned isolated process environment and network access; do not expose the server key or change a credential to make this work. The current SDK/Expo Go compatibility, Android HTTP policy and device timezone data must be checked on the actual target. Backend JWT verification requires the project's supported asymmetric signing configuration, and the server-only key has privileged database access. Session revocation may not immediately invalidate an already issued access token. No test here proves release readiness, exact unlock-boundary behavior, SQL races or future invitation/notification cancellation.
