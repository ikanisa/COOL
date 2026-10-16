// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

const collectMobileRealtimeAreas = <String>{
  'profiles',
  'collections',
  'members',
  'payment_intents',
  'payments',
  'ledger',
};

const collectAdminRealtimeAreas = <String>{
  ...collectMobileRealtimeAreas,
  'admin_roles',
  'audit',
  'feature_flags',
  'settings',
  'system_health',
  'notifications',
};

class RealtimeInvalidationSubscription {
  RealtimeInvalidationSubscription({
    required SupabaseClient client,
    required String topic,
    required Set<String> areas,
    required FutureOr<void> Function() onInvalidate,
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
    FutureOr<void> Function(Set<String> areas)? onInvalidateAreas,
    String? ownerUserId,
    Duration debounce = const Duration(milliseconds: 350),
  }) : _client = client,
       _topic = topic,
       _ownerUserId = ownerUserId,
       _onStatus = onStatus,
       _coordinator = RealtimeInvalidationCoordinator(
         areas: areas,
         onInvalidate: onInvalidate,
         onInvalidateAreas: onInvalidateAreas,
         debounce: debounce,
       );

  final SupabaseClient _client;
  final String _topic;
  final String? _ownerUserId;
  final void Function(RealtimeSubscribeStatus status, Object? error)? _onStatus;
  final RealtimeInvalidationCoordinator _coordinator;

  RealtimeChannel? _channel;
  Timer? _retryTimer;
  Timer? _stableTimer;
  int _channelGeneration = 0;
  int _retryAttempt = 0;
  bool _restarting = false;
  bool _disposed = false;

  void start() {
    if (_disposed ||
        _channel != null ||
        _coordinator.isEmpty ||
        !_ownerCurrent) {
      return;
    }
    try {
      _subscribe();
    } catch (error) {
      _notifyStatus(RealtimeSubscribeStatus.channelError, error);
      _scheduleRetry();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _coordinator.dispose();
    ++_channelGeneration;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.unsubscribe();
      } catch (_) {
        // Local disposal still blocks callbacks if the socket is already gone.
      }
    }
  }

  bool get _ownerCurrent =>
      _ownerUserId == null || _client.auth.currentUser?.id == _ownerUserId;

  void _subscribe() {
    if (_disposed || !_ownerCurrent) return;
    final generation = ++_channelGeneration;
    final channel = _client
        .channel(_topic)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'app_realtime_events',
          callback: (payload) {
            if (generation == _channelGeneration) _handleEvent(payload);
          },
        );
    _channel = channel;
    channel.subscribe((status, error) {
      if (generation == _channelGeneration) {
        _handleStatus(status, error);
      }
    });
  }

  void _handleStatus(RealtimeSubscribeStatus status, Object? error) {
    if (_disposed || !_ownerCurrent) return;
    _notifyStatus(status, error);
    _coordinator.connectionStatus(status);
    if (status == RealtimeSubscribeStatus.subscribed) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _stableTimer?.cancel();
      _stableTimer = Timer(const Duration(seconds: 30), () {
        _retryAttempt = 0;
      });
      return;
    }
    _stableTimer?.cancel();
    _stableTimer = null;
    if (!_restarting) _scheduleRetry();
  }

  void _notifyStatus(RealtimeSubscribeStatus status, Object? error) {
    if (_disposed || !_ownerCurrent) return;
    try {
      _onStatus?.call(status, error);
    } catch (_) {
      // A presentation observer cannot interrupt recovery or authoritative
      // invalidation. Provider/session disposal remains its own boundary.
    }
  }

  void _scheduleRetry() {
    if (_retryTimer != null || _disposed || !_ownerCurrent) return;
    // The SDK retries ordinary socket drops. Recreate a channel as well when
    // the server rejects its postgres_changes binding after a successful join.
    final seconds = 1 << _retryAttempt.clamp(0, 5);
    if (_retryAttempt < 5) _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      _retryTimer = null;
      unawaited(_restart());
    });
  }

  Future<void> _restart() async {
    if (_disposed || !_ownerCurrent || _restarting) return;
    _restarting = true;
    ++_channelGeneration;
    final previous = _channel;
    _channel = null;
    try {
      await previous?.unsubscribe();
    } catch (_) {
      // A failed unsubscribe is not proof of a live binding. The SDK removes
      // the old channel when its socket closes; a new join is still required.
    } finally {
      _restarting = false;
    }
    if (_disposed || !_ownerCurrent) return;
    try {
      _subscribe();
    } catch (error) {
      _notifyStatus(RealtimeSubscribeStatus.channelError, error);
      _scheduleRetry();
    }
  }

  void _handleEvent(PostgresChangePayload payload) {
    if (_disposed || !_ownerCurrent) return;
    _coordinator.event(payload.newRecord);
  }
}

