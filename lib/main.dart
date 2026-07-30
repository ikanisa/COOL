import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/env/app_env.dart';
import 'app/router.dart';
import 'app/theme/collect_colors.dart';
import 'core/logging/app_logger.dart';
import 'shared/repositories/collect_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  final env = AppEnv.fromEnvironment();
  AppLogger.instance.i('Collect starting in ${env.environmentName} mode');

  const mobileEvidenceMode = bool.fromEnvironment(
    'COLLECT_MOBILE_EVIDENCE_MODE',
  );

  runApp(
    ProviderScope(
      overrides: [
        appEnvProvider.overrideWithValue(env),
        collectIncomingAppLinksProvider.overrideWithValue(
          AppLinks().uriLinkStream,
        ),
        if (mobileEvidenceMode)
          appRouterProvider.overrideWithValue(
            createAppRouter(initialLocation: '/home'),
          ),
        if (mobileEvidenceMode)
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.fixture(),
          )
        else if (env.hasAppReviewAuthConfig)
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.appReviewDemo(),
          ),
      ],
      child: const CollectApp(),
    ),
  );
}
