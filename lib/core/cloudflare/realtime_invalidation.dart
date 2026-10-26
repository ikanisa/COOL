import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:realtime_client/realtime_client.dart' show WebSocketTransport;

import 'collect_cloudflare_client.dart';
import '../supabase/collect_supabase_member_realtime.dart';

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

/// Authorized HTTP polling remains the fallback. Native Supabase members may
/// also receive private hints; only the SDK server acknowledgement joins that
/// channel. A timer or polling response never acknowledges a Realtime join.
class CollectSyncInvalidationSubscription {
  CollectSyncInvalidationSubscription({
    required CollectCloudflareClient client,
    required String topic,
    required Set<String> areas,
    required FutureOr<void> Function() onInvalidate,
    FutureOr<void> Function(Set<String> areas)? onInvalidateAreas,
    this.onStatus,
    this.onAuthorityDenied,
    this.realtimeTransport,
    this.observeRealtimeLifecycle = true,
    DateTime Function()? currentTime,
    String? ownerUserId,
    Duration debounce = const Duration(milliseconds: 350),
  }) : _now = currentTime ?? DateTime.now,
       _client = client,
       _areas = Set.unmodifiable(areas),
       _ownerUserId = ownerUserId ?? client.auth.currentUser?.id,
       _sessionId = client.auth.currentSession?.claims['session_id'] as String?,
       _authSubject = client.auth.currentSession?.authSubject,
       _coordinator = CollectSyncInvalidationCoordinator(
         areas: areas,
         onInvalidate: onInvalidate,
         onInvalidateAreas: onInvalidateAreas,
         debounce: debounce,
       );
  final DateTime Function() _now;
  final CollectCloudflareClient _client;
  final void Function(CollectSyncStatus status, Object? error)? onStatus;

