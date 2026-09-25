import 'package:app/attachments/attachment_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sends the question, device id and context, and forwards the result',
    () async {
      late Map<String, Object?> sentArgs;
      final reader = AttachmentReader(
        action: (name, args) async {
          expect(name, 'v1/attachments/actions:read');
          sentArgs = args;
          return {
            'ok': true,
            'answer': 'Total 18.870',
            'transactions': [],
            'warnings': [],
          };
        },
        deviceId: 'device-1',
        buildContext: () async => {'locale': 'es-AR'},
      );

      final result = await reader.read({
        'attachmentId': 'att1',
        'question': '¿Total?',
      });

      expect(result['answer'], 'Total 18.870');
      expect(sentArgs, {
        'attachmentId': 'att1',
        'question': '¿Total?',
        'deviceId': 'device-1',
        'context': {'locale': 'es-AR'},
      });
    },
  );

  test('never throws: a failed call or context becomes a tool error', () async {
    final reader = AttachmentReader(
      action: (_, _) async => throw StateError('offline'),
      deviceId: null,
      buildContext: () async => throw StateError('db closed'),
    );
    expect(
      await reader.read({'attachmentId': 'att1', 'question': 'x'}),
      AttachmentReader.failure,
    );
    expect(
      (await reader.read({'attachmentId': '', 'question': 'x'}))['ok'],
      isFalse,
    );
  });
}
