# App Store readiness: gap analysis

Audit of the iOS release path for `live.walletbot.app` (`apps/native`).
Snapshot taken 2026-09-06 against `main` at `a42ca15`, with the uncommitted
Sign in with Apple work in the tree (`ios/Runner/Runner.entitlements`,
`lib/auth/auth_controller.dart`, `lib/screens/login.dart`). Items marked
**resolved** were fixed the same day, in the pass that produced this document;
everything else is still open.

Scope: Xcode project and signing config, `Info.plist` and entitlements, the
contents of an actually-built release bundle, the backend version gate and
production environment, CI, and the store-facing obligations the legal
documents already commit to. Android is out of scope and covered by
`docs/playstore-readiness.md`.

The build itself is not the problem. `flutter build ios --release
--no-codesign` succeeds today: exit 0, 31.3 MB `Runner.app`, Xcode 26.5,
Flutter 3.44.2, `CFBundleShortVersionString` 0.3.0, `CFBundleVersion` 6,
`MinimumOSVersion` 13.0. Everything below is signing, paperwork, and a short
list of things Apple's automated checks will bounce.

## Technical blockers

### 1. No distribution signing exists (partly resolved 2026-09-06)

`security find-identity -v -p codesigning` on the build machine returns exactly
one identity, `Apple Development: tomascichero@gmail.com`. The only installed
provisioning profile is `iOS Team Provisioning Profile: live.walletbot.app`
with `get-task-allow = true`, which is a development profile and cannot be used
for an App Store build.

The project made it worse: `CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone
Developer"` was pinned in all three build configurations, Release included.
Fixed: Debug and Profile now say `Apple Development`, Release says `Apple
Distribution`. `DEVELOPMENT_TEAM = HN527U7W3J` and `CODE_SIGN_STYLE =
Automatic` were already right.

Still needed, and only the account holder can produce them: an Apple
Distribution certificate and an App Store Connect API key. No provisioning
profile has to be managed by hand — the CI job passes the API key to
`xcodebuild -allowProvisioningUpdates`, which fetches and renews the profile
itself. No IPA has been produced yet.

### 2. The bundled `.env` ships inside the IPA (partly resolved 2026-09-06)

`apps/native/pubspec.yaml:137` declares `.env` as a Flutter asset, so it lands
unencrypted in the artifact. Confirmed in the release build produced for this
audit:
`build/ios/iphoneos/Runner.app/Frameworks/App.framework/flutter_assets/.env`,
303 bytes, byte-identical to the working copy. That file points `CONVEX_URL` at
the **dev** deployment (`proficient-finch-671`; production is
`graceful-chihuahua-196` per `apps/web/public/_native/bootstrap.json`) and
still carries the commented-out Convex **preview deploy key**. Comments ship
verbatim; anyone can unzip the IPA and read it. **The key must be rotated.**

This is the same finding as Play blocker 1, and it is sharper here because
the first upload is a local build rather than a CI one.

Fixed for CI: the new `build-ios` job copies `.env.example` over `.env` before
building, passes the real values through `--dart-define`, and then **fails the
build** unless the `.env` that actually shipped is byte-identical to
`.env.example`. That check is the part worth having; the copy is easy to
forget, the diff is not.

Still open, and it needs a person: the preview deploy key in the working copy
has to be rotated, and the local `.env` cleaned. `apps/native/README.md` now
documents the local release procedure.

### 3. Missing purpose strings for APIs the binary references (resolved 2026-09-06)

`Info.plist` declares one usage description, `NSMicrophoneUsageDescription`.
`nm -u` on the built `Runner` binary shows undefined references to
`PHPhotoLibrary`, `PHAsset`, `PHAssetChangeRequest`, `PHAssetCreationRequest`,
`PHAssetCollection`, `PHAssetResource`, `UIImagePickerController`,
`AVCaptureDevice`, `AVCaptureDeviceInput` and `CLLocationManager`.

They come from `file_picker`'s iOS dependency chain, which is visible in the
bundle: `DKImagePickerController`, `DKPhotoGallery`, `TOCropViewController`,
`SDWebImage`, `SwiftyGif`. Apple's static analysis at upload flags exactly this
shape as ITMS-90683 ("Missing purpose string in Info.plist").

The app never asks for photos or the camera. The single call site is
`apps/native/lib/components/feedback/feedback_sheet.dart:45`, with no
`FileType` filter, which on iOS is the document picker and needs no permission
at all. The honest fix would be to keep the media picker out of the binary, and
`file_picker` 12 does exactly that by moving to `PHPickerViewController` — but
this project pins 11.x deliberately, because 12 pulls `win32 ^6` and collides
with `package_info_plus ^8`, which feeds the client-version gate. That is not a
bump to make as a side effect.

