import 'dart:async';

import 'errors.dart';
import 'protocol.dart';

/// Tracks mutations and actions in flight (≈ convex-js `request_manager.ts`)
/// and owns the per-call timeout timers (docs/dart-convex-client.md §7).
///
/// Lifecycle of a request:
///   notSent   — queued, socket not ready yet (`connectTimeout` running)
///   requested — sent, waiting for a response (`operationTimeout` running)
///   completed — mutation responded success; its Future resolves only when a
///               Transition reaches the commit ts (read-your-own-writes)
///
/// On restart (§5.2): every in-flight mutation is resent — the server dedupes
/// by (sessionId, requestId), making this exactly-once — and every in-flight
/// action fails with [ConnectionLostError] (actions are not idempotent).

enum RequestStatus { notSent, requested, completed }

class _InflightRequest {
  _InflightRequest({
    required this.message,
    required this.udfPath,
    required this.isMutation,
    this.operationTimeout,
  });

  final ClientMessage message;
  final String udfPath;
  final bool isMutation;
  final Duration? operationTimeout;
  final Completer<Object?> completer = Completer<Object?>();
  RequestStatus status = RequestStatus.notSent;
  BigInt? completedTs;
  Object? completedResult;
  Timer? connectTimer;
  Timer? operationTimer;
  bool operationTimerStarted = false;

  void cancelTimers() {
    connectTimer?.cancel();
    operationTimer?.cancel();
  }
}

class RequestManager {
  RequestManager({required this.connectionStatus, required this.decodeValue});

  /// Snapshot of the transport state, for [OperationTimeoutError]s.
  final ConnectionStatus Function() connectionStatus;

  /// Decodes wire-JSON `errorData` into Dart values for typed errors.
  final Object? Function(Object? wireJson) decodeValue;

  int _nextRequestId = 0;
  final Map<int, _InflightRequest> _inflight = {};

  int nextRequestId() => _nextRequestId++;

  bool get hasInflight => _inflight.isNotEmpty;

  Set<int> get inflightRequestIds => Set.of(_inflight.keys);

  bool anyInflightOf(Set<int> requestIds) =>
      requestIds.any(_inflight.containsKey);

  /// Registers a request. [sent] is whether the message went out already; a
  /// queued (notSent) request is sent by the next [restart].
  Future<Object?> register({
    required int requestId,
    required ClientMessage message,
    required String udfPath,
    required bool isMutation,
    required bool sent,
    Duration? connectTimeout,
    Duration? operationTimeout,
  }) {
    final request = _InflightRequest(
      message: message,
      udfPath: udfPath,
      isMutation: isMutation,
      operationTimeout: operationTimeout,
    );
    _inflight[requestId] = request;
    if (sent) {
      _markSent(requestId, request);
    } else if (connectTimeout != null) {
      request.connectTimer = Timer(connectTimeout, () {
        _fail(
          requestId,
          OperationTimeoutError(
            functionName: udfPath,
            phase: TimeoutPhase.connect,
            timeout: connectTimeout,
            connectionStatus: connectionStatus(),
          ),
        );
      });
    }
    return request.completer.future;
  }

  void _markSent(int requestId, _InflightRequest request) {
    request.connectTimer?.cancel();
    request.connectTimer = null;
    if (request.status == RequestStatus.notSent) {
      request.status = RequestStatus.requested;
    }
    // The operation timer starts once and is not restarted by reconnects: a
    // resent mutation is the same operation still waiting (§7).
    final timeout = request.operationTimeout;
    if (timeout != null && !request.operationTimerStarted) {
      request.operationTimerStarted = true;
      request.operationTimer = Timer(timeout, () {
        _fail(
          requestId,
          OperationTimeoutError(
            functionName: request.udfPath,
            phase: TimeoutPhase.operation,
            timeout: timeout,
            connectionStatus: connectionStatus(),
          ),
        );
      });
    }
  }

  /// Handles a MutationResponse / ActionResponse. Duplicate responses for
  /// unknown or already-resolved requestIds are expected after reconnects and
  /// are ignored.
  void onMutationResponse(MutationResponseMessage response) {
    final request = _inflight[response.requestId];
    if (request == null || !request.isMutation) return;
    if (request.status == RequestStatus.completed) return;
    if (response.success) {
      request.status = RequestStatus.completed;
      request.completedTs = response.ts;
      request.completedResult = response.result;
      request.operationTimer?.cancel();
    } else {
      _fail(
        response.requestId,
        ConvexFunctionError(
          functionName: request.udfPath,
          errorMessage: response.errorMessage ?? 'mutation failed',
          errorData: response.errorData == null
              ? null
              : decodeValue(response.errorData),
        ),
      );
    }
  }

  void onActionResponse(ActionResponseMessage response) {
    final request = _inflight[response.requestId];
    if (request == null || request.isMutation) return;
    _inflight.remove(response.requestId);
    request.cancelTimers();
    if (response.success) {
      request.completer.complete(response.result);
    } else {
      request.completer.completeError(
        ConvexFunctionError(
          functionName: request.udfPath,
          errorMessage: response.errorMessage ?? 'action failed',
          errorData: response.errorData == null
              ? null
              : decodeValue(response.errorData),
        ),
      );
    }
  }

  /// Resolves completed mutations whose commit ts the server state has now
  /// reached (read-your-own-writes, §A.6).
  void removeCompleted(BigInt observedTs) {
    final resolved = <int>[];
    _inflight.forEach((requestId, request) {
      final ts = request.completedTs;
      if (request.status == RequestStatus.completed &&
          ts != null &&
          ts <= observedTs) {
        resolved.add(requestId);
      }
    });
    for (final requestId in resolved) {
      final request = _inflight.remove(requestId)!;
      request.cancelTimers();
      request.completer.complete(request.completedResult);
    }
  }

  /// Restart sequence contribution (§5.2 step 4): fails in-flight actions,
  /// returns every mutation to resend (including completed-but-not-yet-
  /// transitioned ones) and flips queued notSent requests to sent.
  List<ClientMessage> restart() {
    final resend = <ClientMessage>[];
    final failedActions = <int>[];
    _inflight.forEach((requestId, request) {
      if (!request.isMutation && request.status == RequestStatus.requested) {
        failedActions.add(requestId);
        return;
      }
      resend.add(request.message);
      _markSent(requestId, request);
    });
    for (final requestId in failedActions) {
      _fail(
        requestId,
        ConnectionLostError(
          'action ${_inflight[requestId]?.udfPath} was in flight when the '
          'connection was lost; it may or may not have run',
        ),
      );
    }
    return resend;
  }

  /// Fails everything (dispose / FatalError).
  void failAll(Object error) {
    final requestIds = List.of(_inflight.keys);
    for (final requestId in requestIds) {
      _fail(requestId, error);
    }
  }

  void _fail(int requestId, Object error) {
    final request = _inflight.remove(requestId);
    if (request == null) return;
    request.cancelTimers();
    request.completer.completeError(error);
  }
}
