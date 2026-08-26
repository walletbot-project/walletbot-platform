import 'dart:async';
import 'dart:io';

import 'package:app/app_config/client_info.dart';
import 'package:app/voice/agent_report_submitter.dart';
import 'package:flutter_test/flutter_test.dart';

const _clientInfo = ClientInfo(
  platform: 'android',
  appVersion: '0.3.1',
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

/// Throws the way a call that never got out does.
class _OfflineConvex {
  Future<String> mutation({
    required String name,
    required Map<String, dynamic> args,
  }) async => throw const SocketException('no route to host');
}

void main() {
  test('sends the flagged turn, its context and the client identity', () async {
    final convex = _FakeConvex(['{"ok":true}']);
    final submitter = AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation: convex.mutation,
    );

    await submitter.submit(
      reason: 'offensive',
      scope: AgentReportScope.response,
      locale: 'es-AR',
      note: 'it insulted me',
      reportedText: 'the reply',
      precedingUserText: 'the question',
      sessionId: 'session-1',
      model: 'gemini-live',
      occurredAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    expect(convex.calls, hasLength(1));
    final call = convex.calls.single;
    expect(call.name, 'v1/agentReports/mutations:submit');
    expect(call.args['reason'], 'offensive');
    expect(call.args['scope'], 'response');
    expect(call.args['note'], 'it insulted me');
    expect(call.args['reportedText'], 'the reply');
    expect(call.args['precedingUserText'], 'the question');
    expect(call.args['sessionId'], 'session-1');
    // The device id is what identifies a local-only account to the server's
    // rate limiter; without it those users could not report at all.
    expect(call.args['deviceId'], 'device-1');
    expect(call.args['platform'], 'android');
    expect(call.args['appVersion'], '0.3.1');
    expect(call.args['locale'], 'es-AR');
  });

  test('omits the empty optionals rather than sending blanks', () async {
    final convex = _FakeConvex(['{"ok":true}']);
    final submitter = AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation: convex.mutation,
    );

    await submitter.submit(
      reason: 'other',
      scope: AgentReportScope.session,
      locale: 'en',
      note: '',
      reportedText: '',
      sessionId: 'session-2',
    );

    final args = convex.calls.single.args;
    expect(args.containsKey('note'), isFalse);
    expect(args.containsKey('reportedText'), isFalse);
    expect(args.containsKey('precedingUserText'), isFalse);
    expect(args.containsKey('occurredAt'), isFalse);
    expect(args['scope'], 'session');
  });

  test('maps a rate limit to its own failure, so the copy can say so', () async {
    final convex = _FakeConvex(['{"ok":false,"error":"rate_limited"}']);
    final submitter = AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation: convex.mutation,
    );

    await expectLater(
      submitter.submit(
        reason: 'offensive',
        scope: AgentReportScope.response,
        locale: 'en',
        reportedText: 'the reply',
      ),
      throwsA(
        isA<AgentReportException>().having(
          (error) => error.failure,
          'failure',
          AgentReportFailure.rateLimited,
        ),
      ),
    );
  });

  test('maps every rejected-payload error to one invalid failure', () async {
    for (final error in const [
      'reason_invalid',
      'scope_invalid',
      'report_invalid',
    ]) {
      final convex = _FakeConvex(['{"ok":false,"error":"$error"}']);
      final submitter = AgentReportSubmitter(
        clientInfo: _clientInfo,
        mutation: convex.mutation,
      );

      await expectLater(
        submitter.submit(
          reason: 'offensive',
          scope: AgentReportScope.response,
          locale: 'en',
          reportedText: 'the reply',
        ),
        throwsA(
          isA<AgentReportException>().having(
            (thrown) => thrown.failure,
            'failure',
            AgentReportFailure.invalid,
          ),
        ),
      );
    }
  });

  test('an unknown server error falls back to a generic failure', () async {
    final convex = _FakeConvex(['{"ok":false,"error":"something_new"}']);
    final submitter = AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation: convex.mutation,
    );

    await expectLater(
      submitter.submit(
        reason: 'offensive',
        scope: AgentReportScope.response,
        locale: 'en',
        reportedText: 'the reply',
      ),
      throwsA(
        isA<AgentReportException>().having(
          (error) => error.failure,
          'failure',
          AgentReportFailure.failed,
        ),
      ),
    );
  });

  test('a call that never got out reads as offline, not as a rejection', () async {
    final submitter = AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation: _OfflineConvex().mutation,
    );

    await expectLater(
      submitter.submit(
        reason: 'dangerous',
        scope: AgentReportScope.response,
        locale: 'en',
        reportedText: 'the reply',
      ),
      throwsA(
        isA<AgentReportException>()
            .having(
              (error) => error.failure,
              'failure',
              AgentReportFailure.offline,
            )
            // The cause is the only forensic record of what the transport did.
            .having((error) => error.cause, 'cause', isA<SocketException>()),
      ),
    );
  });

  test('a timeout is the connection too', () async {
    final submitter = AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation:
          ({required String name, required Map<String, dynamic> args}) async =>
              throw TimeoutException('operation timed out'),
    );

    await expectLater(
      submitter.submit(
        reason: 'other',
        scope: AgentReportScope.session,
        locale: 'en',
      ),
      throwsA(
        isA<AgentReportException>().having(
          (error) => error.failure,
          'failure',
          AgentReportFailure.offline,
        ),
      ),
    );
  });

  test('an unreadable response shape is a failure, not a silent success', () async {
    final convex = _FakeConvex(['"not an object"']);
    final submitter = AgentReportSubmitter(
      clientInfo: _clientInfo,
      mutation: convex.mutation,
    );

    await expectLater(
      submitter.submit(
        reason: 'other',
        scope: AgentReportScope.session,
        locale: 'en',
      ),
      throwsA(
        isA<AgentReportException>().having(
          (error) => error.failure,
          'failure',
          AgentReportFailure.failed,
        ),
      ),
    );
  });
}
