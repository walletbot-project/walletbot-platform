# LiveKit as the agent transport

Status: PROPOSED. No code written. Successor to `docs/agent-overhaul-plan.md`,
which kept the model session on the device; this moves it to a server.

Scope: the Gaston agent on native and web. Transport, session ownership,
tool execution, persistence, telemetry, and the infrastructure to run it.

---

## 0. Executive summary

### The change

Today each client opens its own WebSocket to Google and runs the Gemini Live
session itself. Convex's only job is minting a constrained ephemeral token
that bakes in the prompt, the 42 tool declarations, and the user's context
snapshot (`packages/backend/convex/live/createToken.ts`).

We move the model session off the device. The phone and the browser join a
self-hosted LiveKit room and speak WebRTC. A Node worker joins the same room,
holds the Gemini Live socket, and runs the conversation. Tools keep executing
**on the device**, called from the worker over LiveKit RPC, so the offline-first
data model is untouched.

The model does not change. It stays speech-to-speech Gemini Live
(`gemini-3.1-flash-live-preview`) with native audio in and native audio out.
No STT, no TTS, no pipeline. `@livekit/agents-plugin-google` exposes exactly
that through `google.beta.realtime.RealtimeModel`, whose `modalities` default
is `[Modality.AUDIO]`.

### Architecture

```
┌──────────────────┐                    ┌──────────────────┐
│  Flutter native  │                    │  React web       │
│  Drift (local)   │                    │  Convex queries  │
└────────┬─────────┘                    └────────┬─────────┘
         │                                       │
         │  WebRTC audio (Opus)                  │
         │  lk.chat text stream                  │
         │  RPC: wallet.tool                     │
         └───────────────┬───────────────────────┘
                         ▼
              ┌─────────────────────┐
              │  livekit-server     │  self-hosted, single region
              │  + TURN + Redis     │  room: voice-<sessionId>
              └──────────┬──────────┘
                         │ outbound WS registration
                         ▼
              ┌─────────────────────────────────┐
              │  wallet-bot-agent (Node)        │
              │  @livekit/agents 1.x            │
              │  @livekit/agents-plugin-google  │
              │  imports @wallet-bot/shared     │
              └──────────┬──────────┬───────────┘
                         │          │
                         │          └──▶ Convex HTTP ingest
                         │               (transcript, tools, metrics)
                         ▼
              ┌─────────────────────┐
              │  Gemini Live API    │  our key, never on a device
              └─────────────────────┘
```

Convex keeps one job it already does well: authenticate the user, then mint a
**LiveKit** join token instead of a Gemini one, carrying `platform`,
`appVersion`, and resolved feature flags as participant attributes the client
cannot forge.

### Pros

- The device-to-edge leg becomes Opus over WebRTC: FEC, packet loss
  concealment, a jitter buffer, adaptive bitrate, and ICE restart on a Wi-Fi to
  LTE handoff. Today it is raw PCM16 over a TCP WebSocket, which head-of-line
  blocks on any loss.
- Gemini's socket moves to a datacenter link. Its `goAway` churn, its errors,
  and its reconnects stop being paid for on the user's phone.
- A model-session death becomes a beat of silence instead of a 30 second
  backoff hole plus a token mint plus a full transcript replay over a bad link.
- The prompt stops being frozen inside a JWT, so the context snapshot can be
  refreshed mid-session instead of going stale until reconnect.
- The Gemini API key never leaves our infrastructure. The ephemeral token mint,
  its 20 hour TTL, its `uses: 1` accounting, and the 32KB context cap all go away.
- Telemetry gains data rather than losing it: per-modality token counts survive,
  and we get WebRTC quality metrics (packet loss, jitter, RTT) that we have zero
  visibility into today.
- Exports become server-side and complete, including both audio tracks via
  LiveKit track egress.
- Swapping Gemini for another realtime provider later becomes a config change,
  and SIP telephony (log an expense by calling a number) becomes reachable.

### Cons

- We take on the first always-on services this project has ever run: an SFU, a
  TURN server, Redis, and a worker. Voice currently survives a total outage of
  our infrastructure because the phone talks to Google directly. After this, the
  SFU going down means no voice at all.
- TURN is mandatory, not optional. Argentine mobile carriers sit behind CGNAT
  and a meaningful share of connections fail without a TURN relay on 443.
- One lossy transcode appears that does not exist today: PCM16 becomes Opus and
  back. Accepted, and probably a net win given what FEC and PLC buy on a bad link.
- Tool schema conversion moves from our tested `toGoogleSchema()` to the
  plugin's `convertJSONSchemaToOpenAPISchema`. Same class of transform,
  different implementation, and it must be pinned by a test.
- RPC payloads cap at 15KiB, which `listTransactions` already exceeds at its own
  default limit.
- `@livekit/agents` for Node trails the Python SDK in feature parity. Everything
  we need exists today, but we are downstream of their release cadence for new
  Live API fields instead of adding a JSON key ourselves.
- More moving parts to operate, monitor, and pay for.

### Cost

Self-hosting removes LiveKit Cloud's $0.0100 per agent-session minute and its
concurrency tiers entirely. What replaces it is roughly two VMs (one SFU, one
worker; LiveKit's own deploy guidance suggests 4 cores and 8GB per agent
server), a small Redis, and egress storage. Opus audio is 24 to 32 kbps each
way, so bandwidth is a rounding error.

### Decision status

Settled: self-hosted LiveKit (non-negotiable), tools on the device, Node worker,
speech-to-speech Gemini unchanged, lossy audio accepted, exports and telemetry
move server-side with no loss of granularity.

