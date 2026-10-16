import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/cloudflare_admin_app.dart';
import 'admin/core/admin_account_api.dart';
import 'admin/core/admin_auth_guard.dart';
import 'admin/core/admin_repository_base.dart';
import 'admin/core/cloudflare_admin_account_api.dart';
import 'admin/core/cloudflare_admin_repository.dart';
import 'admin/core/cloudflare_admin_session.dart';
import 'core/supabase/supabase_module.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ProviderScope(
      overrides: cloudflareAdminOverrides(),
      child: const CloudflareAdminApp(),
    ),
  );
}

List<Override> cloudflareAdminOverrides() => [
  // Never initialize or fall back to Supabase, even when the host build
  // environment still contains legacy public configuration.
  supabaseClientProvider.overrideWithValue(null),
  adminAccountApiProvider.overrideWith(
    (ref) => CloudflareAdminAccountApi(
      ref.read(cloudflareAdminSessionProvider.notifier),
    ),
  ),
  adminAuthUserIdProvider.overrideWith(
    (ref) => ref.watch(cloudflareAdminSessionProvider).asData?.value?.id,
  ),
  adminAuthGuardProvider.overrideWith(
    (ref) => AdminAuthGuard(
      isAuthorized:
          ref.watch(cloudflareAdminSessionProvider).asData?.value != null,
    ),
  ),
  adminAuthSessionScopeProvider.overrideWith((ref) {
    final controller = _CloudflareSessionScope();
    controller.update(ref.read(cloudflareAdminSessionProvider).asData?.value);
    ref.listen(
      cloudflareAdminSessionProvider,
      (_, next) => controller.update(next.asData?.value),
    );
    return controller;
  }),
  adminRepositoryProvider.overrideWith((ref) {
    ref.watch(
      cloudflareAdminSessionProvider.select(
        (session) => session.asData?.value?.authorityKey,
      ),
    );
    return CloudflareAdminRepository(
      ref.read(cloudflareAdminSessionProvider.notifier),
    );
  }),
];

class _CloudflareSessionScope extends AdminSessionController {
  _CloudflareSessionScope() : super(null);
  int _generation = 0;
  Object? _authority;
  void update(CloudflareAdminUser? user) {
    final next = user == null
        ? null
        : (userId: user.id, sessionId: user.sessionId);
    final authority = user?.authorityKey;
    if (_authority == authority) return;
    _authority = authority;
    _generation++;
    state = next == null ? null : (key: next, generation: _generation);
  }
}
