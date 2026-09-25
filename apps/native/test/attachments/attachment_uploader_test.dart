import 'dart:convert';
import 'dart:typed_data';

import 'package:app/attachments/attachment_preparer.dart';
import 'package:app/attachments/attachment_types.dart';
import 'package:app/attachments/attachment_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _pdf = PreparedAttachment(
  name: 'resumen.pdf',
  bytes: Uint8List.fromList([0x25, 0x50, 0x44, 0x46]),
  type: attachmentTypeForMime('application/pdf')!,
);

void main() {
  test('uploads with the resolved type and registers the storage id', () async {
    final calls = <({String name, Map<String, Object?> args})>[];
    final uploads = <http.Request>[];
    final uploader = AttachmentUploader(
      deviceId: 'device-1',
      mutation: (name, args) async {
        calls.add((name: name, args: args));
        return name.endsWith('generateUploadUrl')
            ? {'ok': true, 'uploadUrl': 'https://upload.test/x'}
            : {'ok': true, 'attachmentId': 'att1', 'kind': 'pdf'};
      },
      httpClient: MockClient((request) async {
        uploads.add(request);
        return http.Response(jsonEncode({'storageId': 'st1'}), 200);
      }),
    );

    final sent = await uploader.upload(_pdf);

    expect(
      sent,
      const SentAttachment(id: 'att1', name: 'resumen.pdf', kind: 'pdf'),
    );
    expect(uploads.single.headers['Content-Type'], 'application/pdf');
    expect(calls.map((c) => c.name), [
      'v1/attachments/mutations:generateUploadUrl',
      'v1/attachments/mutations:register',
    ]);
    expect(calls.last.args, {
      'storageId': 'st1',
      'name': 'resumen.pdf',
      'deviceId': 'device-1',
    });
  });

  test('maps server refusals and transport errors to failures', () async {
    Future<AttachmentFailure> failureFor({
      Object? urlResult,
      http.Client? client,
    }) async {
      final uploader = AttachmentUploader(
        deviceId: 'device-1',
        mutation: (_, _) async =>
            urlResult ?? {'ok': true, 'uploadUrl': 'https://upload.test/x'},
        httpClient: client ?? MockClient((_) async => http.Response('', 200)),
      );
      try {
        await uploader.upload(_pdf);
      } on AttachmentUploadException catch (error) {
        return error.failure;
      }
      throw StateError('upload unexpectedly succeeded');
    }

    expect(
      await failureFor(urlResult: {'ok': false, 'error': 'rate_limited'}),
      AttachmentFailure.rateLimited,
    );
    expect(
      await failureFor(urlResult: {'ok': false, 'error': 'feature_disabled'}),
      AttachmentFailure.unavailable,
    );
    expect(
      await failureFor(
        client: MockClient((_) async => throw http.ClientException('down')),
      ),
      AttachmentFailure.offline,
    );
    expect(
      await failureFor(
        client: MockClient((_) async => http.Response('nope', 500)),
      ),
      AttachmentFailure.failed,
    );
  });
}
