/// Abstract repository contracts.
///
/// These define the interface for repositories that can operate offline
/// and sync later, and for read-only repositories with optional caching.
library;

import '../sync/sync_status.dart';

/// Contract for repositories that support offline write-then-sync.
///
/// Implementors queue writes locally when offline and sync them to the
/// server when connectivity returns.
///
/// Type parameter [T] is the result type for a successful create operation.
abstract class OfflineCapableRepository<T> {
  /// Sync all pending writes for the given [userId].
  ///
  /// Returns a [SyncFlushResult] summarizing what was synced, failed, etc.
  Future<SyncFlushResult> syncPending({required String userId});

  /// Returns the number of unsynced items for the given [userId].
  Future<int> pendingCount({required String userId});
}

/// Contract for read-only repositories with optional caching.
///
/// Implementors fetch data from the server and optionally cache results
/// locally for a configurable TTL.
abstract class ReadRepository<T> {
  /// Fetch a list of items, optionally from cache.
  Future<List<T>> list({bool forceRefresh = false});

  /// Fetch a single item by [id], optionally from cache.
  Future<T?> get(String id, {bool forceRefresh = false});
}