So both `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription` are now
declared and localized in `en.lproj` and `es.lproj` alongside the microphone
string, and `apps/native/README.md` records why they describe a feature the app
does not have. Revisit when the `file_picker` pin lifts.

One thing to watch on the first upload: the binary also references
`CLLocationManager`, from the same dependency chain. If Apple's scanner flags
location too, the same treatment applies, but there is no point declaring a
location purpose string for an expense tracker on speculation.

### 4. `ITSAppUsesNonExemptEncryption` is not declared (resolved 2026-09-06)

Was absent from `apps/native/ios/Runner/Info.plist` and therefore from the
built bundle, which stops every upload on the export compliance question and
blocks TestFlight distribution until someone answers it by hand. The app uses
HTTPS and platform crypto only, so it qualifies for the exemption: the key is
now declared `false` and verified present in the built `Info.plist`.

### 5. iPad support is enabled, and stays enabled (decided 2026-09-06)

`TARGETED_DEVICE_FAMILY = "1,2"` in all three configurations
(`project.pbxproj:497`, `:628`, `:681`), and `Info.plist` allows every
orientation on both idioms. Owner decision: keep iPad.

That is a listing obligation and a testing obligation, not a config change. The
listing needs iPad 13" screenshots, and the layout has to be walked on an iPad
before submission, because a reviewer will open it there. Guideline 2.4.1 and
anything that breaks at that width are now in scope for the release.

### 6. The launch screen is the Flutter default

`ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@2x.png` is
byte-identical (md5 `978c1bee49d7ad5fc1a4d81099b13e18`) to the file in
`$FLUTTER_ROOT/packages/flutter_tools/templates/module/ios/host_app_ephemeral/`.
The app icon set, by contrast, is custom and the 1024×1024 has no alpha
channel, so it is fine. Not a rejection, but the launch screen is the first
frame a reviewer sees.

### 7. No app-level privacy manifest (resolved 2026-09-06)

The bundle carries 22 third-party `PrivacyInfo.xcprivacy` files (Flutter
engine, GoogleSignIn, AppAuth, `record_ios`, `flutter_secure_storage_darwin`,
`shared_preferences_foundation`, and so on), but the Runner target declared
none of its own.

`ios/Runner/PrivacyInfo.xcprivacy` now does, wired into the target's resources
and verified present in the built bundle: `NSPrivacyTracking = false`, no
tracking domains, the file-timestamp required-reason declaration (`C617.1`,
which the SQLite database file access needs), and the seven data types the app
actually collects. Crash data is deliberately **not** declared, because nothing
collects it yet; add it with the SDK, not before.

### 8. The voice engine has never been verified on iOS hardware

`docs/riesgos.md` (R-003) still marks the unified native engine in
`ios/Runner/PcmAudioPlayer.swift`, built on Apple's voice-processing I/O for
echo cancellation, as **pendiente de verificación en hardware**, after a first
attempt that failed with no diagnosis. The Dart Convex client swap is in the
same state.

Voice is the product's headline feature and the reason the app exists. If it
fails on the reviewer's iPhone that is a guideline 2.1 rejection, and the
feedback loop is days long. A device pass before the first upload is worth more
than everything else on this list.

### 10. `MinimumOSVersion` was 13.0 (resolved 2026-09-07)

Build 74 uploaded with one warning, ITMS-90068: Apple stops accepting anything
below 15.0 in Spring 2027. The floor is now 15.0 in all three configurations,
and the Podfile declares the same value instead of leaving it commented out, so
CocoaPods and the Xcode project cannot drift.

This cost nothing. iOS 15 runs on every device iOS 13 did, iPhone 6s and later
plus the 7th-generation iPod touch; the device list did not shrink until
iOS 16. So the floor excludes no hardware, only someone who owns a supported
phone and never updated it, on an app that has shipped to nobody. Build 76
(`0.3.2`) uploaded with **no warnings at all**.

It also clears half of blocker 3: `file_picker` 12 needs iOS 14 as its floor,
so only the `package_info_plus` / `win32` conflict still pins us to 11.x and
its photo and camera purpose strings.

### 9. No crash reporting

No Crashlytics, no Sentry, no `FlutterError.onError` handler anywhere in
`apps/native`. Post-release visibility on iOS would be limited to whatever App
Store Connect surfaces on its own.

This is a legal blocker rather than an Apple one. `docs/legal/README.md`
required-item 4 records the owner decision to name **Google LLC (Firebase)**,
Crashlytics plus Analytics, as a processor in Privacy §7, with a 12-month
retention. No Firebase SDK exists in the codebase. Publishing the app makes a
published policy claim false.

## App Store Connect and policy blockers

### 10. The App Store Connect record does not exist

