import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'camera permission supports denial education retry and recovery',
    (tester) async {
      final router = createAppRouter(initialLocation: '/groups/scan');
      final container = ProviderContainer(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.fixture(),
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

      // The emulator-only host harness waits for this marker before acting on
      // Android's native Camera prompt. No camera frame or customer data is
      // retained by this test.
      // ignore: avoid_print
      print('collect_camera_permission_uat:camera-deny-prompt-requested');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );

      await _pumpUntil(
        tester,
        () => find.text('Camera access').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );
      expect(
        container.read(cameraPermissionStatusProvider),
        CollectDevicePermissionStatus.denied,
      );
      expect(find.text('Scan again'), findsOneWidget);
      expect(
        find.textContaining('without storing photos or gallery images'),
        findsOneWidget,
      );
      // ignore: avoid_print
      print('collect_camera_permission_uat:camera-denied-recovery-visible');

      // ignore: avoid_print
      print('collect_camera_permission_uat:camera-retry-prompt-requested');
      final retryButton = tester.widget<CollectButton>(
        find.widgetWithText(CollectButton, 'Scan again'),
      );
      retryButton.onPressed!();
      await tester.pump();

      await _pumpUntil(
        tester,
        () =>
            container.read(cameraPermissionStatusProvider) ==
            CollectDevicePermissionStatus.granted,
        timeout: const Duration(seconds: 60),
      );
      expect(find.text('Camera access'), findsNothing);
      // ignore: avoid_print
      print('collect_camera_permission_uat:camera-recovery-pass');
      // Keep the recovered scanner visible long enough for the emulator-only
      // host harness to retain the final state before test teardown.
      await Future<void>.delayed(const Duration(seconds: 5));
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 200));
  }
  if (predicate()) return;
  fail('Timed out after ${timeout.inSeconds}s waiting for Camera state.');
}
