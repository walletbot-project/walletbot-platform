/// Typed errors surfaced by the Dart Convex client
/// (docs/dart-convex-client.md §5.3).
library;

/// The connection lifecycle as observed by callers. `ready` means the socket
/// is open and the restart sequence (Connect → Authenticate → resubscribe →
/// resend) has completed.
enum ConnectionStatus { disconnected, connecting, ready }

/// Which per-call timeout fired (docs/dart-convex-client.md §7).
enum TimeoutPhase {
  /// Waiting for a `ready` socket (`connectTimeout`).
  connect,

  /// Sent, waiting for the server's response (`operationTimeout`).
  operation,
}

/// The server function threw. Carries the server's message and, for
/// `ConvexError`, the decoded `errorData` payload.
class ConvexFunctionError implements Exception {
  ConvexFunctionError({
    required this.functionName,
    required this.errorMessage,
    this.errorData,
  });

  final String functionName;
  final String errorMessage;
  final Object? errorData;

  @override
  String toString() => 'ConvexFunctionError($functionName): $errorMessage';
}

/// An action (not idempotent, never resent) was in flight when the socket was
/// lost, or an HTTP fallback failed at the transport level. Mutations never
/// produce this: they are resent across reconnects.
class ConnectionLostError implements Exception {
  ConnectionLostError(this.message);
  final String message;

  @override
  String toString() => 'ConnectionLostError: $message';
}

/// A configured per-call timeout fired. [phase] and [connectionStatus] say
/// which timeout and what the transport looked like at that moment, so logs
/// can distinguish "server slow" from "socket down".
class OperationTimeoutError implements Exception {
  OperationTimeoutError({
    required this.functionName,
    required this.phase,
    required this.timeout,
    required this.connectionStatus,
  });

  final String functionName;
  final TimeoutPhase phase;
  final Duration timeout;
  final ConnectionStatus connectionStatus;

  @override
  String toString() =>
      'OperationTimeoutError($functionName): ${phase.name} timeout '
      '${timeout.inMilliseconds}ms elapsed while $connectionStatus';
}

/// Auth was required for the call but the client has none (for example an
/// HTTP fallback that needs a token while unauthenticated).
class AuthRequiredError implements Exception {
  AuthRequiredError(this.message);
  final String message;

  @override
  String toString() => 'AuthRequiredError: $message';
}

/// The server sent `FatalError`: the client is permanently stopped and must
/// be disposed; a new instance can be constructed.
class ConvexFatalError implements Exception {
  ConvexFatalError(this.message);
  final String message;

  @override
  String toString() => 'ConvexFatalError: $message';
}

/// The client was disposed while the call was pending.
class ClientDisposedError implements Exception {
  ClientDisposedError();

  @override
  String toString() => 'ClientDisposedError: the ConvexClient was disposed';
}
