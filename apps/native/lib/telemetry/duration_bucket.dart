/// Bucket labels for client-observed latency metrics (voice connect,
/// time-to-first-response). Mirrors the shape of the backend's
/// `costBucket`/`functionDurationBucket` helpers — a continuous value turned
/// into a fixed label for a bar-chart-shaped distribution, not a true
/// cumulative histogram (see docs/metrics/error-rate-and-latency.md).
String clientDurationBucket(int elapsedMs) {
  if (elapsedMs < 250) return '0-250';
  if (elapsedMs < 500) return '250-500';
  if (elapsedMs < 1000) return '500-1000';
  if (elapsedMs < 2500) return '1000-2500';
  if (elapsedMs < 5000) return '2500-5000';
  return '5000+';
}

/// Same shape, wider/coarser scale — matches the backend's
/// `system.function.duration_bucket_count` buckets, which native reuses when
/// reporting `sync_pull` latency (the one call the backend can't time itself,
/// since `pull` is a Convex query with no telemetry write access).
String functionDurationBucket(int elapsedMs) {
  if (elapsedMs < 100) return '0-100';
  if (elapsedMs < 250) return '100-250';
  if (elapsedMs < 500) return '250-500';
  if (elapsedMs < 1000) return '500-1000';
  if (elapsedMs < 2500) return '1000-2500';
  if (elapsedMs < 5000) return '2500-5000';
  return '5000+';
}
