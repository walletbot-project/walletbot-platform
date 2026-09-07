# Wallet Bot — Native App

Flutter app for iOS and Android.

## Getting started

```bash
flutter pub get
flutter run
```

## Localization

The app uses Flutter's built-in `gen-l10n` workflow. English is the template
locale and Spanish is also supported; the device locale is selected
automatically.

- Add or update messages in `lib/l10n/app_en.arb` and `app_es.arb`.
- Use `context.l10n.<message>` in widgets and the localized helpers in
  `lib/l10n/l10n.dart` for model labels, dates, and dashboard defaults.
- Regenerate after changing ARB files with `flutter gen-l10n`.
- Run `flutter analyze` and `flutter test` before committing.

Android resource strings and iOS `InfoPlist.strings` cover OS-owned surfaces
such as the app name and microphone permission prompt.

## Android signing

Debug builds use the system debug keystore (`~/.android/debug.keystore`). Release builds use a project-local keystore.

### Required files (gitignored)

| Path | Purpose |
|---|---|
| `android/keystore/release.jks` | Release signing key (RSA 2048, alias `upload`) |
| `android/key.properties` | Credentials loaded by `android/app/build.gradle.kts` |

Both files are gitignored. **They must be backed up outside the repo** — losing them means you can never publish updates to the Play Store for `live.walletbot.app`.

### `key.properties` format

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=keystore/release.jks
```

`storeFile` is resolved relative to `android/` (the `rootProject` directory).

### Fallback behavior

If `android/key.properties` is missing, the release build type falls back to the debug signing config. This keeps `flutter build` working on machines that don't have the release keystore — but the resulting APK/AAB is **not** publishable.

### Extracting SHA-1 fingerprints

For registering OAuth clients with Google / Firebase / etc.:

```bash
cd android
./gradlew signingReport
```

Look for `Variant: debug` and `Variant: release` blocks. The SHA-1 from each is what you paste into provider consoles.

### Restoring on a new machine

1. Retrieve `release.jks` from your backup, place at `android/keystore/release.jks`.
2. Retrieve `key.properties` from your backup, place at `android/key.properties`.
3. Verify: `cd android && ./gradlew signingReport` — the release variant should show the expected SHA-1.

## iOS signing

Bundle id `live.walletbot.app`, team `HN527U7W3J`. Debug and Profile sign with
`Apple Development`, Release with `Apple Distribution`
(`ios/Runner.xcodeproj`). Automatic signing is on, so Xcode resolves the
profile itself.

Still missing on any machine: the distribution certificate and the App Store
Connect API key. `docs/appstore-readiness.md` covers how to produce both and
which repository secrets they become. The `build-ios` job in
`.github/workflows/prod-deploy.yml` archives and uploads to TestFlight once
they exist.

### Building a release locally

```bash
cp .env.example .env   # never ship your own .env, see below
flutter build ipa --release \
  --dart-define=CONVEX_URL=... \
  --dart-define=CONVEX_SITE_URL=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=...
```

`.env` is a declared Flutter asset, so whatever sits at that path is readable
inside the shipped IPA. Copy the placeholder over it before any build that
leaves this machine, and pass real values through `--dart-define`, which
`lib/config.dart` prefers anyway. CI does exactly this and then fails the build
if the bundled file is not byte-identical to `.env.example`.

### Why the photo and camera purpose strings exist

`Info.plist` declares `NSPhotoLibraryUsageDescription` and
`NSCameraUsageDescription` for a feature the app does not have. `file_picker`
is pinned to 11.x (see the note in `pubspec.yaml`), and that version links
`DKImagePickerController`, so `PHPhotoLibrary`, `UIImagePickerController` and
`AVCaptureDevice` end up referenced in the binary. Apple's static analysis
rejects an upload that touches those APIs with no purpose string, whether or
not the code path is reachable. `file_picker` 12 replaced that dependency with
`PHPickerViewController`; when the `package_info_plus` / `win32` conflict that
pins us to 11.x is resolved, both strings can go.

## Sign in with Apple

iOS only. The button is hidden on every other platform (`_appleSignInAvailable`
in [lib/screens/login.dart](lib/screens/login.dart)) because Apple's non-Apple
platforms go through a browser flow that needs a Services ID nobody has
registered.

It exists because the app offers Google sign-in, and App Store Review Guideline
4.8 then requires an equivalent private option. Email and password does not
count — 4.8 asks for one that lets the user withhold their email address.

### What the code does

The app asks for the `email` and `fullName` scopes, hands Apple the SHA-256
digest of a fresh nonce, and posts `POST /auth/apple` with the identity token
and the **raw** nonce (`signInWithApple` in
[lib/auth/auth_controller.dart](lib/auth/auth_controller.dart)). Apple embeds
the digest in the token; better-auth re-hashes the raw value to compare, so
sending the digest to both sides would hash it twice and fail with a bare 401.

`givenName`/`familyName` ride along on that same request. Apple returns the
user's name **only on the first authorization**, outside the token, and never
again — miss it and the account has no name for good.

The `email` claim has the same once-only behaviour, and better-auth rejects an
ID-token profile without one (`USER_EMAIL_NOT_FOUND`), so untreated the flow
would work exactly once per user and 401 forever after. `mapProfileToUser` in
[packages/backend/convex/auth.ts](../../packages/backend/convex/auth.ts) fills
the gap with `<sub>@apple.invalid`. For a returning user it is never read:
better-auth resolves them by `providerId + accountId` (Apple's `sub`) before it
looks at the email, and it does not overwrite a stored profile on sign-in.

The one case where that address sticks is a **first** sign-in that already has
no email — somebody who authorized this App ID under an earlier build whose
account no longer exists. They get a working account with an undeliverable
address, so password reset and delete-by-email link do not work for them. The
fix is on the device: Settings → Apple ID → Sign in with Apple → the app → stop
using, which makes the next sign-in count as the first one again. An
`@apple.invalid` address in the account switcher is the tell.

### Apple Developer portal

1. Open the App ID `live.walletbot.app` under **Identifiers**, tick
   **Sign in with Apple**, save. (Team `HN527U7W3J`.)
2. Refresh the provisioning profiles — in Xcode, Signing & Capabilities, or by
   toggling automatic signing. The entitlement in
   [ios/Runner/Runner.entitlements](ios/Runner/Runner.entitlements) only takes
   effect if the profile carries the capability, and a build signed against a
   stale profile fails at launch, not at compile time.
3. Add the domain used in the `From:` address of transactional email to
   **Private Email Relay** (Certificates, IDs & Profiles → More). Users who hide
   their address get an `@privaterelay.appleid.com` alias, and Apple silently
   drops mail from unregistered senders — password resets to those users would
   vanish.

No Sign in with Apple key and no Services ID are needed: the ID-token flow
verifies against Apple's public JWKS. Both become necessary the day the web app
grows the button, which also needs a client-secret JWT (ES256, 180-day maximum
lifetime) and domain verification.

### Backend

`APPLE_BUNDLE_ID` must be `live.walletbot.app` on the Convex deployment. It
alone enables the provider; `APPLE_CLIENT_ID` is reserved for a future web
Services ID (see `socialProviders.apple` in
[packages/backend/convex/auth.ts](../../packages/backend/convex/auth.ts)).

### Hidden email addresses

A user who hides their address arrives with an
`@privaterelay.appleid.com` alias. It is a real, deliverable address, but it
does not match the address the same person may have used with Google, so
better-auth cannot link the two and they get a **second account**. That is
Apple's design, not a bug to fix here — but it is the likely cause of any
"where did my data go" report from an iOS user.
