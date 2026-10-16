import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_module.dart';
import 'admin_auth_guard.dart';

/// Socket connectivity is separate from successful authoritative data reads.
/// A join never updates the workspace's last-successful-refresh timestamp.
enum AdminLiveUpdateStatus { unavailable, connecting, live, reconnecting }

extension AdminLiveUpdateStatusDisplay on AdminLiveUpdateStatus {
  String get label => switch (this) {
    AdminLiveUpdateStatus.unavailable => 'Live updates unavailable',
    AdminLiveUpdateStatus.connecting => 'Connecting live updates',
    AdminLiveUpdateStatus.live => 'Live updates',
    AdminLiveUpdateStatus.reconnecting => 'Reconnecting live updates',
  };
}

AdminLiveUpdateStatus adminLiveUpdateStatusFor(
  RealtimeSubscribeStatus status,
) => status == RealtimeSubscribeStatus.subscribed
    ? AdminLiveUpdateStatus.live
    : AdminLiveUpdateStatus.reconnecting;

final adminLiveUpdateStatusProvider = StateProvider<AdminLiveUpdateStatus>((
  ref,
) {
  // Includes the scope generation, so A -> B -> A and replacement logins by
  // the same operator cannot inherit a departed socket's connected status.
  final scope = ref.watch(adminAuthSessionScopeProvider);
  final client = ref.watch(supabaseClientProvider);
  return scope != null && client != null
      ? AdminLiveUpdateStatus.connecting
      : AdminLiveUpdateStatus.unavailable;
});
