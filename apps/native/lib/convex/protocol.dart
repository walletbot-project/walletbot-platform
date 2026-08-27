import 'dart:convert';
import 'dart:typed_data';

/// Convex sync protocol messages (docs/dart-convex-client.md Appendix A).
///
/// Field names are verbatim from convex-js `src/browser/sync/protocol.ts` and
/// the open-source backend's `crates/sync/src/worker.rs`. Values inside
/// messages stay in wire-JSON form (already through `convexToJson`); typed
/// decoding happens at the client surface.

/// Thrown when the server violates the protocol (unparseable frame, version
/// mismatch, malformed chunk stream). The client responds by reconnecting.
class ConvexProtocolException implements Exception {
  ConvexProtocolException(this.message);
  final String message;

  @override
  String toString() => 'ConvexProtocolException: $message';
}

/// Timestamps are u64 nanoseconds encoded as base64 of the 8-byte
/// little-endian value. Kept as BigInt so comparisons never wrap.
BigInt decodeTs(Object? encoded) {
  if (encoded is! String) {
    throw ConvexProtocolException('timestamp must be a base64 string');
  }
  final bytes = base64Decode(encoded);
  if (bytes.length != 8) {
    throw ConvexProtocolException('timestamp must be 8 bytes');
  }
  var value = BigInt.zero;
  for (var i = 7; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[i]);
  }
  return value;
}

String encodeTs(BigInt ts) {
  final unsigned = ts.toUnsigned(64);
  final bytes = Uint8List(8);
  var rest = unsigned;
  for (var i = 0; i < 8; i++) {
    bytes[i] = (rest & BigInt.from(0xff)).toInt();
    rest = rest >> 8;
  }
  return base64Encode(bytes);
}

/// `"module"` means `"module:default"`; a `.js` suffix on the module path is
/// stripped (convex-js `canonicalizeUdfPath`).
String normalizeUdfPath(String udfPath) {
  final colon = udfPath.indexOf(':');
  final module = colon == -1 ? udfPath : udfPath.substring(0, colon);
  final function = colon == -1 ? 'default' : udfPath.substring(colon + 1);
  final canonicalModule = module.endsWith('.js')
      ? module.substring(0, module.length - 3)
      : module;
  return '$canonicalModule:$function';
}

class StateVersion {
  const StateVersion({
    required this.querySet,
    required this.identity,
    required this.ts,
  });

  static final initial = StateVersion(
    querySet: 0,
    identity: 0,
    ts: BigInt.zero,
  );

  factory StateVersion.fromJson(Map<String, Object?> json) => StateVersion(
    querySet: json['querySet'] as int,
    identity: json['identity'] as int,
    ts: decodeTs(json['ts']),
  );

  final int querySet;
  final int identity;
  final BigInt ts;

  bool sameAs(StateVersion other) =>
      querySet == other.querySet &&
      identity == other.identity &&
      ts == other.ts;

  @override
  String toString() => '{querySet: $querySet, identity: $identity, ts: $ts}';
}

// ---- Client → server ----

sealed class ClientMessage {
  Map<String, Object?> toJson();
  String encode() => jsonEncode(toJson());
}

class ConnectMessage extends ClientMessage {
  ConnectMessage({
    required this.sessionId,
    required this.connectionCount,
    required this.lastCloseReason,
    required this.clientTs,
    this.maxObservedTimestamp,
  });

  final String sessionId;
  final int connectionCount;
  final String? lastCloseReason;
  final int clientTs;
  final BigInt? maxObservedTimestamp;

  @override
  Map<String, Object?> toJson() => {
    'type': 'Connect',
    'sessionId': sessionId,
    'connectionCount': connectionCount,
    'lastCloseReason': lastCloseReason,
    if (maxObservedTimestamp != null)
      'maxObservedTimestamp': encodeTs(maxObservedTimestamp!),
    'clientTs': clientTs,
  };
}

sealed class QuerySetModification {
  Map<String, Object?> toJson();
}

class AddQueryModification extends QuerySetModification {
  AddQueryModification({
    required this.queryId,
    required this.udfPath,
    required this.argsJson,
    required this.journal,
    required this.hasJournal,
  });

  final int queryId;
  final String udfPath;
  final Map<String, Object?> argsJson;

  /// Journals are opaque pagination cursors. The server's value (possibly
  /// null) is echoed back once one has been received; before that the field
  /// is omitted, matching convex-js.
  final String? journal;
  final bool hasJournal;

