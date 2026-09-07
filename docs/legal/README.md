# Legal documents

Bilingual (ES/EN) Terms & Conditions and Privacy Policy for Wallet Bot, targeting **Argentina (primary)** and the **United States**. Drafted 2026-08-06 against the codebase at commit `c134410` and current regulation (Ley 25.326, Res. AAIP 14/2018 y 47/2018, Ley 24.240 + Disposición 377/2026, US state privacy laws, COPPA, CAN-SPAM, Google Play / App Store policies).

Amended 2026-08-06 after a code-vs-policy audit (owner decisions): disclosed Grafana Labs and Apple Sign-In as recipients (Privacy §7) and the telemetry installation/session identifiers (§3.4); generalized the password-hash, session-token and cookie/browser-storage wording (§3.1, §11, §15); fixed the Ley 25.326 contract-necessity citation to art. 5.2(d) (§6); softened the expired-deletion-request retention row (§9). Features the policy still promises but the code lacks were kept in by owner decision — they are tracked in § Implementation TODOs below and **must ship before publishing**.

Amended again 2026-08-06 after the T&C code-vs-text audit: the local-only-mode wording (T&C §4, Privacy §2 and §16) is now scoped to financial records/content and discloses that the app sends usage and diagnostic telemetry (random installation ID, `app.started`) even without an online account — the previous "all data stays on your device / never transmitted" claims were contradicted by the native telemetry client, which fires unconditionally at launch (`apps/native/lib/main.dart` `_TelemetryStarter` → `apps/native/lib/telemetry/telemetry_client.dart`).

| File | Content |
|---|---|
| `privacy-policy.es.md` | Política de Privacidad — **legally operative version for Argentine consumers** |
| `privacy-policy.en.md` | Privacy Policy — prevails for non-Argentine users |
| `terms-and-conditions.es.md` | Términos y Condiciones — **legally operative version for Argentine consumers** |
| `terms-and-conditions.en.md` | Terms and Conditions — prevails for non-Argentine users |

The ES and EN versions are substantively identical and **must always be updated together**.

## Before publishing — REQUIRED

1. ~~**Replace the placeholders** in all four files~~ — **DONE (2026-08-23, owner decision).** All four placeholders are filled in all four documents and the effective / last-updated dates were bumped to August 23, 2026:
   - controller name → **Tomás Cichero, CUIT 20-43920814-8** (a human person; there is no company)
   - domicile → **Estanislao del Campo 1260, B1604ADH Florida Oeste, Provincia de Buenos Aires, Argentina**
   - analytics / crash-reporting provider → **Google LLC — Firebase** (Firebase Crashlytics + Google Analytics for Firebase); Grafana Labs keeps its own separate row
   - analytics retention → **12 months** from collection, matching the voice-session retention. See item 4 below for what filling these two now *obliges* us to do.
2. **Create the `support@walletbot.live` mailbox** (or alias). It is the contact named in every document; today only `no-reply@walletbot.live` exists and it cannot receive mail.
3. ~~**Implement the 12-month voice-data retention cron.**~~ — **DONE (2026-09-06).** `VOICE_RETENTION_MS` (`packages/backend/convex/voice/utils.ts`) and two six-hourly crons walk `voiceSessions.by_startedAt` and `voiceSessionEvents.by_occurredAt` oldest-first, in batches, and delete anything past twelve months (`packages/backend/convex/voice/internal.ts`). The indexes exist for retention alone; no client read uses them. `docs/voice-session-lifecycle.md` predates this and still says there is no retention policy.
4. **Firebase is now disclosed but not yet integrated — close the gap before publishing.** By owner decision (2026-08-23) Privacy §7 names **Google LLC — Firebase** (Firebase Crashlytics for crash reporting, Google Analytics for Firebase for usage analytics) and Privacy §9 sets a **12-month** retention. No Firebase SDK exists in the codebase yet (see Implementation TODOs 6 and 7). Before the policy goes live:
   - **Integrate Firebase Crashlytics and Google Analytics for Firebase** in `apps/native`, or the §3.4 / §6.4 / §7 claims are false.
   - **Disable advertising-identifier collection.** Google Analytics for Firebase collects the platform advertising ID by default on Android. Privacy §4 states "No advertising identifiers, no advertising networks, no third-party tracking" — set `google_analytics_adid_collection_enabled=false` (and the iOS equivalent) and disable Google signals / ad personalization in the Firebase console, **or** §4 must be reworded in both languages.
   - **Enforce the 12-month retention** in the Firebase console (Analytics data-retention setting; Crashlytics keeps crash data ~90 days, which is inside the promise) and for `telemetryEvents` (Implementation TODO 2), and delete the account-linked events on account deletion as §9 now promises.
   - **Sign / accept the Firebase DPA** (Google Cloud / Firebase Data Processing and Security Terms) and add Firebase to item 6 below.
   - **Update the Play Data Safety form** for the Firebase installation ID and analytics/crash data.
   - Note: **Grafana Labs (Grafana Cloud)** is disclosed separately in Privacy §7 — the backend exports first-party telemetry (installation/session/user identifiers, app version, platform) to it via OTLP every 5 minutes (`packages/backend/convex/telemetry/actions.ts`, `docs/observability-grafana.md`).
