# Web Live integration

Web uses Google's official `@google/genai` SDK (the existing dependency), with
`Session.sendRealtimeInput`, `sendClientContent`, and `sendToolResponse`. There
is no custom WebSocket protocol implementation. The small `gemini-live.ts`
adapter waits for `setupComplete`, bounds setup to 20 seconds, and closes a
connection that finishes after cancellation. The installed SDK resolves
`live.connect()` after sending setup, before the server acknowledges it.

The backend selects the model and returns it with the constrained ephemeral
token. Updated web requests advertise capability version `0.5.1`. They default
to `gemini-3.8-live`; `agentGemini31` selects
`gemini-3.1-flash-live-preview`. Existing cached web clients (`0.0.0`) retain
3.1. Global and per-user overrides are resolved on the backend. A flag change
applies at the next token mint, including reconnect; existing sockets continue
with their original model. Deploy the backend before the updated web build.
Neither model requires a different browser audio architecture.

## Audio and lifecycle

- Capture opens from the microphone gesture alongside connection setup. A
  five-second PCM16/16 kHz buffer preserves speech before setup completes. It
  flushes once after context seeding. Overflow stops capture and discards the
  whole buffer with an error, rather than sending a truncated utterance.
- Mute, End, navigation away, and hidden-tab cleanup release microphone tracks.
  Late permission results are stopped; a cancelled request cannot resurrect
  capture or block a replacement request.
- Playback uses standard Web Audio `AudioBufferSourceNode` scheduling at
  24 kHz. Interruption stops scheduled sources. The queue is capped at 20
  seconds. The old custom playback worklet is removed. Capture retains its
  small worklet because microphone PCM streaming needs audio-thread delivery.
- The selected microphone is saved in `localStorage` as a device preference.
  Reload does not restore recording. A missing device can fall back to the
  browser default; denied/unavailable storage does not block selection.
- Text-only starts do not request microphone permission or open playback.
- Google owns protocol serialization; the hook still owns application reconnect
  policy, transcript context seeding, and UI state. Tools execute serially;
  duplicate call IDs are ignored within a connection, cancelled queued work is
  skipped, and stale sockets receive no tool responses. A tool already writing
  data can finish, and its result is recorded in its original conversation.
  Reconnect context includes tool arguments and recorded results after waiting
  for executing tools. This reduces blind replay but does not promise
  exactly-once writes across independent reconnects.

## Metrics

Every usage event carries the model of the socket that produced it. The history
uploader identifies new web batches with `source: 'web'`. The backend derives
cost samples in the same transaction that deduplicates history event IDs, so a
retried upload does not count usage twice. Native uploads retain their separate
metrics path.

Each usage report contributes its own token counts; it is not subtracted from
the previous generation. Backend pricing computes estimated cost for the
reported model and modalities. Turn-complete events produce completion counts;
usage events produce cost samples and feed the existing usage aggregation.
There is no new web final-session cost gauge. Model changes within a conversation
retain separate model labels on individual samples.

The history outbox remains in memory with retries. Closing/crashing the browser
can lose its unsent tail, so this is operational telemetry, not a billing ledger.
The native per-generation accounting correction is documented in
[the native notes](gemini-3.8-native.md#telemetry-audit-follow-up).

## Verification and remaining checks

Automated coverage includes setup readiness/cancellation/timeout for both model
IDs, PCM encoding, playback bounds/interruption, startup buffering and overflow,
late permission cancellation, silent text, combined protocol messages, tool
serialization/cancellation, backend model selection and per-model pricing, and
transactional upload deduplication. Web production build, TypeScript, ESLint,
and backend TypeScript/tests are checked locally.

Local validation: **31 web tests, 132 backend tests, and 155 shared tests**
passed, along with workspace TypeScript, web ESLint, and the production build.

An authenticated Chrome session at `http://localhost:5173` completed a real
Gemini 3.8 calculator turn (`123 × 456 → 56,088`). The corresponding development
backend usage sample and completion metric carried `gemini-3.8-live`, web source,
and text mode. Actual microphone capture connected successfully; selecting a
different microphone, reloading, and starting again retained that selection.
Reload left recording off, and the mute control stopped capture in the UI.
The original microphone selection was restored after testing.

A separate Chrome smoke check exercised actual Web Audio playback scheduling,
interruption, close/reopen, and capture-worklet delivery of 512 samples at 16 kHz
with synthetic audio. This is not a spoken-turn listening check. Backend changes
were synced only to the development deployment. Production was not deployed.
A live 3.1 rollback check remains outstanding: the signed-in development account
has no feature-flag admin access. Automated selection/SDK tests cover both models.

Before release, use an authenticated browser to test a real spoken turn starting
immediately after the tap, interrupt playback, mute during permission/setup,
leave and return to the Add page, reconnect, and run a text turn. Repeat with
`agentGemini31` enabled. Check persisted usage samples for each exact model and
confirm retrying a batch does not increase its sample count. Check Safari/iOS
microphone permission and playback activation separately from desktop Chrome.

References: [Google SDK](https://github.com/googleapis/js-genai),
[Live usage metadata](https://ai.google.dev/api/live#UsageMetadata).
