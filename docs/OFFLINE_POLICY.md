# Offline Policy

> Staleness rules, conflict resolution, and per-domain sync behavior.
> Source of truth: `lib/core/sync/sync_engine.dart`
> Last updated: March 2026

## Architecture Overview

The app uses an **explicit sync engine** backed by Hive (local storage). Offline writes are queued and flushed when the caller triggers `flush()`. There is **no automatic background sync** — this keeps behavior testable and predictable.

```
User action → Repository
  → Online: write to Supabase directly
  → Offline: enqueue to SyncEngine (Hive) → flush later
```

## Sync Engine Configuration

| Parameter | Default | Description |
|---|---|---|
| `maxAttempts` | 10 | Max retries before a pending write is discarded |
| `staleDuration` | 48 hours | Entries older than this are discarded on flush |
| `boxName` | `sync_engine_queue` | Hive box name for the pending queue |

## Staleness Rules

| Condition | Action |
|---|---|
| Entry age > 48 hours | Discarded (data likely stale) |
| Retry count > 10 | Discarded (persistent failure) |
| Successful sync | Removed from queue |
| Network error on flush | Increment attempt count, exponential backoff |

## Per-Domain Sync Behavior

| Domain | Offline Behavior | Sync Strategy | Conflict Resolution |
|---|---|---|---|
| **Trips** (`trip`) | Queued in `SyncEngine` | Explicit flush on reconnect | Server wins (latest timestamp) |
| **MoMo Pending** (`momo_pending`) | Queued in `SyncEngine` | Explicit flush on reconnect | Server wins (idempotent by transaction ID) |
| **User Profile** | Cached in Hive | Read from cache, write-through when online | Server wins |
| **Groups** | Cached in Hive | Read from cache, write-through when online | Server wins |
| **Feature Flags** | Cached by Remote Config SDK | 4-hour minimum fetch interval | Latest fetch wins |
| **Analytics Events** | Batched by Firebase SDK | Firebase handles offline batching | N/A (append-only) |

## Network Status Detection

Located in `lib/core/sync/network_status.dart`:

- Heuristic-based: matches common connectivity error messages
- No active polling or connectivity plugin dependency
- Repository methods catch network errors and route to `SyncEngine.enqueue()`

## User-Facing Behavior

### When Offline
- **Read operations**: Serve from Hive cache (may be stale)
- **Write operations**: Queued silently, no error shown to user
- **UI indicator**: `SyncEngine.status` exposes `SyncEngineStatus` via `ValueNotifier` for UI consumption
- **Empty state**: If cache is empty and offline, show "You're offline" empty state

### When Reconnecting
- Caller triggers `flush(domain, handler)` with the appropriate sync handler
- Pending writes processed in FIFO order
- Exponential backoff with jitter on failures
- Status notifier updates UI (syncing → idle / error)

### When Sync Fails Permanently
- Entry discarded after 10 attempts or 48 hours
- No user notification for silently discarded entries (fire-and-forget)
- Errors logged to Crashlytics via breadcrumbs

## Conflict Resolution Strategy

**Server wins** — the server is the source of truth for all persistent data.

Rationale:
- Financial data (MoMo, wallet) must reflect actual server state
- Trip data is multi-party (driver + rider) so server coordinates
- Groups have multiple members writing concurrently

The sync engine is designed for **eventual consistency**, not real-time conflict resolution.

## Cache Invalidation

| Data | Cache Location | TTL | Invalidation Trigger |
|---|---|---|---|
| User profile | Hive | None (persisted) | Login/logout, profile update |
| Feature flags | Remote Config | 4 hours | App restart, manual fetch |
| Trip data | Hive | None (persisted) | Trip completion, sync flush |
| Group data | Hive | None (persisted) | Group update, sync flush |

## Testing Offline Behavior

```bash
# 1. Enable airplane mode on device
# 2. Perform write operations (schedule trip, send MoMo)
# 3. Verify writes are queued: check SyncEngine.status
# 4. Disable airplane mode
# 5. Trigger flush (navigate to relevant screen)
# 6. Verify writes synced to server
```

Unit tests for the sync engine are in `test/core/sync/sync_engine_test.dart` and use an injectable Hive box opener for isolation.
