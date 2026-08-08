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
    'SMS access uses disclosure, native permission, encrypted queue, and turn-off',
    (tester) async {
      const smsAccess = SmsAccessChannel();
      final router = createAppRouter(initialLocation: '/settings/permissions');
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

      expect(find.text('MoMo SMS access'), findsOneWidget);
      await tester.ensureVisible(find.text('Review and allow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and allow'));
      await tester.pumpAndSettle();
      expect(find.text('Allow MoMo SMS access?'), findsOneWidget);
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

      final queued = await _pollForPendingSms(tester, smsAccess);
      expect(queued, hasLength(1));
      expect(queued.single.rawSender.trim(), isNotEmpty);
      expect(queued.single.rawBody, contains('MTN MoMo'));
      expect(queued.single.rawBody, contains('RWF'));
      expect(await smsAccess.acknowledgePendingSms([queued.single.id]), isTrue);
      expect(await smsAccess.readPendingSms(), isEmpty);
      // ignore: avoid_print
      print('collect_sms_permission_uat:encrypted-queue-ack-pass');

      await tester.ensureVisible(find.text('Turn off'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
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

Future<List<SmsAccessEnvelope>> _pollForPendingSms(
  WidgetTester tester,
  SmsAccessChannel channel,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    final pending = await channel.readPendingSms();
    if (pending.isNotEmpty) return pending;
    await tester.pump(const Duration(milliseconds: 250));
  }
  fail('Timed out waiting for the synthetic mobile-money SMS.');
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
