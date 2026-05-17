import 'package:flutter/services.dart';

class PcmAudioPlayer {
  static const _channel = MethodChannel('live.walletbot.app/pcm_audio');

  bool _started = false;

  Future<void> start({int sampleRate = 24000}) async {
    if (_started) return;
    await _channel.invokeMethod<void>('start', {'sampleRate': sampleRate});
    _started = true;
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
