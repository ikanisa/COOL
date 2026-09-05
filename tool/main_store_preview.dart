import '../test/fixtures/collect_repository_fixture.dart';

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Store-artwork-only entry point.
///
/// This target is never referenced by an Xcode build configuration or mobile
/// release wrapper. It renders deterministic synthetic data so App Store
/// screenshots can show the current product without connecting to production,
/// exposing customer data, or embedding a reviewer authentication bypass.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final repository = FixtureCollectRepository(
    fixtureNow: DateTime.utc(2026, 8, 20, 12),
  );
  final router = createAppRouter(initialLocation: '/home');

  runApp(
    ProviderScope(
      overrides: [
        appEnvProvider.overrideWithValue(
          const AppEnv(
            supabaseUrl: '',
            supabaseAnonKey: '',
            publicUrl: defaultCollectPublicUrl,
            adminAppUrl: defaultCollectAdminUrl,
            enableSmsReader: false,
            enableAndroidSmsAccess: false,
            enableAdminPanel: false,
            enableAdminDevTools: false,
            authCaptchaEnabled: false,
            authCaptchaProvider: '',
            authCaptchaSiteKey: '',
            environmentName: 'store-preview',
          ),
        ),
        collectRepositoryProvider.overrideWith((ref) => repository),
        appRouterProvider.overrideWithValue(router),
        collectIncomingAppLinksProvider.overrideWithValue(
          AppLinks().uriLinkStream,
        ),
      ],
      child: const CollectApp(),
    ),
  );
}
