import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../test/fixtures/contribution_layout_repository_fixture.dart';

void main() {
  const enabled = bool.fromEnvironment('COLLECT_MOBILE_EVIDENCE_MODE');
  final origin = Uri.base;
  if (!enabled ||
      origin.scheme != 'http' ||
      !const {'127.0.0.1', 'localhost'}.contains(origin.host)) {
    throw StateError(
      'The member route fixture requires an HTTP loopback host.',
    );
  }

  WidgetsFlutterBinding.ensureInitialized();
  final initialLocation = origin.fragment.isEmpty ? '/' : origin.fragment;
  final signedIn = Uri.parse(initialLocation).path != '/auth';
  final repository = ContributionLayoutRepository(
    seeded: signedIn,
    fixtureNow: DateTime.utc(2026, 9, 2, 10),
  );
  runApp(
    ProviderScope(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        collectAuthenticatedUserIdProvider.overrideWith(
          (ref) => ref.watch(
            collectRepositoryProvider.select(
              (state) => state.currentProfile?.id,
            ),
          ),
        ),
        collectRepositoryProvider.overrideWith((ref) => repository),
        appRouterProvider.overrideWith((ref) {
          final router = createAppRouter(
            initialLocation: initialLocation,
            routeRedirect: (state) => collectAuthenticationRedirect(
              uri: state.uri,
              hasProfile: signedIn,
              isLoading: false,
            ),
          );
          ref.onDispose(router.dispose);
          return router;
        }),
      ],
      child: const CollectApp(),
    ),
  );
}