Also settled, 2026-08-27 (details in § 12): pure tools run in the worker, both
audio tracks always recorded with a 30 day TTL, the local Drift voice log is
retired, one box for the LiveKit stack plus one for the worker, client-driven
re-dispatch with no worker lease, micro-batched near-real-time persistence, and
every session opens a room whether it is voice or text.

Open: none.

---

## 1. Why

### 1.1 What breaks today

Every one of these is in the current code, not hypothetical.

| Failure | Where |
|---|---|
| Reconnect backoff is `2^(n-1)` capped at 30s, so a bad patch leaves a 30 second hole mid-conversation | [gemini_voice_expense_command.dart:1109-1123](../apps/native/lib/voice/gemini_voice_expense_command.dart#L1109-L1123), [use-voice.ts:748-765](../apps/web/src/hooks/use-voice.ts#L748-L765) |
| Every reconnect re-mints a token over the user's own link: Convex action bounded to 6s, then HTTP fallback with a 15s timeout. Worst case ~21s before a socket is attempted | [gemini_voice_expense_command.dart:26-95](../apps/native/lib/voice/gemini_voice_expense_command.dart#L26-L95) |
| Every reconnect re-seeds the full transcript as `clientContent` and re-pays for it | `buildConversationSeed`, [voice_event.dart](../apps/native/lib/voice/voice_event.dart), [voice-seed.ts](../apps/web/src/lib/voice-seed.ts) |
| Gemini's own `goAway` rotation is executed by the phone | [gemini_voice_expense_command.dart:926-938](../apps/native/lib/voice/gemini_voice_expense_command.dart#L926-L938), [use-voice.ts:903-925](../apps/web/src/hooks/use-voice.ts#L903-L925) |
| Backgrounding the app kills the socket; the session goes `suspended` | [voice-session-lifecycle.md](./voice-session-lifecycle.md) |
| Raw PCM16 over a TCP WebSocket: no FEC, no PLC, no jitter buffer, and head-of-line blocking on loss | [gemini_voice_expense_command.dart:706-720](../apps/native/lib/voice/gemini_voice_expense_command.dart#L706-L720) |
| Cost accounting splits or under-reports across suspend and resume | R-026, R-027 in [riesgos.md](./riesgos.md) |

### 1.2 What LiveKit changes mechanically

The device-to-edge leg becomes WebRTC. That single substitution brings NACK,
FEC, packet loss concealment, a jitter buffer, adaptive bitrate, and ICE restart
on network change. A two second tunnel outage becomes a glitch instead of a
session restart.

The worker-to-Gemini leg becomes a datacenter-to-datacenter WebSocket. When it
dies, only the worker reconnects: the user's room stays up, no token is minted
over the phone's link, and the context replay happens over a fast link. This is
exactly the recovery shape remi uses (`remi-worker/src/modules/voice/call.ts`,
the `reconnect` latch).

### 1.3 What it does not fix

- Gemini itself. If the Live API is degraded, the call is degraded.
- A genuinely offline user. Voice needs the network today and will tomorrow.
- Cold-start latency. One extra hop is added (device to SFU to worker). Steady
  state is comparable and jitter is much better, but first-token latency may rise
  by tens of milliseconds.

---

## 2. Target architecture

### 2.1 Components

| Component | Runtime | Responsibility |
|---|---|---|
| `livekit-server` | Go binary, our infra | SFU, signaling, room state |
| TURN | coturn or livekit's built-in | Relay for CGNAT and restrictive networks |
| Redis | our infra | Multi-node room state, egress job queue |
| `wallet-bot-agent` | Node, our infra | Gemini session, prompt, tool bridge, persistence, telemetry |
| `livekit-egress` | our infra | Track egress to GCS for audio export |
| Convex | unchanged hosting | Auth, LiveKit token mint, ingest endpoint, pricing |
| Flutter / React | unchanged | Mic, playback, transcript UI, tool execution |

### 2.2 Session lifecycle

```
1. User starts a session by mic tap or typed message; both take the same path (§ 12.6).
2. Client → Convex: v1/live/actions:requestSession { platform, appVersion, locale, timezone }
3. Convex: requireAuth → resolve feature flags → create voiceSession row →
   mint LiveKit token (identity user-<userId>, room voice-<sessionId>,
   attributes { platform, appVersion, sessionId, locale, timezone, flags })
   → return { url, token, roomName, sessionId }
4. Client: room.connect(url, token); enable mic; register RPC handlers.
5. LiveKit: room created on join → automatic agent dispatch → worker joins.
6. Client → room: sendText(contextSnapshot, topic 'wallet.context')
7. Worker: read attributes → sanitizeAgentContext(snapshot) → build prompt →
   declarationsFor(platform, appVersion, flags) → open Gemini session.
8. Conversation. Model calls a tool → worker performRpc('wallet.tool') →
   device executes against Drift or Convex → envelope back → model continues.
9. Worker streams transcript, tool traffic and metrics to Convex ingest.
10. User ends the session → client disconnects → worker closes → egress finalizes.
```

Step 6 is deliberately a text stream and not a token attribute: the context
snapshot can reach 32KB, well past attribute and RPC limits. The worker waits
for it with a short timeout and falls back to the base prompt, matching the
existing "native config fails open" rule.

### 2.3 Room and identity model

- Room name: `voice-<voiceSessionId>`. One room per logical session, which makes
  the room name derivable for recovery exactly as remi derives `voice-<threadId>`.
- Participant identity: `user-<userId>`. LiveKit kicks an earlier participant
  with the same identity, so opening voice on a second device replaces the first
  rather than fighting it for the microphone.
- Agent identity: `gaston-<workerInstance>`.
- One user per room. No multi-party.

### 2.4 Trust boundary

The client is not trusted, per project rules. What makes the worker's inputs
trustworthy:

- `participant.identity` and `participant.attributes` are signed by Convex into
  the join token with our LiveKit API secret.
- The token grant **must not** include `canUpdateOwnMetadata`. With it, a client
  could rewrite its own attributes at runtime and lie about `appVersion` or its
  feature flags.
- The context snapshot in step 6 **is** client-supplied and stays untrusted. The
  worker runs it through `sanitizeAgentContext` from `@wallet-bot/shared`, the
  same function `createLiveToken` uses today, with the same per-list caps.
- Tool authorization is unchanged, because tools still execute in the client's
  own authenticated context.

---

## 3. Backend changes (Convex)

### 3.1 Token minting

`packages/backend/convex/live/createToken.ts` loses its Google half and keeps
its gating half.

Dies:
- `AUTH_TOKENS_URL`, `TOKEN_TTL_MS`, `NEW_SESSION_WINDOW_MS`, the mint fetch
- The system prompt constants (move to the worker, unchanged text)
- `toGoogleSchema` / `toFunctionDeclarations` / `TOOL_DECLARATIONS` (the worker
  builds declarations from `@wallet-bot/shared` directly)
- `renderUserContext` (moves to the worker)

Survives, moved to the worker:
- `NATIVE_TOOL_MIN_VERSION`, `FLAG_GATED_TOOLS`, `declarationsFor()`
- `sanitizeAgentContext` usage and `AGENT_CONTEXT_CAPS`

New in Convex: a LiveKit `AccessToken`. This is an HS256 JWT over a small claim
set. Keep it in the **default runtime**, not `'use node'`, for the reason the
current file documents: a token request must never pay a Node cold start.
Try `livekit-server-sdk`'s `AccessToken` first (it uses `jose`, which targets
Web Crypto); if it does not load in Convex's runtime, hand-roll the signing with
`crypto.subtle` in about thirty lines. Do not reach for `'use node'` to avoid
writing them.

Grants:

```
roomJoin: true
room: 'voice-<sessionId>'
canPublish: true
canSubscribe: true
canPublishData: true
canUpdateOwnMetadata: false      // required, see § 2.4
attributes: { platform, appVersion, sessionId, locale, timezone, flags }
ttl: 10 minutes                   // authorizes the join, not the session
```

### 3.2 Agent dispatch

Use **automatic dispatch**: a worker registered without an `agentName` is
dispatched to every room. Every voice room needs an agent, so there is nothing
to decide per room, and it removes a Convex-to-LiveKit API call from the connect
path.

Explicit dispatch (`api.agentDispatch.createDispatch`) is the fallback if we
later want rooms without agents, or want to pass job metadata. Note it also
gives Convex a second network dependency at session start, which is exactly what
we are trying to remove.

### 3.3 Ingest endpoint

The worker is a trusted server, not a client, so it does not use Better Auth.

```
POST /v1/live/ingest
Authorization: Bearer <LIVE_WORKER_SERVICE_KEY>   // Convex env var
Body: { sessionId, userId, events: [...], metrics?: {...}, sessionPatch?: {...} }
```

- Verified against a Convex env var, constant-time compare.
- Writes through internal mutations only.
- Batched, up to 50 events, idempotent on `(sessionId, seq)`. This is the same
  contract [voice_session_remote_sync.dart](../apps/native/lib/voice/voice_session_remote_sync.dart)
  already implements, so the server tables need no reshaping.
- The endpoint must reject a `userId` that does not own `sessionId`.

### 3.4 What clients keep calling

`v1/live/actions:requestLiveToken` is replaced by
`v1/live/actions:requestSession`. Keep the old one alive until no supported
client version needs it (§ 8).

---

## 4. The worker

### 4.1 Stack and layout

```
apps/agent/
  package.json          @livekit/agents, @livekit/agents-plugin-google,
                        livekit-server-sdk, @wallet-bot/shared, zod, pino
  src/
    main.ts             AgentServer bootstrap, health on :8081
    session.ts          per-job entry: attributes → prompt → AgentSession
    prompt.ts           moved verbatim from createToken.ts
    context.ts          sanitize + render the client snapshot
    tools/
      bridge.ts         RPC transport to the device
      declarations.ts   declarationsFor(), moved from createToken.ts
      local.ts          pure tools that need no device (§ 4.4)
    ingest.ts           batched writes to Convex
    telemetry.ts        metrics_collected → pricing attributes
    egress.ts           start/stop track egress
```

It lives in the monorepo so it can `import { TOOL_DEFINITIONS, AGENT_SKILLS,
sanitizeAgentContext } from '@wallet-bot/shared'`. That import is the single
strongest argument for Node over Python here: the prompt, the skills, the tool
schemas, and the caps all stay in one place with one typecheck.

### 4.2 Session config mapping

Every field of the current hand-written setup frame
([gemini_voice_expense_command.dart:507-529](../apps/native/lib/voice/gemini_voice_expense_command.dart#L507-L529))
has a `RealtimeModel` option.

| Current setup key | `RealtimeModel` option | Note |
|---|---|---|
| `model: models/<AGENT_MODEL>` | `model` | typed `LiveAPIModels \| string`, so our preview name passes through |
| `generationConfig.responseModalities: ['AUDIO']` | `modalities` | already the default |
| `speechConfig.voiceConfig.prebuiltVoiceConfig.voiceName` | `voice` | `AGENT_VOICE_NAME` |
| `systemInstruction` | `instructions` | assembled in `prompt.ts` |
| `inputAudioTranscription: {}` | `inputAudioTranscription` | required, drives the transcript |
| `outputAudioTranscription: {}` | `outputAudioTranscription` | required |
| `contextWindowCompression.slidingWindow` | `contextWindowCompression` | required, lifts the 15 minute audio cap |
| `sessionResumption: {}` | handled internally | see § 4.7, this is the one to watch |
| (not set today) | `realtimeInputConfig` | carries `automaticActivityDetection` and `activityHandling`; we currently rely on Gemini defaults |
| (not available today) | `enableAffectiveDialog`, `proactivity`, `thinkingConfig`, `temperature`, `mediaResolution` | new capability, not required for parity |

Turn detection stays Gemini's server-side VAD. Do not add a turn detector plugin
and do not add STT or TTS. `AgentSession` with `llm: RealtimeModel` and no `stt`
and no `tts` is native audio end to end.

### 4.3 Prompt assembly

`CORE_IDENTITY`, `PLATFORM_NOTES`, `CAPABILITIES`, `DASHBOARD_GUIDE`,
`CORE_RULES`, `MATH_GUIDE`, `FX_GUIDE`, `FEATURE_DISCOVERY`, `MEMORY_RULES`,
`SKILLS_INDEX`, and `renderUserContext` move to `prompt.ts` as-is. The text does
not change. Two things get better:

- The 32KB serialized cap existed because the block had to fit in a JWT. It can
  relax, though keep a cap for abuse and token cost.
- The "Today is" line can finally use the client's real locale and timezone from
  the attributes, without the token-mint round trip. D8 in the overhaul plan
  called this out; it stays fixed and gets cheaper.

New capability worth taking: the snapshot can be re-rendered and re-injected
mid-session when the client reports a change. Out of scope for phase 1, but the
architecture allows it and the current one does not.

### 4.4 Tool bridge

Tools split three ways.

**Device tools (37).** Everything touching data or device state. Executed over
RPC against Drift on native and against Convex on web, using the existing
executors unchanged.

```
method:   'wallet.tool'                       // ≤64 bytes, fine
request:  { "name": "addExpense", "args": { ... } }
response: { "ok": true, ... } | { "ok": false, "error": "...", "candidates": [...] }
          | { "ok": true, "stream": "<callId>" }        // oversized, see § 4.5
timeout:  8s default (the handler gets less than the caller's budget)
```

Rules:

- The device never throws. A tool failure returns the `{ ok: false, error }`
  envelope so the model sees a normal tool error and can recover in-conversation.
  An RPC-level error means the device is gone, which is a session problem, not a
  tool problem.
- The worker declares only what the client can execute:
  `declarationsFor(platform, appVersion, flags)`, read from signed attributes.
  All the reasoning in `NATIVE_TOOL_MIN_VERSION` survives intact, because the
  device is still the executor.
- Web and native register the same method name with the same envelope, so there
  is exactly one contract.

**Pure tools (4).** `calculate`, `calculateDate`, `readSkill`, and
`getExchangeRate` need no device state. They run in the worker from
`@wallet-bot/shared` and save the round trip (decided, § 12.1).
`getExchangeRate` currently reads a device-scoped rate cache, so the worker
fetches and caches quotes itself: one cache instead of N devices. The device
keeps its own cache for the non-agent FX paths, and a brief disagreement
between the two quotes is accepted.

**Device-only tools.** `updateSettings` writes device-scoped language and theme.
These can never move server-side. RPC, permanently.

### 4.5 Large payloads

RPC caps request and response at 15KiB UTF-8 each. This is not theoretical:
[`_serializeTransaction`](../apps/native/lib/voice/tool_executors.dart) emits 15
fields including three UUIDs and a full `DateTime.toString()`, roughly 380 to
400 bytes per row, and [`listTransactions`](../apps/native/lib/voice/tool_executors.dart#L494)
defaults to 50 rows when filters are present. That is about 19.5KB, over the cap
with nobody doing anything unusual.

`summarizeTransactions` is fine. It returns aggregate rows and stays around 3KB
at realistic category counts.

Three changes, in this order:

1. **Trim the list projection.** Drop `dateConfirmed`, `timeStatus`, and
   null-heavy `toAmount` / `balanceAfter` from list results. Keep them in
   `getTransaction`, which is the tool the model uses when it needs detail.
2. **Lower the default limit from 50 to 25.** A voice agent never reads 50
   movements aloud, and the prompt already says to prefer totals over
   enumeration. Those rows also stay in the model's context and get re-billed as
   text input on every subsequent turn, so this is a token-cost win independent
   of the RPC cap.
3. **Add a stream fallback so nothing truncates silently.** When a serialized
   result exceeds 12KiB (margin under the cap), the device answers the RPC with
   `{ ok: true, stream: callId }` and pushes the full payload over a text stream
   on topic `wallet.tool.result` with `callId` in the stream attributes. The
   worker holds the pending tool result until the stream completes or the budget
   expires.

Chunking a result across several RPC calls was considered and rejected: it turns
one tool call into N model round trips and makes the model reason over partial
pages, which costs exactly the latency we are trying to win back.

### 4.6 Text mode

Typed turns arrive as text streams on the `lk.chat` topic, which `AgentSession`
handles natively. The client sends with
`room.localParticipant.sendText(text, { topic: 'lk.chat' })`.

Reply modality semantics stay as specified today: a typed turn renders a
transcript with audio suppressed at playback, a spoken turn re-enables it. The
Live API cannot switch modality mid-session, so the model still generates audio
for a typed turn and we still pay for it. That is true today too
(`RESPOND_TO_TEXT_WITH_AUDIO = false` suppresses at playback, not at the
server), so it is not a regression. Keep the suppression client-side.

### 4.7 Reconnect and session resumption

Three independent failures, three answers.

**The room drops.** The client SDK reconnects on its own with ICE restart. The
worker sees nothing. No action.

**The Gemini socket drops or sends `goAway`.** The plugin handles it: `goAway`
sets `sessionShouldClose` and triggers reconnection, and `AgentSession` replays
its own `ChatContext` into the new session.

Here is the trap. The plugin reconnects using Gemini `sessionResumption`
handles. [voice-session-lifecycle.md](./voice-session-lifecycle.md) records that
we tested handles against the live API on 2026-08-21 and found that after an
abrupt cut the handle stops resuming within seconds and the server silently
opens a **blank** session. Remi's hand-rolled client rejects handles for the same
reason. What saves us is that `AgentSession` holds the chat context server-side
and re-seeds it, so a blank resume is recoverable in a way it never was on the
clients. **Verify this explicitly** (§ 9) and be ready to disable resumption.

**The worker dies.** The agent participant leaves and the user is alone in a
live room. LiveKit will not re-dispatch into an existing room on its own.
Decided (§ 12.5, § 12.8): recovery is client-driven and there is no worker
lease. The client watches for the agent participant disconnecting, shows a
"reconnecting" state (not an ended session) with a cancel action, waits a 5
second grace period, then calls `v1/live/actions:redispatch`, which issues an
explicit dispatch into the same room. Retries back off to roughly 45 seconds
total (3 attempts, matching remi's join grace); after that the session ends with
a clear message, never an endless spinner (R-035). The rejoining worker reads
the session log from Convex and replays it as context, the same replay remi's
re-claim performs. The double-agent guard is the room itself: a worker that
joins and finds another live agent participant leaves silently. There is
deliberately no heartbeat, epoch fence, or sweep. Remi needs those because its
calls carry queued notifications that must be served with nobody driving; a
wallet-bot room without the user's device is a dead session by definition. A
worker crash that coincides with a dead client simply ends the session, an
accepted rarity. Any new UI string here goes through the ARB files and `useT`,
never inlined.

### 4.8 Telemetry

Granularity is preserved, and this was checked against the Node source rather
than assumed. `RealtimeModelMetrics` in `agents/src/metrics/base.ts` carries:

```
inputTokenDetails:  { audioTokens, textTokens, imageTokens, cachedTokens,
                      cachedTokensDetails?: { audioTokens, textTokens, imageTokens } }
outputTokenDetails: { textTokens, audioTokens, imageTokens }
ttft, duration
```

That maps onto the attribute keys
[`agentPricing.ts`](../packages/backend/convex/telemetry/agentPricing.ts)
already prices:

| Pricing attribute | Source |
|---|---|
| `token_input_text` | `inputTokenDetails.textTokens` |
| `token_input_audio` | `inputTokenDetails.audioTokens` |
| `token_input_media` | `inputTokenDetails.imageTokens` |
| `token_output_text` | `outputTokenDetails.textTokens` |
| `token_output_audio` | `outputTokenDetails.audioTokens` |
| `token_output_media` | `outputTokenDetails.imageTokens` |
| `token_cached_input` | `inputTokenDetails.cachedTokens` |
| `token_thinking` | **gap, see below** |
| `token_tool_use_prompt` | **gap, see below** |

Gemini's raw `usageMetadata` also carries `thoughtsTokenCount` and
`toolUsePromptTokenCount`, which the framework's metrics type does not appear to
surface. Since losing data is explicitly unacceptable, treat this as a blocking
verification item with three escalating answers: read them off the raw
`usageMetadata` if the plugin exposes the server message; wrap or patch
`handleUsageMetadata` locally; or open an upstream PR. Do not ship phase 7
without resolving it.

`agentPricing.ts` itself does not move. Only its input source changes, from a
device-side outbox to the worker's ingest call. The pricing catalog, the
effective-from logic, and the metric names stay put.

**New data we do not have today.** The worker can also record WebRTC quality:
packet loss, jitter, RTT, and `ConnectionQuality` transitions per participant.
That is the ground truth for "was the network the problem" on any given session,
and today we have none of it. Ship it in the same ingest payload.

### 4.9 Persistence and export

Ownership of the durable log flips from the device to the worker.

**Transcript, tool traffic, lifecycle.** The worker writes them through the
ingest endpoint (§ 3.3) into the existing `voiceSessionEvents` shape. Order
matters: append one batch at a time, in call order, for the reason remi
documents in `call.ts`. Two overlapping appends take whichever sequence commits
first, and an inverted pair teaches a replayed model that it answered before it
was asked. Chain the writes.

Cadence is micro-batched (§ 12.7): buffer events and flush every ~2 seconds or
20 events, whichever comes first, idempotent on `(sessionId, seq)`. That is
near real time for any live observer, and a worker crash loses at most the last
unflushed window, an accepted trade.

**Audio.** Use LiveKit **track egress** on every session (decided, § 12.2; no
opt-in setting), one job per published audio track (the user's mic and the
agent's output), written as Opus in OGG to GCS. Track egress connects via SDK
rather than a headless browser, so it is the light variant of egress. This
replaces the local PCM BLOB columns and makes the export server-side and
complete, which was the goal. The transcript is the durable record; the
transcription pair in § 4.2 is what matters long-term, and the recordings exist
to audit and improve it.

Two things this drags in:
- Egress needs its own deployment and must share Redis with `livekit-server`.
- Retention is decided (§ 12.2): audio lives 30 days, enforced by a GCS
  lifecycle rule shipped in the same change as egress, comfortably inside the
  12 month ceiling the legal documents promise (R-013, R-039).

**The local Drift log.** Decided (§ 12.3): it retires. The client keeps no
durable voice store and no telemetry outbox; the worker records the
conversation and pushes transcript, tool traffic, and telemetry to Convex, and
history reads from Convex. The path there is phased: do not touch the native
schema in phase 1. Keep writing `voice_session_events` locally so the
transcript UI has a source, and simply stop the outbox in
`voice_session_remote_sync.dart`, since the server is now the writer. Dropping
those tables and the PCM columns is the phase 9 coordinated schema bump with
its own migration tests, per `docs/schema/README.md`. Known cost accepted:
past-session history stops being readable offline once the local log is gone.

`docs/voice-data-export.md` and `docs/voice-session-lifecycle.md` both need
rewriting once this lands. The lifecycle contract in particular changes shape:
a logical session no longer maps to a client-held socket.

---

## 5. Clients

### 5.1 Native (Flutter)

Add `livekit_client`. It brings WebRTC, so expect the usual platform work:
Android needs foreground-service and microphone permissions handled together for
background audio, iOS needs the audio session category and background mode set.
`record` and the hand-rolled `pcm_audio_player` stop being needed for the agent
path.

Deleted or gutted, roughly 1,550 lines:

| File | Fate |
|---|---|
| [gemini_voice_expense_command.dart](../apps/native/lib/voice/gemini_voice_expense_command.dart) | replaced by a LiveKit room controller, ~1,356 lines gone |
| [mic_capture.dart](../apps/native/lib/voice/mic_capture.dart) | gone, the SDK publishes the mic |
| [pcm_audio_player.dart](../apps/native/lib/voice/pcm_audio_player.dart) | gone, WebRTC plays out |
| [voice_session_remote_sync.dart](../apps/native/lib/voice/voice_session_remote_sync.dart) | outbox disabled; server writes now |

Kept untouched:

| File | Why |
|---|---|
| [tool_executors.dart](../apps/native/lib/voice/tool_executors.dart) | 1,597 lines, still the executor, now behind RPC |
| [tool_calc.dart](../apps/native/lib/voice/tool_calc.dart), [tool_fx.dart](../apps/native/lib/voice/tool_fx.dart), [tool_parsing.dart](../apps/native/lib/voice/tool_parsing.dart) | unchanged |
| [voice_session_repository.dart](../apps/native/lib/voice/voice_session_repository.dart) | local log stays in phase 1 |
| [agent_generated.dart](../apps/native/lib/voice/agent_generated.dart) | still pins the tool manifest; the model and voice constants become worker-side only |

New: register `wallet.tool` on the local participant, dispatch by name into the
existing `ToolExecutors.execute(name, args)`, and add the oversize stream path.
The switch statement does not change.

### 5.2 Web

Add `livekit-client`. Remove `@google/genai`.
[use-voice.ts](../apps/web/src/hooks/use-voice.ts) shrinks from 1,358 lines to a
room controller plus the same RPC handler, delegating to
[executors.ts](../apps/web/src/lib/agent-tools/executors.ts) unchanged.

Web is the right platform to ship first: weaker reconnect story today, and no
app-store release cycle between iterations.

### 5.3 Feature parity

Both platforms move. Neither one gets a capability the other lacks. The
transcript UI, the tool cards, and the editable-tool flow all read from the same
event stream they read today.

---

## 6. Self-hosted infrastructure

### 6.1 livekit-server

A single stateless Go binary, `livekit/livekit-server`, configured by YAML.
Under a few hundred concurrent participants, one dedicated box with host
networking under docker compose is the correct shape. Kubernetes buys nothing
here and costs real operational tax, because LiveKit needs direct host access to
its media ports.

Ports:

| Port | Purpose |
|---|---|
| 7880/TCP | WebSocket signaling (behind TLS) |
| 7881/TCP | TCP media fallback |
| 50000-60000/UDP | RTP media |
| 3478/UDP | TURN over UDP |
| 5349/TCP | TURN over TLS |
| 443/TCP | TLS termination for signaling and TURN |

### 6.2 TURN

Not optional. Our users are on Argentine mobile carriers behind CGNAT, and
without a relay a real share of connections fail outright. TURN over TLS on 443
is what gets through restrictive networks. This is the single most common
self-hosting regret and it is worth doing correctly on day one.

### 6.3 Redis

Only strictly required once more than one `livekit-server` node runs, but egress
needs it regardless, so provision it from the start. Rooms pin to a single node,
so the cluster spreads rooms rather than participants of one room. With one user
per room that is exactly the right property.

### 6.4 Egress

Deployed separately, sharing the same Redis as `livekit-server`. Track egress
(audio only, SDK-based) does not need the headless browser that composite egress
does. Output goes to GCS, which the storage feature already has wiring for.

### 6.5 Worker deployment

Agent servers register **outbound** over a WebSocket and expose no inbound
ports. Only an optional private health endpoint, default `0.0.0.0:8081`.
LiveKit's deploy guidance suggests 4 cores and 8GB per agent server. Each job
spawns a subprocess, so a rollout drains cleanly if SIGTERM handling is wired.

Outbound registration also gives the dev loop for free (§ 12.4): a worker on a
laptop registers against the shared `livekit-server` instance with no tunnel
and no inbound firewall hole. Caveat: it joins the same dispatch pool, so
staging sessions can land on the laptop; isolate with a distinct `agentName`
(or a local `livekit-server` in docker) if that bites.

### 6.6 Region

Pick deliberately. The point of this change is jitter, and Argentine users
reaching Virginia undoes part of the win. São Paulo (`sa-east-1` or equivalent)
is the right first region. Self-hosting means one region rather than LiveKit
Cloud's global mesh, so this choice matters more than it would otherwise.

### 6.7 Secrets

| Secret | Holder |
|---|---|
| `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` | Convex (mint) and worker (join) |
| `LIVEKIT_URL` | Convex, worker, and clients (returned in the session response) |
| `GOOGLE_API_KEY` | worker only, never on a device |
| `LIVE_WORKER_SERVICE_KEY` | worker and Convex (ingest auth) |
| GCS credentials | egress |

The Gemini key leaving client reach is a real security improvement over the
ephemeral-token scheme, which was designed precisely to avoid shipping it.

---

## 7. Versioning and compatibility

### 7.1 Feature flag

Gate the whole transport behind a new `liveKitTransport` flag in `KNOWN_FLAGS`
(`packages/backend/convex/featureFlags/utils.ts`), resolved server-side at
session request. A client whose flag is off gets the current ephemeral-token
path. This lets web and native cut over independently and lets us roll back
without an app release.

### 7.2 Tool gating

Unchanged in substance. `NATIVE_TOOL_MIN_VERSION` and `FLAG_GATED_TOOLS` move to
the worker and read `platform` and `appVersion` from signed attributes instead
of mint arguments. The invariant holds: never declare a tool the connecting
binary cannot execute.

### 7.3 Client contract versioning

`v1/live/actions:requestSession` is a new function under the existing `vN/`
prefix, not a breaking change to `requestLiveToken`. Both run side by side until
no supported version needs the old one.

This is **not** a sync wire change, so it does not by itself force a
`minSupportedVersion` bump or a Drift `schemaVersion` bump. Keep it that way in
phase 1 by leaving the native schema alone (§ 4.9). The later cleanup of
`voice_session_events` and the PCM columns is a separate coordinated bump with
its own migration tests.

---

## 8. Verification checklist

These are the spike's acceptance criteria. Every one is a thing that would be
expensive to discover in phase 5.

| # | Question | How to answer | Blocking |
|---|---|---|---|
| V1 | Does `gemini-3.1-flash-live-preview` work through `RealtimeModel`, or does the plugin's default model differ in wire behavior? | one call, audio in and out, tool round trip | yes |
| V2 | Does the plugin's `convertJSONSchemaToOpenAPISchema` produce the same declarations as our `toGoogleSchema()` for all 42 tools? | a test that diffs both converters over `TOOL_DEFINITIONS` | yes |
| V3 | Does session resumption reproduce the blank-session bug from 2026-08-21, and does `AgentSession` context replay cover it? | kill the socket abruptly mid-call, check the model's memory | yes |
| V4 | Do `thoughtsTokenCount` and `toolUsePromptTokenCount` survive into something we can read? | inspect `metrics_collected` and the raw server message | yes |
| V5 | Does `AgentSession` install its own turn detection in front of the realtime model by default? | check the session config, confirm Gemini's VAD is doing the work | yes |
| V6 | Does the Flutter SDK's RPC handle our envelope sizes and timeouts under real Drift latency? | `listTransactions` at 25 and at 200 rows | yes |
| V7 | Does the oversize text-stream fallback correlate correctly under concurrent tool calls? | two large tools in flight at once | yes |
| V8 | Does audio quality through Opus hold up for Gemini's ASR on Spanish and mixed Spanish/English? | listening test plus transcript accuracy against today's baseline | yes |
| V9 | Does agent re-dispatch into an existing room work after a worker kill? | SIGKILL the worker mid-call | yes |
| V10 | Does TURN over 443 get through a real Argentine mobile carrier? | test on a real device on cellular, not Wi-Fi | yes |
| V11 | Does track egress produce usable OGG for both tracks, and what does it cost per session? | one recorded session end to end | no |
| V12 | Are remote audio frames reachable in Flutter if we ever want local PCM again? | check `AudioRendererOptions` on `RemoteAudioTrack` | no |

---

## 9. Phases

Each phase is independently shippable and independently revertible.

| # | Phase | Contents | Gate |
|---|---|---|---|
| 1 | Spike | Node worker, Gemini realtime, one RPC tool against Drift, run against LiveKit's free tier or a local server | V1-V5 answered |
| 2 | Infrastructure | `livekit-server` + TURN + Redis in staging, TLS, region chosen, monitoring | V10 |
| 3 | Worker MVP | Full prompt assembly, context ingestion, declarations gating, all device tools over RPC | V6, V7 |
| 4 | Payload work | List projection trim, default limit 25, oversize stream fallback | V7 |
| 5 | Web client | Room controller, RPC handler, `@google/genai` removed, behind `liveKitTransport` | V8 |
| 6 | Native client | `livekit_client`, platform audio session work, RPC handler, same flag | V8, V9 |
| 7 | Server-side data | Ingest endpoint, transcript and tool persistence, telemetry with full granularity, WebRTC quality metrics | V4 |
| 8 | Egress and export | Track egress to GCS, 30 day lifecycle rule, export rewritten server-side | V11 |
| 9 | Retirement | Delete the ephemeral mint once no supported version needs it; separately, retire the local voice log and PCM columns as a coordinated bump (§ 12.3) | |

Phases 5 and 6 can run in parallel once 4 lands. Phase 7 should not lag far
behind 6, or we spend time flying without cost telemetry.

---

## 10. Risks to add to `docs/riesgos.md`

| Proposed | Risk | Category | P | I | Mitigation |
|---|---|---|---|---|---|
| R-035 | The self-hosted SFU becomes a single point of failure for voice. Today voice survives a total outage of our infrastructure because the client talks to Google directly. | Infraestructura | Media | Alto | One boring deployment, health checks and alerting from day one, and a client that degrades to manual entry with a clear message rather than a spinner. |
| R-036 | TURN misconfiguration silently fails a share of mobile users while the service looks healthy. | Infraestructura / Red | Media | Alto | TURN over TLS on 443, a real-carrier test in the release checklist, and per-session connection-quality telemetry so failures are visible rather than inferred. |
| R-037 | The plugin's schema converter differs from `toGoogleSchema()` and silently degrades a tool declaration. | Dependencias externas | Media | Medio | A test that diffs both converters over all 42 tools, run in CI. |
| R-038 | Gemini session resumption reintroduces the blank-session behavior found on 2026-08-21. | Dependencias externas | Media | Alto | V3 in the verification checklist, with resumption disabled if it reproduces. |
| R-039 | Recorded audio in GCS without an enforced retention rule breaks the 12 month commitment already published in the legal documents. | Legal / Cumplimiento | Media | Alto | Ship the lifecycle rule in the same change as egress, not after. Related to R-013. |
| R-040 | `@livekit/agents` for Node trails Python, so a new Live API capability may be unreachable until upstream ships it. | Dependencias externas | Media | Bajo | The realtime plugin already exposes more configuration than our current setup frame uses. Escalate through a local patch or an upstream PR if a gap blocks us. |

R-003 (external API changes breaking main flows) should be updated to name
LiveKit alongside the voice and Convex dependencies.

---

## 11. What this explicitly does not change

- The model. Same `gemini-3.1-flash-live-preview`, same voice, same
  speech-to-speech path, no STT and no TTS anywhere.
- Tool semantics. The 42 tools, their schemas, their envelopes, and their
  executors are untouched.
- The offline-first data model. Native still writes to Drift and syncs; the
  agent still reaches that data only through the device.
- Authorization. Tools run in the client's authenticated context, exactly as now.
- The sync wire format. This is not a coordinated bump in phase 1.
- The prompt text. It moves file, not content.

---

## 12. Decisions

All six original open items, plus two raised during review (persistence cadence
and the worker lease model), were decided on 2026-08-27.

1. **`getExchangeRate` placement: worker.** All four pure tools (`calculate`,
   `calculateDate`, `readSkill`, `getExchangeRate`) run in the worker from
   `@wallet-bot/shared` (§ 4.4). The worker fetches and caches FX quotes
   itself: one cache instead of N devices. The device keeps its own cache for
   the non-agent FX paths; a brief disagreement between the two quotes is
   accepted.
2. **Egress scope: always on, short-lived.** Both tracks recorded on every
   session, no opt-in setting. The durable record is the transcript, so
   transcription quality in both directions (§ 4.2) is the thing to protect;
   audio is a 30 day debugging and quality-analysis buffer, deleted by a GCS
   lifecycle rule shipped in the same change as egress. Comfortably inside the
   12 month legal ceiling (R-013, R-039).
3. **Local Drift log: retired.** The client keeps no durable voice store and no
   telemetry outbox. The worker records the conversation and pushes transcript,
   tool traffic, and telemetry to Convex; history reads from Convex, which
   costs offline review of past sessions. Phase 1 leaves the native schema
   untouched; the drop is the phase 9 coordinated bump (§ 4.9).
4. **Hosting shape: two boxes.** One instance (a VM or fly.io) runs the whole
   LiveKit stack under compose: `livekit-server`, TURN, Redis, and egress. A
   second box runs the worker. Dev workers run on a laptop and register against the
   shared LiveKit instance (§ 6.5, including the shared-dispatch-pool caveat).
5. **Re-dispatch policy: patient, client-driven.** 5 second grace after the
   agent participant drops, then `redispatch` with backoff to roughly 45
   seconds total (3 attempts), behind a reconnecting banner with a cancel
   action. After that the session ends with a clear message, never an endless
   spinner (R-035). Details in § 4.7.
6. **Text sessions open a room.** 100% voice/text interop within a single
   session is non-negotiable; it exists today and survives the move. One
   session, one room, one code path regardless of modality; the WebRTC weight
   of a typed-only session is the accepted price of not maintaining two paths.
7. **Persistence cadence: micro-batched, near real time.** The worker buffers
   events and flushes every ~2 seconds or 20 events, chained in order,
   idempotent on `(sessionId, seq)`. A crash loses at most the last unflushed
   window, accepted (§ 4.9).
8. **Worker lease: none.** No heartbeat, no epoch fence, no sweep. Recovery is
   decision 5's client-driven redispatch, and the double-agent guard is room
   presence: a worker that joins a room already holding a live agent
   participant leaves. Remi's lease machinery exists because its calls must be
   served with nobody driving them (queued notifications, claim-based
   dispatch); here a room without the user's device is a dead session by
   definition. The rare worker crash that coincides with a dead client just
   ends the session.

---

## References

- Current implementation: [createToken.ts](../packages/backend/convex/live/createToken.ts),
  [gemini_voice_expense_command.dart](../apps/native/lib/voice/gemini_voice_expense_command.dart),
  [use-voice.ts](../apps/web/src/hooks/use-voice.ts),
  [tool_executors.dart](../apps/native/lib/voice/tool_executors.dart)
- Prior plan: [agent-overhaul-plan.md](./agent-overhaul-plan.md)
- Contracts this must respect: [voice-session-lifecycle.md](./voice-session-lifecycle.md),
  [voice-data-export.md](./voice-data-export.md), [client-api-versioning.md](./client-api-versioning.md),
  [schema/README.md](./schema/README.md)
- Reference implementation of the same pattern: `kiwi-platforms/apps/remi-worker/src/modules/voice/`
  (`audio.ts` for the room, `call.ts` for the lifecycle, `session.ts` for the
  provider contract, `gemini-live.ts` for the hand-rolled wire protocol we are
  choosing not to repeat)
- LiveKit: [RPC](https://docs.livekit.io/transport/data/rpc/),
  [Gemini realtime plugin](https://docs.livekit.io/agents/models/realtime/plugins/gemini.md),
  [self-hosted egress](https://docs.livekit.io/transport/self-hosting/egress/),
  [agent deployment](https://docs.livekit.io/deploy/custom/deployments/)
