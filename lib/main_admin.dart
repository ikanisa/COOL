import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_app.dart';
import 'admin/core/admin_evidence_mode.dart';
import 'app/env/app_env.dart';
import 'core/logging/app_logger.dart';
import 'core/startup/collect_global_error_handlers.dart';
import 'core/startup/collect_startup_controller.dart';
import 'core/startup/collect_startup_host.dart';
import 'core/cloudflare/cloudflare_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = AppEnv.fromEnvironment();
  final diagnostics = CollectDiagnostics(
    surface: CollectDiagnosticSurface.admin,
    environmentName: env.environmentName,
  );
  final startup = CollectStartupController<CollectCloudflareClient?>(
    initialize: () => createCollectBackendClientFromEnvironment(
      environment: env,
      surface: 'admin',
    ),
    diagnostics: diagnostics,
  );
  CollectGlobalErrorHandlers(
    diagnostics: diagnostics,
    onApplicationFault: startup.reportApplicationFailure,
  ).install();
  runApp(
    CollectStartupHost<CollectCloudflareClient?>(
      controller: startup,
      admin: true,
      application: (backend) => ProviderScope(
        overrides: [
          appEnvProvider.overrideWithValue(env),
          collectBackendClientProvider.overrideWithValue(backend),
          ...adminEvidenceOverrides(),
        ],
        child: adminPwaEvidenceMode
            ? Semantics(
                container: true,
                label: 'Collect admin evidence mode marker',
                child: const CollectAdminApp(),
              )
            : const CollectAdminApp(),
      ),
    ),
  );
}
