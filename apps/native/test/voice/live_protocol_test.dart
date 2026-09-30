import 'dart:convert';
import 'package:app/voice/live_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('3.8 setup omits unsupported thinking and affective options', () {
    final setup = LiveProtocol.setup()['setup'];
    expect(setup['model'], 'models/gemini-3.8-live');
    expect(setup['generationConfig']['responseModalities'], ['AUDIO']);
    expect(setup['generationConfig'].containsKey('thinkingConfig'), false);
    expect(setup.containsKey('proactivity'), false);
  });
  test('accepts PCM only and validates rate and sample alignment', () {
    Map<String, dynamic> part(String mime, List<int> bytes) => {
      'inlineData': {'mimeType': mime, 'data': base64Encode(bytes)},
    };
    expect(LiveProtocol.pcm(part('audio/pcm;rate=24000', [0, 1])), [0, 1]);
    expect(LiveProtocol.pcm(part('image/png', [0, 1])), isNull);
    expect(
      () => LiveProtocol.pcm(part('audio/pcm;rate=16000', [0, 1])),
      throwsFormatException,
    );
    expect(
      () => LiveProtocol.pcm(part('audio/pcm;rate=24000', [0])),
      throwsFormatException,
    );
  });
}
