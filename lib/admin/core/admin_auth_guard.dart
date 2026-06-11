import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_module.dart';

final adminAuthGuardProvider = Provider<AdminAuthGuard>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return AdminAuthGuard(isAuthorized: client?.auth.currentSession != null);
});

class AdminAuthGuard {
  const AdminAuthGuard({required this.isAuthorized});

  final bool isAuthorized;
}
