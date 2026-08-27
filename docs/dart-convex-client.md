# Dart-only Convex client — design

A pure-Dart replacement for `convex_flutter` (Rust core over FFI) for
`apps/native`. The design goal is a client that treats mobile network
weirdness — dead sockets, airplane mode, backgrounding, captive portals,
stale tokens — as the normal case, recovers proactively, and makes every
waiting/retry behavior configurable.

Status: **design doc, nothing implemented.** Written from three sources:
(1) a full inventory of how `apps/native` uses `convex_flutter` today,
(2) the Convex sync protocol as implemented by `convex-js` 1.44.0
(`src/browser/sync/*`), `convex-rs`, and the open-source backend
(`crates/sync/src/worker.rs`), and (3) LESSONS.md + the GitHub issue history
of the Rust client family.

---

## 1. Why replace the current client

The problems are structural, not bugs we can patch around:

| # | Problem | Evidence |
|---|---|---|
| 1 | **No recovery escape hatch.** `ConvexClient.initialize()` throws on a second call and `dispose()` is never callable in practice — when the socket wedges, the app cannot rebuild the client. | `convex_flutter-3.0.1/lib/src/convex_client.dart:108-110`; no `dispose()` call in `apps/native` |
| 2 | **`reconnect()` does not reconnect.** On native it only runs a `healthCheckQuery` (which we don't configure, so it throws). | LESSONS.md #2/#6; `convex_client_native.dart:244-253` |
| 3 | **Zero transport observability.** The app never consumes `connectionState`/`isConnected` — and building on them was never viable because recovery primitives (2) don't work. UI cannot distinguish "offline" from "sync error". | grep of `apps/native/lib` — no usages |
| 4 | **Operations hang or block for the fixed 30 s timeout** when the socket is down, forcing per-call hacks: the voice token action is bounded to 6 s with an HTTP bypass, and voice flush is fire-and-forget specifically to dodge the 30 s stall. | `gemini_voice_expense_command.dart:20-27,734-737`; convex-rs issue #9 ("Operations Hang on a Bad Connection", reported from Dart FFI) |
| 5 | **Reconnect/re-auth is where the Rust family breaks.** Reconnect version-mismatch loop (convex-rs #14 / convex_flutter #17), permanent "connecting" from silent TLS failure (convex_flutter #14/#18), auth errors never surfaced (convex-rs #11), iOS use-after-free during reauth churn (convex-mobile #21), stale-token → `AuthError` → reconnect loop (LESSONS.md #1/#12). | issue links in §Appendix C |
| 6 | **The FFI boundary costs us correctness and testability.** Args are per-key `jsonEncode` strings (forcing the `lib/sync/wire.dart` int64 shim), results are raw JSON strings, `ConvexClient` cannot initialize under `flutter test` (three test files carry workarounds), and release builds have an Android ABI risk (`libconvex_flutter.so` arm64-only in release jniLibs). | `wire.dart:1-10`; `test/widget_test.dart:25-29`; `docs/playstore-readiness.md:71-84` |
| 7 | **Refresh scheduling lives in Rust and is opaque.** The one auth loop we can't instrument is the one that has burned us the most (LESSONS.md #1, #12). | LESSONS.md |

A Dart-only client deletes the Rust toolchain, `flutter_rust_bridge`, the
per-platform pods/cmake plumbing, and the ABI risk — and puts every retry,
timeout, and auth decision in code we can read, log, and unit-test.

## 2. Goals and non-goals

**Goals**

- Speak the Convex sync protocol over a single WebSocket, wire-compatible
  with the current backend (`v1/*` functions unchanged — no backend work).
- **Recover from anything short of a `FatalError`**: transport drops, radio
  loss, backgrounding, server restarts, stale auth. Recovery is proactive
  (connectivity + lifecycle signals trigger immediate reconnects) and
  otherwise timer-driven (backoff), never dependent on a user action.
- Every wait is **configurable**: per-call timeouts (including "wait
  forever"), backoff floor/ceiling, inactivity threshold, reconnect attempt
  cap (default: endless).
- First-class observability: connection-state stream, auth-state stream,
  structured event log hook for telemetry.
- Typed Dart values end-to-end (BigInt/Uint8List/special doubles), deleting
  `lib/sync/wire.dart`.
- Constructible and disposable like a normal Dart object; trivially fakeable
  in `flutter test`.

**Non-goals**

- Optimistic updates and a query result cache for UI. The app is
  offline-first: Drift is the cache and the sync engine owns merge semantics
  (`docs/native-data-layer.md`). The client stays a transport.
- Web/JS support. The web app uses official `convex-js`. All native targets
  run `dart:io`.
- Replacing the app's HTTP surfaces (`/auth/*`, `/v1/config`, telemetry) —
  those already bypass the client on purpose and keep doing so.
- Publishing as a pub.dev package (can be extracted later; see §11).

## 3. Reference implementation: port convex-js, not convex-rs

`convex-js` is the implementation Convex maintains first, and it differs from
the Rust core in exactly the places that have hurt us:

| Behavior | convex-js (adopt) | convex-rs / convex_flutter (reject) |
|---|---|---|
| Session identity | **One `sessionId` (UUID v4) for the client's lifetime**, reused across reconnects → server dedupes mutations per `(sessionId, requestId)`, so resending in-flight mutations on reconnect is exactly-once | New UUID per connection attempt → dedup never applies across reconnects |
| Backoff reset | Only after the client has **fully resynced** past the reconnect (all re-added queries answered, auth confirmed, pre-restart requests done) | On any received message (their own TODO flags this as wrong) |
| Network signal | `online` event → reconnect immediately | None |
| Outgoing queue on reconnect | Rebuilt from scratch | Historically flushed stale pre-reconnect messages (the #14 version-mismatch loop) |
| Auth error handling | Explicit `AuthError` state machine with stale-message filtering and a 2-strike fresh-token rule | `AuthError` → blind reconnect (the loop amplifier in LESSONS.md #12) |

We port convex-js's four sync components ~1:1 (see §5) and add a mobile
layer it deliberately lacks (it has **no** visibility/lifecycle handling —
browsers don't kill sockets the way mobile OSes do).

## 4. Protocol summary

Full field-level reference in **Appendix A**; this is the shape:

- **Transport**: one WebSocket to `wss://{deployment}/api/sync`
  (JSON text frames), `Convex-Client: {id}` header on the upgrade request.
  Open item on the identifier value: §13.
- **Client→server**: `Connect` (sessionId, connectionCount, lastCloseReason,
  maxObservedTimestamp), `Authenticate` (tokenType/value/baseVersion),
  `ModifyQuerySet` (baseVersion→newVersion, Add/Remove entries),
  `Mutation` / `Action` (requestId, udfPath, args).
- **Server→client**: `Transition` (startVersion→endVersion + per-query
  QueryUpdated/QueryFailed/QueryRemoved), `TransitionChunk` (reassembly of
  large transitions — mandatory to implement), `MutationResponse` /
  `ActionResponse`, `AuthError`, `FatalError`, `Ping`.
- **Versioning model**: the client mirrors a `{querySet, ts, identity}`
  triple that resets to zeros on every fresh socket. Every `ModifyQuerySet`
  and `Authenticate` carries a `baseVersion`; every `Transition` must start
  exactly at the client's current triple. All subscribed queries are always
  consistent at one `ts`.
- **Mutation guarantee**: a successful `MutationResponse` carries commit
  `ts`; the caller's Future resolves only when a `Transition` reaches
  `endVersion.ts >= ts` (read-your-own-writes). Failures resolve
  immediately. Actions resolve on `ActionResponse` (not idempotent — never
  resent).
- **Values**: Convex JSON encoding — `{"$integer": base64(8-byte LE)}` for
  int64, `{"$bytes": base64}` for byte arrays, `{"$float": ...}` only for
  NaN/±Inf/-0; object keys sorted, `$`-prefixed keys rejected; args always
  wrapped in a one-element array.

## 5. Architecture

```
apps/native/lib/convex/
  convex_client.dart        # public API facade (construct/dispose, query/subscribe/mutation/action, streams)
  socket_manager.dart       # WebSocket lifecycle, state machine, backoff, inactivity watchdog
  local_query_set.dart      # subscription registry + querySet versioning     (≈ convex-js local_state.ts)
  request_manager.dart      # mutations/actions in flight, resend-on-restart  (≈ request_manager.ts)
  auth_manager.dart         # token fetch/refresh scheduler + AuthError FSM   (≈ authentication_manager.ts)
  server_state.dart         # Transition application, chunk reassembly        (≈ remote_query_set.ts)
  protocol.dart             # message types, encode/decode
  values.dart               # convexToJson / jsonToConvex (replaces lib/sync/wire.dart)
  connectivity_hooks.dart   # connectivity_plus + AppLifecycleListener adapters (only Flutter-dependent file)
```

Everything except `connectivity_hooks.dart` is pure Dart
(`web_socket_channel` + `dart:io`) so the whole protocol stack runs under
plain `flutter test` with a fake socket — the thing FFI made impossible.

### 5.1 Socket state machine

```
disconnected ──connect()──▶ connecting ──open+Connect sent──▶ ready
     ▲                          │  │                            │
     │        handshake timeout │  │ socket error/close         │ close / inactivity /
     └──────── backoff ─────────┘  ◀────────────────────────────┘ AuthError restart
                                              (terminal only via dispose() or FatalError)
```

- `connecting` has its own **handshake timeout** (default 10 s): covers DNS,
  TLS, and the WS upgrade. This is the direct fix for the "stuck in
  connecting forever" class (convex_flutter #14/#18 was a *silent TLS
  failure with no error and no timeout*).
- `ready` is guarded by an **inactivity watchdog**: the server pings every
  ~15 s; any received frame resets the timer; no frame for
  `serverInactivityThreshold` (default 45 s) → close with reason
  `InactiveServer` and reconnect. The watchdog is armed from socket
  construction (catches stuck handshakes too, as convex-js does).
- Reconnect delay = `min(initialBackoff · 2^retries, maxBackoff)` ± 50%
  jitter. Defaults: initial 250 ms, max 16 s, attempts **unbounded**.
  `retries` resets only on full resync (§3 table).
- **Proactive triggers that skip the backoff wait entirely**
  (each cancels a pending backoff timer and reconnects now):
  1. `connectivity_plus` reports a usable network after none;
  2. `AppLifecycleListener.onResume` (mobile OSes kill sockets in
     background; on resume we also fast-check the inactivity watchdog);
  3. explicit `client.reconnectNow()` — which really closes and reopens the
     socket, unlike the Rust `reconnect()`;
  4. a queued call arrives (mutation/query) while `disconnected` with a
     pending long backoff → cap the remaining wait at `initialBackoff`.
- Connectivity/lifecycle signals are **hints, never gates**: we reconnect on
  them but never refuse to try because connectivity_plus claims offline
  (captive portals and VPNs lie in both directions).

### 5.2 Restart sequence (on every socket open)

Port of convex-js `onOpen` + `RequestManager.restart()`, in this order:

1. `Connect` — same `sessionId` as the client instance, incremented
   `connectionCount`, previous close reason, `maxObservedTimestamp` (max of
   all seen mutation/transition timestamps, so the server never shows us
   older state than we've already observed).
2. `Authenticate` with `baseVersion: 0` — using a **fresh token** (§6).
3. One `ModifyQuerySet` `0→1` re-adding **every** live subscription with its
   last known journal.
4. Resend all in-flight **mutations** (idempotent via session dedup),
   including completed-but-not-yet-transitioned ones; flip queued `NotSent`
   requests to sent. **Fail all in-flight actions** with a typed
   `ConnectionLostError` (actions are not idempotent; callers like the voice
   token fetch already treat them as at-most-once).
5. Discard the previous socket's server state (version triple → zeros,
   chunk buffer cleared). The outgoing queue is rebuilt from current state,
   never replayed — this is the convex-rs #14 lesson baked into the design:
   *no message composed before a reconnect may survive it*.

### 5.3 Public API sketch

```dart
final client = ConvexClient(
  ConvexClientConfig(
    deploymentUrl: AppConfig.convexUrl,
    clientId: 'wallet-bot-flutter/<appVersion>',
    // every knob below has these defaults; all overridable
    handshakeTimeout: Duration(seconds: 10),
    serverInactivityThreshold: Duration(seconds: 45),
    initialBackoff: Duration(milliseconds: 250),
    maxBackoff: Duration(seconds: 16),
    maxReconnectAttempts: null,            // null = endless (the default)
    defaultOperationTimeout: Duration(seconds: 30),
    defaultConnectTimeout: null,           // null = queue while offline (see §7)
  ),
);

// Observability — the gap the app has today
Stream<ConnectionState> get connectionState; // disconnected|connecting|ready (+ retry count, last close reason)
Stream<AuthState> get authState;             // unauthenticated|authenticating|authenticated|refreshFailed
void onEvent(void Function(ConvexClientEvent) listener); // structured log/telemetry hook

// Operations — typed values in and out (no JSON strings, no wire.dart)
Future<T> query<T>(String name, Map<String, Object?> args, {CallOptions? options});
Future<T> mutation<T>(String name, Map<String, Object?> args, {CallOptions? options});
Future<T> action<T>(String name, Map<String, Object?> args, {CallOptions? options});
SubscriptionHandle subscribe(String name, Map<String, Object?> args,
    {required void Function(Object? value) onUpdate,
     required void Function(ConvexError error) onError});

// Auth — the setAuthWithRefresh shape, owned in Dart (LESSONS.md #1)
void setAuth({required Future<String> Function({required bool forceRefresh}) fetchToken});
void clearAuth();

// Lifecycle
Future<void> reconnectNow();  // real close+reopen
Future<void> dispose();       // idempotent; a new client can be constructed after
```

Errors are typed, not strings: `ConvexFunctionError` (server threw — carries
`errorMessage` + decoded `errorData`), `ConnectionLostError` (action lost to
a reconnect), `OperationTimeoutError` (carries which timeout fired and the
connection state at the time — so logs distinguish "server slow" from
"socket down", the forensic gap of LESSONS.md #5), `AuthRequiredError`.

## 6. Auth design

The stale-token reconnect loop (LESSONS.md #1/#12) is the single worst
failure we've had, so this is specified tightly. Port of convex-js
`AuthenticationManager`:

1. `setAuth(fetchToken)` → pause outgoing traffic, `fetchToken(forceRefresh:
   false)` (may be cached), send `Authenticate`, resume.
2. On server confirmation (a `Transition` advancing `identity`), immediately
   `fetchToken(forceRefresh: true)` and re-`Authenticate`, then schedule the
   next refresh at `exp − refreshLeeway` (default 60 s; our JWTs live 24 h —
   `authNative/utils.ts:3`).
3. **Every reconnect re-runs step 1 with `forceRefresh: true`.** A
   reconnect must never re-present a token the server already rejected.
4. `AuthError` handling — the three-way filter convex-js uses, which the
   Rust client lacks:
   - `authUpdateAttempted == false` while a newer token is already awaiting
     confirmation → ignore (a query ran with the dying token; not our
     problem).
   - `baseVersion` older than our current identity version → stale, ignore.
   - Otherwise: **stop the socket** (so queued mutations can't fire with bad
     auth), fetch fresh, re-authenticate, restart. After **2 consecutive**
     fresh-token failures: give up, send `tokenType: "None"`, emit
     `AuthState.refreshFailed`, and keep the socket **connected
     unauthenticated** — public functions keep working and the app decides
     what to show (`requiresReauth` banner stays app-owned in
     `auth_controller.dart`).
5. The token fetcher is the app's existing `_fetchFreshAccessToken`
   (POST `/auth/refresh`); its 401 → `requiresReauth` path is unchanged.
   The fetcher result is cached in the client with its `exp`, and exposed as
   `Future<String> validToken()` — `TelemetryClient` can stop re-minting a
   JWT per batch (`auth_controller.dart:295`, `main.dart:73-75`).

Every transition of this state machine emits a structured event with
timestamps — the diagnostic LESSONS.md #12 says to build *before* the fix.

## 7. Timeouts and waiting — the configuration story

The user-facing requirement: proactively resolve connection issues, and make
retrying / endless waiting / timeouts configurable. Two orthogonal timeouts
per call, plus queueing semantics:

```dart
class CallOptions {
  final Duration? connectTimeout;   // max wait for a `ready` socket. null = wait forever (queue)
  final Duration? operationTimeout; // max wait for the result once sent. null = wait forever
  final HttpFallback httpFallback;  // none | whenNotReady (queries/actions only)
}
```

- **`connectTimeout`** bounds "the socket isn't ready". While waiting, the
  call sits in the `NotSent` queue (convex-js semantics) and goes out in
  send-order on `ready`. Firing → `OperationTimeoutError(phase: connect)`.
- **`operationTimeout`** bounds "sent but no response". A reconnect
  mid-flight does not restart it for mutations (they resend); it fails
  actions immediately (§5.2).
- Defaults live in `ConvexClientConfig` and are chosen per call site:

| Call site | connectTimeout | operationTimeout | Rationale |
|---|---|---|---|
| `v1/sync/*` pull/push/getCounter | 15 s | 30 s | sync engine has its own outer retry (§9) — fail fast, retry with backoff |
| voice `appendEvents` outbox | 10 s | 20 s | durable outbox retries anyway; today's hardcoded 30 s stall goes away |
| `requestLiveToken` action | ~0 (`whenNotReady` → HTTP) | 6 s | replaces the hand-rolled 6 s + HTTP bypass in `gemini_voice_expense_command.dart:20-72` with client policy |
| user settings query/mutation | null (queue) | 30 s | fire-and-forget UX with rollback already in the controller |

- **HTTP fallback** (`POST /api/query`, `/api/action` with
  `format: "convex_encoded_json"`, `Authorization: Bearer` from the auth
  manager's cached token): only for **queries and actions**, only when the
  socket isn't `ready`. **Mutations never silently fall back** — the
  `(sessionId, requestId)` dedup that makes WS mutations exactly-once does
  not exist over HTTP, and a lost HTTP response would mean a possible
  double-apply. (`v1/sync/mutations:push` would survive it thanks to
  `expectedServerSeq` OCC, but the client must not encode per-callsite
  knowledge; if we ever want it, it's an explicit per-call opt-in.)

## 8. Weirdness → mitigation matrix

Every failure mode we have evidence for, and where the design answers it:

| Weirdness (evidence) | Design answer |
|---|---|
| Socket wedges, nothing recovers it (LESSONS #2/#6, gap #1-3 in §1) | Real `reconnectNow()`; disposable client; watchdog closes zombie sockets (§5.1) |
| Stuck in `connecting` forever — silent TLS failure (convex_flutter #14/#18) | Handshake timeout; watchdog armed from construction (§5.1) |
| Airplane mode → operations hang 30 s or forever (convex-rs #9; voice hacks) | Per-call `connectTimeout`/`operationTimeout`, `null` = intentional endless queue (§7) |
| Backgrounded app: OS kills socket, timers suspended (voice screen comment `screens/voice.dart:112-120`) | `onResume` → immediate reconnect + watchdog fast-check (§5.1); close code 1001 treated as benign (convex-js does the same — "commonly fired on mobile when backgrounded") |
| Radio regained but backoff timer still counting | connectivity_plus signal cancels backoff, reconnects now (§5.1) |
| Stale JWT re-presented on reconnect → `AuthError` → reconnect loop (LESSONS #1/#12) | Force-fresh token on every reconnect; AuthError three-way filter; 2-strike downgrade to unauthenticated instead of looping (§6) |
| Reconnect version-mismatch loop from stale queued messages (convex-rs #14, convex_flutter #17) | Outgoing queue is rebuilt, never replayed, on every restart (§5.2 rule 5) |
| Mutations lost or double-applied across reconnects (convex-rs per-connection session UUID) | Stable per-instance `sessionId` + resend-in-flight → server-side exactly-once (§3, §5.2) |
| Server restarts / `Transition` from a version we never had | Treated as protocol failure → clean reconnect (fresh socket resets versions to zero by design) |
| Huge transitions | `TransitionChunk` reassembly with out-of-order/interleave rejection (App. A) |
| Server overload close reasons (`TooManyConcurrentRequests`, …) | Per-reason initial backoff table from convex-js (App. A.8) |
| Int64s mangled at the FFI JSON boundary (`wire.dart`) | Typed `values.dart` codec; `wire.dart` deleted; sync `v.int64()` args round-trip as `BigInt` |
| Nothing can run under `flutter test` (§1.6) | Pure-Dart core + injected socket factory; `FakeConvexServer` test double (§10) |

## 9. App integration (follow-up work, separate PRs)

The client swap alone doesn't fix the app-level gaps the inventory found;
these become small, now-possible fixes:

1. **`_SyncStarter` gate** (`main.dart:389-399`): today sync never starts if
   the Rust client never fires `onAuthChange(true)`. Replace with watching
   `client.authState` + `connectionState` streams; start sync when
   authenticated, and *retry* starting after failures.
2. **Sync engine** (`sync_engine.dart`):
   - failed `subscribe` at cold start currently leaves the engine
     trigger-starved forever (`:116`) — with the new client, `subscribe` is
     queue-and-deliver-when-ready, so this class disappears; the `onError`
     path resubscribes with backoff instead of only logging (`:112`);
   - `_runOnce` failure gets a retry timer with backoff instead of parking
     in `SyncStatus.error` until the next external trigger (`:215-218`);
   - `SyncStatusPill` can finally show offline vs error vs syncing from
     `connectionState`.
3. **Auth controller**: `setAuthWithRefresh` → `client.setAuth(fetchToken:
   ...)`; `_detachAuth` → `clearAuth()`; delete the
   AuthHandleWrapper dance. `requiresReauth` logic unchanged.
4. **Voice**: replace the hand-rolled 6 s action bound + HTTP bypass with
   `CallOptions(connectTimeout: ~0, httpFallback: whenNotReady,
   operationTimeout: 6s)`; keep the `/v1/live/token` endpoint as the
   fallback target. Outbox keeps its own retry ladder (it's durable-state
   logic, not transport logic — right layer per LESSONS #4).
5. **Delete** `lib/sync/wire.dart` (typed codec), the dead
   `packages/backend/convex/health.ts`, and the three test-file
   "can't initialize under flutter test" workarounds.
6. **Bootstrap**: `resolveBackendConfig`'s "URL can only change on cold
   start" constraint can be relaxed later (dispose + recreate on URL
   change), but that's not in scope for the swap.

## 10. Testing strategy

The reconnect/re-auth path is where every client in this family has broken —
it gets the test budget:

- **Protocol conformance** (pure Dart, fake socket): golden encode/decode
  for every message type; value codec round-trips (int64 boundary values,
  -0.0, NaN, key sorting, `$`-key rejection); chunk reassembly incl.
  interleave/ordering violations.
- **`FakeConvexServer`**: an in-memory server speaking the protocol over a
  `StreamChannel`, scriptable per test: drop the socket at any point, delay
  the handshake, send `AuthError` variants, send stale/duplicate
  `MutationResponse`s, split transitions into chunks, refuse N connects.
- **Scripted weirdness suites** (one test per §8 row): e.g. *mutation sent →
  socket drops before response → reconnect → duplicate MutationResponse →
  exactly one resolution*; *token expires mid-session → AuthError → single
  fresh fetch → no reconnect storm* (assert connect count); *backoff resets
  only after full resync*.
- **Fake time throughout** (`package:clock` / `fake_async`) so backoff and
  watchdog tests run in milliseconds and timings are exact.
- **Device passes** (manual, per LESSONS #9 — user verifies before we call
  it done): airplane-mode toggles mid-mutation, background 10+ min →
  resume, network switch wifi↔cell, against both dev and prod deployments.
- Existing test doubles get simpler: `_StubConvexClient` in
  `voice_session_remote_sync_test.dart` becomes a plain interface fake.

## 11. Rollout

> **Resolved (2026-08-27):** the team chose a direct swap over the gate —
> `convex_flutter` was removed in the same change that wired the new client
> in, with no dual-implementation period. The gate design below is kept for
> the record.

- Land the client behind a **local compile-time/config gate**: keep
  `convex_flutter` in the tree, select the implementation behind the
  existing client interface at startup. The server-side feature-flag system
  can't gate this (the flag rides the transport being replaced); a
  device-local toggle in the debug settings + a default flip per release
  channel does. **Open question for the team: gate default-on for
  dev/internal first, or flip everyone at once?** (CLAUDE.md asks this to be
  an explicit decision, not an assumption.)
- Sequence: client package + conformance tests → swap behind gate → app
  integration fixes (§9) → device passes → default-on → remove
  `convex_flutter` + Rust plumbing (+ update `docs/playstore-readiness.md`:
  the ABI item becomes moot).
- No wire/contract change: `minSupportedVersion` / drift `schemaVersion` are
  untouched (per the coordinated-bump rule in CLAUDE.md — nothing here
  changes the sync wire format).
- `docs/riesgos.md` review happens at implementation time: this removes the
  "client doesn't recover" risk class and the release ABI risk, and adds a
  transitional "two client implementations" risk while the gate exists.

## 12. Dependencies

`web_socket_channel` (already in the tree for Gemini Live), `uuid` (session
id), `connectivity_plus` (**new** — reconnect hints only, never a gate),
`clock` (dev/test). Removed at cleanup: `convex_flutter`,
`flutter_rust_bridge`.

## 13. Open questions

1. **`Convex-Client` identifier**: convex-rs sends `rust-{version}` as an
   upgrade header on `/api/sync`; convex-js embeds `npm-{version}` in the
   path. Whether the managed backend accepts an unknown client name
   (`dart-…`) must be **verified against our deployment before building**
   (spike: open a socket with each candidate, observe accept/deprecation
   headers/`FatalError`). No assumption — if unknown names are rejected,
   mimic a wire-compatible known version and document it.
2. **Rollout default** (§11) — team decision.
3. **`getCounter` subscription vs. journal**: our only subscription has no
   pagination journal; confirm journal handling with a paginated query
   before anyone adds one (conformance test exists either way).

---

## Appendix A — wire protocol reference

Field names verbatim from `convex-js` `main` (npm 1.44.0)
`src/browser/sync/protocol.ts` and the backend `crates/sync/src/worker.rs`.

### A.1 Transport

- URL: `wss://{host}/api/sync` (+ optional `/{clientVersion}` path segment —
  the backend registers both routes; "websockets can't do it in header" per
  `router.rs`). Upgrade header `Convex-Client: {name}-{version}`.
- JSON text frames only. Deprecation warnings arrive as
  `x-convex-deprecation-state` / `x-convex-deprecation-message` response
  headers on the upgrade.

### A.2 Scalars

- `QueryId`, `QuerySetVersion`, `RequestId`, `IdentityVersion`: JSON numbers.
- `TS` (nanoseconds, u64): **base64 of the 8-byte little-endian** value.
- `QueryJournal`: `string | null`, opaque (pagination cursors).

### A.3 Client → server

```ts
{ type: "Connect", sessionId: string /* uuid4, stable per client */, connectionCount: number,
  lastCloseReason: string | null /* "InitialConnect" first time */, maxObservedTimestamp?: TS,
  clientTs: number /* wall-clock ms */ }
{ type: "ModifyQuerySet", baseVersion: number, newVersion: number /* base+1 */, modifications: [
    { type: "Add", queryId, udfPath /* "module:fn"; "module" ⇒ ":default"; strip ".js" */,
      args: [convexJson] /* ALWAYS 1-element array */, journal?: QueryJournal }
  | { type: "Remove", queryId } ] }
{ type: "Mutation", requestId: number /* shared counter w/ actions */, udfPath, args: [convexJson] }
{ type: "Action",   requestId, udfPath, args: [convexJson] }
{ type: "Authenticate", tokenType: "User", value: string /* JWT */, baseVersion: IdentityVersion }
{ type: "Authenticate", tokenType: "None", baseVersion: IdentityVersion }  // clear auth
// Optional telemetry: { type: "Event", eventType: string, event: any }
```

### A.4 Server → client

```ts
{ type: "Transition",
  startVersion: { querySet, ts: TS, identity },  // must equal client's current triple
  endVersion:   { querySet, ts: TS, identity },
  modifications: [
    { type: "QueryUpdated", queryId, value: convexJson /* may be absent ⇒ null */,
      logLines: string[], journal: QueryJournal }
  | { type: "QueryFailed", queryId, errorMessage: string, logLines, errorData: convexJson, journal }
  | { type: "QueryRemoved", queryId } ],
  clientClockSkew?: number }
{ type: "TransitionChunk", chunk: string, partNumber: number /* 0-based, in order */,
  totalParts: number, transitionId: string }
{ type: "MutationResponse", requestId, success: true, result: convexJson, ts: TS, logLines }
{ type: "MutationResponse", requestId, success: false, result: string /* message */,
  logLines, errorData?: convexJson }
{ type: "ActionResponse", requestId, success: true, result: convexJson, logLines }   // no ts
{ type: "ActionResponse", requestId, success: false, result: string, logLines, errorData? }
{ type: "AuthError", error: string, baseVersion: IdentityVersion, authUpdateAttempted: boolean }
{ type: "FatalError", error: string }   // terminal: report and dispose, never reconnect
{ type: "Ping" }                        // no reply; resets inactivity watchdog
```

Chunk reassembly: chunks of one `transitionId` must arrive contiguously and
in order; concatenate `chunk` strings and `JSON.parse` the result (always a
`Transition`). Any other message interleaved → discard the buffer.

### A.5 Versioning rules

- Per-socket client state starts `{querySet: 0, ts: 0, identity: 0}`.
- `Authenticate` increments local identity immediately on send; server
  confirms via a `Transition` with `endVersion.identity > startVersion.identity`.
  There is no dedicated auth-OK message.
- A `Transition` whose `startVersion` ≠ current triple is a protocol
  failure → reconnect.
- Version-mismatch server error text seen in the wild:
  `Base version 0 passed up doesn't match the current version 1`.

### A.6 Mutation lifecycle

- Success: hold the caller's Future until a `Transition` has
  `endVersion.ts >= MutationResponse.ts` (read-your-own-writes). Failure:
  resolve immediately.
- Server dedupes by `(sessionId, requestId)` (`SessionRequestIdentifier` →
  `mutation_identifier` in `worker.rs`) — resending on reconnect is safe
  **only** with a stable sessionId.
- Ignore `MutationResponse` for unknown/completed requestIds (duplicates
  after reconnect are expected; convex-js CX-1513).
- Track `maxObservedTimestamp = max(all MutationResponse.ts, all
  Transition.endVersion.ts)` for the next `Connect`.

### A.7 Value encoding (`convexToJson`)

- `null/bool/string/finite double` → plain JSON. `-0.0`, `NaN`, `±Infinity`
  → `{"$float": base64(8-byte LE IEEE754)}` (plain floats must NOT use it).
- Dart `BigInt`/int64 → `{"$integer": base64(8-byte LE two's-complement)}`,
  range-checked to i64.
- `Uint8List` → `{"$bytes": base64}`.
- Objects: keys byte-order **sorted**; each key ≤1024 chars, ASCII 32–126,
  no leading `$`; null-valued optional args omitted like convex-js omits
  `undefined`.
- Decoder rejects legacy `$set`/`$map`.

### A.8 Reconnect & backoff constants (convex-js reference values)

- Server pings ~every 15 s; convex-js inactivity threshold 60 s (we default
  45 s, configurable). convex-rs uses 30 s with a 5 s check tick.
- Backoff `initial · 2^retries` capped at 16 s, ±50% jitter. Initial by
  close-reason prefix: client-initiated 100 ms; default 1000 ms;
  `InternalServerError` 1000 ms; `SubscriptionsWorkerFullError`,
  `TooManyConcurrentRequests`, `CommitterFullError`, `ExecuteFullError`,
  `SystemTimeoutError`, `ExpiredInQueue`, `TooManyWritesInTimePeriod`, … 3000 ms.
- Benign close codes: 1000, 1001 (mobile backgrounding), 1005, 4040
  (transient during deploys — retry).
- Auth refresh leeway: convex-js default 10 s before `exp` (we default 60 s).

### A.9 HTTP one-shot API (fallback transport)

```
POST {deployment}/api/query | /api/action | /api/mutation
Content-Type: application/json
Convex-Client: {name}-{version}
Authorization: Bearer {jwt}          # when authenticated

{ "path": "v1/live/actions:requestLiveToken",
  "format": "convex_encoded_json",
  "args": [ {…convex-encoded args object…} ] }

→ 200 { "status": "success", "value": …convex-encoded…, "logLines": [] }
→ 560 { "status": "error", "errorMessage": "...", "errorData"?: …, "logLines": [] }
```

## Appendix B — current app call sites the client must serve

From the usage inventory (the complete contract):

| Kind | Function | Site |
|---|---|---|
| subscribe | `v1/sync/queries:getCounter` (bare int64) | `sync_engine.dart:99` |
| query | `v1/sync/queries:pull` (int64 `since`) | `sync_engine.dart:256` |
| query | `v1/users/queries:getSettings` | `default_currency_controller.dart:69` |
| mutation | `v1/sync/mutations:push` (int64 `expectedServerSeq`) | `sync_engine.dart:481` |
| mutation | `v1/users/mutations:updateDefaultCurrency` | `default_currency_controller.dart:101` |
| mutation | `v1/voice/sessions:appendEvents` | `voice_session_remote_sync.dart:73` |
| action | `v1/live/actions:requestLiveToken` | `gemini_voice_expense_command.dart:39` |
| auth | fetcher = POST `/auth/refresh` (24 h JWT) | `auth_controller.dart:254,277` |

## Appendix C — issue references

convex-rs [#14](https://github.com/get-convex/convex-rs/issues/14)
(reconnect version-mismatch loop),
[#9](https://github.com/get-convex/convex-rs/issues/9) (operations hang on
bad connection, reported from Dart FFI),
[#11](https://github.com/get-convex/convex-rs/issues/11) (invalid token
loads forever), [#8](https://github.com/get-convex/convex-rs/issues/8)
(subscriber ID already taken),
[#4](https://github.com/get-convex/convex-rs/issues/4) (unchanged values
resent); convex-mobile
[#21](https://github.com/get-convex/convex-mobile/issues/21) (iOS
use-after-free during reauth churn); convex_flutter
[#14](https://github.com/jkuldev/convex_flutter/issues/14) /
[#18](https://github.com/jkuldev/convex_flutter/issues/18) (stuck in
"connecting", silent TLS failure),
[#17](https://github.com/jkuldev/convex_flutter/issues/17) (reconnect-loop
fix bump), [#23](https://github.com/jkuldev/convex_flutter/issues/23) (web
impl sends outdated Authenticate payload). Plus LESSONS.md #1, #2, #4, #6,
#12 (this repo).
