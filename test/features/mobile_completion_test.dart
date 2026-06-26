import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
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
    AppEnv? appEnv,
    CollectRepository? repository,
  }) async {
    final router = createAppRouter(initialLocation: route);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          if (appEnv != null) appEnvProvider.overrideWithValue(appEnv),
          collectRepositoryProvider.overrideWith(
            (ref) => repository ?? CollectRepository.fixture(),
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

  testWidgets('missing group deep link renders recovery empty state', (
    tester,
  ) async {
    final router = createAppRouter(initialLocation: '/groups/missing-group');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => CollectRepository()),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Group is not available.'), findsOneWidget);
    expect(find.text('Open groups'), findsWidgets);
  });

  testWidgets('onboarding continues directly to sign-in', (tester) async {
    await pumpRoute(tester, '/onboarding');

    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Before you continue'), findsNothing);
  });

  testWidgets('auth OTP submit does not detour to legal consent', (
    tester,
  ) async {
    await pumpRoute(tester, '/auth');

    await tester.enterText(find.byType(TextField).first, '+250788123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Send WhatsApp code'));
    await tester.pump();

    expect(find.text('Before you continue'), findsNothing);
    expect(find.text('Authentication failed'), findsOneWidget);
    expect(
      find.textContaining('WhatsApp sign-in is unavailable'),
      findsOneWidget,
    );
    expect(find.text('Verify WhatsApp'), findsNothing);
  });

  testWidgets('app review OTP signs in with configured static code', (
    tester,
  ) async {
    final repository = CollectRepository.appReviewDemo();
    await pumpRoute(
      tester,
      '/auth',
      legalConsentAccepted: true,
      repository: repository,
      appEnv: const AppEnv(
        supabaseUrl: '',
        supabaseAnonKey: '',
        publicUrl: '',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: false,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: '',
        authCaptchaSiteKey: '',
        appReviewAuthEnabled: true,
        appReviewAuthPhone: '+250700000001',
        appReviewAuthOtp: '135790',
      ),
    );

    await tester.enterText(find.byType(TextField).first, '+250700000001');
    await tester.tap(find.widgetWithText(FilledButton, 'Send WhatsApp code'));
    await tester.pump();

    expect(find.text('OTP'), findsOneWidget);
    expect(find.text('Authentication failed'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify and continue'));
    await tester.pump();

    expect(find.text('Authentication failed'), findsOneWidget);
    expect(repository.state.currentProfile, isNull);

    await tester.enterText(find.byType(TextField).first, '135790');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify and continue'));
    await tester.pumpAndSettle();

    expect(find.text('WhatsApp verified.'), findsOneWidget);
    expect(repository.state.currentProfile?.whatsappPhone, '+250700000001');
    expect(repository.state.collections, isNotEmpty);
  });

  testWidgets('auth country code chip opens all-country picker', (
    tester,
  ) async {
    await pumpRoute(tester, '/auth', legalConsentAccepted: true);

    expect(
      find.byKey(const ValueKey('auth_country_code_picker')),
      findsOneWidget,
    );
    expect(find.text('+250'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auth_country_code_picker')));
    await tester.pumpAndSettle();

    expect(find.text('Search country'), findsOneWidget);
    expect(find.textContaining('Rwanda'), findsWidgets);
    expect(find.textContaining('+250'), findsWidgets);
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

  testWidgets('home search opens dedicated group search screen', (
    tester,
  ) async {
    await pumpRoute(tester, '/home', legalConsentAccepted: true);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Find a group.'), findsOneWidget);
    expect(find.text('Search groups'), findsOneWidget);
    expect(find.text('No groups yet'), findsNothing);
  });

  testWidgets('home join opens direct group code entry', (tester) async {
    await pumpRoute(tester, '/home', legalConsentAccepted: true);

    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(find.text('Join with a code.'), findsOneWidget);
    expect(find.text('Group code'), findsOneWidget);
    expect(find.text('Group code or link'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Join group'), findsOneWidget);
    expect(find.text('Scan QR'), findsOneWidget);
  });

  testWidgets('onboarding legal route redirects away from OTP terms gate', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(tester, '/onboarding/legal');

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Before you continue'), findsNothing);
      expect(find.text('Accept and continue'), findsNothing);
      expect(find.text('Accept before using Collect.'), findsNothing);
      expect(find.text('Required acknowledgement'), findsNothing);
      expect(find.text('Read privacy policy'), findsNothing);

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
        title: 'Alerts blocked',
        action: 'App settings',
      ),
      (
        route: '/permissions/camera-denied',
        title: 'Camera blocked',
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
            (ref) => CollectRepository.fixture(),
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

  testWidgets('home groups and activity sections support large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(tester, '/home', textScale: 2);

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('My groups'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('Momentum'), findsNothing);
      expect(find.text('My groups'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
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

  testWidgets('payment handoff route tolerates Pixel width large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpRoute(
      tester,
      '/groups/col-church/pay/intent-render/handoff',
      textScale: 2,
    );

    final exception = tester.takeException();
    expect(exception, isNull);
    expect(find.byType(CollectApp), findsOneWidget);
  });

  testWidgets('create group walks through five owner setup steps', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpRoute(tester, '/groups/create');

      expect(find.text('Create group'), findsWidgets);
      expect(find.text('Group name'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Parish support');
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(find.text('Collection type'), findsOneWidget);
      expect(find.text('Ikimina'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(find.text('Receiver MoMo'), findsOneWidget);
      expect(find.text('Receiver privacy'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

      expect(find.text('Group color'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();

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
    expect(find.text('Safe note'), findsWidgets);
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