  @override
  Map<String, Object?> toJson() => {
    'type': 'Add',
    'queryId': queryId,
    'udfPath': udfPath,
    'args': [argsJson],
    if (hasJournal) 'journal': journal,
  };
}

class RemoveQueryModification extends QuerySetModification {
  RemoveQueryModification({required this.queryId});
  final int queryId;

  @override
  Map<String, Object?> toJson() => {'type': 'Remove', 'queryId': queryId};
}

class ModifyQuerySetMessage extends ClientMessage {
  ModifyQuerySetMessage({
    required this.baseVersion,
    required this.newVersion,
    required this.modifications,
  });

  final int baseVersion;
  final int newVersion;
  final List<QuerySetModification> modifications;

  @override
  Map<String, Object?> toJson() => {
    'type': 'ModifyQuerySet',
    'baseVersion': baseVersion,
    'newVersion': newVersion,
    'modifications': [for (final m in modifications) m.toJson()],
  };
}

class MutationRequestMessage extends ClientMessage {
  MutationRequestMessage({
    required this.requestId,
    required this.udfPath,
    required this.argsJson,
  });

  final int requestId;
  final String udfPath;
  final Map<String, Object?> argsJson;

  @override
  Map<String, Object?> toJson() => {
    'type': 'Mutation',
    'requestId': requestId,
    'udfPath': udfPath,
    'args': [argsJson],
  };
}

class ActionRequestMessage extends ClientMessage {
  ActionRequestMessage({
    required this.requestId,
    required this.udfPath,
    required this.argsJson,
  });

  final int requestId;
  final String udfPath;
  final Map<String, Object?> argsJson;

  @override
  Map<String, Object?> toJson() => {
    'type': 'Action',
    'requestId': requestId,
    'udfPath': udfPath,
    'args': [argsJson],
  };
}

class AuthenticateMessage extends ClientMessage {
  AuthenticateMessage({required this.token, required this.baseVersion});

  /// Null clears auth (`tokenType: "None"`).
  final String? token;
  final int baseVersion;

  @override
  Map<String, Object?> toJson() => token == null
      ? {
          'type': 'Authenticate',
          'tokenType': 'None',
          'baseVersion': baseVersion,
        }
      : {
          'type': 'Authenticate',
          'tokenType': 'User',
          'value': token,
          'baseVersion': baseVersion,
        };
}

// ---- Server → client ----

sealed class ServerMessage {}

sealed class QueryModification {
  int get queryId;
}

class QueryUpdatedModification extends QueryModification {
  QueryUpdatedModification({
    required this.queryId,
    required this.value,
    required this.logLines,
    required this.journal,
    required this.hasJournal,
  });

  @override
  final int queryId;

  /// Wire-JSON value; an absent field means the Convex value null.
  final Object? value;
  final List<String> logLines;
  final String? journal;
  final bool hasJournal;
}

class QueryFailedModification extends QueryModification {
  QueryFailedModification({
    required this.queryId,
    required this.errorMessage,
    required this.errorData,
    required this.logLines,
    required this.journal,
    required this.hasJournal,
  });

  @override
  final int queryId;
  final String errorMessage;
  final Object? errorData;
  final List<String> logLines;
  final String? journal;
  final bool hasJournal;
}

class QueryRemovedModification extends QueryModification {
  QueryRemovedModification({required this.queryId});

  @override
  final int queryId;
}

class TransitionMessage extends ServerMessage {
  TransitionMessage({
    required this.startVersion,
    required this.endVersion,
    required this.modifications,
  });

  final StateVersion startVersion;
  final StateVersion endVersion;
  final List<QueryModification> modifications;
}

class TransitionChunkMessage extends ServerMessage {
  TransitionChunkMessage({
    required this.chunk,
    required this.partNumber,
    required this.totalParts,
    required this.transitionId,
  });

  final String chunk;
  final int partNumber;
  final int totalParts;
  final String transitionId;
}

class MutationResponseMessage extends ServerMessage {
  MutationResponseMessage({
    required this.requestId,
    required this.success,
    required this.result,
    required this.errorMessage,
    required this.errorData,
    required this.ts,
    required this.logLines,
  });

  final int requestId;
  final bool success;

  /// Wire-JSON result when [success].
  final Object? result;
  final String? errorMessage;
  final Object? errorData;

  /// Commit timestamp; present only when [success].
  final BigInt? ts;
  final List<String> logLines;
}

