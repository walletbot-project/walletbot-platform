import 'dart:convert';

import 'package:app/app_config/client_info.dart';
import 'package:app/feedback/feedback_submitter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _clientInfo = ClientInfo(
  platform: 'android',
  appVersion: '0.2.0',
  deviceId: 'device-1',
);

/// Records every mutation and answers from a queue of canned JSON responses.
class _FakeConvex {
  _FakeConvex(this._responses);

  final List<String> _responses;
  final calls = <({String name, Map<String, dynamic> args})>[];
  var _index = 0;

  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) async {
    calls.add((name: name, args: args));
    return _responses[_index++];
  }
}

/// Collects the streamed upload bodies, so a test can assert the bytes really
/// went to the upload URL and not through a Convex function.
class _FakeHttp extends http.BaseClient {
  final uploads = <List<int>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    uploads.add(await request.finalize().toBytes());
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"storageId":"kg2abc"}')),
      200,
      request: request,
    );
  }
}

void main() {
  test('uploads each attachment, then submits only the storage ids', () async {
    final convex = _FakeConvex([
      '{"ok":true,"uploadUrl":"https://example.convex.cloud/upload/1"}',
      '{"ok":true}',
    ]);
    final httpClient = _FakeHttp();

    await FeedbackSubmitter(
      clientInfo: _clientInfo,
      mutation: convex.mutation,
      httpClient: httpClient,
    ).submit(
      message: 'the totals are wrong',
      attachments: [
        FeedbackAttachment(
          name: 'shot.png',
          size: 3,
          openRead: () => Stream.value(const [1, 2, 3]),
        ),
      ],
      locale: 'es',
    );

    expect(convex.calls.map((call) => call.name), [
      'v1/feedback/mutations:generateAttachmentUploadUrl',
      'v1/feedback/mutations:submit',
    ]);
    expect(httpClient.uploads, [
      [1, 2, 3],
    ]);

    final args = convex.calls.last.args;
    expect(args['message'], 'the totals are wrong');
    expect(args['attachments'], [
      {'storageId': 'kg2abc', 'name': 'shot.png'},
    ]);
    // A local account has no identity, so this is what the server's rate
    // limiter keys on.
    expect(args['deviceId'], 'device-1');
  });

  test('a rate-limited upload URL never reaches the submit call', () async {
    final convex = _FakeConvex(['{"ok":false,"error":"rate_limited"}']);
    final httpClient = _FakeHttp();

    await expectLater(
      FeedbackSubmitter(
        clientInfo: _clientInfo,
        mutation: convex.mutation,
        httpClient: httpClient,
      ).submit(
        message: 'hi',
        attachments: [
          FeedbackAttachment(
            name: 'a.png',
            size: 1,
            openRead: () => Stream.value(const [1]),
          ),
        ],
        locale: 'en',
      ),
      throwsA(
        isA<FeedbackException>().having(
          (error) => error.failure,
          'failure',
          FeedbackFailure.rateLimited,
        ),
      ),
    );
    expect(httpClient.uploads, isEmpty);
    expect(convex.calls.length, 1);
  });

  test('server rejections map to the failure the sheet has copy for', () async {
    Future<FeedbackFailure> failureFor(String response) async {
      try {
        await FeedbackSubmitter(
          clientInfo: _clientInfo,
          mutation: _FakeConvex([response]).mutation,
          httpClient: _FakeHttp(),
        ).submit(message: 'hi', attachments: const [], locale: 'en');
        fail('expected a FeedbackException');
      } on FeedbackException catch (error) {
        return error.failure;
      }
    }

    expect(
      await failureFor('{"ok":false,"error":"rate_limited"}'),
      FeedbackFailure.rateLimited,
    );
    expect(
      await failureFor('{"ok":false,"error":"attachment_invalid"}'),
      FeedbackFailure.attachmentRejected,
    );
    expect(
      await failureFor('{"ok":false,"error":"something new"}'),
      FeedbackFailure.failed,
    );
  });
}
