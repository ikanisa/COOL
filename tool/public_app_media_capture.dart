// Explicit fixture-only browser entrypoint for real Collect interface previews.
// This target is never imported from lib or deployed as the public website.
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../test/fixtures/collect_repository_fixture.dart';

void main() {
  const enabled = bool.fromEnvironment('COLLECT_PUBLIC_MEDIA_CAPTURE');
  if (!enabled) throw StateError('Explicit media capture target required.');
  WidgetsFlutterBinding.ensureInitialized();
  final path = Uri.base.fragment;
  final textScale = switch (Uri.base.queryParameters['text-scale']) {
    null || '1' => 1.0,
    '2' => 2.0,
    _ => throw StateError('Unknown fixture text scale.'),
  };
  final recovery = Uri.base.queryParameters['recovery'];
  if (recovery != null && !{'stale', 'success', 'failure'}.contains(recovery)) {
    throw StateError('Unknown synthetic recovery outcome.');
  }
  const routes = {
    '/home',
    '/groups',
    '/groups/qa-private-group',
    '/groups/qa-private-group/members',
    '/settings/notifications',
    '/settings/appearance',
    '/settings/help',
    '/settings/security',
    '/settings/legal/privacy',
    '/settings/legal/terms',
    '/settings/account/delete',
    '/offline',
    '/sync',
  };
  if (!routes.contains(path)) {
    throw StateError('Unknown media capture route.');
  }
  runApp(
    ProviderScope(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        collectAuthenticatedUserIdProvider.overrideWithValue('local-user'),
        collectRepositoryProvider.overrideWith(
          (ref) => recovery == null
              ? FixtureCollectRepository(
                  fixtureNow: DateTime.utc(2026, 9, 2, 10),
                )
              : _RecoveryFixtureRepository(recovery),
        ),
        appRouterProvider.overrideWithValue(
          createAppRouter(initialLocation: path),
        ),
        collectThemeModeProvider.overrideWith(
          (ref) => CollectThemeModeController(loadPersistedMode: false),
        ),
      ],
      child: textScale == 1
          ? const CollectApp()
          : Builder(
              builder: (context) => MediaQuery(
                data: MediaQueryData.fromView(
                  View.of(context),
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: const CollectApp(),
              ),
            ),
    ),
  );
}

// Explicit synthetic outcomes for rendered recovery acceptance. No network,
// payment submission, SMS retry or Auth/provider interaction is simulated.
class _RecoveryFixtureRepository extends FixtureCollectRepository {
  _RecoveryFixtureRepository(this.outcome)
    : super(fixtureNow: DateTime.utc(2026, 9, 2, 10)) {
    state = state.copyWith(
      usingStaleCache: true,
      lastSuccessfulSyncAt: DateTime.utc(2026, 9, 2, 10),
    );
  }

  final String outcome;

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    if (syncPendingSms) throw StateError('Fixture must never replay SMS.');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (outcome == 'success') {
      state = state.copyWith(
        usingStaleCache: false,
        lastSuccessfulSyncAt: state.lastSuccessfulSyncAt!.add(
          const Duration(minutes: 1),
        ),
      );
    } else if (outcome == 'failure') {
      throw StateError('Synthetic data read unavailable.');
    }
  }
}
