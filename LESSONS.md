# Lessons learned — mistakes Claude made on this project

Read this before working on auth, the native app, or any task that touches
`convex_flutter`. These are concrete failure modes that happened on this
codebase and the rule that comes out of each one. Every "rule" was paid for
with a user-visible bug.

## 1. Read package docs before designing around a package

The single most expensive recurring pattern. `convex_flutter` documents
`setAuthWithRefresh(fetchToken, onAuthChange)` as the supported way to manage
auth — the Rust client calls the fetcher on schedule **and on every WS
reconnect with `force_refresh=true`**. Instead, a custom Dart-side
`Timer` + `_scheduleNextRefresh` + `_doRefresh` pipeline was built on top of
the simpler `setAuth(token)`. Because `setAuth` hard-codes the token, the
Rust client kept re-presenting the same stale JWT on every reconnect, the
server replied `AuthError`, and the WebSocket entered a continuous
`connected → connecting → connected` loop. Hours lost.

Rule: when a package exposes a primitive whose name matches what you need
(`*WithRefresh`, `set*Callback`, `*Observer`), read its docs and source before
writing one. Use Context7 / WebFetch on pub.dev pages or the package's
README — don't guess at the API surface from training data.

Related: do not pick the first package you find. We initially used
`convex_dart` (no `reconnect()`, no state stream, no lifecycle), only to
discover `convex_flutter` already exposed all of it. Survey pub.dev before
designing around limitations.

## 2. Never assume. Distinguish "evidence" from "hypothesis"

Repeated violations:
- "Android killed the socket during background" — never proved; the
  oscillation in the logs was actually our refresh loop.
- "`setAuth` bounces the WebSocket" — wrong; reading
  [convex-0.10.3/src/base_client/mod.rs:238-245](.) showed it just sends an
  `Authenticate` frame.
- "`ConvexClient.reconnect()` re-establishes the socket" — wrong; on native
  it only runs `healthCheckQuery` ([convex_client_native.dart:244-253](.)).
  Three "fix" calls turned into three back-to-back probe timeouts (~21 s
  total) before the user pointed it out.
- "User is on macOS" → recommended `com.apple.security.network.client`
  entitlements. Logs prefix `I/flutter` is **Android** logcat. User was livid.

Rule: when stating *why* something happens, attach evidence — file path,
line number, log line, or doc quote. If you only have a hypothesis, say
"hypothesis" out loud. Per project CLAUDE.md: *NEVER ASSUME*. If you can't
prove it, ask for a log or add diagnostic logging before acting.

## 3. Read past sessions before diagnosing recurring problems

The 60 s access TTL + 60 s leeway scheduler bug had been identified in a
previous session. On a fresh session I re-derived it from scratch instead of
scanning prior transcripts, until the user explicitly said "go and read past
claude sessions". Past sessions live at
`/Users/tomas/.claude/projects/-Users-tomas-projects-wallet-bot/*.jsonl`.

Rule: at the start of any non-trivial task in a recurring problem area
(auth, sync, the banner, refresh, native build), scan past JSONL transcripts
for prior diagnoses before forming your own.

## 4. Apply fixes at the layer where the bug lives

Repeated layer-confusion:
- Added auth-layer pre-flight (`_ensureFreshAuth()`) to "self-heal" a dead
  WebSocket. The token wasn't expired — the transport was broken.
- Added query-layer `TimeoutException` retry + `reconnect()` call to mask a
  WS reconnect cycle caused by server `AuthError` from our refresh loop.
  Reverted in full.
- Recommended bumping access TTL to 15 min when the root cause was the
  `setAuth` → stale-token-on-reconnect loop, not refresh frequency. User
  called it: *"If it fails with 1 min will fail with 15, with 99…"*

Rule: classify the failure first — *transport, auth, protocol, app logic*.
A retry wrapper in the auth layer won't fix a dead socket. A timeout
shortening won't fix a reauth loop. A TTL bump won't fix a stale-token bug.

## 5. Don't suppress diagnostic evidence

The 401 response body from `/auth/refresh` was silently dropped at
`auth_controller.dart:374` (only non-401 errors got `debugPrint`). That is
why the rotation-race 401 bug had no log evidence and took multiple sessions
to diagnose. Same pattern in `setAuth` failures (try/catch → debugPrint a
short message, drop the rest).

