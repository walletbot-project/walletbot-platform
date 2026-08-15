import 'package:flutter/services.dart';

class PcmAudioPlayer {
  static const _channel = MethodChannel('live.walletbot.app/pcm_audio');

  bool _started = false;

  /// Starts native playback. On iOS the platform side returns a diagnostics
  /// map (voice-processing state, session formats, route) that callers
  /// should surface into the session event log; Android returns null.
  Future<Map<String, Object?>?> start({int sampleRate = 24000}) async {
    if (_started) return null;
    final diagnostics = await _channel.invokeMethod<Map<Object?, Object?>>(
      'start',
      {'sampleRate': sampleRate},
    );
    _started = true;
    return diagnostics?.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> enqueue(Uint8List pcm16Bytes) async {
    if (!_started || pcm16Bytes.isEmpty) return;
    await _channel.invokeMethod<void>('enqueue', pcm16Bytes);
  }

  Future<void> interrupt() async {
    if (!_started) return;
    await _channel.invokeMethod<void>('interrupt');
  }

  Future<void> stop() async {
    if (!_started) return;
    await _channel.invokeMethod<void>('stop');
    _started = false;
  }
}
