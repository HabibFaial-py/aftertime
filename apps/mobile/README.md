# AfterTime mobile

Minimal Android-first Expo Router + strict TypeScript scaffold. The welcome route has no buttons, network calls or capsule features.

From PowerShell:

```powershell
Set-Location C:\Users\Hp\Desktop\aftertime\apps\mobile
npm install
npx expo install --check
npm run typecheck
npm run lint
npm start
```

Use Node 24.19.0/npm 12.0.2 (the supplied environment). The first install must succeed before the remaining commands can work. Keep the generated `package-lock.json` after successful installation; subsequent clean installs should use `npm ci`.

Update Android Expo Go to the SDK 58 compatible release from https://expo.dev/go. Put the phone and PC on the same Wi-Fi, open Expo Go and scan the QR code from `npm start`. No Android Studio or USB setup is required. Allow Node through Windows Firewall for your private network if prompted. Stop the server with Ctrl+C. Restart with `npm start -- --clear` if Metro's cache becomes stale.

SDK 58 compatibility was checked on 2026-11-10 against:

- https://expo.dev/go (SDK 58 listed as latest, Android supported).
- https://expo.dev/changelog/sdk-58 (stable release dated 2026-10-15).
- https://github.com/expo/expo/blob/sdk-58/packages/expo/bundledNativeModules.json (matching native package versions).
- https://github.com/expo/expo/blob/sdk-58/templates/expo-template-default/package.json (React, React Native and TypeScript versions).

Dependencies are pinned in `package.json` using these official sources. This environment could not access npm, so their registry availability, peer resolution and runtime behavior remain unverified. No lockfile was fabricated. The scaffold was authored directly because the generator also requires registry access. Do not rerun a generator over these files.

Pending manual acceptance: launch on Android, confirm the app name and tagline, check large font size and small-screen scrolling, and confirm there are no actionable controls. The physical phone's installed Expo Go version has not been inspected.
