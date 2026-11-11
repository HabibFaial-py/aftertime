# AfterTime mobile

Android-first Expo Go app with email/password Supabase Auth. Uses Expo 58.0.23,
Expo Router 58.0.30, React Native 0.88.1 and React 19.3.0.

## Setup (PowerShell)

```powershell
Set-Location C:\Users\Hp\Desktop\aftertime\apps\mobile
npm ci
# Copy only if .env does not already exist; edit locally, never commit it.
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
npm start
```

Fill apps/mobile/.env with your development project's HTTPS URL and new
sb_publishable_... key using EXPO_PUBLIC_SUPABASE_URL and
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY. Expo embeds these public values in the
app. Never use a secret/service-role key. Root ignore rules exclude .env.
Restart Expo and reload after changes. No actual credentials are supplied.

Set `EXPO_PUBLIC_API_BASE_URL` in that same `.env` to the FastAPI server's
origin, for example `http://<laptop-lan-ip>:8001` in local development. On
Android, `localhost` refers to the phone, not the laptop: use the laptop's
current private LAN IP and put both devices on the same network. Find the IP
with `ipconfig`; it can change. Ensure the server listens on the network, for
example from `services/api` run
`..\..\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8001`,
and allow the port on the private firewall if necessary. Expo Go or the device
may restrict cleartext HTTP; use an HTTPS setup if the local connection fails for
that reason. HTTP sends the bearer token without transport encryption: use it
only on a trusted local development network. Non-development builds require
HTTPS; development HTTP is accepted only for localhost or private IPv4 LAN
addresses. Do not put a production URL or token in source code.

Home checks `/v1/auth/me` using the current Supabase access token with a
10-second timeout (overridable in the client method), displays Checking,
Connected or Failed, and offers retry. A failed check does not sign the user
out. A 401/403 or missing/expired session may require signing in again. The
client cancels pending network requests when Home unmounts and does not send a
request without an active session. Never share tokens when diagnosing failures.

Use Node 24 and the SDK 58-compatible Android Expo Go app. Put the phone and PC
on the same Wi-Fi and scan the terminal QR code. Stop with Ctrl+C.

```powershell
npx expo install --check
npm run typecheck
npm run lint
```

New exact pins: @supabase/supabase-js 2.119.0, react-native-url-polyfill 4.0.0
and expo-secure-store 58.0.2, with the npm lockfile. SecureStore matches Expo's
installed native-module manifest; Supabase requires Node >=22.

## Authentication and storage

Signup sends Supabase's normal confirmation email; the confirmation screen can
resend it. No passwords or tokens are placed in navigation parameters or logged.
Auth events update the session provider; Router Stack.Protected guards home and
removes protected history after logout. No profiles or capsule queries are made.

SecureStore persists the complete SDK session encrypted on the device. The SDK
restores it and refreshes tokens while active, stopping its timer in the
background. An expiry timer also hides home when a token expires offline.
This is client navigation protection only; FastAPI must enforce authorization.

SecureStore works in Expo Go without biometric prompts. Large payloads may be
rejected by native storage (older iOS releases had limits near 2 KB). Test real
session sizes on target Android devices. Storage errors are surfaced, with no
plaintext fallback. Android uninstall removes stored credentials; iOS keychain
lifecycle may differ. iOS is not the release target.

Logout uses scope 'local'. In this pinned SDK, it removes local storage before
requesting server refresh-token revocation, so offline logout can clear this
device. Remote revocation can fail offline, and already-issued access tokens
remain valid until expiry. Other devices remain signed in. If storage deletion
fails, retry or restart rather than assuming cleanup succeeded.

## Email confirmation configuration

Keep Supabase Email Auth and **Confirm email** enabled. Set development Auth
**Site URL** to a reachable, trusted web destination suitable for completing
email confirmation and review its redirect allowlist. Keep the standard
Supabase confirmation URL in the email template. The user confirms in a browser,
returns to Expo Go, then signs in with their password. No session after signup
is expected. Generic wording also covers Supabase masking an existing account.

This slice does not consume browser token fragments or exchange deep-link codes.
detectSessionInUrl is false. Expo Go does not register the production
aftertime:// scheme. Automatic return/sign-in requires a separately configured
development build, approved redirects and a callback route. Do not configure an
unimplemented callback or disable email confirmation to work around setup.
Expired links can be resent from the app; wait before retrying rate-limited requests.

## Manual Android acceptance (not run by the agent)

1. Configure env values and launch. Check small screens, keyboard, large text,
   errors and loading states. Rapid taps must submit only once while pending.
2. Sign up with a consenting test user's inbox. Confirm instructions appear;
   home must remain inaccessible. Sign in before confirmation and check the
   error. Test resend and an expired link.
3. Confirm in the browser, return and sign in. Verify the correct email on home.
   A wrong password must show a friendly error without sensitive data.
4. Force-close and reopen: restore home without a signed-out flash. Background
   and resume around token expiry; refresh should preserve the session.
5. Disable network during sign-in, signup, refresh and logout. Check errors
   and retries. After expiry home must be unavailable; reconnect or sign in.
   Verify offline logout remains signed out after restart.
6. Log out online. Back navigation and direct /home navigation must not reopen
   home. Restart and verify no old session. Sign in as a second test user.
7. Revoke a test session server-side, wait for access-token expiry and verify
   refresh failure removes access. Test realistic session sizes and simulated
   SecureStore read/write/delete failures in a test environment.

For backend integration, sign in and confirm Home changes from Checking to
Connected. Stop FastAPI or disconnect Wi-Fi, tap Retry and confirm Failed;
restart it and retry to see Connected. Verify a missing or invalid API URL,
an expired/invalid session and an unauthorized backend response show failure.
Log out during a pending request, then verify signed-out navigation and that
no stale status appears on the next user's Home. Repeat on a release build with
HTTPS before production. These integration scenarios have not been tested here.

## Sources and results

- [Supabase Expo quickstart](https://supabase.com/docs/guides/getting-started/quickstarts/expo-react-native)
- [Expo SecureStore](https://docs.expo.dev/versions/v58.0.0/sdk/securestore/)
- [Router protected routes](https://docs.expo.dev/router/advanced/protected/)
- [Foreground refresh](https://supabase.com/docs/reference/javascript/auth-startautorefresh)

Compatibility, TypeScript and lint passed during implementation. Initial
registry/Expo metadata requests needed network approval; initial type/lint
failures were fixed. npm reported 10 moderate vulnerabilities; review separately
before beta without blind force-upgrades. No Android, live Auth, email delivery
or native storage tests were performed here.
