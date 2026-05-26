/// Coarse-grained state for the sync pipeline. Surfaced to the UI as a
/// status pill on the home screen.
enum SyncStatus {
  /// Never run since the engine started (or no remote account attached).
  idle,

  /// Pull or push in progress.
  syncing,

  /// Last cycle completed with no remaining dirty rows.
  synced,

  /// Last cycle failed. `SyncEngine.lastError` holds the cause.
  error,
}
