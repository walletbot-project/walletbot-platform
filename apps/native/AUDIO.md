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

### Current configuration (working, no echo cancellation)

- **Playback** — [PcmAudioPlayer.swift](ios/Runner/PcmAudioPlayer.swift),
  registered on the `live.walletbot.app/pcm_audio` method channel from
  [AppDelegate.swift](ios/Runner/AppDelegate.swift). Plain `AVAudioEngine`
  + `AVAudioPlayerNode` (NO voice processing); 24 kHz mono PCM16 in,
  converted to Float32 and scheduled on the node (non-blocking — no
  generation counter needed, unlike Android's blocking `AudioTrack.write`).
  `interrupt` maps to `AVAudioPlayerNode.stop()`, which per
  `AVAudioPlayerNode.h` clears *all* scheduled buffers including the one
  mid-play, then `play()` re-arms the node.
- **Capture** — the `record` plugin, same as Android, but with
  `echoCancel: false` on iOS (platform-dependent field in `voice.dart`'s
  `_recordConfig`) so it never enables Apple's voice-processing unit.
- **Session** — the Swift side owns the `AVAudioSession`:
  `.playAndRecord` + mode `.voiceChat` + `[.defaultToSpeaker,
  .allowBluetoothHFP, .allowBluetoothA2DP]` on `start`; deactivate + restore
  on `stop`. `record` is told to keep its hands off via
  `AudioRecorder.ios.manageAudioSession(false)` (called before
  `startStream`; ordering holds because `_command.start()` always precedes
  mic capture).
- **Permissions** — `permission_handler_apple` compiles the microphone
  strategy out unless `PERMISSION_MICROPHONE=1` is defined; it is set in the
  [Podfile](ios/Podfile) `post_install`. Without it, permission requests
  return denied without ever prompting.

### KNOWN ISSUE: no echo cancellation on iOS

The agent's speech can leak from the loudspeaker into the mic and Gemini
may treat it as a barge-in, interrupting the agent mid-sentence. This is
accepted for now because every configuration of Apple's voice-processing
I/O failed on a physical iPad (2026-08-07):

| Configuration | Result |
|---|---|
| `record` with `echoCancel: true` (VP on its own capture engine) + separate playback engine | vpio unit render-error loop (`auou/vpio/appl render err: -1` spam), agent audio **silent** |
| `record` with `echoCancel: false` + separate playback engine | **Works** — but speaker leaks into mic, agent barges in on itself (current state) |
| One engine, VP enabled, capture tap + playback inside it (the topology `AVAudioIONode.h` documents) | **Everything dead** — no input, no output. Root cause never diagnosed: the run ended before `[PcmAudio]` logs were captured |

If someone picks this up again (the unified-engine attempt was never
committed — it has to be rebuilt): enable
`inputNode.setVoiceProcessingEnabled(true)` before engine start, tap the
input node, convert to 16 kHz PCM16, and — critically — capture the
`[PcmAudio]` log sequence on-device to see which call dies, which is the
diagnosis that was never obtained. Alternatives if VP stays broken: a
software AEC (WebRTC AEC3 via a plugin), or half-duplex (mute mic
forwarding while agent audio plays — kills voice barge-in,
tap-to-interrupt keeps working).

## Notes

- If echo is still observed on specific devices that lack a working hardware
  AEC, the next step is to ship a software AEC (e.g. WebRTC AEC3 via a Flutter
  plugin) rather than half-duplexing the mic.
