import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  bool authButtonEnabled(WidgetTester tester, String key) {
    final button = tester.widget<CupertinoButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(CupertinoButton),
      ),
    );
    return button.onPressed != null;
  }

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

  Finder textFieldWithLabel(String label) {
    return find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
  }

  Future<void> pressFilledButton(WidgetTester tester, String label) async {
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, label),
    );
    expect(button.onPressed, isNotNull, reason: '$label should be enabled');
    button.onPressed!();
    await tester.pumpAndSettle();
  }

  testWidgets('new mobile completion routes render', (tester) async {
    const routes = [
      '/groups/col-church/contribute',
      '/groups/col-church/manage',
      '/groups/col-church/profile',
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

  testWidgets('primary routes show loading panels during live startup', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final entry in const <String, String>{
        '/home': 'Loading home',
        '/groups': 'Loading groups',
        '/groups/col-church': 'Loading group',
        '/settings': 'Loading settings',
      }.entries) {
        final router = createAppRouter(initialLocation: entry.key);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appRouterProvider.overrideWithValue(router),
              collectRepositoryProvider.overrideWith(
                (ref) => _LoadingCollectRepository(),
              ),
            ],
            child: const CollectApp(),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
        expect(
          find.bySemanticsLabel('Loading screen: ${entry.value}'),
          findsOneWidget,
          reason: entry.key,
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('auth OTP submit does not detour to legal consent', (
    tester,
  ) async {
    await pumpRoute(tester, '/auth');

    expect(authButtonEnabled(tester, 'auth_submit_button'), isFalse);
    await tester.enterText(find.byType(TextField).first, '+250788123456');
    await tester.pump();
    expect(authButtonEnabled(tester, 'auth_submit_button'), isTrue);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pump();

    expect(find.text('Before you continue'), findsNothing);
    expect(find.text('Authentication failed'), findsOneWidget);
    expect(
      find.textContaining('WhatsApp sign-in is unavailable'),
      findsOneWidget,
    );
    expect(find.text('Verify WhatsApp'), findsNothing);
  });

  testWidgets('auth screen avoids duplicate decorative WhatsApp semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(tester, '/auth', legalConsentAccepted: true);

      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Use your WhatsApp number.'), findsOneWidget);
      expect(find.bySemanticsLabel('Send WhatsApp code'), findsOneWidget);
      expect(find.bySemanticsLabel('WhatsApp'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth_country_code_picker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('auth_whatsapp_phone_input')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
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
    await tester.pump();
    expect(authButtonEnabled(tester, 'auth_submit_button'), isTrue);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pump();

    expect(find.text('OTP'), findsOneWidget);
    expect(find.text('Authentication failed'), findsNothing);
    expect(authButtonEnabled(tester, 'auth_submit_button'), isFalse);
    expect(authButtonEnabled(tester, 'auth_change_button'), isTrue);
    expect(authButtonEnabled(tester, 'auth_resend_button'), isTrue);

    await tester.enterText(find.byType(TextField).first, '000000');
    await tester.pump();
    expect(authButtonEnabled(tester, 'auth_submit_button'), isTrue);
    await tester.tap(find.text('Verify and continue'));
    await tester.pump();

    expect(find.text('Authentication failed'), findsOneWidget);
    expect(repository.state.currentProfile, isNull);

    await tester.enterText(find.byType(TextField).first, '135790');
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();

    expect(find.text('TOTAL COLLECTED'), findsOneWidget);
    expect(find.text('WhatsApp verified.'), findsNothing);
    expect(repository.state.currentProfile?.whatsappPhone, '+250700000001');
    expect(repository.state.currentProfile?.momoNumber, isNull);
    expect(repository.state.collections, isEmpty);
    expect(repository.state.contributions, isEmpty);
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

  testWidgets('auth disables send until WhatsApp phone is valid', (
    tester,
  ) async {
    await pumpRoute(tester, '/auth', legalConsentAccepted: true);

    expect(authButtonEnabled(tester, 'auth_submit_button'), isFalse);
    await tester.enterText(find.byType(TextField).first, 'bad-number');
    await tester.pump();

    expect(authButtonEnabled(tester, 'auth_submit_button'), isFalse);
    expect(find.text('Authentication failed'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '788123456');
    await tester.pump();

    expect(authButtonEnabled(tester, 'auth_submit_button'), isTrue);
  });

  testWidgets(
    'group creation accepts signed-in non-MTN users without MoMo prefill',
    (tester) async {
      final repository = CollectRepository.fixture(seeded: false);
      await repository.signInWithOtp(phone: '+250720000001', otp: '123456');

      await pumpRoute(
        tester,
        '/groups/create',
        legalConsentAccepted: true,
        repository: repository,
      );

      expect(find.text('Create group'), findsWidgets);
      expect(find.text('Profile setup'), findsNothing);
      expect(repository.state.currentProfile?.momoNumber, isNull);

      await tester.enterText(
        textFieldWithLabel('Group name'),
        'Parish support',
      );
      await tester.pumpAndSettle();
      await pressFilledButton(tester, 'Continue');
      await pressFilledButton(tester, 'Continue');

      expect(find.text('Number'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('0788123456'), findsNothing);
      final emptyReceiverButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(emptyReceiverButton.onPressed, isNull);
    },
  );

  testWidgets('group creation without profile only requires receiver MoMo', (
    tester,
  ) async {
    final repository = CollectRepository();

    await pumpRoute(
      tester,
      '/groups/create',
      legalConsentAccepted: true,
      repository: repository,
    );

    expect(find.text('Create group'), findsWidgets);
    expect(find.text('Sign in required'), findsNothing);
    expect(find.text('Sign in first.'), findsNothing);
    expect(repository.state.currentProfile, isNull);

    await tester.enterText(textFieldWithLabel('Group name'), 'Parish support');
    await tester.pumpAndSettle();
    await pressFilledButton(tester, 'Continue');
    await pressFilledButton(tester, 'Continue');

    expect(find.text('Number'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    final emptyReceiverButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(emptyReceiverButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, '0789123456');
    await tester.pumpAndSettle();
    final filledReceiverButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(filledReceiverButton.onPressed, isNotNull);
  });

  testWidgets('home keeps scan as the only join entry', (tester) async {
    await pumpRoute(tester, '/home', legalConsentAccepted: true);

    expect(find.text('Join'), findsNothing);
    expect(find.text('Scan QR'), findsOneWidget);
    expect(find.text('Join with a code.'), findsNothing);
    expect(find.text('Group code'), findsNothing);
    expect(find.text('Group code or link'), findsNothing);
  });

  testWidgets('groups low-data route keeps actions in chrome', (tester) async {
    await pumpRoute(tester, '/groups', legalConsentAccepted: true);

    expect(
      find.bySemanticsLabel(
        'GROUPS, RWF 35,000, 2 members moving money together',
      ),
      findsOneWidget,
    );
    expect(find.text('Scan'), findsNothing);
    expect(find.text('Supported'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
  });

  testWidgets('groups empty state does not show home hero actions', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      '/groups',
      legalConsentAccepted: true,
      repository: CollectRepository(),
    );

    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.text('Scan'), findsNothing);
    expect(find.text('Supported'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byTooltip('Create group'), findsWidgets);
  });

  testWidgets('home labels restored cache as offline saved data', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const cache = CollectOfflineCache(
      preferencesKey: 'collect.offline_snapshot.home_widget_test',
    );
    final seeded = CollectRepository.fixture();
    await cache.save(
      CollectOfflineSnapshot(
        savedAt: DateTime.utc(2026, 6, 30, 10, 5),
        currentProfile: seeded.state.currentProfile,
        collections: seeded.state.collections,
        paymentIntents: seeded.state.paymentIntents,
        contributions: seeded.state.contributions,
      ),
    );
    final staleRepository = CollectRepository.fixture(
      seeded: false,
      offlineCache: cache,
    );
    await staleRepository.restoreOfflineSnapshot(
      reason: 'SocketException: network offline',
    );

    await pumpRoute(tester, '/home', repository: staleRepository);

    expect(find.textContaining('Offline saved data'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
  });

  testWidgets('profile edit supports 200 percent text scale', (tester) async {
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

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Save MoMo number'), findsOneWidget);
    expect(find.text('Number'), findsOneWidget);
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
      '/groups/col-church/manage',
      '/groups/col-church/profile',
      '/groups/col-church/contribute',
    ]) {
      await pumpRoute(tester, route, textScale: 2);
      expect(tester.takeException(), isNull, reason: route);
      expect(find.byType(CollectApp), findsOneWidget, reason: route);
    }
  });

  testWidgets('contribution route tolerates Pixel width large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpRoute(tester, '/groups/col-church/contribute', textScale: 2);

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
      expect(find.text('Description, optional'), findsOneWidget);
      await tester.enterText(
        textFieldWithLabel('Group name'),
        'Parish support',
      );
      await tester.pumpAndSettle();
      await pressFilledButton(tester, 'Continue');

      expect(find.text('Collection type'), findsNothing);
      expect(find.text('Ikimina'), findsNothing);
      expect(find.byIcon(CollectIcons.savings), findsOneWidget);
      expect(find.textContaining('Savings cycles'), findsNothing);
      await pressFilledButton(tester, 'Continue');

      expect(find.text('Number'), findsOneWidget);
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Receiver privacy'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '0789123456');
      await tester.pumpAndSettle();
      await pressFilledButton(tester, 'Continue');

      expect(find.text('Group color'), findsOneWidget);
      await pressFilledButton(tester, 'Continue');

      expect(find.text('SMS readiness check.'), findsNothing);
      expect(find.text('Review group'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('fresh link recovery route is removed from the mobile surface', (
    tester,
  ) async {
    await pumpRoute(tester, '/share/expired/request');
    expect(find.text('Fresh link'), findsNothing);
    expect(find.text('Request a fresh link.'), findsNothing);
    expect(find.text('Groups'), findsWidgets);
  });
}

class _LoadingCollectRepository extends CollectRepository {
  _LoadingCollectRepository() : super.fixture(seeded: false) {
    state = state.copyWith(isLoading: true);
  }
}
