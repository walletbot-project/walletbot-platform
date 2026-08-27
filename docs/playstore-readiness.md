# Play Store readiness — gap analysis

Audit of the Android release path for `live.walletbot.app` (`apps/native`).
Snapshot taken 2026-07-31 against branch `codex/version-client-apis-v1`.

Scope: Gradle and signing config, `AndroidManifest.xml`, bundled Flutter assets,
the native libs inside the already-built release APK, the backend version gate,
CI, and the web app as a host for legal pages. iOS is out of scope.

## Blockers — technical

### 1. Bundled `.env` ships a real credential and points at the dev backend

`apps/native/pubspec.yaml:88` declares `.env` as a Flutter asset, so it lands
unencrypted inside the artifact — confirmed present in the built release APK at
`assets/flutter_assets/.env` (303 bytes). That file currently contains:

- `CONVEX_URL` / `CONVEX_SITE_URL` pointing at the **dev** deployment
  (`proficient-finch-…`, matching `CONVEX_DEPLOYMENT=dev:proficient-finch-…` in
  `packages/backend/.env.local`). Production is `graceful-chihuahua-…`, per
  `apps/web/public/_native/bootstrap.json`.
- a commented-out Convex **preview deploy key**
  (`# preview:wallet-bot:walletbot-platform|…`). Comments ship verbatim inside
  the asset; anyone can unzip the AAB and read it. **The key must be rotated.**

L0 bootstrap does override the URL in release
(`apps/native/lib/app_config/bootstrap.dart`), but it fails *open* by design —
a first launch whose bootstrap fetch fails talks to the **dev** deployment.

Fix direction: release builds must inject production values via `--dart-define`
(already supported in `apps/native/lib/config.dart:20-34`), and `.env` must not
carry secrets.

### 2. Launcher icon is still the default Flutter icon

`apps/native/android/app/src/main/res/mipmap-*/ic_launcher.png` are byte-for-byte
identical (md5) to the Flutter template files. Also missing:

- adaptive icon (no `mipmap-anydpi-v26/`)
- monochrome / themed icon (Android 13+)
- splash is the template white `@android:color/white`
  (`apps/native/android/app/src/main/res/drawable/launch_background.xml`)

### 3. `android:allowBackup` not disabled while using `flutter_secure_storage`

`apps/native/android/app/src/main/AndroidManifest.xml:5-8` sets no backup
attributes, so Android Auto Backup is enabled. The plugin's own documentation
(v10) requires `android:allowBackup="false"` plus excluding its shared
preferences; otherwise restored installs hit
`java.security.InvalidKeyException: Failed to unwrap key`, because the Keystore
key is not restorable.

Affected state lives in secure storage: session tokens
(`apps/native/lib/auth/auth_controller.dart`), the bootstrap cache and device
identity (`apps/native/lib/app_config/`), instantiated at
`apps/native/lib/main.dart:36`. The drift database would also be backed up and
restored out of sync with sync state. Symptom in production: crashes and lost
sessions on device-migration installs, visible in Play vitals.

### 4. Google Sign-In will fail on Play-distributed builds

`apps/native/lib/auth/auth_controller.dart:57` uses
`GoogleSignIn.instance.authenticate()`. Play App Signing re-signs the upload
with Google's own key, so the SHA-1 registered on the Google OAuth Android
client must include **both** the upload key and the Play-managed signing
certificate. `apps/native/README.md` documents `gradlew signingReport` but not
the Play-managed fingerprint.

Unverified from the repo: whether the production Convex deployment has the
Google provider environment variables set.

### 5. No AAB has ever been produced; ABI coverage unverified

Only `build/app/outputs/apk/release/app-release.apk` exists. Play requires an
AAB for a new app.

Update 2026-08-27: `convex_flutter` (and its Rust `libconvex_flutter.so`) was
removed — the Convex client is now pure Dart (`apps/native/lib/convex/`), so
the arm64-only Rust-lib risk is gone. Still unverified: drift's native-assets
`libsqlite3.so` path through an `appbundle` build.

## Blockers — Play Console / policy

### 6. No privacy policy exists

Nothing in `apps/web/src/pages/`, `apps/web/public/`, or the repo. Required for
the store listing and the Data safety form. The app collects email and name,
financial data, audio, and device identifiers, and streams audio to a
third-party model (`packages/backend/convex/v1/live/actions.ts`) — all of which
must be declared, including third-party sharing.

