import '../fixtures/collect_repository_fixture.dart';
import '../fixtures/auth_otp_gateway_fixture.dart';
import '../fixtures/collect_scroll_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/cloudflare/auth_otp_gateway.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
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

part 'mobile_completion_account_cases.dart';

class _TestAuthOtpGateway implements AuthOtpGateway {
  _TestAuthOtpGateway({this.unavailable = false});
  final bool unavailable;
  @override
  bool get whatsAppSignInAvailable => true;

  static const acceptedOtp = '135790';
  String? sentPhone;

  @override
  Future<void> sendWhatsAppOtp({
    required String phone,
    String? captchaToken,
  }) async {
    if (unavailable) throw StateError('WhatsApp sign-in is unavailable.');
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

const _incompleteRwandaProfile = CollectProfile(
  id: 'local-user',
  publicId: '038491',
  whatsappPhone: '+250788123456',
  countryCode: 'RW',
  currencyCode: 'RWF',
);

class _TestSmsAccessChannel extends SmsAccessChannel {
  const _TestSmsAccessChannel();

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async => true;
}

class _PlatformOwnerRepository extends FixtureCollectRepository {
  _PlatformOwnerRepository() : super() {
    state = state.copyWith(
      collections: [
        for (final group in state.collections)
          group.id == 'qa-private-group'
              ? group.copyWith(isPlatformSponsored: true, isPublic: true)
              : group,
      ],
    );
  }
}

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
        collectBackendClientProvider.overrideWithValue(null),
        appRouterProvider.overrideWithValue(router),
        if (appEnv != null) appEnvProvider.overrideWithValue(appEnv),
        if (authOtpGateway != null)
          authOtpGatewayProvider.overrideWithValue(authOtpGateway),
        collectRepositoryProvider.overrideWith(
          (ref) => repository ?? FixtureCollectRepository(),
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
  await revealCollectPageContent(
    tester,
    find.widgetWithText(FilledButton, label),
  );
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, label),
  );
  expect(button.onPressed, isNotNull, reason: '$label should be enabled');
  button.onPressed!();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new mobile completion routes render', (tester) async {
    const routes = [
      '/contribute',
      '/activity',
      '/settings/notifications',
      '/settings/appearance',
      '/settings/security',
      '/settings/help',
      '/groups/qa-private-group/contribute',
      '/groups/qa-private-group/manage',
      '/groups/qa-private-group/profile',
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

    await tester.tap(find.text('QA private group').first);
    await tester.pumpAndSettle();

    expect(find.text('How much?'), findsOneWidget);
    expect(find.text('QA MoMo'), findsOneWidget);
    expect(find.text('0788123456'), findsOneWidget);
    expect(find.textContaining('receiver'), findsNothing);
    expect(find.textContaining('MTN MoMo'), findsNothing);
    expect(find.text('QA private group'), findsOneWidget);
    expect(find.text('Choose a group'), findsNothing);
    expect(find.text('Profile'), findsNothing);
    await revealCollectPageContent(tester, find.text('Continue to MoMo'));
    expect(find.text('Continue to MoMo'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('native_momo_contribution_flow')))
          .width,
      lessThanOrEqualTo(430),
    );
  });

  testWidgets('incomplete Rwanda profile cannot start a contribution', (
    tester,
  ) async {
    final repository = FixtureCollectRepository(
      profileOverride: _incompleteRwandaProfile,
    );
    final priorIntents = repository.state.paymentIntents.length;
    await pumpRoute(
      tester,
      '/groups/col-public-savings-fixture/contribute',
      legalConsentAccepted: true,
      repository: repository,
    );
    await tester.enterText(find.byType(TextField).first, '1000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('native_profile_editor')), findsOneWidget);
    expect(repository.state.paymentIntents, hasLength(priorIntents));
    expect(find.text('Review transfer'), findsNothing);
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
      '/groups/qa-private-group/contribute',
      textScale: 2,
      repository: FixtureCollectRepository(),
    );
    await tester.pumpAndSettle();
    const payee = 'QA MoMo';
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

  for (final network in ['mtn_momo', 'airtel_money']) {
    testWidgets('MoMo recipient keeps identity and number for $network', (
      tester,
    ) async {
      final repository = FixtureCollectRepository();
      final number = network == 'mtn_momo' ? '0788123456' : '0738123456';
      repository.state = repository.state.copyWith(
        collections: [
          for (final group in repository.state.collections)
            group.id == 'qa-private-group'
                ? group.copyWith(
                    receiverNetwork: network,
                    receiverMomoNumber: number,
                  )
                : group,
        ],
      );
      await pumpRoute(
        tester,
        '/groups/qa-private-group/contribute',
        repository: repository,
      );
      await tester.pumpAndSettle();

      void expectRecipient() {
        final card = find.bySemanticsLabel('QA MoMo, $number');
        expect(card, findsOneWidget);
        expect(find.text('QA MoMo'), findsOneWidget);
        expect(find.text(number), findsOneWidget);
        for (final label in ['receiver', 'MTN MoMo', 'Airtel Money']) {
          expect(
            find.descendant(of: card, matching: find.textContaining(label)),
            findsNothing,
          );
        }
      }

      expectRecipient();
      await tester.enterText(find.byType(TextField).first, '1234');
      await tester.pumpAndSettle();
      await pressFilledButton(tester, 'Continue to MoMo');
      expect(find.text('Open MoMo USSD'), findsOneWidget);
      expectRecipient();
      final intent = repository.state.paymentIntents.last;
      expect(intent.receiverMomoNumber, number);
      expect(intent.momoNetwork, network);
      expect(intent.expectedAmountRwf, 1234);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'MoMo groups typed amounts and quick picks without changing value',
    (tester) async {
      final repository = FixtureCollectRepository();
      await pumpRoute(
        tester,
        '/groups/col-public-savings-fixture/contribute',
        legalConsentAccepted: true,
        repository: repository,
      );
      final field = find.byType(TextField).first;
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      final amountHint = tester.widget<TextField>(field).decoration!.hint;
      expect(amountHint, isA<ExcludeSemantics>());
      expect(((amountHint! as ExcludeSemantics).child as Text).data, '0');
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
    expect(find.text('Recorded contributions'), findsWidgets);
    expect(
      find.textContaining(
        'A receipt SMS or a ledger entry alone does not verify provider settlement.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'global Activity distinguishes recorded totals from pending intents and settlement',
    (tester) async {
      await pumpRoute(tester, '/activity', legalConsentAccepted: true);

      expect(find.text('Activity'), findsWidgets);
      expect(find.text('QA private group'), findsWidgets);
      expect(find.text('RWF 25,000'), findsOneWidget);
      expect(find.text('RWF 10,000'), findsOneWidget);
      expect(find.text('RWF 15,000'), findsNothing);
      expect(find.textContaining('intent-render'), findsNothing);
      expect(find.textContaining('confirmed'), findsNothing);
      expect(find.byIcon(CollectIcons.ledger), findsOneWidget);
      expect(find.text('Recorded contributions'), findsOneWidget);
      expect(
        find.textContaining(
          'A receipt SMS or a ledger entry alone does not verify provider settlement.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<ActivityFeedItem>(find.byType(ActivityFeedItem))
            .every((item) => item.tone == CollectStatusTone.info),
        isTrue,
      );
    },
  );

  testWidgets('dense Activity avoids a viewport-spanning backdrop filter', (
    tester,
  ) async {
    final repository = FixtureCollectRepository(fixtureContributionCount: 80);
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
      '/groups/qa-private-group/ledger',
      legalConsentAccepted: true,
      repository: FixtureCollectRepository(fixtureContributionCount: 80),
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
      repository: FixtureCollectRepository(
        profileOverride: _incompleteRwandaProfile,
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
    final repository = FixtureCollectRepository();
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
    expect(find.text('Recorded contributions'), findsOneWidget);
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
          collectBackendClientProvider.overrideWithValue(null),
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
        '/groups/qa-private-group': 'Loading group',
        '/settings': 'Loading settings',
      }.entries) {
        final router = createAppRouter(initialLocation: entry.key);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectBackendClientProvider.overrideWithValue(null),
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
      await pumpRoute(
        tester,
        '/auth',
        authOtpGateway: _TestAuthOtpGateway(unavailable: true),
      );
      await selectWhatsAppSignIn(tester);

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

  _registerMobileCompletionAccountCases();
}

class _LoadingCollectRepository extends FixtureCollectRepository {
  _LoadingCollectRepository() : super(seeded: false) {
    state = state.copyWith(isLoading: true);
  }
}
