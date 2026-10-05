import 'dart:async';

/// Serializes local operations without blocking the socket receive loop.
/// IDs are scoped to a connection; duplicates execute once. Cancellation can
/// prevent a queued operation, but cannot undo a write already committed.
class LiveToolDispatcher {
  LiveToolDispatcher({
    required this.execute,
    required this.isCurrent,
    required this.onCall,
    required this.onResult,
    required this.respond,
  });

  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  execute;
  final bool Function(int) isCurrent;
  final void Function(String, String, Map<String, dynamic>) onCall;
  final void Function(String, String, Map<String, dynamic>) onResult;
  final void Function(Map<String, dynamic>, int) respond;
  final Set<String> _seen = {};
  final Set<String> _cancelled = {};
  Future<void> _tail = Future.value();
  int? _epoch;

  void _useEpoch(int epoch) {
    if (_epoch == epoch) return;
    _epoch = epoch;
    _seen.clear();
    _cancelled.clear();
  }

  void cancel(List<String> ids, int epoch) {
    _useEpoch(epoch);
    _cancelled.addAll(ids);
  }

  Future<void> dispatch(Map<String, dynamic> message, int epoch) {
    _useEpoch(epoch);
    final calls = message['functionCalls'];
    if (calls is! List) return Future.value();
    for (final call in calls) {
      if (call is! Map) continue;
      final id = call['id'];
      final name = call['name'];
      if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
        continue;
      }
      if (!_seen.add(id)) continue;
      final rawArgs = call['args'];
      final args = rawArgs is Map
          ? rawArgs.cast<String, dynamic>()
          : <String, dynamic>{};
      _tail = _tail.then((_) async {
        if (!isCurrent(epoch) || _cancelled.contains(id)) return;
        onCall(id, name, args);
        Map<String, dynamic> result;
        try {
          result = await execute(name, args);
        } catch (error) {
          result = {'ok': false, 'error': error.toString()};
        }
        // Preserve committed outcomes in the durable log even when a socket
        // has disappeared. Never replay a result on a new connection.
        onResult(id, name, result);
        if (!isCurrent(epoch) || _cancelled.contains(id)) return;
        respond({
          'toolResponse': {
            'functionResponses': [
              {
                'id': id,
                'name': name,
                'response': {'result': result},
              },
            ],
          },
        }, epoch);
      });
    }
    return _tail;
  }

  Future<void> get settled => _tail;
}
