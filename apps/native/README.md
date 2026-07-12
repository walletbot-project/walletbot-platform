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

(pending — set up after Apple Developer account is provisioned)