5. **Register the database with the RNBD (AAIP)** — free, via the TAD platform: register the responsable, then the database, declaring the transfer to the United States. Required by Ley 25.326 art. 21 / Res. AAIP 132/2018. The policy deliberately does not claim registration; optionally add the registration number once obtained.
6. **Verify data-processing agreements (DPAs)** are in place with Convex, Google (Cloud/Gemini API), Resend and Grafana Labs — the transfer clause (Privacy §8) relies on "contractual safeguards". Also confirm which Gemini API tier is in use and whether Google uses API data for training; if the paid tier's no-training guarantee applies, the policy can be strengthened to say so.
7. **Lawyer review** (Argentine counsel) — especially: consumer clauses under Disposición 377/2026, the RNBD filing, and re-verifying that no new data-protection law replaced Ley 25.326 after mid-2026 (reform bills were pending in Congress when this was drafted).

## Implementation TODOs — features the policy promises that do not exist yet

Audit of 2026-08-06 (policy text vs. `main` at `ba3f017` and branch `wal-151-agregar-opcion-para-eliminar-cuenta`). Owner decision: **implement these rather than reword the policy.** None of the affected claims may go live before its feature ships.

1. **Ship PR #192 (`wal-151-agregar-opcion-para-eliminar-cuenta`).** The entire account-deletion flow (Privacy §10: in-app option, `app.walletbot.live/delete-account`, 24 h confirmation link), the deletion-request + tombstone retention rows (§9), the Resend integration and ALL transactional emails (§3.5, §6: verification, password reset, deletion confirmation) exist only on that unmerged branch — none of it is on `main`. Merge hazard: the branch's `crons.ts` drops `main`'s five telemetry crons; re-add them when resolving.
2. **Purge user-scoped telemetry on account deletion.** `telemetryEvents` rows carry `userId` (`packages/backend/convex/schema/telemetry.ts`) and PR #192's `purgeUserData` predates telemetry, so they survive deletion — contradicting §9/§10 ("hard-deleted; only a random identifier and timestamp remain"). Extend the purge list and define a telemetry retention period (ties into the §9 analytics-retention placeholder).
3. **Enforce mandatory email verification.** §11 claims it; `packages/backend/convex/auth.ts` sets `requireEmailVerification: false`.
4. **Implement password reset, revoking ALL sessions on reset** (§6.2, §9, §11). No reset flow exists on `main`; note native sessions live in the app's own `refreshTokens` table, which better-auth's built-in reset would NOT revoke — needs explicit handling.
5. **Implement effective rate limiting and anti-enumeration** (§3.4, §11). Better-auth's default rate limiter uses per-isolate memory storage (ineffective on Convex) and only guards its own router — the custom endpoints (`/auth/email/sign-in`, `/auth/email/sign-up`, `/auth/google`, `/auth/refresh`, `/v1/config`, `/v1/live/token`) bypass it entirely. Sign-up currently forwards `USER_ALREADY_EXISTS` verbatim (`packages/backend/convex/authNative/http.ts`) — an email-enumeration vector.
6. **Implement crash reporting** (§3.4). No crash handler or SDK exists anywhere (no `FlutterError.onError` / `runZonedGuarded` / crash SDK); nothing captures stack traces today.
7. **Implement usage analytics as described** (§3.4: screens viewed, features used, device model/OS/language). Today only one `app.started` event plus 4 business counters are collected, and the web app sends no client telemetry at all. Ties into required-item 4 (choose the SDK).
8. ~~**Signup acceptance checkbox + 18+ age gate**~~ — **DONE** (2026-08-23). Both platforms collect the two checks (18+ and accepting the documents) on email sign-up, and an acceptance **gate** covers every other entry point: a brand-new Google account, a local-only account's first run, and any signed-in user whose accepted version is below the floor. Acceptance is recorded append-only — never inferred from having shown the documents — in `legalAcceptances` (Convex, one row per acceptance with document, version, timestamp, 18+ flag, platform) and in the native per-account `legal_acceptances` table (drift v3), which is the whole record for a local-only account and an offline mirror for a remote one. See § Document versions and the acceptance gate below.
9. **`support@walletbot.live` mailbox** — deferred by owner (2026-08-06); required before publishing (required-item 2 above).
10. ~~**Apple Sign-In**~~ — **DONE** (2026-09-06). Shipped on iOS, where App Store Review Guideline 4.8 requires it alongside Google sign-in. Disclosed in §7 as "where available", which stays accurate: the button appears on iOS only. The backend enables the provider whenever `APPLE_BUNDLE_ID` is set (`packages/backend/convex/auth.ts`). No policy change was needed. One operational consequence: users who hide their address arrive as `@privaterelay.appleid.com`, so the sending domain has to be registered with Apple's Private Email Relay or transactional mail to them is dropped.

