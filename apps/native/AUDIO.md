# Voice audio (Android & iOS)

How live-voice audio is wired on the native apps, and why.

## The problem

While the AI was speaking through the loudspeaker, the microphone was capturing
that playback and re-sending it to Gemini Live. Gemini transcribed it as user
speech, marked it as a barge-in, and cut the AI off mid-sentence.

The same code path worked perfectly on the **web app on the same device**.

## Why the web "just works" but native didn't

Chrome's WebRTC stack runs its own software AEC (AEC3) over the played PCM and
captured PCM in user space — fully independent of the OS audio framework.

Android only engages `AcousticEchoCanceler` when **both halves** of the audio
loop are explicitly set to the "phone call" configuration:

- **Output** must use `USAGE_VOICE_COMMUNICATION` while
  `AudioManager.mode == MODE_IN_COMMUNICATION`.
- **Input** must be captured with `MediaRecorder.AudioSource.VOICE_COMMUNICATION`
  (the matching capture source).

If only one half is in comm mode, AEC is not engaged. If neither is, there is
no system AEC at all — every loudspeaker sample leaks straight into the mic.

## Android

### Playback — [MainActivity.kt](android/app/src/main/kotlin/live/walletbot/app/MainActivity.kt)

On `start`, before creating the `AudioTrack`:

1. Save previous `AudioManager.mode` and `isSpeakerphoneOn` state.
2. Set `AudioManager.mode = MODE_IN_COMMUNICATION`.
3. Force loudspeaker via `setCommunicationDevice(BUILTIN_SPEAKER)` on API 31+,
   falling back to `isSpeakerphoneOn = true`.

The `AudioTrack` is built with:

- `USAGE_VOICE_COMMUNICATION`
- `CONTENT_TYPE_SPEECH`
- 24 kHz mono PCM16, streaming mode

On `stop`, mode and routing are restored to what they were before.

### Capture — [voice.dart](lib/screens/voice.dart)

`RecordConfig` for the `record` plugin:

- `encoder: pcm16bits`, 16 kHz mono
- `echoCancel: true`, `noiseSuppress: true`, `autoGain: false`
- `androidConfig.audioSource: voiceCommunication` (the key bit — must match
  the playback's comm-stream so the platform AEC can link them)

## Things we tried that did not work

| Capture source     | Output usage              | Result                                                |
|--------------------|---------------------------|-------------------------------------------------------|
| `mic` (default)    | `VOICE_COMMUNICATION`     | Involuntary barge-in from speaker leak                |
| `voiceRecognition` | `VOICE_COMMUNICATION`     | Suppressed real user speech during playback           |
| `voiceRecognition` | `MEDIA` (no comm mode)    | Severe loopback — AI's own speech transcribed as user |
| `voiceCommunication` | `VOICE_COMMUNICATION` | Works — platform AEC engages                            |

## iOS

### Current configuration (unified engine + voice processing — PENDING hardware verification)

One `AVAudioEngine` does BOTH playback and capture, with Apple's
voice-processing I/O (echo cancellation) enabled on it — the same
"phone call" pairing Android gets from comm-mode AEC. Rebuilt 2026-08-07
following Apple's "Using voice processing" sample (AVEchoTouch), WebRTC's
iOS ADM, and LiveKit's AVAudioEngine ADM. **Not yet verified on hardware**
— a previous unified-engine attempt died undiagnosed (table below); this
rebuild instruments every step so the next failure is diagnosable.

- **Engine** — [PcmAudioPlayer.swift](ios/Runner/PcmAudioPlayer.swift),
  registered from [AppDelegate.swift](ios/Runner/AppDelegate.swift).
  Call sequence (order is load-bearing, sources in the header doc):
  session configured + activated → `setVoiceProcessingEnabled(true)` on a
  fresh stopped engine before any wiring → formats re-read AFTER the VP
  switch (it changes them) + zero-rate guard with explicit fallback to
  non-VP → player→mixer and mixer→output connected explicitly at the
  24 kHz voiceIO format → input tap installed BEFORE `engine.start()`
  (the record_ios sequence, proven to capture on this hardware) →
  start retried up to 5× (VPIO fails transiently with undocumented
  -66635/-66637) → engine restarted on `AVAudioEngineConfigurationChange`.
  AGC left enabled: WebRTC force-enables it citing all-zero recordings
  with it off — the failed attempt had disabled it.
- **Playback** — `live.walletbot.app/pcm_audio` method channel
  (start/enqueue/interrupt/stop), 24 kHz mono PCM16 in, converted to
  Float32 and scheduled non-blocking; `interrupt` =
  `AVAudioPlayerNode.stop()` (flushes all scheduled buffers) + `play()`.
- **Capture** — `live.walletbot.app/pcm_audio/capture` EventChannel:
  the engine's input tap converted to 16 kHz mono PCM16 (Gemini's wire
  format). Dart side: `IosEngineMicCapture` in
  [mic_capture.dart](lib/voice/mic_capture.dart); every other platform
  keeps the `record` plugin (`RecordMicCapture`). The `record` plugin must
  NOT run on iOS — its own engine fights the voice-processing unit.
