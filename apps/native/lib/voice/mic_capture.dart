import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// Mobile capture and playback share one native audio session and route.
/// The record plugin is only the desktop fallback; it never owns a second
/// mobile audio session or competes for audio focus.
abstract class MicCapture {
  /// 16 kHz mono PCM16 — the wire format Gemini Live expects.
  static const sampleRate = 16000;

  factory MicCapture.forPlatform() {
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      return NativeEngineMicCapture();
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

/// Desktop capture fallback.
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
    // The plugin pauses capture on ANY audio-focus loss — a notification
    // sound is enough — and its default mode (`pause`) never resumes it,
    // leaving the mic silently dead. `pauseResume` resumes capture when
    // focus returns (see record_android AudioRecorder.requestAudioFocus).
    audioInterruption: AudioInterruptionMode.pauseResume,
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

/// Exactly one EventChannel subscription owns capture. Audio and level
/// listeners share its broadcast stream; stop/dispose cancel the native input
/// even if a caller forgets to cancel its own subscription.
class NativeEngineMicCapture implements MicCapture {
  static const _events = EventChannel('live.walletbot.app/pcm_audio/capture');
  StreamController<Uint8List>? _controller;
  StreamSubscription<dynamic>? _native;
  bool _disposed = false;

  @override
  Future<MicCaptureIssue?> checkAvailability() async => null;

  @override
  Future<Stream<Uint8List>> start() async {
    if (_disposed) throw StateError('Microphone disposed');
    if (_controller != null) return _controller!.stream;
    final controller = StreamController<Uint8List>.broadcast();
    _controller = controller;
    _native = _events.receiveBroadcastStream().listen(
      (dynamic event) {
        if (!identical(_controller, controller)) return;
        if (event is Uint8List && event.length.isEven) {
          controller.add(event);
        } else {
          controller.addError(
            const FormatException('Invalid microphone PCM16'),
          );
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_controller, controller)) {
          controller.addError(error, stack);
        }
      },
      onDone: () {
        if (identical(_controller, controller)) {
          controller.addError(StateError('Microphone stream closed'));
        }
      },
    );
    return controller.stream;
  }

  @override
  Stream<double> onAmplitudeDbfs(Duration interval) {
    final controller = _controller;
    if (controller == null) throw StateError('Start microphone first');
    final timer = Stopwatch()..start();
    return controller.stream
        .where((_) {
          if (timer.elapsed < interval) return false;
          timer.reset();
          return true;
        })
        .map(_peakDbfs);
  }

  @override
  Future<void> stop() async {
    final native = _native;
    final controller = _controller;
    _native = null;
    _controller = null;
    await native?.cancel();
    await controller?.close();
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }

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
