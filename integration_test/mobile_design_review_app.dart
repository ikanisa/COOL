import '../test/fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Interactive, synthetic QA target. Uses the normal Android rendering surface
/// so OS screenshots can independently verify integration-test captures.
/// This target is never imported by the production application.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (appFlavor != 'dev' ||
      kReleaseMode ||
      !const bool.fromEnvironment('COLLECT_MOBILE_EVIDENCE_MODE')) {
    throw StateError(
      'Design review requires an explicit non-release dev build.',
    );
  }

  final repository = FixtureCollectRepository(
    fixtureNow: DateTime.utc(2026, 9, 2, 10),
  );
  final router = createAppRouter(
    initialLocation: const String.fromEnvironment(
      'COLLECT_DESIGN_REVIEW_ROUTE',
      defaultValue: '/settings',
    ),
    routeRedirect: (state) => collectAuthenticationRedirect(
      uri: state.uri,
      hasProfile: repository.state.currentProfile != null,
      isLoading: repository.state.isLoading,
    ),
  );
  runApp(
    ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        collectRepositoryProvider.overrideWith((ref) => repository),
        collectThemeModeProvider.overrideWith(
          (ref) => CollectThemeModeController(
            initialMode: ThemeMode.dark,
            loadPersistedMode: false,
          ),
        ),
      ],
      child: const CollectApp(),
    ),
  );
}
