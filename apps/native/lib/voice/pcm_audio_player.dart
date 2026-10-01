import 'dart:async';
import 'package:flutter/services.dart';

/// Orders platform calls and invalidates queued audio synchronously on mute,
/// interruption and stop. Native drivers own the bounded hardware queues.
class PcmAudioPlayer {
  PcmAudioPlayer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('live.walletbot.app/pcm_audio');

  final MethodChannel _channel;
  Future<void> _tail = Future.value();
  bool _started = false;
  bool _requested = false;
  int _generation = 0;

  Future<T> _serial<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, Object?>?> start({int sampleRate = 24000}) {
    _requested = true;
    return _serial(() async {
      if (!_requested || _started) return null;
      final diagnostics = await _channel.invokeMethod<Map<Object?, Object?>>(
        'start',
        {'sampleRate': sampleRate},
      );
      _started = true;
      return diagnostics?.map((key, value) => MapEntry(key.toString(), value));
    });
  }

  Future<void> enqueue(Uint8List bytes) {
    if (!_requested || bytes.isEmpty) return Future.value();
    if (bytes.length.isOdd) {
      return Future.error(const FormatException('Unaligned PCM16'));
    }
    final generation = _generation;
    return _serial(() async {
      if (!_started || !_requested || generation != _generation) return;
      await _channel.invokeMethod<void>('enqueue', bytes);
    });
  }

  Future<void> interrupt() {
    ++_generation;
    return _serial(() async {
      if (_started) await _channel.invokeMethod<void>('interrupt');
    });
  }

  Future<void> stop() {
    _requested = false;
    ++_generation;
    return _serial(() async {
      if (!_started) return;
      try {
        await _channel.invokeMethod<void>('stop');
      } finally {
        _started = false;
      }
    });
  }
}
