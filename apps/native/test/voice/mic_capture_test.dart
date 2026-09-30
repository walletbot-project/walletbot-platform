import 'package:app/voice/mic_capture.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const name = 'live.walletbot.app/pcm_audio/capture';
  const channel = MethodChannel(name);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'audio and meter share capture; stop cancels native input with listeners attached',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final mic = NativeEngineMicCapture();
      final stream = await mic.start();
      final audio = <Uint8List>[];
      final levels = <double>[];
      final first = stream.listen(audio.add);
      final second = mic.onAmplitudeDbfs(Duration.zero).listen(levels.add);
      await Future<void>.delayed(Duration.zero);
      await messenger.handlePlatformMessage(
        name,
        const StandardMethodCodec().encodeSuccessEnvelope(
          Uint8List.fromList([0, 64]),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['listen']);
      expect(audio.single, [0, 64]);
      expect(levels.single, closeTo(-6.02, 0.01));
      await mic.stop();
      expect(calls, ['listen', 'cancel']);
      await first.cancel();
      await second.cancel();
      await mic.dispose();
      await expectLater(mic.start(), throwsStateError);
    },
  );
}
