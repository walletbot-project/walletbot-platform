# Gemini 3.8 native integration — September 20, 2026

## Research

Google released **Gemini 3.8 Flash** September 2 and **3.8 Live / Live Extended
Thinking** September 15. Flash targets general reasoning and agent workflows;
Live is the relevant audio-to-audio API for this app. These are distinct model
IDs, not interchangeable generation settings.
[Release notes](https://ai.google.dev/gemini-api/docs/changelog)

Use **`gemini-3.8-live`** as the native default. Google positions it for low-latency
voice agents; it supports interleaved reasoning and asynchronous function calls.
Migration changes: omit thinking configuration, do not disable proactive audio,
remove affective-dialogue options, request AUDIO and enable transcription for
text. Explicit user/model roles are supported throughout a session; completing
a client-content turn interrupts active generation.
[Model and migration guide](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-live)

**Extended Thinking** supports background reasoning and configurable thinking
levels. It requires asynchronous tools, and turn completion alone is insufficient
to decide whether the interaction is idle. That is a separate product decision;
the current rebuild uses standard Live and preserves ordered financial tools.
[Capabilities comparison](https://ai.google.dev/gemini-api/docs/live-api/capabilities)

3.8 defaults to nonblocking tools. We explicitly declare **BLOCKING** for this
release so confirmations follow committed local results. The client still keeps
its receive loop responsive to speech, cancellation and disconnects while tools
execute. Opting tools into background completion would also require UI states
for outstanding work and a deliberate response-scheduling policy.
[Tool documentation](https://ai.google.dev/gemini-api/docs/live-api/tools)

Google lists 3.8 Live at the same token rates as 3.1 Live: input text $0.75/audio
$3.00 per million; output text $4.50/audio $12.00 per million. The backend pricing
catalog now recognizes 3.8 instead of leaving its cost metrics unpriced.
[Pricing](https://ai.google.dev/gemini-api/docs/pricing)

## Implementation

See [native audio architecture](../apps/native/AUDIO.md). The rebuild separates
credential issuance, transport state, protocol, tool dispatch, conversation
orchestration and platform audio ownership. Existing local repositories,
financial tool validation, consent and conversation persistence remain in use.

The main reliability changes are explicit connection epochs, handshake gating,
no stale microphone replay, no tool responses crossing connections, serialized
local tools, duplicate-call suppression, immediate playback interruption,
bounded native audio queues, and permission-aware microphone startup.

Native 0.5.0 uses 3.8; the backend continues minting the legacy model for older
clients and the existing web implementation. This avoids requiring every user
to update simultaneously. No database schema migration is required.

## Verification

- Native test suite: 719 tests passed, including new transport, cancellation,
  duplicate-call and audio-lifecycle regression tests.
- Backend: 123 tests passed, including native model rollout compatibility.
- Shared package: 155 tests passed; generated model constants are current.
- Flutter analyzer and backend TypeScript checks passed.
- Android debug APK and iOS simulator debug build succeeded.
- Development backend deployed. Real 3.8 constrained token + WebSocket setup
  accepted; a synthetic greeting returned a complete transcript and 210,720
  bytes of PCM audio.
- Pixel 8 Pro (Android 17): build installed in place, preserving app data.
  Typed greeting returned a visible 3.8 response. An explicit calculator
  request executed the local `calculate` tool and returned 56,088 for 123×456,
  without creating financial records. Silent text mode held neither microphone
  capture nor audio focus. OS diagnostics confirmed
  mono PCM16 capture at 16 kHz, 24 kHz playback, acoustic echo cancellation
  and noise suppression. Backgrounding stopped capture, abandoned audio focus
  and restored normal audio mode. Foregrounding restarted capture with a new
  recording session. The app was left with capture stopped.

These checks establish connection, PCM transport and lifecycle behavior, not a
subjective acoustic assessment. Real speech, barge-in and headset quality still
need a listening check.

Physical iOS voice quality, Bluetooth route transitions and phone-call
interruptions require hardware coverage. A simulator build cannot establish
that echo cancellation or speaker/microphone quality is correct on an iPhone.

## Model rollback / comparison flag

Native **0.5.1+13** adds `agentGemini31` to the existing admin feature flags:

- **Off (default):** `gemini-3.8-live` with the new architecture.
- **On:** `gemini-3.1-flash-live-preview` with the same new architecture.

Use Admin → Feature flags to set a per-user override for a signed-in test account,
including a false override if the global setting is true. Local accounts follow
the global setting. Flags are resolved server-side for both token endpoints;
there is no separately cached client flag selecting a competing model.

A token carries its authorized model through prefetch, WebSocket setup and
reconnect. Missing or unsupported model IDs are refused. Existing connections
are not interrupted by a toggle: it applies on the next token mint. A prefetched
token can retain its model for up to 60 seconds. For a clean comparison, end the
conversation and restart the app after changing the flag, then open a new voice
session. Inspect the setup model in its session log. Session metadata records
the latest connection model, and setup events preserve model-switch history.
Usage metrics retain the model that produced the usage. Response reports link
to the session instead of asserting a compiled-in model for historical messages.

The backend ignores rollback for 0.5.0 (that binary only accepts 3.8). Older
native builds and cached web clients below capability version 0.5.1 retain
their existing 3.1 behavior. Updated web clients use the same rollback flag; see
[the web implementation notes](gemini-3.8-web.md). Deploy the
backend change and install 0.5.1+ before using the switch. No schema migration is
needed. The development-only `GEMINI_LIVE_TOKEN` override bypasses server minting
and remains paired with the default 3.8 model; leave it unset for flag testing.

There is no audio architecture barrier to 3.1: the shared PCM transport,
transcriptions, client-content updates and synchronous tools remain usable.
For 3.1 the mint omits the 3.8 tool `behavior` field; for 3.8 it explicitly selects
BLOCKING. No unsupported thinking/proactive/affective settings are sent.
[3.1 compatibility guide](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-live-preview)

This is a **model-only rollback**. It helps compare model quality/behavior but
cannot undo a bug in the new audio engines, startup buffer or connection layer.
Physical-device comparison is still required before release.

Local validation of this follow-up: 241 native tests and 126 backend tests passed;
Flutter analysis and backend TypeScript checks passed. Android debug and iOS
simulator debug builds passed. The Pixel 8 Pro was disconnected, so this flag
has not been verified on hardware. These changes have not been pushed or deployed.

### Telemetry audit follow-up

HTTP payload tests confirm that both supported model IDs are preserved on
interaction cost, completed-interaction count, and session cost metrics. Backend
normalization accepts and prices both IDs without replacing the model. Monthly
usage grouping also includes model. These are local tests, not proof of receipt
from a physical device by the deployed backend.

Accounting correction (PR review follow-up): each usage report is now counted
as one generation. Equal-cost reports are retained, smaller reports keep their
full token attributes, and final session totals accumulate separately for each
model. Backend pricing remains authoritative for the model's rates.
[UsageMetadata reference](https://ai.google.dev/api/live#UsageMetadata)

Transport is best effort: failed telemetry POSTs are logged without a durable
retry queue. Model-label, equal/smaller-generation and per-model session-total regression
tests cover the accounting changes. Delivery remains best effort. See the PR
for current build, CI and device verification results.


### PR review corrections

Startup recovery resets the UI even when command cleanup fails; the failing
consent-test fake also implements the current command contract. Background
transitions carry a generation guard, remember microphone intent during a
permission dialog, and restore playback independently of mute. Regression tests
cover failed start/cleanup retry, muted playback restoration, and permission
approval through rapid background/foreground/background transitions.

The reconnect seed includes tool arguments and recorded outcomes, after waiting
for executing tools and flushing native history. This reduces blind replay but
is not cross-connection idempotency; `docs/riesgos.md` R-001 records the remaining
risk. Application message/parser failures no longer reconnect a healthy socket;
invalid audio parts are skipped with diagnostics.

Android transient audio-focus loss pauses capture/playback and resumes when
focus returns unless the user muted or left the screen. Permanent focus loss
requires a new microphone gesture. Native-handle release waits for audio threads
off the UI thread. iOS configuration changes rebuild the graph, tap and converter
for the current engine, ignoring notifications from an obsolete engine.

For a production model cohort, set global `agentGemini31=true` and set a
per-user override to `false` for each 3.8 test user. The built-in default remains
3.8, as requested. This flag selects the model; it cannot restore the removed
native audio implementation. Backend deployment must precede client distribution;
0.4.x retains 3.1 and 0.5.0 remains fixed to 3.8. Version 0.5.1 accepts both models,
so failed optional context/version lookup can degrade to 3.1 without terminating
the session. Fresh tokens pick up a flag change; prefetched tokens can lag briefly.


### Latest PR validation (2026-09-21)

The full native suite now passes **740 tests**; Flutter analysis is clean.
Android debug APK and iOS simulator debug builds pass. Backend has **132 passing
tests**, shared has **155**, and workspace TypeScript passes. Earlier counts
above describe earlier checkpoints, not the current PR head.

The updated APK was installed on the Pixel 8 Pro. A new permission-flow check
was started but not completed before the user redirected validation to web;
this is not evidence of a passed first-grant or listening test. Physical iOS,
Bluetooth/call interruption, degraded-network startup speech, and financial-write
reconnect checks remain unverified on this revision. The earlier native smoke
results above apply to their original revision.