### 7. No user-account deletion — resolved (2026-08-06)

Play's data-deletion policy requires an in-app deletion path plus a
web-accessible deletion URL for apps with account creation. Both now exist:
native Settings → "Delete my account" requests a confirmation email
(`POST /v1/account-deletion/request`), and the web app serves the public
deletion URL at `${SITE_URL}/delete-account` (works logged out). The emailed
link lands on `/delete-account/confirm`, which warns the action is
irreversible and purges all user data plus the better-auth user
(`packages/backend/convex/userDeletion/`). Remaining Play Console task:
declare the deletion URL in the Data safety form.

### 8. No terms of service

Also absent. Needed if the listing or onboarding references it.

### 9. App access declaration

The app is login-gated, but the "without account" local path exists
(`apps/native/lib/screens/login.dart:407`, `_LoginPath.local`), so the Console
declaration can point reviewers there instead of shipping demo credentials.
Confirm that path is fully usable with no network.

### 10. Closed-testing requirement

If the developer account is a personal (non-organization) account created after
Nov 2023, production access requires a closed test with 12+ testers for 14
continuous days. Calendar gap, not a code gap.

## Store listing assets — none present in the repo

- 512×512 icon
- 1024×500 feature graphic
- two or more phone screenshots (plus tablet screenshots if tablet support is
  claimed)
- short and full description
- content rating questionnaire, target audience, ads declaration, data safety
  form

The app is localized en/es
(`apps/native/android/app/src/main/res/values-es/strings.xml`, `lib/l10n/*.arb`),
so the listing should be localized too.

## Release-process gaps

- **No release pipeline.** `.github/workflows/native.yml` runs only `analyze`
  and `test`, and does `touch .env`. There is no build / sign / upload job. The
  keystore and `key.properties` are local-only (correctly gitignored).
- **Debug-signing footgun.** `apps/native/android/app/build.gradle.kts:54-58`
  falls back to the debug signing config when `key.properties` is absent. A CI
  release job missing that secret would silently emit a debug-signed AAB that
  Play rejects.
- **Flutter version drift.** CI pins 3.41.6; the local toolchain is 3.44.2.
  Release builds should be pinned to a single version.
- **Version bump policy.** `apps/native/pubspec.yaml:19` is `0.1.0+1`, and
  `BASE_MIN_SUPPORTED_VERSION` / `BASE_LATEST_VERSION` in
  `packages/backend/convex/config/helpers.ts` are hardcoded to `0.1.0`. Every
  release needs a coordinated bump on both sides (already mandated by
  `CLAUDE.md` for wire changes).
- **No crash reporting** (no Sentry / Crashlytics in `pubspec.yaml`). Post-release
  visibility is limited to Play vitals. `build/app/outputs/native-debug-symbols/`
  and `build/app/outputs/mapping/` are produced and should be uploaded to the
  Console.

## Verified fine

- `targetSdk` / `compileSdk` = 36, `minSdk` = 24 (Flutter 3.44 defaults) — meets
  Play's current API-level requirement.
- **16 KB page-size compliance**: `libsqlite3.so` reports LOAD segment
  alignment `0x4000` (NDK 28.2.13676358); `libconvex_flutter.so` no longer
  ships (the Convex client is pure Dart since 2026-08-27). Mandatory for
  API 35+ targets; it passes.
- Release keystore and `key.properties` exist locally, with a documented
  backup / restore procedure in `apps/native/README.md`.
- No permissions requiring a Play declaration form: only `INTERNET` and
  `RECORD_AUDIO`, plus a scoped `PROCESS_TEXT` `<queries>` block (not
  `QUERY_ALL_PACKAGES`). Microphone is requested at point of use
  (`apps/native/lib/screens/voice.dart:303`) with a denial path; iOS
  `NSMicrophoneUsageDescription` is written.
- `applicationId live.walletbot.app` matches the Play URL already wired into the
  update banner (`packages/backend/convex/config/helpers.ts`).
- Version-gating infrastructure (soft / hard update banners, server-side
  `isClientSupported`) is in place for day-one releases.

## Not verified in this audit

- Whether the production Convex deployment has its auth and Gemini environment
  variables set.
- Whether `flutter build appbundle --release` succeeds — no bundle build was
  run.