Nothing in the repo references an Apple app ID or SKU, and the landing still
advertises iOS as "coming soon"
(`apps/landing/src/components/store-badges.astro`, `t.download.ios`). Creating
the record needs: app name, primary language, bundle id, SKU, Finance as the
primary category, and the current age-rating questionnaire answered honestly
about the AI assistant, its chat interface and its user-generated content. The
T&C sets a hard 18+ minimum, so the store age rating has to be reconciled with
that rather than left at whatever the questionnaire suggests.

### 11. Privacy nutrition labels

Mirror the Play Data Safety declaration that `docs/legal/README.md` already
specifies: Contact Info (name, email), Financial Info (user-entered
transactions), User Content (voice and chat), Identifiers (the random telemetry
installation ID in `telemetryEvents.installationId`), Diagnostics, Usage Data.
Sharing has to name Google (audio streamed to the Gemini Live API) and Grafana
Labs (OTLP telemetry export). Declare the account deletion URL
`https://app.walletbot.live/delete-account`.

### 12. `support@walletbot.live` cannot receive mail yet

Legal required-item 2, open since 2026-08-06. The code side landed with WAL-185
(the Resend inbound webhook at `/resend-inbound-webhook`, the `supportEmails`
table, forwarding to `SUPPORT_FORWARD_TO`, env vars set in dev and prod), but
per R-013 the domain's MX records still do not point at Resend and the
`email.received` webhook has not been created in the dashboard. Until both are
done, the address published in all four legal documents, and shown to users as
`feedbackSupportEmail`, silently drops everything sent to it.

Apple requires a working support URL on the listing. A support address that
swallows mail is worse than no address.

### 13. The 12-month voice retention cron (resolved 2026-09-06)

Legal required-item 3. Privacy §5 and §9 promise automatic deletion of
`voiceSessions` and `voiceSessionEvents` older than twelve months, and nothing
implemented it.

Two six-hourly crons now do: `deleteOldVoiceSessions` and
`deleteOldVoiceSessionEvents` (`packages/backend/convex/voice/internal.ts`)
walk `by_startedAt` and `by_occurredAt` oldest-first in batches of 200 and
2000. Both indexes exist for retention alone and no client read uses them. The
retention window lives in one place, `VOICE_RETENTION_MS`, next to a note that
changing it means changing a published document first.

### 14. App Review notes and demo credentials

The app is login-gated. Review notes need a working account, and should also
point at the local-only path (`lib/screens/login.dart:552`, `_LoginPath.local`)
which needs no account at all. Say explicitly that voice requires a physical
device with a microphone and network access, and say where the
report-this-response control is, because guideline 1.2 compliance is only
credible if the reviewer finds it.

### 15. iOS has no distribution URL in the version gate

`packages/backend/convex/config/helpers.ts:202` carries the TODO: `[PLATFORM_IOS]`
gets the base soft and hard update banners with no action, so `updateUrl` stays
null and the hard-update prompt renders a critical banner with no button. A
user gated out of sync has nowhere to go. Fill in the App Store link the moment
the app has one, matching `ANDROID_PLAY_STORE_URL`, and flip the landing badge
off "coming soon" at the same time.

## Store listing assets: none present in the repo

- iPhone 6.9" screenshots, at least one, up to ten
- iPad 13" screenshots if iPad support stays enabled (see blocker 5)
- subtitle, description, keywords, promotional text
- support URL, marketing URL, privacy policy URL, copyright line
- optional app preview video

The app is localized en/es (`lib/l10n/*.arb`, `ios/Runner/{en,es}.lproj/`), so
the listing should be too. The 1024×1024 icon comes from the asset catalog and
is already correct. The files in `docs/store/` are 1024×500 Play feature
graphics and have no Apple equivalent.

## Release-process gaps

- **iOS CI works end to end** (added 2026-09-06, green 2026-09-07). Build
  `0.3.1` (74) went from a clean checkout to `UPLOAD SUCCEEDED with no errors,
  1 warning` on a `blacksmith-6vcpu-macos-15` runner with Xcode 26.3, 27.6 MB
  IPA, delivery UUID `905bfd23-c447-4e6e-a56d-1f87008a16eb`. No ITMS
  purpose-string complaints, which is the `Info.plist` work in blocker 3 doing
  its job. The one server warning is the deployment target, below.
- **What the job does.** `build-ios` in
  `.github/workflows/prod-deploy.yml` selects the newest Xcode, installs the
  certificate into a throwaway keychain, compiles with the production
  dart-defines, verifies the bundled `.env`, archives with
  `xcodebuild -allowProvisioningUpdates` against the App Store Connect API key,
  exports, and uploads to TestFlight. `workflow_dispatch` runs it alone, with
  `deploy` and `build-android` held back, so retrying it costs no version bump
  and cuts no Android release.
- **Two things it taught us, both worth keeping.** `connectivity_plus` 7.3.x
  calls `NWPath.isUltraConstrained`, so the build needs the iOS 26 SDK and the
  job has to select Xcode explicitly rather than take the image default. And
  Release must not pin `CODE_SIGN_IDENTITY` while the target signs
  automatically: `xcodebuild` refuses both at once with "Runner has conflicting
  provisioning settings".
