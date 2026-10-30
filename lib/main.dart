import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/env/app_env.dart';
import 'app/router.dart';
import 'app/theme/collect_colors.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/collect_diagnostic_queue.dart';
import 'core/logging/collect_member_diagnostics.dart';
import 'core/notifications/collect_notification_service.dart';
import 'core/startup/collect_global_error_handlers.dart';
import 'core/startup/collect_startup_controller.dart';
import 'core/startup/collect_startup_host.dart';
import 'core/cloudflare/cloudflare_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = AppEnv.fromEnvironment();
  final diagnosticQueue = CollectDiagnosticQueue(
    surface: CollectDiagnosticSurface.member,
    store: CollectPreferenceDiagnosticStore(CollectDiagnosticSurface.member),
  );
  final diagnosticBinding = CollectMemberDiagnostics(diagnosticQueue);
  final diagnostics = CollectDiagnostics(
    surface: CollectDiagnosticSurface.member,
    environmentName: env.environmentName,
    sink: (event) {
      debugPrint(event);
      diagnosticQueue.add(event);
    },
  );
  final startup = CollectStartupController<CollectCloudflareClient?>(
    initialize: () async {
      final backend = await createCollectBackendClientFromEnvironment(
        environment: env,
      );
      diagnosticBinding.bind(backend);
      return backend;
    },
    diagnostics: diagnostics,
  );
  CollectGlobalErrorHandlers(
    diagnostics: diagnostics,
    onApplicationFault: startup.reportApplicationFailure,
  ).install();
  configureCollectAndroidPushBackgroundHandler();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: CollectColors.transparentColor,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: CollectColors.referenceChromeBlack,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
      systemNavigationBarDividerColor: CollectColors.transparentColor,
    ),
  );

  const mobileEvidenceMode = bool.fromEnvironment(
    'COLLECT_MOBILE_EVIDENCE_MODE',
  );

  runApp(
    CollectStartupHost<CollectCloudflareClient?>(
      controller: startup,
      application: (backend) => ProviderScope(
        overrides: [
          appEnvProvider.overrideWithValue(env),
          collectBackendClientProvider.overrideWithValue(backend),
          collectIncomingAppLinksProvider.overrideWithValue(
            AppLinks().uriLinkStream,
          ),
          if (mobileEvidenceMode)
            appRouterProvider.overrideWithValue(
              createAppRouter(initialLocation: '/home'),
            ),
        ],
        child: const CollectApp(),
      ),
    ),
  );
}
