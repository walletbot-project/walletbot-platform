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

1. **Replace the placeholders** in all four files — **done (2026-08-21, owner-provided values):**
   - Controller legal name: Tomás Cichero.
   - Controller domicile: Estanislao del Campo 1260, B1604ADH Florida Oeste, Provincia de Buenos Aires, Argentina.
   - Analytics / crash-reporting provider (Privacy §7) and its retention row (§9): Google LLC — Firebase (Firebase Analytics, Crashlytics), with Firebase's documented retention (up to 14 months for user-level analytics, 90 days for crash reports). Named ahead of integration by owner decision — see item 4 for what remains when the SDK actually ships.
2. **Create the `support@walletbot.live` mailbox** (or alias). It is the contact named in every document; today only `no-reply@walletbot.live` exists and it cannot receive mail.
3. **Implement the 12-month voice-data retention cron.** The Privacy Policy (§5, §9) commits to auto-deleting `voiceSessions` / `voiceSessionEvents` older than 12 months. No such cleanup exists today (`docs/voice-session-lifecycle.md` explicitly notes there is no retention policy). **The policy must not go live before the cron ships.**
4. **Name the analytics / crash-reporting provider and set its retention period.** By owner decision (2026-08-06) the policy discloses usage analytics and crash reporting, but no SDK is integrated in the codebase yet. When integrating one (e.g. PostHog, Sentry): replace the provider placeholder in Privacy §7, set the retention period in Privacy §9, sign the provider's DPA, and verify what device identifiers it collects (this may change the "What we do NOT collect" list and the Data Safety form). Note: **Grafana Labs (Grafana Cloud)** is already disclosed separately in Privacy §7 — the backend exports first-party telemetry (installation/session/user identifiers, app version, platform) to it via OTLP every 5 minutes (`packages/backend/convex/telemetry/actions.ts`, `docs/observability-grafana.md`).
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
8. **Signup acceptance checkbox + 18+ age gate** (§2, §8, §14 and T&C), **plus a first-run acceptance step for local-only mode** — T&C §1 promises affirmative acceptance also "when first using the app" without an account, which is a separate piece of UI from the signup checkbox. Deferred by owner (2026-08-06); required before publishing, see the publishing checklist below. **Persist acceptance state** (accepted document version, user/device, timestamp) server-side (or device-side for local-only mode) and re-prompt when the documents were shown but not accepted — merely displaying them must never be recorded as acceptance (PR #193 review feedback, 2026-08-08). **Shipped (2026-08-21, WAL-172):** one combined 18+/acceptance checkbox with document links on the web and native sign-up forms and on the native local-account panel; acceptance persisted server-side in the `termsAcceptances` table (`documentVersion` = the documents' "Última actualización" date, currently `2026-08-06`; userId; timestamp; source) via the sign-up body plus `v1/legal` RPCs, and device-side in secure storage for local accounts; post-auth blocking gates on both platforms re-prompt any account without a record for the current version (first Google sign-ins, pre-existing accounts) — display alone is never recorded. Native gate fails open while offline; local-mode acceptance works fully offline. Document updates re-prompt via the min/current/grace policy — see § Versioning & re-acceptance below.
9. **`support@walletbot.live` mailbox** — deferred by owner (2026-08-06); required before publishing (required-item 2 above).
10. **Apple Sign-In** — now disclosed in §7 as "where available". The backend already enables it whenever `APPLE_CLIENT_ID` is set (`packages/backend/convex/auth.ts`); client-side support will ship eventually — no further policy change needed then.

11. **12-month voice-retention cron** (required-item 3 above). Privacy §5/§9 promise automatic deletion of `voiceSessions` / `voiceSessionEvents` older than 12 months; no such cleanup exists on `main` or the PR #192 branch. Owner decision (PR #193 review, 2026-08-08): the policy keeps the 12-month promise — the cron must ship before the policy goes live.

## Versioning & re-acceptance — how to publish updated documents

A document version is its "Última actualización" date (`YYYY-MM-DD`), compared
as a plain string. The policy lives in `packages/shared/src/legal.ts` and is
what installed clients obey — remote accounts receive a per-user verdict from
`v1/legal/queries:getMyAcceptance`, native local accounts receive the policy
inside the `/v1/config` payload (cached, fail-open) and evaluate it on-device
(`apps/native/lib/legal/terms_acceptance.dart` mirrors the verdict function —
keep both in sync). Publishing an update is a backend deploy; no app release:

1. Edit the four documents (ES and EN together, as always) and set the new
   "Última actualización" date.
2. In `packages/shared/src/legal.ts`: set `CURRENT_LEGAL_VERSION` to that date
   and `LEGAL_GRACE_ENDS_AT` to the notice deadline (ms epoch, e.g. +30 days).
   Leave `MIN_ACCEPTED_LEGAL_VERSION` alone for routine updates.
3. Deploy the backend. Users on the previous version get a **dismissible**
   prompt ("Not now") until the deadline; after it, the gate blocks. New
   sign-ups accept the new version directly.

Semantics: acceptance ≥ current → nothing; acceptance below
`MIN_ACCEPTED_LEGAL_VERSION` (or none) → blocking gate, no grace; anything in
between → dismissible prompt while the grace runs, blocking after. Fail-safe
defaults: a `null` grace deadline means the prompt stays dismissible forever
(forgetting it can never lock users out), a client that receives a status it
does not recognize renders the dismissible prompt (a future policy state can
never hard-block an old build), and a native remote account never hard-blocks
from cached data alone — only a live server verdict can (accepting needs the
network). Raising `MIN_ACCEPTED_LEGAL_VERSION` is the only immediate-lockout
lever; reserve it for "the old terms are legally void".

## Publishing checklist (app stores)

- Host both languages at public URLs (e.g. `app.walletbot.live/privacy` and `/terms`) — Google Play and Apple both require a public, non-PDF privacy-policy URL. Add links inside the app (settings/about) and on the login/signup screen next to the acceptance checkbox. *(Login/signup links shipped with the acceptance checkbox, 2026-08-21 — they open `www.walletbot.live/{es,en}/{terms,privacy}`; settings/about links still pending.)*
- **Signup must collect affirmative acceptance** (checkbox / explicit button referencing both documents). Browse-wrap acceptance is an abusive clause in Argentina (Disp. 377/2026) and unenforceable in the US.
- **Google Play Data Safety form** must match the policy: collects Personal info (name, email), Financial info (user-entered transactions), Audio (voice feature; shared with Google/Gemini), App info & performance (crash logs, diagnostics, usage/analytics events), Device IDs — **must be declared**: the app sends a random telemetry installation ID that is stored server-side and exported to Grafana (`telemetryEvents.installationId`); the config/sync `deviceId` is transient and never persisted; also verify what the analytics SDK chosen adds. Declare encryption in transit and the deletion URL `https://app.walletbot.live/delete-account`.
- Apple privacy nutrition labels (when iOS ships): Contact Info, Financial Info, User Content (audio/chat), Identifiers, Diagnostics, Usage Data — mirror the Data Safety form.

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
