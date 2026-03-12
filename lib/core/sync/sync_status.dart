/// Sync status types and result containers.
library;

/// Status of a single pending write.
enum SyncItemStatus {
  /// Successfully synced to server.
  synced,

  /// Waiting to be synced (queued locally).
  pending,

  /// Sync attempted but server returned a conflict (e.g. duplicate key).
  conflicted,

  /// Too old to sync — will be discarded.
  stale,

  /// Sync failed after retries.
  failed,
}

/// Overall sync engine status (for UI consumption).
enum SyncEngineStatus {
  /// No pending writes, everything is synced.
  idle,

  /// Currently flushing pending writes.
  syncing,

  /// Some writes failed and are still pending.
  hasFailures,
}

/// Result of a single `flush` operation.
class SyncFlushResult {
  const SyncFlushResult({
    this.synced = 0,
    this.failed = 0,
    this.discarded = 0,
    this.skippedBackoff = 0,
  });

  /// Number of items successfully synced.
  final int synced;

  /// Number of items that failed and will be retried later.
  final int failed;

  /// Number of items discarded due to staleness or corruption.
  final int discarded;

  /// Number of items skipped because they are in backoff cooldown.
  final int skippedBackoff;

  /// Total items processed (synced + failed + discarded).
  int get total => synced + failed + discarded + skippedBackoff;

  /// True if all processed items were synced or discarded.
  bool get isFullyResolved => failed == 0 && skippedBackoff == 0;
}
