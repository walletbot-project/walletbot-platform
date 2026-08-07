import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// Why the mic capture path is per-platform.
///
/// On Android (and every other platform) capture goes through the `record`
/// plugin. On iOS it must NOT: echo cancellation there is Apple's
/// voice-processing I/O unit, and it only works when capture and playback
/// run inside the SAME AVAudioEngine — the far-end audio played through the
/// engine's output is the AEC reference. `record` runs its own engine, so
/// with `echoCancel: true` its voice-processing unit conflicted with the
/// separate playback engine (`auou/vpio/appl render err: -1` loop, silent
/// agent), and with `echoCancel: false` the speaker leaked into the mic and
/// the agent barged in on itself. See AUDIO.md § iOS.
///
/// The iOS implementation therefore streams mic audio from the same native
/// engine that plays the agent audio (PcmAudioPlayer.swift), which means the
/// voice session's playback (`PcmAudioPlayer.start` in Dart, done by
/// `_command.start()`) must be running before [start] is called.
abstract class MicCapture {
  /// 16 kHz mono PCM16 — the wire format Gemini Live expects.
  static const sampleRate = 16000;

  factory MicCapture.forPlatform() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return IosEngineMicCapture();
    }
    return RecordMicCapture();
  }

  /// Post-permission sanity checks for this capture backend. Assumes the
  /// microphone permission was already requested via permission_handler.
  Future<MicCaptureIssue?> checkAvailability();

  /// Starts capture and returns the 16 kHz mono PCM16 chunk stream.
  Future<Stream<Uint8List>> start();

  /// Peak amplitude in dBFS (0 is full scale, -160 is silence), emitted
  /// roughly at [interval].
  Stream<double> onAmplitudeDbfs(Duration interval);

  /// Stops capture. Safe to call when not capturing.
  Future<void> stop();

  Future<void> dispose();
}

enum MicCaptureIssue { permissionDenied, pcmUnsupported }

/// Capture via the `record` plugin — every platform except iOS.
class RecordMicCapture implements MicCapture {
  final AudioRecorder _recorder = AudioRecorder();

  static const _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: MicCapture.sampleRate,
    numChannels: 1,
    echoCancel: true,
    noiseSuppress: true,
    autoGain: false,
    streamBufferSize: 3200,
    androidConfig: AndroidRecordConfig(
      audioSource: AndroidAudioSource.voiceCommunication,
    ),
  );

  @override
  Future<MicCaptureIssue?> checkAvailability() async {
    final hasPermission = await _recorder.hasPermission(request: false);
    if (!hasPermission) return MicCaptureIssue.permissionDenied;
    final supportsPcm = await _recorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );
    if (!supportsPcm) return MicCaptureIssue.pcmUnsupported;
    return null;
  }

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(_config);

  @override
  Stream<double> onAmplitudeDbfs(Duration interval) =>
      _recorder.onAmplitudeChanged(interval).map((a) => a.current);

  @override
  Future<void> stop() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

/// Capture from the native voice engine (PcmAudioPlayer.swift) — iOS only.
///
/// Subscribing to [start]'s stream installs the mic tap on the engine
/// (EventChannel onListen); cancelling every subscription removes it
/// (onCancel). The engine itself is started/stopped by the playback side of
/// the channel, so capture requires an active voice session.
class IosEngineMicCapture implements MicCapture {
  static const _events = EventChannel('live.walletbot.app/pcm_audio/capture');

  Stream<Uint8List>? _chunks;

  @override
  Future<MicCaptureIssue?> checkAvailability() async {
    // Permission is handled by permission_handler before this point, and the
    // native engine always produces PCM16.
    return null;
  }

  @override
  Future<Stream<Uint8List>> start() async {
    final chunks = _events.receiveBroadcastStream().map(
      (dynamic event) => event as Uint8List,
    );
    _chunks = chunks;
    return chunks;
  }

  @override
  Stream<double> onAmplitudeDbfs(Duration interval) {
    final chunks = _chunks;
    if (chunks == null) {
      throw StateError('IosEngineMicCapture.start() must be called first');
    }
    // Chunks arrive at ~100 ms cadence already; derive the level from them
    // instead of asking the platform (record's formula: peak dBFS).
    return chunks.map(_peakDbfs);
  }

  @override
  Future<void> stop() async {
    // Nothing to do: cancelling the stream subscriptions triggers the
    // EventChannel's onCancel, which removes the native tap.
    _chunks = null;
  }

  @override
  Future<void> dispose() async {}

  static double _peakDbfs(Uint8List chunk) {
    if (chunk.length < 2) return -160;
    final data = ByteData.sublistView(chunk);
    var maxAbs = 0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = data.getInt16(i, Endian.little).abs();
      if (sample > maxAbs) maxAbs = sample;
    }
    if (maxAbs == 0) return -160;
    return 20 * math.log(maxAbs / 32767.0) / math.ln10;
  }
}
