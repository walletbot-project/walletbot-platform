import 'dart:convert';

import 'package:app/app_config/client_info.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/feedback/feedback_submitter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _clientInfo = ClientInfo(
  platform: 'android',
  appVersion: '0.2.0',
  deviceId: 'device-1',
);

/// Records every mutation and answers from a queue of canned JSON responses,
/// decoded like the Convex client hands them to callers.
class _FakeConvex {
  _FakeConvex(this._responses);

  final List<String> _responses;
  final calls = <({String name, Map<String, Object?> args})>[];
  var _index = 0;

  Future<Object?> mutation(String name, Map<String, Object?> args) async {
    calls.add((name: name, args: args));
    return jsonDecode(_responses[_index++]);
  }
}

/// Answers every upload the way the storage endpoint refuses one.
class _RefusingHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    return http.StreamedResponse(const Stream.empty(), 500, request: request);
  }
}

/// Fails every upload the way a dropped connection does.
class _DisconnectedHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw http.ClientException('connection closed', request.url);
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
    expect(args.containsKey('localAccountId'), isFalse);
  });

  test(
    'resolves the local account before the first call and sends it',
    () async {
      final convex = _FakeConvex([
        '{"ok":true,"uploadUrl":"https://example.convex.cloud/upload/1"}',
        '{"ok":true}',
      ]);
      var callsWhenResolved = -1;

      await FeedbackSubmitter(
        clientInfo: _clientInfo,
        mutation: convex.mutation,
        httpClient: _FakeHttp(),
        resolveLocalAccountId: () async {
          callsWhenResolved = convex.calls.length;
          return 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
        },
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
      );

      // Before the upload URL too: a remote session that authenticates while
      // this waits gets the user's rate limit there instead of the device's.
      expect(callsWhenResolved, 0);
      expect(
        convex.calls.last.args['localAccountId'],
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      );
    },
  );

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

  test(
    "the client's own operation timeout is offline, not a failure",
    () async {
      // `ConvexClientConfig.defaultOperationTimeout` (30 s by default) is what
      // ends a call that never gets out, throwing `OperationTimeoutError`.
      // Nothing here adds a second deadline on top of it, so this is the
      // exception the submitter has to classify.
      final submitter = FeedbackSubmitter(
        clientInfo: _clientInfo,
        mutation: (name, args) => Future.error(
          OperationTimeoutError(
            functionName: name,
            phase: TimeoutPhase.operation,
            timeout: const Duration(seconds: 30),
            connectionStatus: ConnectionStatus.connecting,
          ),
        ),
        httpClient: _FakeHttp(),
      );

      await expectLater(
        submitter.submit(message: 'hi', attachments: const [], locale: 'en'),
        throwsA(
          isA<FeedbackException>()
              .having(
                (error) => error.failure,
                'failure',
                FeedbackFailure.offline,
              )
              .having(
                (error) => error.cause,
                'cause',
                isA<OperationTimeoutError>(),
              ),
        ),
      );
    },
  );

  test('a dropped upload is offline; a refused one is a failure', () async {
    Future<FeedbackFailure> failureFor(http.Client client) async {
      try {
        await FeedbackSubmitter(
          clientInfo: _clientInfo,
          mutation: _FakeConvex([
            '{"ok":true,"uploadUrl":"https://example.convex.cloud/upload/1"}',
          ]).mutation,
          httpClient: client,
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
        );
        fail('expected a FeedbackException');
      } on FeedbackException catch (error) {
        return error.failure;
      }
    }

    expect(await failureFor(_DisconnectedHttp()), FeedbackFailure.offline);
    expect(await failureFor(_RefusingHttp()), FeedbackFailure.failed);
  });
}
