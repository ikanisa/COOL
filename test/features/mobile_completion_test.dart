import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  bool authButtonEnabled(WidgetTester tester, String key) {
    final button = tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextButton),
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
      '/contribute',
      '/activity',
      '/settings/notifications',
      '/settings/appearance',
      '/settings/security',
      '/settings/help',
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

  testWidgets('global Contribute selects a group and reuses payment flow', (
    tester,
  ) async {
    await pumpRoute(tester, '/contribute', legalConsentAccepted: true);

    expect(find.text('Choose a group'), findsOneWidget);
    expect(find.text('Contribute'), findsWidgets);
    expect(find.text('Activity'), findsOneWidget);

    await tester.tap(find.text('St Michel building fund').first);
    await tester.pumpAndSettle();

    expect(find.text('Review contribution'), findsOneWidget);
    expect(find.text('Choose a group'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('global Activity renders confirmed records but not intents', (
    tester,
  ) async {
    await pumpRoute(tester, '/activity', legalConsentAccepted: true);

    expect(find.text('Activity'), findsWidgets);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Ref MTN12345'), findsOneWidget);
    expect(find.text('Ref MTN12346'), findsOneWidget);
    expect(find.text('RWF 15,000'), findsNothing);
    expect(find.textContaining('intent-render'), findsNothing);
  });

  testWidgets('dense Activity avoids a viewport-spanning backdrop filter', (
    tester,
  ) async {
    final repository = CollectRepository.fixture(fixtureContributionCount: 80);
    await pumpRoute(
      tester,
      '/activity',
      legalConsentAccepted: true,
      repository: repository,
    );

    final activityCard = find
        .ancestor(
          of: find.byType(ActivityFeedItem).first,
          matching: find.byType(CollectCard),
        )
        .first;
    expect(activityCard, findsOneWidget);
    expect(
      find.descendant(of: activityCard, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'Dense activity content must not build a glass blur layer.',
    );
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('ledger sort sheet avoids blurred backdrop on performance path', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      '/groups/col-church/ledger',
      legalConsentAccepted: true,
      repository: CollectRepository.fixture(fixtureContributionCount: 80),
    );

    await tester.tap(find.byTooltip('Sort ledger'));
    await tester.pumpAndSettle();

    final sheet = find.byType(CollectBottomSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Sort ledger')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'Performance-critical sort sheet must not animate a blur layer.',
    );
  });

  testWidgets('notification settings persist repository preferences', (
    tester,
  ) async {
    final repository = CollectRepository.fixture();
    await pumpRoute(
      tester,
      '/settings/notifications',
      legalConsentAccepted: true,
      repository: repository,
    );

    expect(
      repository.state.notificationPreferences.contributionConfirmations,
      isTrue,
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(
      repository.state.notificationPreferences.contributionConfirmations,
      isFalse,
    );
  });

  testWidgets('security is a standalone Collect-specific detail screen', (
    tester,
  ) async {
    await pumpRoute(tester, '/settings/security', legalConsentAccepted: true);

    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Contribution verification'), findsOneWidget);
    expect(find.text('Receiver privacy'), findsOneWidget);
    expect(find.text('Report fraud'), findsNothing);
    expect(find.text('Lost device'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('appearance switches the persisted app theme mode', (
    tester,
  ) async {
    await pumpRoute(tester, '/settings/appearance', legalConsentAccepted: true);

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    final preview = find.byKey(const ValueKey('appearance-live-preview'));
    expect(preview, findsOneWidget);
    final previewLogo = tester.widget<Image>(
      find.descendant(of: preview, matching: find.byType(Image)),
    );
    expect(
      (previewLogo.image as AssetImage).assetName,
      CollectRuntimeAssets.officialLogo,
    );
    final previewSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: preview,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'Dark Collect home preview',
            ),
          )
          .first,
    );
    expect(previewSemantics.properties.image, isTrue);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Light Collect home preview',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('System'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    final systemSemantics = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.text('System'),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.label == 'System mode',
            ),
          )
          .first,
    );
    expect(systemSemantics.properties.button, isTrue);
    expect(systemSemantics.properties.selected, isTrue);
  });

  testWidgets('appearance modes remain usable at 320 px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpRoute(
      tester,
      '/settings/appearance',
      legalConsentAccepted: true,
      textScale: 2,
    );

    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('System'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'appearance mode choices stack at native width and 320 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpRoute(
        tester,
        '/settings/appearance',
        legalConsentAccepted: true,
        textScale: 3.2,
      );

      final darkChoice = find.ancestor(
        of: find.text('Dark'),
        matching: find.byType(AnimatedContainer),
      );
      final lightChoice = find.ancestor(
        of: find.text('Light'),
        matching: find.byType(AnimatedContainer),
      );

      expect(darkChoice, findsOneWidget);
      expect(lightChoice, findsOneWidget);
      expect(
        tester.getTopLeft(lightChoice).dy,
        greaterThan(tester.getBottomLeft(darkChoice).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

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
          find.bySemanticsLabel(
            RegExp('^Loading screen: ${RegExp.escape(entry.value)}\\.'),
          ),
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
    final semantics = tester.ensureSemantics();
    try {
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
      expect(
        find.bySemanticsLabel(
          'Authentication failed. WhatsApp sign-in is unavailable right now. Try again later.',
        ),
        findsOneWidget,
      );
      expect(find.text('Verify WhatsApp'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('archived groups leave active surfaces and become read only', (
    tester,
  ) async {
    final repository = CollectRepository.fixture();
    await repository.archiveCollection('col-church');

    for (final route in const ['/home', '/groups', '/contribute']) {
      await pumpRoute(
        tester,
        route,
        legalConsentAccepted: true,
        repository: repository,
      );
      expect(find.text('St Michel building fund'), findsNothing, reason: route);
      if (route != '/home') {
        expect(find.text('Kigali Lions away kit'), findsWidgets, reason: route);
      }
    }

    for (final route in const [
      '/groups/col-church',
      '/groups/col-church/contribute',
      '/groups/col-church/manage',
      '/groups/col-church/profile',
      '/groups/col-church/share',
    ]) {
      await pumpRoute(
        tester,
        route,
        legalConsentAccepted: true,
        repository: repository,
      );
      expect(
        find.text('This group is archived.'),
        findsOneWidget,
        reason: route,
      );
      expect(find.text('Open ledger'), findsOneWidget, reason: route);
      expect(find.text('Pay'), findsNothing, reason: route);
    }
  });

  testWidgets('supported-groups filter has a clear empty recovery state', (
    tester,
  ) async {
    final repository = CollectRepository.fixture();
    await repository.archiveCollection('col-church');
    await pumpRoute(
      tester,
      '/groups?filter=contributed',
      legalConsentAccepted: true,
      repository: repository,
    );

    expect(find.text('No supported groups yet'), findsOneWidget);
    expect(find.text('Show all groups'), findsOneWidget);
    await tester.tap(find.text('Show all groups'));
    await tester.pumpAndSettle();
    expect(find.text('Kigali Lions away kit'), findsOneWidget);
  });

  testWidgets('group admin sheet validates, announces, and completes safely', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = CollectRepository.fixture();
    try {
      await pumpRoute(
        tester,
        '/groups/col-church/manage',
        legalConsentAccepted: true,
        repository: repository,
      );

      await tester.scrollUntilVisible(
        find.text('Add admin'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(
        find.byType(ListView).first,
        const Offset(0, -80),
        warnIfMissed: false,
      );
      await tester.pump();
      await tester.tap(find.text('Add admin'));
      await tester.pumpAndSettle();

      expect(find.textContaining('six-digit Collect ID'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Add admin'));
      await tester.pump();
      expect(find.text('Enter a 6 digit Collect ID.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Enter a 6 digit Collect ID')),
        findsOneWidget,
      );

      await tester.enterText(textFieldWithLabel('Collect ID'), '038491');
      await tester.tap(find.widgetWithText(FilledButton, 'Add admin'));
      await tester.pump();
      expect(find.textContaining('already own this group'), findsOneWidget);

      await tester.enterText(textFieldWithLabel('Collect ID'), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Add admin'));
      await tester.pumpAndSettle();

      expect(find.text('Admin invitation created.'), findsOneWidget);
      expect(find.text('Collect ID'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('contribution review exposes duplicate-intent recovery', (
    tester,
  ) async {
    final repository = CollectRepository.fixture();
    await pumpRoute(
      tester,
      '/groups/col-church/contribute',
      legalConsentAccepted: true,
      repository: repository,
    );

    await tester.enterText(find.byType(TextField).first, '15000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Review contribution'));
    await tester.pump();

    expect(find.text('Contribution already pending'), findsOneWidget);
    expect(find.text('Continue existing contribution'), findsOneWidget);
    expect(repository.state.paymentIntents, hasLength(1));
  });

  testWidgets('contribution review explains an expired matching request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const cache = CollectOfflineCache(
      preferencesKey: 'collect.offline_snapshot.expired_intent_widget_test',
    );
    final seeded = CollectRepository.fixture();
    final now = DateTime.now();
    await cache.save(
      CollectOfflineSnapshot(
        savedAt: now,
        currentProfile: seeded.state.currentProfile,
        collections: seeded.state.collections,
        paymentIntents: [
          PaymentIntentModel(
            id: 'expired-intent',
            collectionId: 'col-church',
            expectedAmountRwf: 15000,
            receiverMomoNumber: '0788123456',
            receiverLabel: 'St Michel treasury',
            senderPhoneHash: 'hash-redacted',
            status: 'pending',
            createdAt: now.subtract(const Duration(days: 2)),
            expiresAt: now.subtract(const Duration(days: 1)),
          ),
        ],
        contributions: seeded.state.contributions,
      ),
    );
    final repository = CollectRepository.fixture(
      seeded: false,
      offlineCache: cache,
    );
    expect(
      await repository.restoreOfflineSnapshot(reason: 'offline fixture'),
      isTrue,
    );
    await pumpRoute(
      tester,
      '/groups/col-church/contribute',
      legalConsentAccepted: true,
      repository: repository,
    );

    await tester.enterText(find.byType(TextField).first, '15000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Review contribution'));
    await tester.pump();

    expect(find.text('Previous request expired'), findsOneWidget);
    expect(find.text('Contribute with MoMo'), findsOneWidget);
    expect(find.text('Contribution already pending'), findsNothing);
  });

  testWidgets('auth screen avoids duplicate decorative WhatsApp semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(tester, '/auth', legalConsentAccepted: true);

      expect(find.text('Sign in'), findsOneWidget);
      expect(
        find.text(
          'Enter your WhatsApp number to receive a secure sign-in code.',
        ),
        findsOneWidget,
      );
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
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('auth_otp_digit_0')))
          .autofillHints,
      contains(AutofillHints.oneTimeCode),
    );
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

    expect(find.text('Total collected'), findsOneWidget);
    expect(find.text('WhatsApp verified.'), findsNothing);
    expect(repository.state.currentProfile?.whatsappPhone, '+250700000001');
    expect(repository.state.currentProfile?.momoNumber, '0788123456');
    expect(repository.state.collections, isNotEmpty);
    expect(repository.state.contributions, isNotEmpty);
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

    expect(find.text('Groups'), findsWidgets);
    expect(
      find.bySemanticsLabel('St Michel building fund, RWF 35,000, 2 members'),
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
    await tester.scrollUntilVisible(
      find.text('My groups'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
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
      expect(find.text('Activity'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('My groups'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();

      expect(find.text('Momentum'), findsNothing);
      expect(find.text('My groups'), findsOneWidget);
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
