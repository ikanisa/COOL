import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_module.dart';

final adminAuthStateProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream<AuthState>.empty();
  return client.auth.onAuthStateChange;
});

final adminAuthGuardProvider = Provider<AdminAuthGuard>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final streamedSession = ref
      .watch(adminAuthStateProvider)
      .valueOrNull
      ?.session;
  return AdminAuthGuard(
    isAuthorized: (streamedSession ?? client?.auth.currentSession) != null,
  );
});

class AdminAuthGuard {
  const AdminAuthGuard({required this.isAuthorized});

  final bool isAuthorized;
}
