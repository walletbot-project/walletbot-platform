import 'protocol.dart';

/// Mirrors the server's view of this socket: the `{querySet, ts, identity}`
/// version triple and the latest result per subscribed query
/// (≈ convex-js `remote_query_set.ts`). Reset to zeros on every fresh socket.

/// Latest outcome of one subscribed query, in wire-JSON form.
class QueryResult {
  QueryResult.success(this.value)
    : success = true,
      errorMessage = null,
      errorData = null;

  QueryResult.failure({required String this.errorMessage, this.errorData})
    : success = false,
      value = null;

  final bool success;
  final Object? value;
  final String? errorMessage;
  final Object? errorData;
}

class RemoteQuerySet {
  StateVersion version = StateVersion.initial;
  final Map<int, QueryResult> results = {};

  /// Applies a transition and returns the queryIds whose results changed.
  /// Throws [ConvexProtocolException] when the transition does not start at
  /// our current version — the caller must tear the socket down.
  Set<int> ingest(TransitionMessage transition) {
    if (!transition.startVersion.sameAs(version)) {
      throw ConvexProtocolException(
        'transition starts at ${transition.startVersion} '
        'but client is at $version',
      );
    }
    final changed = <int>{};
    for (final modification in transition.modifications) {
      switch (modification) {
        case QueryUpdatedModification(:final queryId, :final value):
          results[queryId] = QueryResult.success(value);
          changed.add(queryId);
        case QueryFailedModification(
          :final queryId,
          :final errorMessage,
          :final errorData,
        ):
          results[queryId] = QueryResult.failure(
            errorMessage: errorMessage,
            errorData: errorData,
          );
          changed.add(queryId);
        case QueryRemovedModification(:final queryId):
          results.remove(queryId);
      }
    }
    version = transition.endVersion;
    return changed;
  }
}

/// Reassembles `TransitionChunk` frames (docs/dart-convex-client.md §A.4).
///
/// Chunks of one transitionId must arrive contiguously and in order. A
/// non-chunk message interleaved with a partial buffer discards the buffer
/// (matching convex-js); an out-of-order or mismatched chunk is a protocol
/// error, which makes the caller reconnect.
class TransitionChunkAssembler {
  final List<String> _parts = [];
  String? _transitionId;
  int _totalParts = 0;

  bool get hasPending => _parts.isNotEmpty;

  /// Feeds one server message. Returns the message to process now: the input
  /// itself (after discarding any partial buffer), a fully reassembled
  /// [TransitionMessage], or null while a chunk sequence is still incomplete.
  ServerMessage? add(ServerMessage message) {
    if (message is! TransitionChunkMessage) {
      _reset();
      return message;
    }
    if (_parts.isEmpty) {
      if (message.partNumber != 0) {
        throw ConvexProtocolException(
          'chunk sequence for ${message.transitionId} '
          'started at part ${message.partNumber}',
        );
      }
      _transitionId = message.transitionId;
      _totalParts = message.totalParts;
    } else {
      if (message.transitionId != _transitionId) {
        throw ConvexProtocolException(
          'chunk of ${message.transitionId} interleaved with '
          'incomplete $_transitionId',
        );
      }
      if (message.partNumber != _parts.length ||
          message.totalParts != _totalParts) {
        throw ConvexProtocolException(
          'chunk ${message.partNumber}/${message.totalParts} of '
          '$_transitionId arrived out of order '
          '(expected ${_parts.length}/$_totalParts)',
        );
      }
    }
    _parts.add(message.chunk);
    if (_parts.length < _totalParts) return null;
    final payload = _parts.join();
    _reset();
    final reassembled = parseServerMessage(payload);
    if (reassembled is! TransitionMessage) {
      throw ConvexProtocolException(
        'reassembled chunk payload is ${reassembled.runtimeType}, '
        'expected Transition',
      );
    }
    return reassembled;
  }

  void _reset() {
    _parts.clear();
    _transitionId = null;
    _totalParts = 0;
  }
}
