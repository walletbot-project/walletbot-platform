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