Rule: at error sites that flip user-visible state (`requiresReauth`, "Sync
paused"), log the full response — status code, headers worth knowing, full
body. Don't strip the only forensic trail to keep logs tidy.

## 6. Don't add band-aids on top of broken primitives

- Wired `ConvexClient.instance.reconnect()` into `didChangeAppLifecycleState`
  and into `runConvexAuthenticated` / `subscribeConvex` retry paths — without
  ever verifying that `reconnect()` actually reconnects on native. It does
  not.
- Created `convex/health.ts` to back this broken `reconnect()`. The query was
  fine; the consumer was wrong. Deleted.
- Lowered `operationTimeout` to 7 s to "fail fast" without proving the WS
  hang was a transport issue (it wasn't — it was our reauth loop).

Rule: before wrapping or configuring an API, prove the API does what its
name suggests. Read the implementation if necessary. Otherwise you're
stacking complexity on a no-op.

## 7. For native/mobile, prefer long-lived revocable tokens over rotation

The initial design rotated the refresh token on every use. The
`_refreshInFlight` future coalesced *concurrent* refreshes but not
*queued sequential* ones, so a timer + resume + retry path firing close
together would capture the same stale token from `activeAccount`, race
through `/auth/refresh`, and the second arrival would 401. That flipped
`requiresReauth` → "Sync paused" banner. Rotation gives marginal theft
detection at the cost of real concurrency bugs.

Switched to a non-rotating long-lived session token; class of bug
disappeared. See `packages/backend/convex/authNative/{http,mutations}.ts`.

Rule: rotation is a browser-tab pattern. On native, where the device has
encrypted storage (`flutter_secure_storage` → Keystore/Keychain) and there's
a single client per session, prefer a long-lived opaque revocable session
token. Add rotation only if you can detect compromise some other way.

## 8. Check for `well-known` and `applicationID` collisions before adding an issuer

Initial `auth.config.ts` used `applicationID: 'convex'` — already owned by
better-auth's component. JWKS was originally at `/.well-known/jwks.json` —
also owned by better-auth. Both caught by typecheck/manual test but should
have been on the design checklist.

Rule: when adding a new auth issuer or http route alongside an existing
provider, list the routes/IDs the existing provider claims first, then
namespace under a prefix you own (`/native-auth/...`).

## 9. Don't declare success before user verification

Multiple times: long "Summary of what's live" reports posted immediately
after edits, followed by *"It doesn't work… at all"* from the user. Especially
common after non-trivial native-app changes where the user has to rebuild
and re-run.

Rule: after a multi-file change that affects runtime behavior, end with
"want to test before I summarize?" — not with a victory lap. Or at minimum,
caveat that the change is unverified.

## 10. Verify deploys / env-var changes you make

`convex env set JWT_PRIVATE_KEY` once mangled the multi-line PEM in shell;
`requireEnv` then threw at runtime. The deploy was treated as done.

Rule: after `convex env set` of any non-trivial value (multi-line, base64),
follow with `convex env get` or curl the dependent endpoint (JWKS, OIDC
discovery) to confirm it actually applied.

## 11. Don't recommend platform-specific config without knowing the platform

`I/flutter (pid)` is Android logcat. Don't recommend macOS entitlements or
iOS Info.plist edits when the only logs you've seen are Android.

Rule: read the log prefix. If still unclear, ask one-line: *"which platform
are you running on?"* before recommending platform-specific files.

## 12. Build the diagnostic before the fix when timing is involved

When the user reported continuous `connected → connecting` oscillation we
went through three wrong root-cause hypotheses (OS suspend, setAuth bounce,
TTL frequency) before reading the convex Rust SDK source and finding that
`ServerMessage::AuthError` triggers a reconnect
([base_client/mod.rs:688](.)) and a stale-token fetcher creates a loop.

Rule: for any "this happens repeatedly / at unknown cadence" symptom, the
first response should be adding timestamped logs at the suspected trigger
points, not proposing a fix. *No timestamp → no diagnosis.*

---

## Quick checklist before sending an auth/sync diagnosis to the user

- [ ] Have you read the relevant package docs (Context7 + pub.dev) in this
      session?
- [ ] Have you grep'd past JSONL sessions for the same symptom?
- [ ] Is each causal claim backed by a file:line reference or a log line you
      can point to?
- [ ] Are you fixing at the same layer as the bug (transport vs. auth vs.
      protocol vs. app logic)?
- [ ] Are 401 / TimeoutException / WS-close paths logging *enough* to
      diagnose if it happens again?
- [ ] Have you asked the user to verify before declaring done?