class ActionResponseMessage extends ServerMessage {
  ActionResponseMessage({
    required this.requestId,
    required this.success,
    required this.result,
    required this.errorMessage,
    required this.errorData,
    required this.logLines,
  });

  final int requestId;
  final bool success;
  final Object? result;
  final String? errorMessage;
  final Object? errorData;
  final List<String> logLines;
}

class AuthErrorMessage extends ServerMessage {
  AuthErrorMessage({
    required this.error,
    required this.baseVersion,
    required this.authUpdateAttempted,
  });

  final String error;
  final int? baseVersion;
  final bool authUpdateAttempted;
}

class FatalErrorMessage extends ServerMessage {
  FatalErrorMessage({required this.error});
  final String error;
}

class PingMessage extends ServerMessage {}

ServerMessage parseServerMessage(String frame) {
  final Object? decoded;
  try {
    decoded = jsonDecode(frame);
  } on FormatException catch (e) {
    throw ConvexProtocolException('unparseable frame: ${e.message}');
  }
  if (decoded is! Map<String, Object?>) {
    throw ConvexProtocolException('frame is not a JSON object');
  }
  return serverMessageFromJson(decoded);
}

ServerMessage serverMessageFromJson(Map<String, Object?> json) {
  final type = json['type'];
  try {
    switch (type) {
      case 'Transition':
        return TransitionMessage(
          startVersion: StateVersion.fromJson(
            (json['startVersion'] as Map).cast<String, Object?>(),
          ),
          endVersion: StateVersion.fromJson(
            (json['endVersion'] as Map).cast<String, Object?>(),
          ),
          modifications: [
            for (final m in json['modifications'] as List)
              _queryModificationFromJson((m as Map).cast<String, Object?>()),
          ],
        );
      case 'TransitionChunk':
        return TransitionChunkMessage(
          chunk: json['chunk'] as String,
          partNumber: json['partNumber'] as int,
          totalParts: json['totalParts'] as int,
          transitionId: json['transitionId'] as String,
        );
      case 'MutationResponse':
        final success = json['success'] as bool;
        return MutationResponseMessage(
          requestId: json['requestId'] as int,
          success: success,
          result: success ? json['result'] : null,
          errorMessage: success ? null : json['result'] as String?,
          errorData: json['errorData'],
          ts: success ? decodeTs(json['ts']) : null,
          logLines: _logLines(json['logLines']),
        );
      case 'ActionResponse':
        final success = json['success'] as bool;
        return ActionResponseMessage(
          requestId: json['requestId'] as int,
          success: success,
          result: success ? json['result'] : null,
          errorMessage: success ? null : json['result'] as String?,
          errorData: json['errorData'],
          logLines: _logLines(json['logLines']),
        );
      case 'AuthError':
        return AuthErrorMessage(
          error: json['error'] as String? ?? 'unknown auth error',
          baseVersion: json['baseVersion'] as int?,
          authUpdateAttempted: json['authUpdateAttempted'] as bool? ?? false,
        );
      case 'FatalError':
        return FatalErrorMessage(
          error: json['error'] as String? ?? 'unknown fatal error',
        );
      case 'Ping':
        return PingMessage();
      default:
        throw ConvexProtocolException('unknown server message type "$type"');
    }
  } on TypeError catch (e) {
    throw ConvexProtocolException('malformed $type message: $e');
  }
}

QueryModification _queryModificationFromJson(Map<String, Object?> json) {
  switch (json['type']) {
    case 'QueryUpdated':
      return QueryUpdatedModification(
        queryId: json['queryId'] as int,
        value: json['value'],
        logLines: _logLines(json['logLines']),
        journal: json['journal'] as String?,
        hasJournal: json.containsKey('journal'),
      );
    case 'QueryFailed':
      return QueryFailedModification(
        queryId: json['queryId'] as int,
        errorMessage: json['errorMessage'] as String? ?? 'query failed',
        errorData: json['errorData'],
        logLines: _logLines(json['logLines']),
        journal: json['journal'] as String?,
        hasJournal: json.containsKey('journal'),
      );
    case 'QueryRemoved':
      return QueryRemovedModification(queryId: json['queryId'] as int);
    default:
      throw ConvexProtocolException(
        'unknown query modification type "${json['type']}"',
      );
  }
}

List<String> _logLines(Object? value) =>
    value is List ? value.cast<String>() : const [];
