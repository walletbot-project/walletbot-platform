import 'dart:async';
import 'package:app/voice/pcm_audio_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/pcm');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'interrupt invalidates queued chunks before crossing platform boundary',
    () async {
      final calls = <String>[];
      final starting = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'start') await starting.future;
        return null;
      });
      final player = PcmAudioPlayer(channel: channel);
      final start = player.start();
      await Future<void>.delayed(Duration.zero);
      final audio = player.enqueue(Uint8List(2));
      final interrupt = player.interrupt();
      starting.complete();
      await start;
      await audio;
      await interrupt;
      expect(calls, ['start', 'interrupt']);
      await player.enqueue(Uint8List(2));
      await player.stop();
      expect(calls, ['start', 'interrupt', 'enqueue', 'stop']);
    },
  );

  test(
    'stop during startup releases native resource when startup finishes',
    () async {
      final calls = <String>[];
      final starting = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'start') await starting.future;
        return null;
      });
      final player = PcmAudioPlayer(channel: channel);
      final start = player.start();
      await Future<void>.delayed(Duration.zero);
      final stop = player.stop();
      starting.complete();
      await start;
      await stop;
      await player.enqueue(Uint8List(2));
      expect(calls, ['start', 'stop']);
    },
  );
}