- **Session** — Swift-owned: `.playAndRecord` + `.voiceChat` +
  `[.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]`,
  preferred rate 24 kHz (the voiceIO/graph rate, per Apple's sample),
  20 ms IO buffer (WebRTC's choice); deactivate + restore on stop.
- **Diagnostics** — `start` returns a map (VP state, `vpFallback` reason,
  formats, route, rates) that Dart emits as a `VoiceSystemEvent`, so it is
  persisted in the voice-session event log and inspectable WITHOUT a
  console. Full `[PcmAudio]` NSLog trail on-device: session state, post-VP
  formats, per-50-chunk playback state, per-100-chunk capture peak levels
  (zero peaks = dead mic), config-change transitions.
- **Permissions** — `permission_handler_apple` compiles the microphone
  strategy out unless `PERMISSION_MICROPHONE=1` is defined; it is set in
  the [Podfile](ios/Podfile) `post_install`. Without it, permission
  requests return denied without ever prompting.

### History: earlier configurations that failed on hardware (2026-08-07, physical iPad)

| Configuration | Result |
|---|---|
| `record` with `echoCancel: true` (VP on its own capture engine) + separate playback engine | vpio unit render-error loop (`auou/vpio/appl render err: -1` spam), agent audio **silent** |
| `record` with `echoCancel: false` + separate playback engine | Audio worked both ways, but **no echo cancellation** — speaker leaked into mic, agent barged in on itself |
| One engine, VP enabled (first unified attempt) | **Everything dead** — no input, no output; zero logs captured, root cause never diagnosed |

Deltas between that dead unified attempt and the current rebuild, each
one a guard some production stack considers load-bearing: AGC was
disabled (WebRTC: zero-recording reports), tap was installed on a
RUNNING engine with `outputFormat(forBus: 0)` read before VP settled
(Apple sample and record_ios install before start), mixer→output was
left to the implicit connection (Apple sample connects it explicitly),
no preferred session rate, no start retry, no restart on
configuration-change (LiveKit rebuilds; a naive engine stays silently
stopped).

If audio dies again: read the `Voice engine: {...}` system event in the
session log first (`vpFallback` tells you if/why VP was rejected), then
capture the `[PcmAudio]` Console.app trail. Fallback if VPIO proves
genuinely broken on this hardware: software AEC (WebRTC AEC3 via a
native plugin). Half-duplex was evaluated and REJECTED — interrupting
the agent by voice is a product requirement.

## Notes

- If echo is still observed on specific devices that lack a working hardware
  AEC, the next step is to ship a software AEC (e.g. WebRTC AEC3 via a Flutter
  plugin) rather than half-duplexing the mic.
