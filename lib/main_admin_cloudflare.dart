import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/cloudflare_admin_app.dart';
import 'admin/core/admin_account_api.dart';
import 'admin/core/admin_auth_guard.dart';
import 'admin/core/admin_repository_base.dart';
import 'admin/core/cloudflare_admin_account_api.dart';
import 'admin/core/cloudflare_admin_recovery_host.dart';
import 'admin/core/cloudflare_admin_diagnostics_host.dart';
import 'admin/core/cloudflare_admin_repository.dart';
import 'admin/core/cloudflare_admin_session.dart';
import 'admin/core/cloudflare_admin_sync.dart';
import 'core/cloudflare/cloudflare_module.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/collect_diagnostic_queue.dart';

// Keep web accessibility available for the complete Admin app lifetime,
// including installed windows that do not expose Flutter's opt-in placeholder.
SemanticsHandle? _webSemantics;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    _webSemantics ??= SemanticsBinding.instance.ensureSemantics();
  }
  final diagnosticQueue = CollectDiagnosticQueue(
    surface: CollectDiagnosticSurface.admin,
    store: CollectPreferenceDiagnosticStore(CollectDiagnosticSurface.admin),
  );
  final diagnostics = CollectDiagnostics(
    surface: CollectDiagnosticSurface.admin,
    environmentName: const String.fromEnvironment(
      'APP_ENVIRONMENT',
      defaultValue: 'local',
    ),
    sink: (event) {
      debugPrint(event);
      diagnosticQueue.add(event);
    },
  );
  runApp(
    ProviderScope(
      overrides: cloudflareAdminOverrides(),
      child: CloudflareAdminDiagnosticsHost(
        queue: diagnosticQueue,
        child: CloudflareAdminRecoveryHost(
          diagnostics: diagnostics,
          child: const CloudflareAdminApp(),
        ),
      ),
    ),
  );
}

List<Override> cloudflareAdminOverrides() => [
  // The cookie-authenticated workspace owns its independent session.
  // No bearer client is initialized for this entrypoint.
  collectBackendClientProvider.overrideWithValue(null),
  adminRealtimeSubscriptionProvider.overrideWith((ref) {
    ref.watch(cloudflareAdminSyncSubscriptionProvider);
  }),
  adminLiveUpdateStatusProvider.overrideWith((ref) {
    ref.watch(
      cloudflareAdminSessionProvider.select(
        (value) => value.asData?.value?.authorityKey,
      ),
    );
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    return cloudflareAdminSyncAreas(user).isEmpty
        ? AdminLiveUpdateStatus.unavailable
        : AdminLiveUpdateStatus.connecting;
  }),
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
