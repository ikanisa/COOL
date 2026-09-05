import '../test/fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'notification permission supports denial retry and settings recovery',
    (tester) async {
      final router = createAppRouter(
        initialLocation: '/settings/notifications',
      );
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => FixtureCollectRepository(),
          ),
          collectThemeModeProvider.overrideWith(
            (ref) => CollectThemeModeController(
              initialMode: ThemeMode.dark,
              loadPersistedMode: false,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Review phone permission'), findsOneWidget);
      await tester.tap(find.text('Review phone permission'));
      await tester.pumpAndSettle();
      expect(find.text('Enable'), findsOneWidget);

      // The external harness waits for this marker before acting on the native
      // Android prompt. It never reads notification contents or customer data.
      // ignore: avoid_print
      print('collect_permission_uat:notification-deny-prompt-requested');
      await tester.tap(find.text('Enable'));
      await _pumpUntil(
        tester,
        () => find.text('Try again').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 45),
      );
      await _pumpFrames(tester);

      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.denied,
      );
      // During the bottom-sheet exit animation the outgoing education sheet
      // and the recovery sheet can briefly expose the same secondary label.
      expect(find.text('Open app settings'), findsWidgets);
      // ignore: avoid_print
      print('collect_permission_uat:notification-denied-recovery-visible');

      // ignore: avoid_print
      print('collect_permission_uat:notification-retry-prompt-requested');
      await tester.tap(find.text('Try again'));
      final grantedByRetry = await _pumpUntil(
        tester,
        () =>
            container.read(notificationPermissionStatusProvider) ==
            CollectDevicePermissionStatus.granted,
        timeout: const Duration(seconds: 25),
        failOnTimeout: false,
      );

      if (!grantedByRetry) {
        await _pumpUntil(
          tester,
          () => find.text('Open app settings').evaluate().isNotEmpty,
          timeout: const Duration(seconds: 10),
        );
        // ignore: avoid_print
        print(
          'collect_permission_uat:notification-settings-recovery-requested',
        );
        await tester.tap(find.text('Open app settings').last);
        await _pumpUntil(
          tester,
          () =>
              container.read(notificationPermissionStatusProvider) ==
              CollectDevicePermissionStatus.granted,
          timeout: const Duration(seconds: 45),
        );
      }

      expect(
        container.read(notificationPermissionStatusProvider),
        CollectDevicePermissionStatus.granted,
      );
      // ignore: avoid_print
      print('collect_permission_uat:notification-recovery-pass');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 14; index += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
  bool failOnTimeout = true,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return true;
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (predicate()) return true;
  if (failOnTimeout) {
    fail('Timed out after ${timeout.inSeconds}s waiting for permission state.');
  }
  return false;
}
