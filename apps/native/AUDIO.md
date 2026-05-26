# Voice audio (Android)

How live-voice audio is wired on the native Android app, and why.

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

## Current configuration

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

## Notes

- iOS is not covered here — the `record` plugin manages its own
  `AVAudioSession`; verify separately if behavior diverges.
- If echo is still observed on specific devices that lack a working hardware
  AEC, the next step is to ship a software AEC (e.g. WebRTC AEC3 via a Flutter
  plugin) rather than half-duplexing the mic.
