part of 'mobile_completion_test.dart';

void _registerMobileCompletionAccountCases() {
  testWidgets('archived groups leave active surfaces and become read only', (
    tester,
  ) async {
    final repository = FixtureCollectRepository();
    await repository.archiveCollection('qa-private-group');

    for (final route in const ['/home', '/groups', '/contribute']) {
      await pumpRoute(
        tester,
        route,
        legalConsentAccepted: true,
        repository: repository,
      );
      expect(find.text('QA private group'), findsNothing, reason: route);
      if (route != '/home') {
        expect(find.text('Gikundiro'), findsWidgets, reason: route);
      }
    }

    for (final route in const [
      '/groups/qa-private-group',
      '/groups/qa-private-group/contribute',
      '/groups/qa-private-group/manage',
      '/groups/qa-private-group/profile',
      '/groups/qa-private-group/share',
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
    final repository = FixtureCollectRepository();
    await repository.archiveCollection('qa-private-group');
    await pumpRoute(
      tester,
      '/groups?filter=contributed',
      legalConsentAccepted: true,
      repository: repository,
    );

    expect(find.text('Supported groups'), findsOneWidget);
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
      '/groups/qa-private-group',
      legalConsentAccepted: true,
      repository: _PlatformOwnerRepository(),
    );
    expect(find.text('Manage'), findsNothing);
    expect(find.text('Contribute'), findsWidgets);
    await pumpRoute(
      tester,
      '/groups/qa-private-group/manage',
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
    final repository = FixtureCollectRepository(
      fixtureAdditionalMembers: {
        'qa-private-group': [
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
        '/groups/qa-private-group/manage',
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
          'qa-private-group',
        )).singleWhere((member) => member.publicId == '123456').role,
        'admin',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('auth screen removes legacy decorative WhatsApp chrome', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpRoute(
        tester,
        '/auth',
        legalConsentAccepted: true,
        authOtpGateway: _TestAuthOtpGateway(),
      );
      await selectWhatsAppSignIn(tester);

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
        findsNothing,
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
    final repository = FixtureCollectRepository(seeded: false);
    final authOtpGateway = _TestAuthOtpGateway();
    await pumpRoute(
      tester,
      '/auth',
      legalConsentAccepted: true,
      repository: repository,
      authOtpGateway: authOtpGateway,
    );
    await selectWhatsAppSignIn(tester);

    await tester.enterText(find.byType(TextField).first, '+250788000001');
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
    expect(find.text('+250788000001'), findsOneWidget);

    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm and send'));
    await tester.pumpAndSettle();

    expect(find.text('6-digit code'), findsOneWidget);
    expect(find.text('Authentication failed'), findsNothing);
    expect(find.text('Resend code in 01:00'), findsOneWidget);
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
    expect(repository.state.currentProfile?.whatsappPhone, '+250788000001');
    expect(repository.state.collections, isEmpty);
    expect(repository.state.contributions, isEmpty);
  });

  testWidgets('auth fixes Rwanda calling code', (tester) async {
    await pumpRoute(
      tester,
      '/auth',
      legalConsentAccepted: true,
      authOtpGateway: _TestAuthOtpGateway(),
    );
    await selectWhatsAppSignIn(tester);
    expect(find.text('+250'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auth_country_code_picker')),
      findsNothing,
    );
  });

  testWidgets('Rwanda calling code remains visible at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpRoute(
      tester,
      '/auth',
      legalConsentAccepted: true,
      textScale: 2,
      authOtpGateway: _TestAuthOtpGateway(),
    );
    await selectWhatsAppSignIn(tester);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('auth_whatsapp_phone_input')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('+250'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth disables send until WhatsApp phone is valid', (
    tester,
  ) async {
    await pumpRoute(
      tester,
      '/auth',
      legalConsentAccepted: true,
      authOtpGateway: _TestAuthOtpGateway(),
    );
    await selectWhatsAppSignIn(tester);

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

  testWidgets('group creation needs no MoMo receiver setup', (tester) async {
    final repository = FixtureCollectRepository(seeded: false);
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

    expect(find.text('Airtel Money receiver'), findsNothing);
    expect(find.text('0720000001'), findsNothing);
    expect(find.text('Enable MoMo receipt SMS'), findsNothing);

    expect(find.text('Group color'), findsOneWidget);
    expect(find.text('Number'), findsNothing);
    expect(find.text('Code'), findsNothing);
    expect(find.text('0788123456'), findsNothing);
    final colorStepButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue'),
    );
    expect(colorStepButton.onPressed, isNotNull);
  });

  testWidgets('group creation without a session cannot publish a group', (
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

    expect(find.text('MTN MoMo receiver'), findsNothing);
    expect(find.text('Group color'), findsOneWidget);
    await pressFilledButton(tester, 'Continue');
    await pressFilledButton(tester, 'Create group');
    expect(find.text('Sign in before creating a group.'), findsOneWidget);
    expect(repository.state.collections, isEmpty);
  });

  testWidgets('home offers public group discovery', (tester) async {
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
    expect(find.text('Scan QR'), findsNothing);
    expect(find.text('Explore Groups'), findsOneWidget);
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
    expect(find.text('QA private group'), findsWidgets);
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
    final seeded = FixtureCollectRepository();
    await cache.save(
      CollectOfflineSnapshot(
        savedAt: DateTime.utc(2026, 6, 30, 10, 5),
        currentProfile: seeded.state.currentProfile,
        collections: seeded.state.collections,
        paymentIntents: seeded.state.paymentIntents,
        contributions: seeded.state.contributions,
      ),
    );
    final staleRepository = FixtureCollectRepository(
      seeded: false,
      offlineCache: cache,
    );
    await staleRepository.restoreOfflineSnapshot(
      reason: 'SocketException: network offline',
    );

    await pumpRoute(tester, '/home', repository: staleRepository);

    expect(find.textContaining('Offline saved data'), findsOneWidget);
    await revealCollectPageContent(tester, find.text('My groups'));
    await tester.pump();
    expect(find.text('QA private group'), findsWidgets);
  });

  testWidgets('profile edit supports 200 percent text scale', (tester) async {
    final router = createAppRouter(initialLocation: '/settings/profile');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => FixtureCollectRepository(),
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

  testWidgets('Rwanda MoMo profile saves without changing verified WhatsApp', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const cache = CollectOfflineCache(
      preferencesKey: 'mobile_completion.rwanda_profile',
    );
    final repository = FixtureCollectRepository(
      smsAccessChannel: const _TestSmsAccessChannel(),
      offlineCache: cache,
    );
    final verifiedWhatsApp = repository.state.currentProfile!.whatsappPhone;
    await pumpRoute(
      tester,
      '/settings/profile',
      repository: repository,
      legalConsentAccepted: true,
    );
    final field = find.descendant(
      of: find.byKey(const ValueKey('profile_momo_number_input')),
      matching: find.byType(TextField),
    );
    await tester.scrollUntilVisible(
      field,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(field, '0788123457');
    await tester.pump();
    await pressFilledButton(tester, 'Save');
    expect(repository.state.currentProfile!.whatsappPhone, verifiedWhatsApp);
    expect(repository.state.currentProfile!.countryCode, 'RW');
    expect(repository.state.currentProfile!.currencyCode, 'RWF');
    expect((await cache.read())!.currentProfile!.momoNumber, '0788123457');
  });

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
      '/groups/qa-private-group/manage',
      '/groups/qa-private-group/profile',
      '/groups/qa-private-group/contribute',
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

    await pumpRoute(
      tester,
      '/groups/qa-private-group/contribute',
      textScale: 2,
    );

    final exception = tester.takeException();
    expect(exception, isNull);
    expect(find.byType(CollectApp), findsOneWidget);
  });

  testWidgets(
    'Android create group retains type photo colour and review in four steps',
    (tester) async {
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

        expect(find.text('MTN MoMo receiver'), findsNothing);
        expect(find.text('Enable MoMo receipt SMS'), findsNothing);

        expect(find.text('Group color'), findsOneWidget);
        expect(find.text('Number'), findsNothing);
        expect(find.text('Code'), findsNothing);
        expect(find.text('Receiver privacy'), findsNothing);
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        for (final text in ['Parish support', 'Optional group photo']) {
          final label = find.text(text);
          await tester.ensureVisible(label);
          final paragraph = tester.renderObject<RenderParagraph>(label);
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Add photo'));
        await tester.pumpAndSettle();
        expect(find.text('Group photo'), findsOneWidget);
        final photo = find.text('Neighbourhood savings circle');
        await tester.scrollUntilVisible(
          photo,
          160,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('group-photo-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(photo);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Use photo'));
        await tester.pumpAndSettle();
        expect(find.text('Photo selected'), findsOneWidget);
        await pressFilledButton(tester, 'Continue');

        expect(find.text('SMS readiness check.'), findsNothing);
        expect(find.text('Review group'), findsOneWidget);
        expect(find.text('Private group'), findsOneWidget);
        expect(find.text('Group photo selected'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('fresh link recovery route is removed from the mobile surface', (
    tester,
  ) async {
    await pumpRoute(tester, '/share/expired/request');
    expect(find.text('Fresh link'), findsNothing);
    expect(find.text('Request a fresh link.'), findsNothing);
    expect(find.text('Groups'), findsWidgets);
  });
}