11. ~~**12-month voice-retention cron**~~ — **DONE** (2026-09-06). Owner decision (PR #193 review, 2026-08-08) was to keep the 12-month promise in the policy and ship the cron; it now runs every six hours over both voice tables. See required-item 3 above.

## Publishing checklist (app stores)

- Both languages are already hosted by the landing (**not** the web app, which is `app.walletbot.live`): `www.walletbot.live/{en,es}/{privacy,terms}`. Google Play and Apple each want a single public, non-PDF privacy-policy URL, so give the stores the unprefixed `https://www.walletbot.live/privacy` (and `/terms`) — a Pages Function negotiates `Accept-Language` and 302s to the reader's language (`apps/landing/functions/privacy.ts`). Add links inside the app (settings/about) and on the login/signup screen next to the acceptance checkbox.
- ~~**Signup must collect affirmative acceptance**~~ — done (see implementation TODO 8). Browse-wrap acceptance is an abusive clause in Argentina (Disp. 377/2026) and unenforceable in the US, so the boxes are never pre-ticked and the submit/accept button stays disabled until both are ticked. Still open: links to both documents from **inside the app** (settings/about) — the sign-up form and the gate link them, nothing else does yet.
- **Google Play Data Safety form** must match the policy: collects Personal info (name, email), Financial info (user-entered transactions), Audio (voice feature; shared with Google/Gemini), App info & performance (crash logs, diagnostics, usage/analytics events), Device IDs — **must be declared**: the app sends a random telemetry installation ID that is stored server-side and exported to Grafana (`telemetryEvents.installationId`); the config/sync `deviceId` is transient and never persisted; also verify what the analytics SDK chosen adds. Declare encryption in transit and the deletion URL `https://app.walletbot.live/delete-account`.
- Apple privacy nutrition labels (when iOS ships): Contact Info, Financial Info, User Content (audio/chat), Identifiers, Diagnostics, Usage Data — mirror the Data Safety form.

## Document versions and the acceptance gate

Each document carries an **ordered version string** — today its "Last updated"
date (`2026-08-23`); a suffix is allowed (`2026-08-23b`). Ordering is a
guarantee of how versions are minted, so they are compared **lexicographically**,
never as semver.

Two constants per document, in `packages/shared/src/legal.ts`:

| Constant | Meaning |
|---|---|
| `current` | What a fresh acceptance records, and what users are prompted for |
| `min` | The floor that still grants access — the grace period |

What the user sees, per document:

| Accepted version | Result |
|---|---|
| `>= current` | Nothing asked |
| `>= min` but `< current` | Prompt, **dismissible** ("Later" — session-scoped) |
| `< min`, or never accepted | **Blocking** gate: accept, switch account, or sign out |

The gate names only the document that actually changed, so nobody is asked to
re-accept a text that did not move.

### Publishing a new version

1. Edit **both languages** of the document under `docs/legal` (rules at the top
   of this file) and bump its "Last updated" date. The landing publishes the
   files verbatim, so this is also what goes live at
   `www.walletbot.live/{en,es}/{terms,privacy}`.
2. Bump that document's `current` in `packages/shared/src/legal.ts`.
3. Mirror the constants in `apps/native/lib/legal/legal_versions.dart` — native
   needs them offline for local-only accounts. `/v1/config` serves the
   authoritative values; the Dart copy is the bundled fallback.
4. Leave `min` alone: that is the grace period. Existing users get the
   dismissible prompt.
5. When the grace period ends, raise `min` to the same value. **Every user
   below it is blocked on their next launch**, so this is a deliberate,
   announced step — not a drive-by edit.

### Where acceptance is recorded

- **Convex `legalAcceptances`** — append-only, one row per acceptance
  (`userId`, document, version, `acceptedAt`, `ageConfirmed`, platform, app
  version, locale). Written by `v1/legal/mutations:accept` for a signed-in user
  and by `/auth/email/sign-up` for a sign-up form (that endpoint issues no
  session, so the acceptance travels with the request). The version written is
  always the server's `current` — a client never names the version it accepts.
  Purged with the account (`userDeletion/internal.ts`), per Privacy §9/§10.
- **Native `legal_acceptances`** (drift v3, per account) — the whole record for
  a local-only account; for a remote account, a mirror of the backend's rows so
  a later offline launch resolves the gate without the network. Not synced: it
  is absent from `SYNCED_TABLES`, so the sync wire format is unchanged.

Every evaluation **fails open**: a config or status fetch that fails never
blocks a user out of their own offline data.

## Scope decisions (agreed 2026-08-06)

- **EU/GDPR intentionally excluded** per owner decision — the documents contain no GDPR sections and no EU-representative appointment, and do not geographically restrict EU users. If EU users are ever targeted (or sign up in relevant numbers), revisit: GDPR applies extraterritorially with no size threshold; an Art. 27 EU representative and Art. 13 disclosures would be needed.
- Minimum age **18+**; single T&C per language with consumer carve-outs (no separate AR/international split); governing law Argentina with consumer-domicile forum; Spanish prevails for AR consumers, English otherwise; formal *usted* register.
- Future-proofing included: paid features require reasonable advance notice + express opt-in (T&C §11); marketing e-mail would be opt-in only (Privacy §6).

## Keep the documents in sync with the code

These documents describe the code as of `c134410`. Any of the following changes requires updating **both languages of both documents** before or at release:

- Integrating the actual analytics / crash-reporting SDK (replace the provider and retention placeholders; re-check device identifiers), or adding push notifications, ads, or any other new third-party processor (new recipient + purposes + Data Safety form).
- Adding payments/subscriptions (fees section, new processor, possibly consumer-billing rules).
- Adding file/receipt uploads, bank connections, or new personal-data fields.
- Changing the sync wire format's device metadata, storing the install `deviceId` or locale server-side (currently disclosed as *not stored*).
- Changing voice-session storage (e.g. uploading audio, storing web sessions) or the 12-month retention.
- ~~Shipping Apple Sign-In client-side~~ — no longer a doc change: Apple Inc. is disclosed in Privacy §7 as of 2026-08-06 ("where available").
