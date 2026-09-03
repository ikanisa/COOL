import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/auth_otp_gateway.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestAuthOtpGateway implements AuthOtpGateway {
  static const acceptedOtp = '135790';
  String? sentPhone;

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {
    sentPhone = phone;
  }

  @override
  Future<void> verifyWhatsAppOtp({
    required String phone,
    required String otp,
    String? captchaToken,
  }) async {
    if (phone != sentPhone || otp != acceptedOtp) {
      throw const FormatException('Invalid OTP');
    }
  }
}

const _diasporaProfile = CollectProfile(
  id: 'local-user',
  publicId: '038491',
  whatsappPhone: '+250788123456',
  countryCode: 'GB',
  currencyCode: 'GBP',
  revolutLink: 'https://revolut.me/collectmember',
  revolutAccount: '000123456789',
);

class _TestSmsAccessChannel extends SmsAccessChannel {
  const _TestSmsAccessChannel();

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async => enabled;
}

class _PlatformOwnerRepository extends CollectRepository {
  _PlatformOwnerRepository() : super.fixture() {
    state = state.copyWith(
      collections: [
        for (final group in state.collections)
          group.id == 'col-church'
              ? group.copyWith(isPlatformSponsored: true, isPublic: true)
              : group,
      ],
    );
  }
}

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
    AuthOtpGateway? authOtpGateway,
  }) async {
    final router = createAppRouter(initialLocation: route);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          if (appEnv != null) appEnvProvider.overrideWithValue(appEnv),
          if (authOtpGateway != null)
            authOtpGatewayProvider.overrideWithValue(authOtpGateway),
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

  testWidgets('global Contribute selects a group and opens Rwanda MoMo flow', (
    tester,
  ) async {
    await pumpRoute(tester, '/contribute', legalConsentAccepted: true);

    expect(find.text('Choose a group'), findsOneWidget);
    expect(find.text('Your groups'), findsOneWidget);
    expect(find.text('Public groups'), findsOneWidget);
    expect(find.text('Scan group QR'), findsNothing);
    expect(find.text('Contribute'), findsNothing);
    expect(find.text('Activity'), findsOneWidget);

    await tester.tap(find.text('St Michel building fund').first);
    await tester.pumpAndSettle();

    expect(find.text('How much?'), findsOneWidget);
    expect(find.textContaining('MTN MoMo ·'), findsOneWidget);
    expect(find.text('Continue to MoMo'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('native_momo_contribution_flow')))
          .width,
      lessThanOrEqualTo(430),
    );
    expect(find.text('St Michel building fund'), findsOneWidget);
    expect(find.text('Choose a group'), findsNothing);
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('Buri Munsi never falls back to bank transfer by profile', (
    tester,
  ) async {
    final repository = CollectRepository.fixture(
      profileOverride: _diasporaProfile,
    );

    await pumpRoute(
      tester,
      '/groups/col-public-savings-fixture/contribute',
      legalConsentAccepted: true,
      repository: repository,
    );

    expect(find.text('MoMo contribution'), findsNothing);
    expect(
      find.text('Enter your contribution in Rwanda francs.'),
      findsNothing,
    );
    expect(find.text('1 / 2'), findsNothing);
    expect(find.text('Quick pick'), findsOneWidget);
    expect(find.text('IKANISA LTD'), findsOneWidget);
    expect(find.text('MTN MoMo · 41258'), findsOneWidget);
    expect(find.textContaining('MoMo receiver'), findsNothing);
    expect(find.text('Approve in MoMo'), findsNothing);
    expect(find.textContaining('secure MTN MoMo prompt'), findsNothing);
    expect(find.text('1,000'), findsOneWidget);
    expect(find.text('2,000'), findsOneWidget);
    expect(find.text('5,000'), findsOneWidget);
    expect(find.text('10,000'), findsOneWidget);
    expect(find.text('20,000'), findsNothing);
    expect(find.text('50,000'), findsNothing);
    expect(find.text('Bank transfer'), findsNothing);
    expect(find.text('EUR '), findsNothing);
  });

  testWidgets('MoMo payee stays complete at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpRoute(
      tester,
      '/groups/col-church/contribute',
      textScale: 2,
      repository: CollectRepository.fixture(),
    );
    await tester.pumpAndSettle();
    const payee = 'St Michel MTN MoMo';
    await tester.scrollUntilVisible(
      find.text(payee),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<Text>(find.text(payee)).maxLines, isNull);
    expect(
      tester.renderObject<RenderParagraph>(find.text(payee)).didExceedMaxLines,
      isFalse,
    );
    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(payee),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<Text>(find.text(payee)).maxLines, isNull);
    expect(
      tester.renderObject<RenderParagraph>(find.text(payee)).didExceedMaxLines,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'MoMo groups typed amounts and quick picks without changing value',
    (tester) async {
      final repository = CollectRepository.fixture();
      await pumpRoute(
        tester,
        '/groups/col-public-savings-fixture/contribute',
        legalConsentAccepted: true,
        repository: repository,
      );
      final field = find.byType(TextField).first;
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      expect(tester.widget<TextField>(field).decoration!.hintText, '0');
      await tester.enterText(field, '12345');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '12,345');

      await tester.tap(find.text('2,000'));
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '2,000');
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'RWF 2000' &&
              widget.properties.selected == true,
        ),
        findsOneWidget,
      );

      await tester.enterText(field, '1234');
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text, '1,234');
      await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
      await tester.pumpAndSettle();
      expect(find.text('Review contribution'), findsOneWidget);
      expect(find.text('2 / 2'), findsNothing);
      expect(
        repository.state.paymentIntents.any(
          (intent) =>
              intent.collectionId == 'col-public-savings-fixture' &&
              intent.expectedAmountRwf == 1234,
        ),
        isTrue,
      );
    },
  );

  testWidgets('Contribute prioritizes public discovery when data is empty', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      '/contribute',
      legalConsentAccepted: true,
      repository: CollectRepository(),
    );

    expect(find.text('Explore public groups'), findsWidgets);
    expect(find.text('No groups available'), findsNothing);
    expect(find.text('Scan group QR'), findsNothing);
  });

  testWidgets('public group detail omits category and explanatory labels', (
    tester,
  ) async {
    await pumpRoute(tester, '/groups/col-public-savings-fixture');

    expect(find.text('Buri Munsi'), findsOneWidget);
    expect(find.byIcon(CollectIcons.savings), findsWidgets);
    expect(find.text('IKIMINA'), findsNothing);
    expect(find.text('Open to everyone'), findsNothing);
    expect(find.textContaining('first contribution also joins'), findsNothing);
    expect(find.text('Contribute & Join'), findsWidgets);
    expect(find.text('Contribute'), findsNothing);
  });

  testWidgets('global Activity renders confirmed records but not intents', (
    tester,
  ) async {
    await pumpRoute(tester, '/activity', legalConsentAccepted: true);

    expect(find.text('Activity'), findsWidgets);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('RWF 25,000'), findsOneWidget);
    expect(find.text('RWF 10,000'), findsOneWidget);
    expect(find.text('RWF 15,000'), findsNothing);
    expect(find.textContaining('intent-render'), findsNothing);
    expect(find.textContaining('confirmed'), findsNothing);
    expect(find.byIcon(CollectIcons.check), findsOneWidget);
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
          matching: find.byType(CollectSliverCardList),
        )
        .first;
    expect(activityCard, findsOneWidget);
    expect(
      find.descendant(of: activityCard, matching: find.byType(BackdropFilter)),
      findsNothing,
      reason: 'Dense activity content must not build a glass blur layer.',
    );
    expect(
      find.ancestor(
        of: find.byType(ActivityFeedItem).first,
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    expect(find.byType(ActivityFeedItem).evaluate().length, lessThan(20));
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

  testWidgets('settings identity omits redundant profile label', (
    tester,
  ) async {
    await pumpRoute(tester, '/settings', legalConsentAccepted: true);

    expect(find.text('038491'), findsOneWidget);
    expect(find.text('Collect profile'), findsNothing);
    expect(find.text('Complete your profile'), findsNothing);
    expect(find.text('Account details'), findsOneWidget);
    expect(find.text('MoMo and USSD'), findsNothing);
    expect(find.text('App permissions'), findsOneWidget);
    await tester.tap(find.text('038491'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('native_profile_editor')), findsOneWidget);
  });

  testWidgets('settings retains actionable incomplete profile prompt', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      '/settings',
      legalConsentAccepted: true,
      repository: CollectRepository.fixture(
        profileOverride: _diasporaProfile.copyWith(revolutAccount: ''),
      ),
    );

    expect(find.text('Collect profile'), findsNothing);
    expect(find.text('Complete your profile'), findsOneWidget);
  });

  testWidgets('account profile row omits redundant labels and still opens', (
    tester,
  ) async {
    await pumpRoute(tester, '/settings/account', legalConsentAccepted: true);

    expect(find.text('Profile and Collect ID'), findsNothing);
    expect(find.text('Payment beneficiary managed centrally.'), findsNothing);
    final profileRow = find.widgetWithText(CollectListTile, 'Profile');
    expect(profileRow, findsOneWidget);
    expect(tester.widget<CollectListTile>(profileRow).subtitle, isNull);
    expect(find.text('Delete data'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    await tester.tap(profileRow);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('native_profile_editor')), findsOneWidget);
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
    expect(find.text('Payment privacy'), findsOneWidget);
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
      await tester.pumpAndSettle();

      expect(find.text('Confirm your number'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth_confirmation_phone')),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm and send'));
      await tester.pumpAndSettle();

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
      expect(find.text('6-digit code'), findsNothing);
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
        expect(find.text('Gikundiro'), findsWidgets, reason: route);
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

  testWidgets('my-groups filter has a clear empty recovery state', (
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

    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.text('Show all groups'), findsOneWidget);
    await tester.tap(find.text('Show all groups'));
    await tester.pumpAndSettle();
    expect(find.text('Gikundiro'), findsOneWidget);
  });

  testWidgets('platform group owner cannot use member management controls', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      '/groups/col-church',
      legalConsentAccepted: true,
      repository: _PlatformOwnerRepository(),
    );
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Contribute'), findsWidgets);
    await pumpRoute(
      tester,
      '/groups/col-church/manage',
      legalConsentAccepted: true,
      repository: _PlatformOwnerRepository(),
    );
    expect(find.text('Managed in Admin'), findsOneWidget);
    expect(find.text('Archive group'), findsNothing);
    expect(find.text('Transfer ownership'), findsNothing);
    expect(find.text('Add admin'), findsNothing);
  });

  testWidgets('group Add admin uses Collect ID, not platform phone approval', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = CollectRepository.fixture(
      fixtureAdditionalMembers: {
        'col-church': [
          CollectMember(
            publicId: '123456',
            role: 'member',
            status: 'active',
            joinedAt: DateTime.utc(2026, 8, 1),
          ),
        ],
      },
    );
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
      await tester.tap(find.text('Add admin'));
      await tester.pumpAndSettle();
      expect(find.textContaining('six-digit Collect ID'), findsOneWidget);
      expect(find.textContaining('pre-approved'), findsNothing);
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
      await tester.enterText(textFieldWithLabel('Collect ID'), '654321');
      await tester.tap(find.widgetWithText(FilledButton, 'Add admin'));
      await tester.pumpAndSettle();
      expect(find.text('Choose another active group member.'), findsOneWidget);
      expect(find.text('Group admin added.'), findsNothing);
      await tester.enterText(textFieldWithLabel('Collect ID'), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Add admin'));
      await tester.pumpAndSettle();
      expect(find.text('Choose another active group member.'), findsNothing);
      expect(find.textContaining('pre-approved'), findsNothing);
      expect(find.text('Group admin added.'), findsOneWidget);
      expect(
        (await repository.membersForCollection(
          'col-church',
        )).singleWhere((member) => member.publicId == '123456').role,
        'admin',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('contribution review reuses an exact pending bank request', (
    tester,
  ) async {
    final repository = CollectRepository.fixture(
      profileOverride: _diasporaProfile,
    );
    final pendingIntent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 15000),
    );
    await pumpRoute(
      tester,
      '/groups/col-church/contribute',
      legalConsentAccepted: true,
      repository: repository,
    );

    await tester.enterText(find.byType(TextField).first, '150.00');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Review transfer'));
    await tester.pump();

    expect(find.text('Review transfer'), findsWidgets);
    expect(find.text(pendingIntent.transferReference), findsOneWidget);
    expect(find.text('Open Revolut'), findsOneWidget);
    expect(repository.state.paymentIntents, hasLength(2));
  });

  testWidgets('contribution review replaces an expired bank request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const cache = CollectOfflineCache(
      preferencesKey: 'collect.offline_snapshot.expired_intent_widget_test',
    );
    final seeded = CollectRepository.fixture(profileOverride: _diasporaProfile);
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
            expectedAmountMinor: 15000,
            rail: 'diaspora_bank',
            transferReference: 'COL-EXPIRED001',
            destination: const BankTransferDestination(
              id: 'fixture-bank',
              beneficiaryName: 'IKANISA Collect',
              iban: 'DE89370400440532013000',
              ibanMasked: 'DE89••••3000',
              bic: 'COBADEFFXXX',
              bankName: 'Collect Bank',
              status: 'active',
              enabled: true,
            ),
            status: 'awaiting_transfer',
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

    await tester.enterText(find.byType(TextField).first, '150.00');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Review transfer'));
    await tester.pump();

    expect(find.text('Review transfer'), findsWidgets);
    expect(find.text('COL-EXPIRED001'), findsNothing);
    expect(find.text('Open Revolut'), findsOneWidget);
    expect(repository.state.paymentIntents, hasLength(2));
  });

  testWidgets('auth screen removes legacy decorative WhatsApp chrome', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(tester, '/auth', legalConsentAccepted: true);

      expect(find.text("Let's get started!"), findsOneWidget);
      expect(
        find.text(
          'Enter your phone number. We will send a secure sign-in code on WhatsApp.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Send WhatsApp code'), findsOneWidget);
      expect(find.bySemanticsLabel('WhatsApp'), findsNothing);
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

  testWidgets('auth uses an injected OTP gateway without a credential bypass', (
    tester,
  ) async {
    final repository = CollectRepository.fixture(seeded: false);
    final authOtpGateway = _TestAuthOtpGateway();
    await pumpRoute(
      tester,
      '/auth',
      legalConsentAccepted: true,
      repository: repository,
      authOtpGateway: authOtpGateway,
    );

    await tester.enterText(find.byType(TextField).first, '+250700000001');
    await tester.pump();
    expect(authButtonEnabled(tester, 'auth_submit_button'), isTrue);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm your number'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auth_confirmation_phone')),
      findsOneWidget,
    );
    await tester.tap(find.text('Edit number'));
    await tester.pumpAndSettle();
    expect(find.text('OTP'), findsNothing);
    expect(find.text('+250700000001'), findsOneWidget);

    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and send'));
    await tester.pumpAndSettle();

    expect(find.text('6-digit code'), findsOneWidget);
    expect(find.text('Authentication failed'), findsNothing);
    expect(find.textContaining('Resend code in 00:'), findsOneWidget);
    final firstOtpField = tester.widget<TextField>(
      find.byKey(const ValueKey('auth_otp_digit_0')),
    );
    expect(firstOtpField.autofocus, isTrue);
    expect(firstOtpField.autofillHints, contains(AutofillHints.oneTimeCode));
    expect(authButtonEnabled(tester, 'auth_submit_button'), isFalse);
    expect(authButtonEnabled(tester, 'auth_change_button'), isTrue);
    expect(authButtonEnabled(tester, 'auth_resend_button'), isFalse);

    await tester.enterText(find.byType(TextField).first, '000000');
    await tester.pump();
    expect(authButtonEnabled(tester, 'auth_submit_button'), isTrue);
    await tester.tap(find.text('Verify and continue'));
    await tester.pump();

    expect(find.text('Authentication failed'), findsOneWidget);
    expect(repository.state.currentProfile, isNull);

    await tester.enterText(find.byType(TextField).first, '135790');
    await tester.ensureVisible(find.text('Verify and continue'));
    await tester.pump();
    await tester.tap(find.text('Verify and continue'));
    await tester.pumpAndSettle();

    expect(find.text('My confirmed contributions'), findsNothing);
    expect(find.byIcon(CollectIcons.people), findsWidgets);
    expect(find.text('0 supported groups'), findsNothing);
    expect(find.text('WhatsApp verified.'), findsNothing);
    expect(repository.state.currentProfile?.whatsappPhone, '+250700000001');
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

    await tester.tap(find.byKey(const ValueKey('auth_country_row_AF_93')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth_country_list')), findsNothing);
    expect(find.text('+93'), findsOneWidget);
  });

  testWidgets('country picker keeps codes and names readable on one line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: const Scaffold(body: AuthCountryPickerSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final longCode = find.byKey(const ValueKey('auth_country_code_AS_1684'));
    await tester.scrollUntilVisible(
      longCode,
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('auth_country_list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();

    final codeText = tester.widget<Text>(longCode);
    expect(codeText.data, '+1684');
    expect(codeText.maxLines, 1);
    expect(codeText.softWrap, isFalse);
    expect(tester.getSize(longCode).width, greaterThan(45));

    final countryName = find.byKey(const ValueKey('auth_country_name_AS_1684'));
    final countryNameText = tester.widget<Text>(countryName);
    final countryNameParagraph = tester.renderObject<RenderParagraph>(
      countryName,
    );
    expect(countryNameText.data, 'American Samoa');
    expect(countryNameText.maxLines, 1);
    expect(countryNameText.softWrap, isFalse);
    expect(countryNameParagraph.didExceedMaxLines, isFalse);
    expect(
      countryNameParagraph.textScaler.scale(
        countryNameParagraph.text.style?.fontSize ?? 14,
      ),
      lessThanOrEqualTo(14),
    );
    expect(tester.takeException(), isNull);
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

    await tester.enterText(find.byType(TextField).first, '78812345');
    await tester.pump();

    expect(authButtonEnabled(tester, 'auth_submit_button'), isFalse);

    await tester.enterText(find.byType(TextField).first, '788123456');
    await tester.pump();

    expect(authButtonEnabled(tester, 'auth_submit_button'), isTrue);
  });

  testWidgets('group creation uses the Rwanda profile MoMo receiver', (
    tester,
  ) async {
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
    expect(repository.state.currentProfile?.whatsappPhone, '+250720000001');

    await tester.enterText(textFieldWithLabel('Group name'), 'Parish support');
    await tester.pumpAndSettle();
    await pressFilledButton(tester, 'Continue');
    await pressFilledButton(tester, 'Continue');

    expect(find.text('Airtel Money receiver'), findsOneWidget);
    expect(find.text('0720000001'), findsOneWidget);
    await pressFilledButton(tester, 'Continue');

    expect(find.text('Group color'), findsOneWidget);
    expect(find.text('Number'), findsNothing);
    expect(find.text('Code'), findsNothing);
    expect(find.text('0788123456'), findsNothing);
    final colorStepButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(colorStepButton.onPressed, isNotNull);
  });

  testWidgets('group creation without profile blocks at receiver setup', (
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

    expect(find.text('MTN MoMo receiver'), findsOneWidget);
    expect(find.text('Group color'), findsNothing);
    final receiverStepButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(receiverStepButton.onPressed, isNull);
  });

  testWidgets('home keeps scan as the only join entry', (tester) async {
    await pumpRoute(tester, '/home', legalConsentAccepted: true);

    final quickActions = find.byType(CollectHeroQuickActionRow);
    expect(quickActions, findsOneWidget);
    expect(
      find.descendant(of: quickActions, matching: find.text('Contribute')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quickActions, matching: find.text('Groups')),
      findsNothing,
    );
    expect(
      find.descendant(of: quickActions, matching: find.text('Supported')),
      findsNothing,
    );
    expect(find.text('Join'), findsNothing);
    expect(find.text('Scan QR'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Join with a code.'), findsNothing);
    expect(find.text('Group code'), findsNothing);
    expect(find.text('Group code or link'), findsNothing);

    await tester.tap(
      find.descendant(of: quickActions, matching: find.text('Contribute')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a group'), findsOneWidget);
  });

  testWidgets('groups low-data route keeps actions in chrome', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpRoute(tester, '/groups', legalConsentAccepted: true);

    expect(find.text('Groups'), findsWidgets);
    expect(find.byIcon(CollectIcons.people), findsWidgets);
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

    expect(find.text('Profile'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile_momo_number_input')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Rwanda uses MoMo'), findsNothing);
    expect(
      find.byKey(const ValueKey('profile_momo_number_input')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'profile country updates currency without changing verified WhatsApp',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repository = CollectRepository.fixture(
        smsAccessChannel: const _TestSmsAccessChannel(),
      );
      final verifiedWhatsApp = repository.state.currentProfile!.whatsappPhone;
      await pumpRoute(
        tester,
        '/settings/profile',
        repository: repository,
        legalConsentAccepted: true,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile_country_picker')),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('WhatsApp'), findsOneWidget);
      expect(find.textContaining(verifiedWhatsApp), findsOneWidget);
      expect(find.text('Rwanda · RWF'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile_revolut_name_input')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('profile_country_picker')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('auth_country_search_input')),
        'United Kingdom',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('auth_country_row_GB_44')));
      await tester.pumpAndSettle();

      expect(find.text('United Kingdom · GBP'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile_revolut_name_input')),
        findsNothing,
      );
      expect(find.text('Name'), findsNothing);
      expect(find.text('Account name'), findsNothing);
      expect(
        find.byKey(const ValueKey('profile_revolut_link_input')),
        findsNothing,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('profile_revolut_account_input')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('profile_revolut_account_input')),
          matching: find.byType(TextField),
        ),
        '000123456789',
      );
      await tester.pump();
      await pressFilledButton(tester, 'Save');
      expect(find.text('Profile saved.'), findsOneWidget);

      final updated = repository.state.currentProfile!;
      expect(updated.whatsappPhone, verifiedWhatsApp);
      expect(updated.countryCode, 'GB');
      expect(updated.currencyCode, 'GBP');
      expect(updated.isComplete, isTrue);
    },
  );

  testWidgets('home groups and activity sections support large text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(
        tester,
        '/home',
        textScale: 2,
        legalConsentAccepted: true,
      );

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Activity'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
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

  testWidgets('Android create group walks through five MoMo setup steps', (
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

      expect(find.text('MTN MoMo receiver'), findsOneWidget);
      expect(find.text('Enable MoMo receipt SMS'), findsOneWidget);
      await pressFilledButton(tester, 'Continue');

      expect(find.text('Group color'), findsOneWidget);
      expect(find.text('Number'), findsNothing);
      expect(find.text('Code'), findsNothing);
      expect(find.text('Receiver privacy'), findsNothing);
      await pressFilledButton(tester, 'Continue');

      expect(find.text('SMS readiness check.'), findsNothing);
      expect(find.text('Review group'), findsOneWidget);
      expect(find.text('Private group'), findsOneWidget);
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
