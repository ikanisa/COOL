import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRoute(
    WidgetTester tester,
    String route, {
    bool legalConsentAccepted = false,
    double textScale = 1,
  }) async {
    final router = createAppRouter(initialLocation: route);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.seeded(),
          ),
          legalConsentAcceptedProvider.overrideWith(
            (ref) => legalConsentAccepted,
          ),
        ],
        child: textScale == 1
            ? const CollectApp()
            : MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: const CollectApp(),
              ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('new mobile completion routes render', (tester) async {
    const routes = [
      '/onboarding/legal',
      '/permissions/notifications-denied',
      '/permissions/camera-denied',
      '/share/expired/request',
      '/groups/col-church/support/payment/intent-render',
    ];

    for (final route in routes) {
      await pumpRoute(tester, route);
      expect(tester.takeException(), isNull, reason: route);
      expect(find.byType(CollectApp), findsOneWidget, reason: route);
    }
  });

  testWidgets('onboarding requires legal consent before sign-in', (
    tester,
  ) async {
    await pumpRoute(tester, '/onboarding');

    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Review terms'), findsOneWidget);
  });

  testWidgets('auth resend cooldown disables resend after sending OTP', (
    tester,
  ) async {
    await pumpRoute(tester, '/auth', legalConsentAccepted: true);

    await tester.enterText(find.byType(TextField).first, '+250788123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Send WhatsApp code'));
    await tester.pump();

    expect(find.text('Verify WhatsApp'), findsOneWidget);
    expect(find.text('Resend in 45s'), findsOneWidget);
    final resend = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Resend in 45s'),
    );
    expect(resend.onPressed, isNull);
  });

  testWidgets('auth shows validation error for invalid WhatsApp number', (
    tester,
  ) async {
    await pumpRoute(tester, '/auth', legalConsentAccepted: true);

    await tester.enterText(find.byType(TextField).first, 'bad-number');
    await tester.tap(find.widgetWithText(FilledButton, 'Send WhatsApp code'));
    await tester.pump();

    expect(find.text('Authentication failed'), findsOneWidget);
  });

  testWidgets('legal consent route meets core accessibility guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(tester, '/onboarding/legal');

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('permission recovery routes explain settings recovery', (
    tester,
  ) async {
    const cases = [
      (
        route: '/permissions/sms-denied',
        title: 'Enable Android SMS access',
        action: 'Open app settings',
      ),
      (
        route: '/permissions/notifications-denied',
        title: 'Notification permission was blocked.',
        action: 'App settings',
      ),
      (
        route: '/permissions/camera-denied',
        title: 'Camera permission was blocked.',
        action: 'App settings',
      ),
    ];

    for (final item in cases) {
      await pumpRoute(tester, item.route);
      expect(find.text(item.title), findsWidgets, reason: item.route);
      expect(find.text(item.action), findsWidgets, reason: item.route);
    }
  });

  testWidgets('profile setup supports 200 percent text scale', (tester) async {
    final router = createAppRouter(initialLocation: '/settings/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => CollectRepository.seeded(),
          ),
        ],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: CollectApp(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Profile setup'), findsOneWidget);
    expect(find.text('Save MoMo number'), findsOneWidget);
    expect(find.text('MoMo number'), findsOneWidget);
  });

  testWidgets('completion sheets and dialogs tolerate 200 percent text scale', (
    tester,
  ) async {
    for (final route in const [
      '/permissions/camera-denied',
      '/groups/col-church/support/payment/intent-render',
      '/groups/col-church/manage',
      '/groups/col-church/profile',
    ]) {
      await pumpRoute(tester, route, textScale: 2);
      expect(tester.takeException(), isNull, reason: route);
      expect(find.byType(CollectApp), findsOneWidget, reason: route);
    }
  });

  testWidgets('create group walks through five owner setup steps', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpRoute(tester, '/groups/create');

      expect(find.text('Step 1 of 4'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Parish support');
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(find.text('Step 2 of 4'), findsOneWidget);
      expect(find.text('Receiver privacy'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(find.text('Step 3 of 4'), findsOneWidget);
      expect(find.text('Group color'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(find.text('SMS readiness check.'), findsNothing);
      expect(find.text('Review group'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('payment support review and fresh link recovery submit safely', (
    tester,
  ) async {
    await pumpRoute(tester, '/groups/col-church/support/payment/intent-render');
    expect(find.text('Safe note'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Submit review'));
    await tester.pump();
    expect(find.text('Review submitted.'), findsOneWidget);

    await pumpRoute(tester, '/share/expired/request');
    expect(find.text('Fresh link'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Request fresh link'));
    await tester.pump();
    expect(find.text('Request sent.'), findsOneWidget);
  });
}