- **Three things broke on the way there, all now fixed.** Worth keeping,
  because each cost a run: `connectivity_plus` 7.3.x calls
  `NWPath.isUltraConstrained`, so the build needs the iOS 26 SDK and the job
  has to select Xcode instead of taking the image default. Release must not pin
  `CODE_SIGN_IDENTITY` while the target signs automatically, or `xcodebuild`
  refuses both at once. And the App Store Connect API key must carry **Admin**,
  because cloud signing is the one thing App Manager cannot do — reported as
  `Cloud signing permission error` plus `No profiles for 'live.walletbot.app'
  were found`, which sends you hunting for a profile instead of a permission. A
  key's access level cannot be edited after creation; revoke and make a new
  one.
- **The version gate is now shared** (changed 2026-09-06). The bump detection
  moved out of `build-android` into its own `version` job, because both store
  jobs must agree on what counts as a release and two copies of that shell
  would drift. `build-android` behaves as before; it reads
  `needs.version.outputs.*` instead of `steps.version.outputs.*`. **This
  touched the working Play release path and deserves a careful read.**
- **macOS runner cost.** Private-repo macOS minutes bill at ten times the Linux
  rate, so `build-ios` runs only on a version bump and has no artifact-only
  path. Roughly 100 to 150 billed minutes per release.
- **Flutter version drift.** CI pins 3.41.6, this machine has 3.44.2, and every
  build verified in this audit used the latter. The iOS job pins 3.41.6 to
  match Android, which means the first CI build compiles on a toolchain no one
  has yet used for iOS here.
- **Build number policy.** Apple requires `CFBundleVersion` to increase
  strictly within a version string, across every upload including rejected
  ones. The Android release flow keys off the `pubspec.yaml` `version:` line
  only, so the iOS job passes `--build-number` from `github.run_number`
  instead, which is the only number in the pipeline that always moves
  forward.
- **Individual developer account.** Team `HN527U7W3J` is registered to a person,
  not a company, so the App Store lists that person as the seller. The legal
  documents already name the same individual, so this changes nothing legally,
  but it is worth knowing before the listing goes public.

## Verified fine

- Release build succeeds end to end, unsigned, on Xcode 26.5 / Flutter 3.44.2.
- Bundle id `live.walletbot.app` matches the Play application id, the
  entitlements file, and `APPLE_BUNDLE_ID` on the production Convex deployment.
- **Sign in with Apple is fully wired.** The entitlement is in
  `ios/Runner/Runner.entitlements`, the App ID carries the capability (the
  development profile's entitlements include
  `com.apple.developer.applesignin`), and production Convex has
  `APPLE_BUNDLE_ID` set, which is what enables the provider in
  `packages/backend/convex/auth.ts`. Guideline 4.8 is satisfied: the app offers
  Google sign-in and now offers the equivalent private option on iOS.
- **Account deletion exists**, in-app under Settings and at the public
  `app.walletbot.live/delete-account` URL. Guideline 5.1.1(v) is satisfied.
- **AI content reporting exists**, a flag control on every agent turn plus the
  long-press sheet and the app-bar fallback, landing in `agentReports`.
  Guidelines 1.2 and 4.7.1 are satisfied. Do not ship a build with the
  `agentReportButton` flag disabled.
- Microphone permission is requested at point of use with a denial path, and
  `NSMicrophoneUsageDescription` is written and localized in both `en.lproj`
  and `es.lproj`.
- App icon is custom, complete for every required size, and the 1024×1024 has
  no alpha channel.
- Google sign-in is configured for iOS: `GIDClientID` and the reversed-client-id
  URL scheme are in `Info.plist`, and production Convex has
  `GOOGLE_IOS_CLIENT_ID` set.
- Legal documents are hosted and language-negotiated at
  `www.walletbot.live/{privacy,terms}`, which is the single non-PDF URL Apple
  asks for.
- Version-gating infrastructure (soft and hard banners, server-side
  `isClientSupported`, `IOS_MIN_SUPPORTED_VERSION`) is in place for day-one
  releases, apart from the missing update URL in blocker 15.

## Not verified in this audit

- ~~Whether an App Store Connect record, an Apple Distribution certificate or
  an App Store Connect API key exist~~ — all three exist as of 2026-09-07, and
  CI has used them to deliver a build.
- Whether the sending domain for transactional email is registered with Apple's
  Private Email Relay. `apps/native/README.md` documents why it must be:
  password resets to `@privaterelay.appleid.com` users are silently dropped
  otherwise.
- iPad layout behaviour, since no iPad build has been run.
- Whether the app behaves on a real iPhone at all, beyond compiling (blocker 8).
