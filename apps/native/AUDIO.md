# Native AI and audio

The native app uses Gemini 3.8 Live for both spoken and typed conversations.
The UI and local financial tools retain their existing contracts. Connection,
credential, tool-dispatch and audio responsibilities have separate owners.

## Ownership

| Layer | Responsibility |
| --- | --- |
| `gemini_voice_command_factory.dart` | Active conversation, one-use token prefetch, restorable history |
| `live_token_provider.dart` | Constrained backend tokens, refusal handling, model compatibility |
| `live_connection.dart` | Socket readiness, setup handshake, connection epochs, retry and GoAway rotation |
| `live_protocol.dart` | Gemini wire messages and PCM validation |
| `live_tool_dispatcher.dart` | Ordered local execution, duplicate call IDs, cancellation, connection-scoped responses |
| `gemini_voice_expense_command.dart` | Conversation events, durable history, metrics and orchestration |
| `voice_event_log.dart` | Persisted event encoding and binary-data redaction |
| `pcm_audio_player.dart` | Ordered platform calls, immediate invalidation of queued speech |
| `mic_capture.dart` | One native capture subscription shared by audio and level listeners |
| Android `VoiceAudioEngine.kt` | AudioRecord, AudioTrack, audio focus, communication routing and effects |
| iOS `PcmAudioPlayer.swift` | AVAudioSession, one AVAudioEngine, voice-processing capture and playback |

## Connection rules

A connection waits for both WebSocket readiness and Gemini `setupComplete`.
Each attempt has an epoch, invalidated immediately by disconnect or close.
Late credential completions and tool results cannot resurrect a closed socket.

Only bounded intentional text input waits through reconnects. Microphone chunks
and old tool responses are discarded when disconnected. Replaying several
seconds of stale speech can create unintended turns; replaying tool responses
into a fresh session can misrepresent the status of a financial operation.

Reconnects open a fresh server session and seed it from the durable transcript,
including committed tool outcomes. The seed waits for already-started local
tools and log writes to settle. Resume handles remain freshness markers for the
existing two-hour history policy; they are not presented to Google. This retains
the repository's previous recovery behavior instead of assuming that an old
server handle includes the latest local writes.

Local tool execution is serialized across messages. A duplicate call ID is
executed once per connection; cancelled queued calls never execute. Cancellation
cannot undo an already-committed write: its result is still logged, while the
cancelled/stale network response is suppressed. This does not claim cross-session
exactly-once semantics for a model issuing a new call ID after a disconnect.

## Audio contract

- Input: signed little-endian PCM16, mono, 16 kHz, approximately 100 ms chunks.
- Output: signed little-endian PCM16, mono, 24 kHz.
- Native playback queues are capped at 20 seconds and report overflow.
- Interruption invalidates pending Dart chunks and clears the native queue.
- Muting playback flushes audio already queued, not just future chunks.
- Backgrounding stops microphone capture and releases native audio/focus; foregrounding
  restores capture only when the microphone was previously on.
- Capture errors stop the UI's microphone state rather than leaving a dead mic
  displayed as recording.

### Android

`VoiceAudioEngine` owns both directions. It uses `MODE_IN_COMMUNICATION`,
`USAGE_VOICE_COMMUNICATION` and a `VOICE_COMMUNICATION` recording source, with
`AcousticEchoCanceler` and `NoiseSuppressor` when available. It requests transient
audio focus and reports focus loss to capture listeners. Communication headsets
are preferred; the speaker is the default when no headset is available.

Playback writes run on a dedicated handler thread in 20 ms pieces. Capture has
its own blocking-read thread. Generation counters fence both queues, and stop
unblocks threads before releasing audio resources. Previous routing and mode
are restored on teardown. `MainActivity` only registers/disposes the engine.

The `record` plugin remains a desktop fallback and does not run on Android/iOS.

### iOS

Silent text sessions acquire no audio device. Audible output starts playback
only and does not acquire microphone input.
After the UI grants permission, attaching the capture listener rebuilds the
graph as one voice-processing engine. Capture and playback must share that
engine so the echo canceller has the actual far-end output as its reference.

Duplex uses `.playAndRecord` / `.voiceChat`, speaker default and Bluetooth HFP.
The input tap is installed before starting the engine and resampled to 16 kHz
with a persistent converter. Voice-processing failure is surfaced instead of
silently starting echo-prone full-duplex audio. Route changes rebuild stopped
graphs and converters. OS interruptions report capture failure and release the
session. Cancelling capture returns to playback-only mode.

Native buffers and capture callbacks are generation-scoped. Old callbacks cannot
feed a replacement capture session. Playback completion tracks the bounded queue.
The session category and mode are restored on teardown.

## Model rollout

`packages/shared/src/tools/constants.ts` generates the native model constant.
Native version 0.5.0+ is minted `gemini-3.8-live`; older native versions and the
existing web integration retain `gemini-3.1-flash-live-preview`. Deploy the backend
before distributing the new native build. A mismatched token model fails clearly
instead of retrying a permanently incompatible setup.

The mobile app uses constrained short-lived tokens, never a bundled Google API
key. The development-only `GEMINI_LIVE_TOKEN` override must itself be constrained
with the app's instructions and tools.

See [the research and migration notes](../../docs/gemini-3.8-native.md) for model
choices, primary sources, verification and remaining device coverage.
