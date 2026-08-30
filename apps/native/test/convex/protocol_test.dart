import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/protocol.dart';

void main() {
  group('timestamps', () {
    test('golden encodings', () {
      expect(encodeTs(BigInt.zero), 'AAAAAAAAAAA=');
      expect(encodeTs(BigInt.one), 'AQAAAAAAAAA=');
      expect(decodeTs('AAAAAAAAAAA='), BigInt.zero);
      expect(decodeTs('AQAAAAAAAAA='), BigInt.one);
    });

    test('round-trips large u64 values', () {
      final values = [
        BigInt.parse('1789897901234567890'),
        BigInt.parse('9223372036854775807'),
        BigInt.parse('18446744073709551615'), // u64 max
      ];
      for (final ts in values) {
        expect(decodeTs(encodeTs(ts)), ts);
      }
    });

    test('rejects malformed timestamps', () {
      expect(() => decodeTs('AQ=='), throwsA(isA<ConvexProtocolException>()));
      expect(() => decodeTs(7), throwsA(isA<ConvexProtocolException>()));
    });
  });

  group('normalizeUdfPath', () {
    test('appends :default and strips .js', () {
      expect(normalizeUdfPath('module'), 'module:default');
      expect(normalizeUdfPath('module.js'), 'module:default');
      expect(normalizeUdfPath('dir/module.js:fn'), 'dir/module:fn');
      expect(normalizeUdfPath('v1/sync/queries:pull'), 'v1/sync/queries:pull');
    });
  });

  group('client message encoding', () {
    test('Connect with and without maxObservedTimestamp', () {
      final withoutTs = ConnectMessage(
        sessionId: 's-1',
        connectionCount: 1,
        lastCloseReason: 'InitialConnect',
        clientTs: 123,
      );
      expect(withoutTs.toJson(), {
        'type': 'Connect',
        'sessionId': 's-1',
        'connectionCount': 1,
        'lastCloseReason': 'InitialConnect',
        'clientTs': 123,
      });
      final withTs = ConnectMessage(
        sessionId: 's-1',
        connectionCount: 2,
        lastCloseReason: 'InactiveServer',
        clientTs: 456,
        maxObservedTimestamp: BigInt.from(99),
      );
      expect(
        withTs.toJson()['maxObservedTimestamp'],
        encodeTs(BigInt.from(99)),
      );
    });

    test('ModifyQuerySet Add wraps args in a 1-element array', () {
      final message = ModifyQuerySetMessage(
        baseVersion: 0,
        newVersion: 1,
        modifications: [
          AddQueryModification(
            queryId: 0,
            udfPath: 'v1/sync/queries:getCounter',
            argsJson: const {},
            journal: null,
            hasJournal: false,
          ),
        ],
      );
      expect(message.toJson(), {
        'type': 'ModifyQuerySet',
        'baseVersion': 0,
        'newVersion': 1,
        'modifications': [
          {
            'type': 'Add',
            'queryId': 0,
            'udfPath': 'v1/sync/queries:getCounter',
            'args': [<String, Object?>{}],
          },
        ],
      });
    });

    test('Add includes journal (even null) once one was received', () {
      final add = AddQueryModification(
        queryId: 3,
        udfPath: 'q:f',
        argsJson: const {},
        journal: null,
        hasJournal: true,
      );
      expect(add.toJson().containsKey('journal'), isTrue);
      expect(add.toJson()['journal'], isNull);
    });

    test('Remove modification', () {
      expect(RemoveQueryModification(queryId: 4).toJson(), {
        'type': 'Remove',
        'queryId': 4,
      });
    });

    test('Mutation and Action requests', () {
      expect(
        MutationRequestMessage(
          requestId: 7,
          udfPath: 'v1/sync/mutations:push',
          argsJson: const {'x': 1},
        ).toJson(),
        {
          'type': 'Mutation',
          'requestId': 7,
          'udfPath': 'v1/sync/mutations:push',
          'args': [
            {'x': 1},
          ],
        },
      );
      expect(
        ActionRequestMessage(
          requestId: 8,
          udfPath: 'v1/live/actions:requestLiveToken',
          argsJson: const {},
        ).toJson()['type'],
        'Action',
      );
    });

    test('Authenticate User and None', () {
      expect(AuthenticateMessage(token: 'jwt', baseVersion: 0).toJson(), {
        'type': 'Authenticate',
        'tokenType': 'User',
        'value': 'jwt',
        'baseVersion': 0,
      });
      expect(AuthenticateMessage(token: null, baseVersion: 2).toJson(), {
        'type': 'Authenticate',
        'tokenType': 'None',
        'baseVersion': 2,
      });
    });
  });

  group('server message decoding', () {
    test('Transition with all modification kinds', () {
      final message =
          parseServerMessage(
                jsonEncode({
                  'type': 'Transition',
                  'startVersion': {
                    'querySet': 0,
                    'identity': 0,
                    'ts': 'AAAAAAAAAAA=',
                  },
                  'endVersion': {
                    'querySet': 1,
                    'identity': 1,
                    'ts': 'AQAAAAAAAAA=',
                  },
                  'modifications': [
                    {
                      'type': 'QueryUpdated',
                      'queryId': 0,
                      'value': 5,
                      'logLines': ['log'],
                      'journal': null,
                    },
                    {
                      'type': 'QueryFailed',
                      'queryId': 1,
                      'errorMessage': 'boom',
                      'errorData': {'code': 'X'},
                      'logLines': [],
                      'journal': null,
                    },
                    {'type': 'QueryRemoved', 'queryId': 2},
                  ],
                }),
              )
              as TransitionMessage;
      expect(message.startVersion.sameAs(StateVersion.initial), isTrue);
      expect(message.endVersion.querySet, 1);
      expect(message.endVersion.identity, 1);
      expect(message.endVersion.ts, BigInt.one);
      final updated = message.modifications[0] as QueryUpdatedModification;
      expect(updated.value, 5);
      expect(updated.hasJournal, isTrue);
      expect(updated.journal, isNull);
      final failed = message.modifications[1] as QueryFailedModification;
      expect(failed.errorMessage, 'boom');
      expect(failed.errorData, {'code': 'X'});
      expect(message.modifications[2], isA<QueryRemovedModification>());
    });

    test('QueryUpdated with absent value decodes to null value', () {
      final message =
          parseServerMessage(
                jsonEncode({
                  'type': 'Transition',
                  'startVersion': {
                    'querySet': 0,
                    'identity': 0,
                    'ts': 'AAAAAAAAAAA=',
                  },
                  'endVersion': {
                    'querySet': 1,
                    'identity': 0,
                    'ts': 'AQAAAAAAAAA=',
                  },
                  'modifications': [
                    {'type': 'QueryUpdated', 'queryId': 0, 'logLines': []},
                  ],
                }),
              )
              as TransitionMessage;
      final updated = message.modifications.single as QueryUpdatedModification;
      expect(updated.value, isNull);
      expect(updated.hasJournal, isFalse);
    });

    test('MutationResponse success and failure', () {
      final success =
          parseServerMessage(
                jsonEncode({
                  'type': 'MutationResponse',
                  'requestId': 1,
                  'success': true,
                  'result': {'ok': true},
                  'ts': 'AQAAAAAAAAA=',
                  'logLines': [],
                }),
              )
              as MutationResponseMessage;
      expect(success.success, isTrue);
      expect(success.result, {'ok': true});
      expect(success.ts, BigInt.one);
      final failure =
          parseServerMessage(
                jsonEncode({
                  'type': 'MutationResponse',
                  'requestId': 2,
                  'success': false,
                  'result': 'Uncaught Error: nope',
                  'logLines': [],
                  'errorData': {'code': 'CONFLICT'},
                }),
              )
              as MutationResponseMessage;
      expect(failure.success, isFalse);
      expect(failure.errorMessage, 'Uncaught Error: nope');
      expect(failure.errorData, {'code': 'CONFLICT'});
      expect(failure.ts, isNull);
    });

    test('ActionResponse has no ts', () {
      final response =
          parseServerMessage(
                jsonEncode({
                  'type': 'ActionResponse',
                  'requestId': 3,
                  'success': true,
                  'result': 'token',
                  'logLines': [],
                }),
              )
              as ActionResponseMessage;
      expect(response.success, isTrue);
      expect(response.result, 'token');
    });

    test('AuthError, FatalError, Ping', () {
      final authError =
          parseServerMessage(
                jsonEncode({
                  'type': 'AuthError',
                  'error': 'expired',
                  'baseVersion': 0,
                  'authUpdateAttempted': true,
                }),
              )
              as AuthErrorMessage;
      expect(authError.error, 'expired');
      expect(authError.baseVersion, 0);
      expect(authError.authUpdateAttempted, isTrue);
      expect(
        (parseServerMessage(jsonEncode({'type': 'FatalError', 'error': 'x'}))
                as FatalErrorMessage)
            .error,
        'x',
      );
      expect(parseServerMessage('{"type":"Ping"}'), isA<PingMessage>());
    });

    test('TransitionChunk decodes', () {
      final chunk =
          parseServerMessage(
                jsonEncode({
                  'type': 'TransitionChunk',
                  'chunk': 'abc',
                  'partNumber': 0,
                  'totalParts': 2,
                  'transitionId': 't1',
                }),
              )
              as TransitionChunkMessage;
      expect(chunk.chunk, 'abc');
      expect(chunk.totalParts, 2);
    });

    test('unknown or malformed frames throw ConvexProtocolException', () {
      expect(
        () => parseServerMessage('{"type":"Mystery"}'),
        throwsA(isA<ConvexProtocolException>()),
      );
      expect(
        () => parseServerMessage('not json'),
        throwsA(isA<ConvexProtocolException>()),
      );
      expect(
        () => parseServerMessage('[1,2]'),
        throwsA(isA<ConvexProtocolException>()),
      );
      expect(
        () => parseServerMessage('{"type":"Transition","startVersion":5}'),
        throwsA(isA<ConvexProtocolException>()),
      );
    });
  });
}
