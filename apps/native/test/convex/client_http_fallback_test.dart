import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/convex/values.dart';

import 'helpers/fake_convex_server.dart';

class PosterScript {
  final List<(Uri, Map<String, String>, String)> calls = [];
  HttpPostResponse? response;
  Object? throwWith;
  Completer<HttpPostResponse>? gate;

  Future<HttpPostResponse> call(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) {
    calls.add((uri, headers, body));
    final error = throwWith;
    if (error != null) return Future.error(error);
    final pending = gate;
    if (pending != null) return pending.future;
    return Future.value(
      response ??
          const HttpPostResponse(200, '{"status":"success","value":null}'),
    );
  }
}

void main() {
  test('query falls back to POST /api/query while the socket is not ready', () {
    fakeAsync((fake) {
      final poster = PosterScript()
        ..response = HttpPostResponse(
          200,
          jsonEncode({
            'status': 'success',
            'value': convexToJson(BigInt.from(31)),
          }),
        );
      final server = FakeConvexServer()..hangNext = 100;
      final h = makeClient(fake, server: server, httpPoster: poster.call);
      final probe = FutureProbe(
        h.client.query<BigInt>('v1/sync/queries:getCounter', {
          'since': BigInt.from(4),
        }, options: const CallOptions(httpFallback: HttpFallback.whenNotReady)),
      );
      fake.flushMicrotasks();
      expect(probe.isDone, isTrue);
      expect(probe.value, BigInt.from(31));
      final (uri, headers, body) = poster.calls.single;
      expect(uri.path, '/api/query');
      expect(uri.host, 'fake.convex.cloud');
      expect(headers['Convex-Client'], 'dart-test-0.0.0');
      expect(headers.containsKey('Authorization'), isFalse);
      expect(jsonDecode(body), {
        'path': 'v1/sync/queries:getCounter',
        'format': 'convex_encoded_json',
        'args': [
          {'since': convexToJson(BigInt.from(4))},
        ],
      });
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('action falls back to POST /api/action and carries the auth token', () {
    fakeAsync((fake) {
      final poster = PosterScript()
        ..response = const HttpPostResponse(
          200,
          '{"status":"success","value":"live-token"}',
        );
      final server = FakeConvexServer()..hangNext = 100;
      final h = makeClient(fake, server: server, httpPoster: poster.call);
      final jwt = makeJwt();
      h.client.setAuth(fetchToken: ({required bool forceRefresh}) async => jwt);
      fake.flushMicrotasks();
      final probe = FutureProbe(
        h.client.action<String>(
          'v1/live/actions:requestLiveToken',
          {},
          options: const CallOptions(httpFallback: HttpFallback.whenNotReady),
        ),
      );
      fake.flushMicrotasks();
      expect(probe.value, 'live-token');
      final (uri, headers, _) = poster.calls.single;
      expect(uri.path, '/api/action');
      expect(headers['Authorization'], 'Bearer $jwt');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('no fallback when the socket is ready: the call goes over the wire', () {
    fakeAsync((fake) {
      final poster = PosterScript();
      final h = makeClient(fake, httpPoster: poster.call);
      final conn = h.server.latest;
      final probe = FutureProbe(
        h.client.action<Object?>(
          'a:f',
          {},
          options: const CallOptions(httpFallback: HttpFallback.whenNotReady),
        ),
      );
      fake.flushMicrotasks();
      expect(poster.calls, isEmpty);
      expect(conn.ofType('Action'), hasLength(1));
      conn.respondToAction(0, 'ws');
      fake.flushMicrotasks();
      expect(probe.value, 'ws');
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('an error envelope becomes ConvexFunctionError with decoded '
      'errorData', () {
    fakeAsync((fake) {
      final poster = PosterScript()
        ..response = HttpPostResponse(
          560,
          jsonEncode({
            'status': 'error',
            'errorMessage': 'Uncaught ConvexError: nope',
            'errorData': {'retryAfter': convexToJson(BigInt.from(60))},
          }),
        );
      final server = FakeConvexServer()..hangNext = 100;
      final h = makeClient(fake, server: server, httpPoster: poster.call);
      final probe = FutureProbe(
        h.client.query<Object?>(
          'q:f',
          {},
          options: const CallOptions(httpFallback: HttpFallback.whenNotReady),
        ),
      );
      fake.flushMicrotasks();
      final error = probe.error as ConvexFunctionError;
      expect(error.errorMessage, 'Uncaught ConvexError: nope');
      expect(error.errorData, {'retryAfter': BigInt.from(60)});
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('transport failures and non-JSON bodies become ConnectionLostError', () {
    fakeAsync((fake) {
      final poster = PosterScript()..throwWith = Exception('DNS failure');
      final server = FakeConvexServer()..hangNext = 100;
      final h = makeClient(fake, server: server, httpPoster: poster.call);
      final first = FutureProbe(
        h.client.query<Object?>(
          'q:f',
          {},
          options: const CallOptions(httpFallback: HttpFallback.whenNotReady),
        ),
      );
      fake.flushMicrotasks();
      expect(first.error, isA<ConnectionLostError>());

      poster
        ..throwWith = null
        ..response = const HttpPostResponse(502, '<html>Bad Gateway</html>');
      final second = FutureProbe(
        h.client.query<Object?>(
          'q:f',
          {},
          options: const CallOptions(httpFallback: HttpFallback.whenNotReady),
        ),
      );
      fake.flushMicrotasks();
      expect(second.error, isA<ConnectionLostError>());
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });

  test('the operation timeout bounds a hung fallback request', () {
    fakeAsync((fake) {
      final poster = PosterScript()..gate = Completer<HttpPostResponse>();
      final server = FakeConvexServer()..hangNext = 100;
      final h = makeClient(fake, server: server, httpPoster: poster.call);
      final probe = FutureProbe(
        h.client.query<Object?>(
          'q:f',
          {},
          options: const CallOptions(
            httpFallback: HttpFallback.whenNotReady,
            operationTimeout: Duration(seconds: 3),
          ),
        ),
      );
      fake.elapse(const Duration(seconds: 3));
      final error = probe.error as OperationTimeoutError;
      expect(error.phase, TimeoutPhase.operation);
      h.client.dispose();
      fake.flushMicrotasks();
    });
  });
}
