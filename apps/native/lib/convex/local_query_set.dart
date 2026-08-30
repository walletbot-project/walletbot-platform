import 'dart:convert';

import 'protocol.dart';

/// The client's own subscription registry and querySet version counter
/// (≈ convex-js `local_state.ts`).
///
/// Identical (udfPath, args) subscriptions share one queryId via refcounting.
/// QueryIds are stable across reconnects; the querySet version resets to 0 on
/// every fresh socket and [restart] re-adds every live query as one `0 → 1`
/// modification.

class LocalQuery {
  LocalQuery({
    required this.queryId,
    required this.udfPath,
    required this.argsJson,
  });

  final int queryId;
  final String udfPath;
  final Map<String, Object?> argsJson;
  String? journal;
  bool hasJournal = false;
  int refCount = 0;
}

class LocalQuerySet {
  int _nextQueryId = 0;
  int version = 0;
  final Map<String, LocalQuery> _byKey = {};
  final Map<int, LocalQuery> _byId = {};

  Iterable<LocalQuery> get queries => _byId.values;

  LocalQuery? byId(int queryId) => _byId[queryId];

  static String queryKey(String udfPath, Map<String, Object?> argsJson) =>
      jsonEncode([udfPath, argsJson]);

  /// Registers a subscriber. Returns the query and, when this is the first
  /// subscriber for the key, the ModifyQuerySet message to send.
  (LocalQuery, ModifyQuerySetMessage?) subscribe(
    String udfPath,
    Map<String, Object?> argsJson,
  ) {
    final key = queryKey(udfPath, argsJson);
    final existing = _byKey[key];
    if (existing != null) {
      existing.refCount++;
      return (existing, null);
    }
    final query = LocalQuery(
      queryId: _nextQueryId++,
      udfPath: udfPath,
      argsJson: argsJson,
    )..refCount = 1;
    _byKey[key] = query;
    _byId[query.queryId] = query;
    final message = ModifyQuerySetMessage(
      baseVersion: version,
      newVersion: ++version,
      modifications: [
        AddQueryModification(
          queryId: query.queryId,
          udfPath: query.udfPath,
          argsJson: query.argsJson,
          journal: query.journal,
          hasJournal: query.hasJournal,
        ),
      ],
    );
    return (query, message);
  }

  /// Drops one subscriber. Returns the Remove message when the last
  /// subscriber for the query is gone.
  ModifyQuerySetMessage? unsubscribe(LocalQuery query) {
    if (_byId[query.queryId] != query) return null;
    query.refCount--;
    if (query.refCount > 0) return null;
    _byId.remove(query.queryId);
    _byKey.remove(queryKey(query.udfPath, query.argsJson));
    return ModifyQuerySetMessage(
      baseVersion: version,
      newVersion: ++version,
      modifications: [RemoveQueryModification(queryId: query.queryId)],
    );
  }

  void saveJournal(int queryId, String? journal) {
    final query = _byId[queryId];
    if (query == null) return;
    query.journal = journal;
    query.hasJournal = true;
  }

  /// Resets the version for a fresh socket and returns the message re-adding
  /// every live subscription with its last known journal. Null when there are
  /// no subscriptions.
  ModifyQuerySetMessage? restart() {
    version = 0;
    if (_byId.isEmpty) return null;
    return ModifyQuerySetMessage(
      baseVersion: 0,
      newVersion: ++version,
      modifications: [
        for (final query in _byId.values)
          AddQueryModification(
            queryId: query.queryId,
            udfPath: query.udfPath,
            argsJson: query.argsJson,
            journal: query.journal,
            hasJournal: query.hasJournal,
          ),
      ],
    );
  }
}
