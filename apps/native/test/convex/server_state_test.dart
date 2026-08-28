import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:app/convex/protocol.dart';
import 'package:app/convex/server_state.dart';

Map<String, Object?> _version({
  int querySet = 0,
  int identity = 0,
  int ts = 0,
}) => {
  'querySet': querySet,
  'identity': identity,
  'ts': encodeTs(BigInt.from(ts)),
};

TransitionMessage _transition({
  required Map<String, Object?> start,
  required Map<String, Object?> end,
  List<Map<String, Object?>> modifications = const [],
}) =>
    parseServerMessage(
          jsonEncode({
            'type': 'Transition',
            'startVersion': start,
            'endVersion': end,
            'modifications': modifications,
          }),
        )
        as TransitionMessage;

List<Map<String, Object?>> _chunksOf(
  Map<String, Object?> transitionJson, {
  required int parts,
  String transitionId = 't1',
}) {
  final payload = jsonEncode(transitionJson);
  final size = (payload.length / parts).ceil();
  return [
    for (var i = 0; i < parts; i++)
      {
        'type': 'TransitionChunk',
        'chunk': payload.substring(
          i * size,
          (i * size + size) > payload.length ? payload.length : i * size + size,
        ),
        'partNumber': i,
        'totalParts': parts,
        'transitionId': transitionId,
      },
  ];
}

final _sampleTransitionJson = {
  'type': 'Transition',
  'startVersion': _version(),
  'endVersion': _version(querySet: 1, ts: 10),
  'modifications': [
    {
      'type': 'QueryUpdated',
      'queryId': 0,
      'value': 42,
      'logLines': [],
      'journal': null,
    },
  ],
};

void main() {
  group('RemoteQuerySet', () {
    test('applies modifications and advances the version', () {
      final remote = RemoteQuerySet();
      final changed = remote.ingest(
        _transition(
          start: _version(),
          end: _version(querySet: 1, ts: 5),
          modifications: [
            {
              'type': 'QueryUpdated',
              'queryId': 0,
              'value': 1,
              'logLines': [],
              'journal': null,
            },
            {
              'type': 'QueryFailed',
              'queryId': 1,
              'errorMessage': 'nope',
              'errorData': null,
              'logLines': [],
              'journal': null,
            },
          ],
        ),
      );
      expect(changed, {0, 1});
      expect(remote.version.querySet, 1);
      expect(remote.version.ts, BigInt.from(5));
      expect(remote.results[0]!.success, isTrue);
      expect(remote.results[0]!.value, 1);
      expect(remote.results[1]!.success, isFalse);
      expect(remote.results[1]!.errorMessage, 'nope');
    });

    test('QueryRemoved drops the result', () {
      final remote = RemoteQuerySet();
      remote.ingest(
        _transition(
          start: _version(),
          end: _version(querySet: 1, ts: 1),
          modifications: [
            {
              'type': 'QueryUpdated',
              'queryId': 0,
              'value': 1,
              'logLines': [],
              'journal': null,
            },
          ],
        ),
      );
      remote.ingest(
        _transition(
          start: _version(querySet: 1, ts: 1),
          end: _version(querySet: 2, ts: 2),
          modifications: [
            {'type': 'QueryRemoved', 'queryId': 0},
          ],
        ),
      );
      expect(remote.results, isEmpty);
    });

    test('version mismatch throws', () {
      final remote = RemoteQuerySet();
      expect(
        () => remote.ingest(
          _transition(start: _version(querySet: 3), end: _version(querySet: 4)),
        ),
        throwsA(isA<ConvexProtocolException>()),
      );
    });
  });

  group('TransitionChunkAssembler', () {
    test('reassembles in-order chunks into a Transition', () {
      final assembler = TransitionChunkAssembler();
      final chunks = _chunksOf(_sampleTransitionJson, parts: 3);
      expect(assembler.add(serverMessageFromJson(chunks[0])), isNull);
      expect(assembler.hasPending, isTrue);
      expect(assembler.add(serverMessageFromJson(chunks[1])), isNull);
      final result = assembler.add(serverMessageFromJson(chunks[2]));
      expect(result, isA<TransitionMessage>());
      final updated =
          (result as TransitionMessage).modifications.single
              as QueryUpdatedModification;
      expect(updated.value, 42);
      expect(assembler.hasPending, isFalse);
    });

    test('single-part chunk completes immediately', () {
      final assembler = TransitionChunkAssembler();
      final chunks = _chunksOf(_sampleTransitionJson, parts: 1);
      expect(
        assembler.add(serverMessageFromJson(chunks[0])),
        isA<TransitionMessage>(),
      );
    });

    test('interleaved non-chunk message discards the buffer', () {
      final assembler = TransitionChunkAssembler();
      final chunks = _chunksOf(_sampleTransitionJson, parts: 2);
      assembler.add(serverMessageFromJson(chunks[0]));
      final passthrough = assembler.add(PingMessage());
      expect(passthrough, isA<PingMessage>());
      expect(assembler.hasPending, isFalse);
    });

    test('out-of-order part throws', () {
      final assembler = TransitionChunkAssembler();
      final chunks = _chunksOf(_sampleTransitionJson, parts: 3);
      assembler.add(serverMessageFromJson(chunks[0]));
      expect(
        () => assembler.add(serverMessageFromJson(chunks[2])),
        throwsA(isA<ConvexProtocolException>()),
      );
    });

    test('sequence starting past part 0 throws', () {
      final assembler = TransitionChunkAssembler();
      final chunks = _chunksOf(_sampleTransitionJson, parts: 2);
      expect(
        () => assembler.add(serverMessageFromJson(chunks[1])),
        throwsA(isA<ConvexProtocolException>()),
      );
    });

    test('mismatched transitionId throws', () {
      final assembler = TransitionChunkAssembler();
      final first = _chunksOf(_sampleTransitionJson, parts: 2);
      final other = _chunksOf(
        _sampleTransitionJson,
        parts: 2,
        transitionId: 't2',
      );
      assembler.add(serverMessageFromJson(first[0]));
      expect(
        () => assembler.add(serverMessageFromJson(other[1])),
        throwsA(isA<ConvexProtocolException>()),
      );
    });

    test('reassembled payload that is not a Transition throws', () {
      final assembler = TransitionChunkAssembler();
      expect(
        () => assembler.add(
          serverMessageFromJson({
            'type': 'TransitionChunk',
            'chunk': '{"type":"Ping"}',
            'partNumber': 0,
            'totalParts': 1,
            'transitionId': 'x',
          }),
        ),
        throwsA(isA<ConvexProtocolException>()),
      );
    });
  });
}
