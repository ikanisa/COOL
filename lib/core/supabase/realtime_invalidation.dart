// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

const collectMobileRealtimeAreas = <String>{
  'profiles',
  'collections',
  'members',
  'payment_intents',
  'payments',
  'allocations',
  'ledger',
  'receivers',
  'sms_events',
};

const collectAdminRealtimeAreas = <String>{
  ...collectMobileRealtimeAreas,
  'admin_roles',
  'audit',
  'feature_flags',
  'settings',
  'system_health',
};

class RealtimeInvalidationSubscription {
  RealtimeInvalidationSubscription({
    required SupabaseClient client,
    required String topic,
    required Set<String> areas,
    required FutureOr<void> Function() onInvalidate,
    Duration debounce = const Duration(milliseconds: 350),
  }) : _client = client,
       _topic = topic,
       _areas = areas,
       _onInvalidate = onInvalidate,
       _debounce = debounce;

  final SupabaseClient _client;
  final String _topic;
  final Set<String> _areas;
  final FutureOr<void> Function() _onInvalidate;
  final Duration _debounce;

  RealtimeChannel? _channel;
  Timer? _timer;

  void start() {
    if (_channel != null || _areas.isEmpty) return;
    _channel = _client
        .channel(_topic)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'app_realtime_events',
          callback: _handleEvent,
        )
        .subscribe();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await channel.unsubscribe();
    }
  }

  void _handleEvent(PostgresChangePayload payload) {
    final area = payload.newRecord['area'];
    if (area is! String || !_areas.contains(area)) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      unawaited(Future<void>.sync(_onInvalidate));
    });
  }
}
