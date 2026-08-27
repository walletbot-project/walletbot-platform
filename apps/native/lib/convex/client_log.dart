import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import 'convex_client.dart';

/// Console view of [ConvexClient.onEvent].
///
/// The client emits a full trace of its own behaviour (socket lifecycle, auth
/// fetches and rejections, per-call request/response, HTTP fallback) and
/// nothing in the app was listening, so every question about it on device came
/// down to guessing from the outside.
///
/// The part that is not just formatting is [_sweep]: a call that never comes
/// back emits no completion event, so printing events alone can only ever show
/// what already finished. The sweep reports calls that are *still outstanding*
/// while they are outstanding, which is the shape every "the agent went quiet"
/// report has had.
class ConvexClientLog {
  ConvexClientLog({
    this.slowCall = const Duration(seconds: 2),
    this.sweepInterval = const Duration(seconds: 5),
    Set<String>? muted,
    void Function(String line)? sink,
  }) : muted = muted ?? const {'query.subscribe', 'query.unsubscribe'},
       _sink = sink ?? debugPrint;

  /// A call slower than this is worth looking at, and a still-outstanding one
  /// past it is reported every sweep until it ends.
  final Duration slowCall;

  final Duration sweepInterval;

  /// Event types dropped before formatting. Query subscribe/unsubscribe fire
  /// on every widget rebuild that changes a filter and drown everything else.
  final Set<String> muted;

  final void Function(String line) _sink;

  final Map<Object, _Outstanding> _outstanding = {};
  StreamSubscription<ConnectionSnapshot>? _connection;
  Timer? _timer;
  bool _attached = false;

  void attach(ConvexClient client) {
    if (_attached) return;
    _attached = true;
    client.onEvent(_onEvent);
    _connection = client.connectionState.listen((snapshot) {
      _sink(
        '[convex] connection ${snapshot.status.name} '
        'retries=${snapshot.retries}'
        '${snapshot.lastCloseReason == null ? '' : ' lastClose=${snapshot.lastCloseReason}'}',
      );
    });
    _timer = Timer.periodic(sweepInterval, (_) => _sweep());
  }

  void detach() {
    _timer?.cancel();
    _timer = null;
    unawaited(_connection?.cancel());
    _connection = null;
    _outstanding.clear();
    _attached = false;
  }

  @visibleForTesting
  void handle(ConvexClientEvent event) => _onEvent(event);

  @visibleForTesting
  void sweep() => _sweep();

  void _onEvent(ConvexClientEvent event) {
    final type = event.type;
    if (muted.contains(type)) return;
    final requestId = event.data['requestId'];
    if (requestId != null) {
      if (type.endsWith('.request')) {
        _outstanding[requestId] = _Outstanding(
          udfPath: event.data['udfPath']?.toString() ?? '?',
          startedAt: event.at,
          delivered: event.data['delivered'] == true,
        );
      } else {
        _outstanding.remove(requestId);
      }
    }
    final elapsed = event.data['elapsedMs'];
    final slow = elapsed is int && elapsed >= slowCall.inMilliseconds;
    _sink('[convex]${slow ? ' SLOW' : ''} $type ${_format(event.data)}');
  }

  void _sweep() {
    if (_outstanding.isEmpty) return;
    final now = clock.now();
    for (final entry in _outstanding.entries) {
      final waiting = now.difference(entry.value.startedAt);
      if (waiting < slowCall) continue;
      _sink(
        // delivered=false is the informative case: there was no socket to
        // even buffer on, so this call is waiting out a reconnect backoff
        // rather than waiting on the server.
        '[convex] WAITING ${entry.value.udfPath} '
        'requestId=${entry.key} for=${waiting.inMilliseconds}ms '
        'delivered=${entry.value.delivered}',
      );
    }
  }

  String _format(Map<String, Object?> data) =>
      data.entries.map((e) => '${e.key}=${e.value}').join(' ');
}

class _Outstanding {
  _Outstanding({
    required this.udfPath,
    required this.startedAt,
    required this.delivered,
  });

  final String udfPath;
  final DateTime startedAt;
  final bool delivered;
}
