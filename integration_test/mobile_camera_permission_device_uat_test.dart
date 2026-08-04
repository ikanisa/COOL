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

const _hostActionDelayMs = int.fromEnvironment(
  'COLLECT_PERMISSION_HOST_ACTION_DELAY_MS',
  defaultValue: 0,
);
const _uatPhase = String.fromEnvironment(
  'COLLECT_CAMERA_PERMISSION_UAT_PHASE',
  defaultValue: 'continuous',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'camera permission supports denial education retry and recovery',
    (tester) async {
      expect(
        _uatPhase,
        anyOf('continuous', 'denied', 'granted', 'physical-settings'),
      );
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

      if (_uatPhase == 'granted') {
        // ignore: avoid_print
        print('collect_camera_permission_uat:camera-granted-phase-requested');
      } else {
        // The emulator-only host harness waits for this marker before acting
        // on Android's native Camera prompt. No camera frame or customer data
        // is retained by this test.
        // ignore: avoid_print
        print('collect_camera_permission_uat:camera-deny-prompt-requested');
        await _waitForHostPermissionAction(tester);
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );

      if (_uatPhase == 'granted') {
        await _pumpUntil(
          tester,
          () =>
              container.read(cameraPermissionStatusProvider) ==
              CollectDevicePermissionStatus.granted,
          timeout: const Duration(seconds: 60),
        );
        expect(find.text('Camera access'), findsNothing);
        // ignore: avoid_print
        print('collect_camera_permission_uat:camera-granted-phase-pass');
        await Future<void>.delayed(const Duration(seconds: 2));
        await tester.pump();
        return;
      }

      await _pumpUntil(
        tester,
        () => find.text('Camera access').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60),
      );
      // Advance the modal-sheet animation before the host captures the
      // recovery state. Finding the sheet in the widget tree alone does not
      // prove that it has reached a visible frame on a physical device.
      await tester.pump(const Duration(milliseconds: 500));
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
      if (_uatPhase == 'denied') {
        // Keep the modal sheet visibly rendered while the exact-simulator
        // harness captures the native screen. Flutter-driver screenshots do
        // not reliably retain modal overlays on every iOS runtime.
        await Future<void>.delayed(const Duration(seconds: 8));
        await tester.pump();
        // ignore: avoid_print
        print('collect_camera_permission_uat:camera-denied-phase-pass');
        return;
      }
      if (_uatPhase == 'physical-settings') {
        // iOS does not present the Camera prompt again after an explicit
        // denial. Exercise the real recovery path: open this staging app's
        // Settings page, let the device owner enable Camera, and verify that
        // the scanner resumes without remounting or fabricating permission.
        // ignore: avoid_print
        print(
          'collect_camera_permission_uat:camera-settings-recovery-requested',
        );
        final openSettingsButton = tester.widget<CollectButton>(
          find.widgetWithText(CollectButton, 'Open app settings'),
        );
        openSettingsButton.onPressed!();
        await tester.pump();
        await _pumpUntil(
          tester,
          () =>
              container.read(cameraPermissionStatusProvider) ==
              CollectDevicePermissionStatus.granted,
          timeout: const Duration(seconds: 120),
        );
        expect(find.text('Camera access'), findsNothing);
        // ignore: avoid_print
        print(
          'collect_camera_permission_uat:camera-physical-settings-recovery-pass',
        );
        return;
      }
      await binding.takeScreenshot('ios_camera_permission_denied_recovery');
      // Keep the education/retry state on screen long enough for the host
      // harness to capture it before the test advances to the second native
      // permission prompt. Without this bounded hold, faster physical devices
      // can transition between the two prompts before `adb screencap` runs.
      await Future<void>.delayed(const Duration(seconds: 3));
      await tester.pump();

      // ignore: avoid_print
      print('collect_camera_permission_uat:camera-retry-prompt-requested');
      await _waitForHostPermissionAction(tester);
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

Future<void> _waitForHostPermissionAction(WidgetTester tester) async {
  if (_hostActionDelayMs == 0) return;
  await Future<void>.delayed(const Duration(milliseconds: _hostActionDelayMs));
  await tester.pump();
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
