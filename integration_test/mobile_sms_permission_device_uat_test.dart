import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'SMS access uses disclosure, native permission, account binding, and turn-off',
    (tester) async {
      const smsAccess = SmsAccessChannel();
      final router = createAppRouter(initialLocation: '/settings/permissions');
      final repository = _DeviceSmsPermissionRepository(smsAccess);
      final container = ProviderContainer(
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
      );
      addTearDown(router.dispose);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CollectApp(),
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('Review and allow').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );

      expect(find.text('MoMo receipt SMS'), findsOneWidget);
      final reviewButton = find.widgetWithText(
        OutlinedButton,
        'Review and allow',
      );
      await tester.scrollUntilVisible(
        reviewButton,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(reviewButton);
      await _pumpUntil(
        tester,
        () => find.text('Allow MoMo receipt SMS access?').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
      );
      expect(find.text('Allow MoMo receipt SMS access?'), findsOneWidget);
      expect(
        find.textContaining('does not read inbox history'),
        findsOneWidget,
      );
      expect(find.textContaining('encrypted on this device'), findsOneWidget);

      // ignore: avoid_print
      print('collect_sms_permission_uat:native-prompt-requested');
      await tester.tap(find.text('Continue'));
      await _pumpUntil(
        tester,
        () => find.text('Turn off').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 120),
      );
      expect((await smsAccess.status()).enabled, isTrue);
      // ignore: avoid_print
      print('collect_sms_permission_uat:permission-granted');

      expect(await smsAccess.readPendingSms(), isEmpty);
      // ignore: avoid_print
      print('collect_sms_permission_uat:account-bound-opt-in-pass');

      final turnOffButton = find.widgetWithText(OutlinedButton, 'Turn off');
      await tester.scrollUntilVisible(
        turnOffButton,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(turnOffButton);
      await _pumpUntil(
        tester,
        () => find.text('Review and allow').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20),
      );
      expect((await smsAccess.status()).enabled, isFalse);
      expect(await smsAccess.readPendingSms(), isEmpty);
      // ignore: avoid_print
      print('collect_sms_permission_uat:turn-off-pass');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _DeviceSmsPermissionRepository extends CollectRepository {
  _DeviceSmsPermissionRepository(this._smsAccess) : super.fixture();

  final SmsAccessChannel _smsAccess;

  @override
  Future<bool> setSmsAccess(bool enabled) async {
    final profile = state.currentProfile;
    final granted = await _smsAccess.setEnabled(
      enabled,
      ownerUserId: profile?.id,
    );
    final consentEnabled = enabled && granted;
    state = state.copyWith(
      smsAccessEnabled: consentEnabled,
      smsAccessDenied: enabled && !granted,
    );
    return consentEnabled;
  }
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
  if (!predicate()) {
    fail('Timed out after ${timeout.inSeconds}s waiting for device state.');
  }
}