/// Only invalidation IDs enter this coordinator. Financial rows are always
/// refetched through scoped RPCs after a join or a relevant event.
class RealtimeInvalidationCoordinator {
  RealtimeInvalidationCoordinator({
    required Set<String> areas,
    required FutureOr<void> Function() onInvalidate,
    FutureOr<void> Function(Set<String> areas)? onInvalidateAreas,
    Duration debounce = const Duration(milliseconds: 350),
  }) : _areas = areas,
       _onInvalidate = onInvalidate,
       _onInvalidateAreas = onInvalidateAreas,
       _debounce = debounce;

  final Set<String> _areas;
  final FutureOr<void> Function() _onInvalidate;
  final FutureOr<void> Function(Set<String> areas)? _onInvalidateAreas;
  final Duration _debounce;
  final Set<String> _seenIds = <String>{};
  final Set<String> _pendingAreas = <String>{};
  Timer? _timer;
  bool _connected = false;
  bool _invalidateInFlight = false;
  bool _invalidateRequested = false;
  bool _disposed = false;

  bool get isEmpty => _areas.isEmpty;

  void connectionStatus(RealtimeSubscribeStatus status) {
    if (_disposed) return;
    if (status == RealtimeSubscribeStatus.subscribed) {
      if (_connected) return;
      _connected = true;
      // A change between the last RPC read and the new Realtime join is not
      // replayed by the channel. Reconcile once after every successful join.
      _pendingAreas.addAll(_areas);
      _scheduleInvalidation();
    } else {
      _connected = false;
    }
  }

  void event(Map<String, dynamic> row) {
    if (_disposed || !_connected || !_areas.contains(row['area'])) return;
    final id = row['id'];
    if (id is String && id.isNotEmpty) {
      if (!_seenIds.add(id)) return;
      if (_seenIds.length > 256) _seenIds.remove(_seenIds.first);
    }
    _pendingAreas.add(row['area'] as String);
    _scheduleInvalidation();
  }

  void _scheduleInvalidation() {
    // Leading debounce: a continuous stream cannot postpone a refresh forever.
    if (_timer != null) return;
    _timer = Timer(_debounce, () {
      _timer = null;
      unawaited(_invalidate());
    });
  }

  Future<void> _invalidate() async {
    if (_disposed) return;
    if (_invalidateInFlight) {
      _invalidateRequested = true;
      return;
    }
    _invalidateInFlight = true;
    try {
      _invalidateRequested = false;
      await _refreshOnce();
      if (_invalidateRequested && !_disposed) {
        _invalidateRequested = false;
        await _refreshOnce();
      }
    } finally {
      final needsAnotherWindow = _invalidateRequested && !_disposed;
      _invalidateRequested = false;
      _invalidateInFlight = false;
      if (needsAnotherWindow) _scheduleInvalidation();
    }
  }

  Future<void> _refreshOnce() async {
    final areas = Set<String>.unmodifiable(_pendingAreas);
    _pendingAreas.clear();
    try {
      await _onInvalidateAreas?.call(areas);
    } catch (_) {
      // A presentation/access observer cannot suppress the authoritative read.
    }
    if (_disposed) return;
    try {
      await Future<void>.sync(_onInvalidate);
    } catch (_) {
      // The next event or reconnect retries. Do not leak RPC error details
      // through an uncaught asynchronous Realtime callback.
    }
  }

  void dispose() {
    _disposed = true;
    _connected = false;
    _timer?.cancel();
    _timer = null;
    _seenIds.clear();
    _pendingAreas.clear();
  }
}