  /// Current bearer only; called before any debounce or subsequent await.
  final FutureOr<void> Function(String deniedBearer)? onAuthorityDenied;
  final WebSocketTransport? realtimeTransport;
  final bool observeRealtimeLifecycle;
  CollectSupabaseMemberRealtime? _memberRealtime;
  bool _foreground = true;
  DateTime? _lastReconciliation;
  final Set<String> _areas;
  final String? _ownerUserId;
  final String? _sessionId;
  final String? _authSubject;
  final CollectSyncInvalidationCoordinator _coordinator;
  Timer? _timer;
  bool _disposed = false;
  bool _polling = false;
  bool _started = false;
  int _failures = 0;
  String _cursor = '0';
  bool get _ownerCurrent =>
      _ownerUserId != null &&
      _client.auth.currentUser?.id == _ownerUserId &&
      _client.auth.currentSession?.claims['session_id'] == _sessionId &&
      _client.auth.currentSession?.authSubject == _authSubject &&
      (_memberRealtime?.ownsCurrentSession ?? true);
  void start() {
    if (_disposed || _started || _coordinator.isEmpty || !_ownerCurrent) return;
    _started = true;
    if (!kIsWeb &&
        _client.supabaseConfiguration != null &&
        _client.auth.surface == 'member') {
      _memberRealtime = CollectSupabaseMemberRealtime(
        client: _client,
        transport: realtimeTransport,
        observeLifecycle: observeRealtimeLifecycle,
        onReconcile: () {
          if (!_disposed && _ownerCurrent) _coordinator.reconcileAll();
        },
        onConnectionChanged: (connected) {
          if (_disposed || !_ownerCurrent) return;
          _coordinator.connectionStatus(
            connected
                ? CollectSyncStatus.connected
                : CollectSyncStatus.disconnected,
          );
          onStatus?.call(
            connected
                ? CollectSyncStatus.connected
                : CollectSyncStatus.disconnected,
            null,
          );
          _timer?.cancel();
          _timer = null;
          if (_foreground) unawaited(_poll());
        },
        onForegroundChanged: (foreground) {
          if (_disposed || !_ownerCurrent) return;
          _foreground = foreground;
          _timer?.cancel();
          _timer = null;
          if (foreground) unawaited(_poll());
        },
      )..start();
      _foreground = _memberRealtime!.isForeground;
    }
    unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_disposed || _polling || !_ownerCurrent || !_foreground) return;
    _polling = true;
    Duration? failureDelay;
    try {
      if (_memberRealtime != null && _client.auth.currentSession!.isExpired) {
        final expired = _client.auth.currentSession!.accessToken;
        try {
          await _client.auth.refreshSession();
        } catch (_) {
          if (_ownerCurrent &&
              _client.auth.currentSession?.accessToken == expired &&
              _client.auth.currentSession!.isExpired) {
            await _client.auth.clearLocalSession();
          }
          rethrow;
        }
        if (_disposed || !_ownerCurrent || !_foreground) return;
      }
      final bearer = _client.auth.currentSession!.accessToken;
      final (status, data) = await _client.request(
        'GET',
        'v1/sync',
        bearer: bearer,
        responseLimit: 131072,
        query: {
          'cursor': _cursor,
          'limit': '100',
          'areas': (_areas.toList()..sort()).join(','),
        },
      );
      if (_disposed || !_ownerCurrent || !_foreground) return;
      // An old JWT reply cannot deny or invalidate a rotated token scope.
      if (_memberRealtime != null &&
          bearer != _client.auth.currentSession?.accessToken) {
        return;
      }
      if (_memberRealtime != null && (status == 401 || status == 403)) {
        _memberRealtime!.authorityDenied();
        final denial = onAuthorityDenied;
        if (denial != null) {
          await denial(bearer);
        } else {
          _coordinator.reconcileAll();
        }
        return;
      }
      if (status != 200 ||
          data is! Map<String, dynamic> ||
          data['events'] is! List ||
          (data['events'] as List).length > 100 ||
          data['cursor'] is! String ||
          !RegExp(r'^[0-9]{1,20}$').hasMatch(data['cursor'] as String) ||
          BigInt.parse(data['cursor'] as String) < BigInt.parse(_cursor)) {
        throw const CollectApiException(code: 'invalid_sync_response');
      }
      final events = data['events'] as List;
      if (events.any(
        (row) =>
            row is! Map<String, dynamic> ||
            row['id'] is! String ||
            (row['id'] as String).isEmpty ||
            row['area'] is! String,
      )) {
        throw const CollectApiException(code: 'invalid_sync_response');
      }
      _coordinator.connectionStatus(CollectSyncStatus.connected);
      // Poll success permits scoped fallback invalidation; native public status
      // remains the actual private-channel acknowledgement, never this HTTP200.
      if (_memberRealtime == null) {
        onStatus?.call(CollectSyncStatus.connected, null);
      }
      for (final row in events) {
        _coordinator.event(row as Map<String, dynamic>);
      }
      _cursor = data['cursor'] as String;
      if (_memberRealtime != null &&
          (_lastReconciliation == null ||
              _now().difference(_lastReconciliation!) >=
                  const Duration(seconds: 60))) {
        _lastReconciliation = _now();
        _coordinator.reconcileAll();
      }
      _failures = 0;
    } catch (_) {
      if (_disposed || !_ownerCurrent || !_foreground) return;
      _coordinator.connectionStatus(CollectSyncStatus.disconnected);
      if (_memberRealtime == null) {
        onStatus?.call(CollectSyncStatus.disconnected, null);
      }
      _failures = (_failures + 1).clamp(1, 5);
      failureDelay = Duration(seconds: (1 << _failures).clamp(5, 60));
    } finally {
      _polling = false;
      if (!_disposed && _ownerCurrent && _foreground) {
        final delay =
            failureDelay ??
            Duration(seconds: _memberRealtime?.isConnected == true ? 60 : 5);
        _timer = Timer(delay, () => unawaited(_poll()));
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _coordinator.dispose();
    await _memberRealtime?.dispose();
    _memberRealtime = null;
  }
}

/// Only invalidation IDs enter this coordinator. Financial rows are always
/// refetched through scoped RPCs after a join or a relevant event.
class CollectSyncInvalidationCoordinator {
  CollectSyncInvalidationCoordinator({
    required Set<String> areas,
    required FutureOr<void> Function() onInvalidate,
    FutureOr<void> Function(Set<String> areas)? onInvalidateAreas,
    Duration debounce = const Duration(milliseconds: 350),
  }) : this._(areas, onInvalidate, onInvalidateAreas, debounce);

  CollectSyncInvalidationCoordinator._(
    this._areas,
    this._onInvalidate,
    this._onInvalidateAreas,
    this._debounce,
  );

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

  void connectionStatus(CollectSyncStatus status) {
    if (_disposed) return;
    if (status == CollectSyncStatus.connected) {
      if (_connected) return;
      _connected = true;
      // A change between the last RPC read and the new Realtime join is not
      // replayed by the channel. Reconcile once after every successful join.
      reconcileAll();
    } else {
      _connected = false;
    }
  }

  /// Request authoritative reads without manufacturing a join or row event.
  void reconcileAll() {
    if (_disposed) return;
    _pendingAreas.addAll(_areas);
    _scheduleInvalidation();
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
