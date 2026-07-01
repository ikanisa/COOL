import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Future<void> pumpLaunchFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i += 1) {
      await tester.pump();
    }
  }

  Future<void> pumpMainAppAt(
    WidgetTester tester,
    String initialLocation, {
    CollectRepository? repository,
    bool legalConsentAccepted = false,
    String? pendingSharedGroupSlug,
  }) async {
    final router = createAppRouter(initialLocation: initialLocation);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith(
            (ref) => repository ?? CollectRepository.fixture(),
          ),
          legalConsentAcceptedProvider.overrideWith(
            (ref) => legalConsentAccepted,
          ),
          if (pendingSharedGroupSlug != null)
            pendingSharedGroupSlugProvider.overrideWith(
              (ref) => pendingSharedGroupSlug,
            ),
        ],
        child: const CollectApp(),
      ),
    );
    await pumpLaunchFrames(tester);
  }

  Future<void> scrollToVisible(
    WidgetTester tester,
    Finder finder, {
    double delta = 240,
  }) async {
    final initialMatches = finder.evaluate();
    if (initialMatches.isNotEmpty) {
      final target = initialMatches.length > 1 ? finder.first : finder;
      await tester.ensureVisible(target);
      await tester.pump();
      return;
    }
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    );
    final scrollables = verticalScrollable.evaluate().toList().reversed;
    for (final element in scrollables) {
      try {
        final scrollable = element.widget as Scrollable;
        final scrollableFinder = find.byWidget(element.widget);
        final moveStep = switch (scrollable.axisDirection) {
          AxisDirection.up => Offset(0, delta),
          AxisDirection.down => Offset(0, -delta),
          AxisDirection.left => Offset(delta, 0),
          AxisDirection.right => Offset(-delta, 0),
        };
        for (var i = 0; i < 12 && finder.evaluate().isEmpty; i += 1) {
          await tester.drag(scrollableFinder, moveStep, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 50));
        }
        if (finder.evaluate().isNotEmpty) break;
      } catch (_) {
        continue;
      }
    }
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, delta, maxScrolls: 12);
    }
    final visibleMatches = finder.evaluate();
    final visibleTarget = visibleMatches.length > 1 ? finder.first : finder;
    await tester.ensureVisible(visibleTarget);
    await tester.pump();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await scrollToVisible(tester, finder);
    }
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await pumpLaunchFrames(tester);
  }

  Future<void> tapTableAction(WidgetTester tester, String label) async {
    final horizontalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.horizontal,
    );
    await tester.scrollUntilVisible(
      find.text(label),
      240,
      scrollable: horizontalScrollable.last,
    );
    await tapVisible(tester, find.text(label));
  }

  void expectNoGlobalSecrets() {
    expect(find.textContaining('service_role'), findsNothing);
    expect(find.textContaining('OPENAI_API_KEY'), findsNothing);
    expect(find.textContaining('WHATSAPP'), findsNothing);
    expect(find.textContaining('SMS_HOOK'), findsNothing);
  }

  testWidgets('main app launches without admin or secret-bearing surface', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: CollectApp()));
    await pumpLaunchFrames(tester);

    expect(find.text('Collect'), findsOneWidget);
    expect(find.text('Groups. MoMo. Done.'), findsNothing);
    expect(find.text('TOTAL COLLECTED'), findsNothing);
    expect(find.text('038491'), findsNothing);
    expect(find.text('St Michel building fund'), findsNothing);
    expect(find.text('CONFIRMED'), findsNothing);
    expect(find.text('PENDING'), findsNothing);
    expect(find.text('FAILED'), findsNothing);
    expect(find.text('Platform admin'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('member browses groups without receiver data leakage', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups');

    expect(find.text('Groups'), findsWidgets);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Auto allocation'), findsNothing);
    expect(find.textContaining('SMS matched'), findsNothing);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('home supported groups chip opens contributed groups', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/home');

    expect(find.text('Featured Groups'), findsOneWidget);
    expect(find.text('Public groups'), findsNothing);
    expect(find.byTooltip('Supported groups'), findsOneWidget);
    final router = GoRouter.of(
      tester.element(find.byKey(const Key('home_supported_groups_chip'))),
    );
    await tapVisible(
      tester,
      find.byKey(const Key('home_supported_groups_chip')),
    );
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      contains('filter=contributed'),
    );
    expect(find.text('Groups'), findsWidgets);
    expect(find.text('Supported groups'), findsWidgets);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Kigali Lions away kit'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets(
    'groups screen lists compact cards without search or filter dock',
    (tester) async {
      final repository = CollectRepository.fixture();
      await repository.createCollection(
        title: 'Private family support',
        description: 'Family group',
        receiverMomoNumber: '+250789123456',
      );

      await pumpMainAppAt(tester, '/groups', repository: repository);

      expect(find.text('Groups'), findsWidgets);
      expect(find.text('St Michel building fund'), findsWidgets);
      expect(find.text('Private family support'), findsWidgets);
      expect(find.text('VISIBILITY'), findsNothing);
      expect(find.text('SORT'), findsNothing);
      expect(find.text('Search groups'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expectNoGlobalSecrets();
    },
  );

  testWidgets('group detail keeps hero compact and labels untruncated', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups/col-church');

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.textContaining('Transparent support'), findsNothing);
    expect(find.text('MEMBERS'), findsNothing);
    expect(find.textContaining('PARTICIP'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('contributor launches MoMo and returns to group', (tester) async {
    final repository = CollectRepository.fixture();
    await pumpMainAppAt(
      tester,
      '/groups/col-church/contribute',
      repository: repository,
    );

    expect(find.text('Review contribution'), findsWidgets);
    expect(find.text('Pending payment'), findsNothing);
    expect(find.text('MoMo handoff'), findsNothing);
    expect(find.text('Automated SMS match'), findsNothing);
    expect(find.text('Collect ID'), findsNothing);
    expect(find.textContaining('manual'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '5000');
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Review contribution'),
    );
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Pay with MOMO'),
    );
    await tester.pumpAndSettle();
    await pumpLaunchFrames(tester);

    expect(repository.state.paymentIntents, isNotEmpty);
    expect(find.text('Waiting for MoMo SMS'), findsNothing);
    expect(find.text('Checking MoMo confirmation.'), findsNothing);
    expect(find.text('Payment pending'), findsNothing);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.textContaining('+250789123456'), findsNothing);
    expect(find.text('078***3456'), findsNothing);
    final router = GoRouter.of(
      tester.element(find.text('St Michel building fund').first),
    );
    router.go('/groups/col-church/ledger');
    await tester.pumpAndSettle();
    await pumpLaunchFrames(tester);

    expect(find.text('Ledger'), findsWidgets);
    expect(find.text('Private'), findsNothing);
    expect(find.text('Safe ledger'), findsNothing);
    expect(find.text('038491'), findsWidgets);
    expect(find.text('RWF 5,000'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('creator share routes preserve group boundaries', (tester) async {
    await pumpMainAppAt(tester, '/groups/col-church/share');

    expect(find.text('Group QR'), findsWidgets);
    expect(find.text('St Michel building fund'), findsNothing);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Group sharing'), findsNothing);
    expect(find.text('Private receiver'), findsNothing);
    expect(
      find.textContaining('does not expose the receiver MoMo number'),
      findsNothing,
    );
    expect(find.textContaining('+250788'), findsNothing);

    final router = GoRouter.of(tester.element(find.text('Share').first));
    router.go('/groups/col-church/invite');
    await tester.pumpAndSettle();

    expect(find.text('Group QR'), findsWidgets);
    expect(find.text('St Michel building fund'), findsNothing);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('SMS'), findsNothing);
    expect(find.text('WhatsApp'), findsNothing);
    expect(find.text('Copy deep link'), findsNothing);
    expect(find.text('Private receiver'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('/c/'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('invalid shared links return to groups', (tester) async {
    await pumpMainAppAt(tester, '/share/invalid');

    expect(find.text('Groups'), findsWidgets);
    expect(find.text('Link unavailable'), findsNothing);
    expect(find.text('Receiver privacy'), findsNothing);
    expect(find.textContaining('receiver MoMo details'), findsNothing);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('expired shared links return to groups', (tester) async {
    await pumpMainAppAt(tester, '/share/expired');

    expect(find.text('Groups'), findsWidgets);
    expect(find.text('Link expired'), findsNothing);
    expect(find.textContaining('fresh private link'), findsNothing);
    expect(find.text('Receiver privacy'), findsNothing);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('member opens shared group link by slug', (tester) async {
    await pumpMainAppAt(tester, '/c/st-michel-building-fund');
    await pumpLaunchFrames(tester);

    expect(find.text('Group joined'), findsNothing);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Open group'), findsNothing);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('member joins from QR entry without receiver leakage', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups/scan');

    expect(find.text('Scan QR'), findsNothing);
    expect(find.bySemanticsLabel('Close scanner'), findsOneWidget);
    expect(find.text('Join with a code.'), findsNothing);
    expect(find.text('Group code'), findsNothing);
    expect(find.text('Group code or link'), findsNothing);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('iPhone home hides group creation entry', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpMainAppAt(tester, '/home');

      expect(find.text('Create'), findsNothing);
      expect(find.text('Join options'), findsNothing);
      expect(find.text('Create group'), findsNothing);
      expectNoGlobalSecrets();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iPhone direct create route does not expose group form', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpMainAppAt(tester, '/groups/create');

      expect(find.text('Groups'), findsWidgets);
      expect(find.text('Group name'), findsNothing);
      expect(find.text('Receiver MoMo number'), findsNothing);
      expect(find.text('Create groups on Android'), findsNothing);
      expectNoGlobalSecrets();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android group creation does not require SMS access approval', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpMainAppAt(
        tester,
        '/groups/create',
        repository: CollectRepository.fixture(
          smsAccessChannel: _DenySmsAccessChannel(),
        ),
      );

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == 'Group name',
        ),
        'Parish support',
      );
      await pumpLaunchFrames(tester);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tester.enterText(find.byType(TextField).last, '0789123456');
      await pumpLaunchFrames(tester);
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Create group'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Parish support'), findsWidgets);
      expect(find.text('SMS access'), findsNothing);
      expect(find.text('Open app settings'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expectNoGlobalSecrets();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('unsigned profile edit does not prefill a sample MoMo number', (
    tester,
  ) async {
    await pumpMainAppAt(
      tester,
      '/settings/profile',
      repository: CollectRepository(),
    );

    expect(find.text('Edit profile'), findsWidgets);
    expect(find.text('Sign in first.'), findsOneWidget);
    expect(find.textContaining('+250789123456'), findsNothing);
    expect(find.text('MoMo number'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('auth phone flow fails closed without live Supabase auth', (
    tester,
  ) async {
    final repository = CollectRepository();
    await pumpMainAppAt(
      tester,
      '/auth',
      repository: repository,
      legalConsentAccepted: true,
    );

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Send WhatsApp code'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '+250789123456');
    await tapVisible(tester, find.text('Send WhatsApp code'));

    expect(find.text('Authentication failed'), findsOneWidget);
    expect(
      find.textContaining('WhatsApp sign-in is unavailable'),
      findsOneWidget,
    );
    expect(find.text('Verify WhatsApp'), findsNothing);
    expect(repository.state.currentProfile, isNull);
    expectNoGlobalSecrets();
  });

  testWidgets('profile edit walks Collect ID and MoMo fields', (tester) async {
    await pumpMainAppAt(
      tester,
      '/settings/profile',
      repository: CollectRepository.fixture(),
    );

    expect(find.text('Edit profile'), findsWidgets);
    await scrollToVisible(tester, find.text('COLLECT ID'));
    expect(find.text('COLLECT ID'), findsOneWidget);
    expect(find.text('038491'), findsOneWidget);

    expect(find.text('Linked MoMo'), findsNothing);
    expect(find.text('MoMo number'), findsNothing);
    expect(find.text('Number'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('MoMo Pay code'), findsNothing);
    expect(find.textContaining('public share links'), findsNothing);
    expect(find.textContaining('Rwanda format'), findsNothing);

    expect(find.text('MoMo Code'), findsNothing);
    expect(find.byTooltip('MoMo code'), findsOneWidget);
    expect(find.text('Save MoMo number'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '0789123456');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save MoMo number'));

    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.text('Back to settings'), findsOneWidget);
    expect(find.text('Device permissions'), findsNothing);
    expect(find.text('Finish setup'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('profile save opens pending shared group deep link', (
    tester,
  ) async {
    await pumpMainAppAt(
      tester,
      '/settings/profile',
      repository: CollectRepository.fixture(),
      pendingSharedGroupSlug: 'st-michel-building-fund',
    );

    await tester.enterText(find.byType(TextField).first, '0789123456');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Save MoMo number'));
    await tester.pumpAndSettle();

    expect(find.text('Group joined'), findsNothing);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Open group'), findsNothing);
    expect(find.text('Finish setup'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('settings opens native notification recovery sheet', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings');

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Permission use'), findsNothing);
    expect(find.text('SMS access'), findsNothing);
    expect(find.text('Notifications'), findsWidgets);
    await tapVisible(tester, find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('Open app settings'), findsOneWidget);
    expect(find.text('Access boundary'), findsNothing);
    expect(find.text('SMS access details'), findsNothing);
    expect(find.textContaining('raw SMS text'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('contribution review creates intent and returns to group', (
    tester,
  ) async {
    final repository = CollectRepository.fixture();
    await pumpMainAppAt(
      tester,
      '/groups/col-church/contribute',
      repository: repository,
    );

    expect(find.text('Review contribution'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await pumpLaunchFrames(tester);
    expect(find.text('Target account'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '6000');

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Review contribution'),
    );

    expect(find.text('Review contribution'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('St Michel treasury'), findsNothing);
    expect(find.text('+250788123456'), findsOneWidget);
    expect(find.text('078***3456'), findsNothing);
    expect(find.text('038491'), findsNothing);

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Pay with MOMO'),
    );
    await pumpLaunchFrames(tester);

    expect(repository.state.paymentIntents, isNotEmpty);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Checking MoMo confirmation.'), findsNothing);
    expect(find.text('Payment pending'), findsNothing);
    expect(find.text('Open MoMo'), findsNothing);
    expect(find.text('Open MoMo USSD'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets(
    'contribution attempt without profile MoMo routes to link state',
    (tester) async {
      final repository = CollectRepository.fixture(seeded: false);
      await repository.signInWithOtp(phone: '+250722123456', otp: '123456');
      final collection = await repository.createCollection(
        title: 'Family group',
        description: 'Family support',
        receiverMomoNumber: '+250789123456',
      );

      await pumpMainAppAt(
        tester,
        '/groups/${collection.id}/contribute',
        repository: repository,
      );

      expect(find.text('Link your MoMo number first.'), findsOneWidget);
      expect(find.text('Link MoMo number'), findsOneWidget);
      expect(find.text('Review contribution'), findsNothing);
      expect(repository.state.paymentIntents, isEmpty);
      expectNoGlobalSecrets();
    },
  );

  testWidgets('ledger hides unvalidated local MoMo attempts', (tester) async {
    final repository = CollectRepository.fixture();
    final intent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 7000),
    );
    await pumpMainAppAt(
      tester,
      '/groups/col-church/ledger',
      repository: repository,
    );

    expect(find.text('Ledger'), findsWidgets);
    expect(find.text('Confirmed ledger'), findsNothing);
    expect(find.text('RWF 35,000'), findsOneWidget);
    expect(find.text('MTN12345'), findsOneWidget);

    expect(find.text('Pending'), findsNothing);
    expect(find.text('Needs review'), findsNothing);
    expect(find.text('RWF 7,000'), findsNothing);
    expect(find.text('Awaiting MoMo confirmation'), findsNothing);
    expect(find.textContaining(intent.id), findsNothing);
    expect(find.textContaining('raw SMS'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('settings keeps permissions action-triggered', (tester) async {
    await pumpMainAppAt(tester, '/settings');

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Account center'), findsNothing);
    expect(find.text('Collect ID'), findsNothing);
    expect(find.text('Action-led'), findsNothing);
    expect(find.text('No secrets'), findsNothing);
    expect(find.text('Ready for group activity'), findsNothing);
    expect(find.text('Device permissions'), findsNothing);
    expect(find.byTooltip('Profile'), findsNothing);
    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('Readiness'), findsNothing);
    expect(find.text('SMS access'), findsNothing);
    expect(find.text('Linked MoMo'), findsNothing);
    expect(find.textContaining('manual'), findsNothing);

    final router = GoRouter.of(tester.element(find.text('Settings').first));
    router.go('/settings/account');
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsWidgets);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Linked MoMo'), findsNothing);
    await tapVisible(tester, find.text('Edit profile'));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsWidgets);
    expect(find.text('MoMo number'), findsNothing);
    expect(find.text('Number'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('account action sheets expose accessible native-style actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final semantics = tester.ensureSemantics();
    try {
      await pumpMainAppAt(tester, '/settings/account');

      await tapVisible(tester, find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign out?'), findsOneWidget);
      expect(
        find.textContaining('Group ledgers and verified records'),
        findsOneWidget,
      );
      expect(find.semantics.byLabel('Cancel'), findsOne);
      expect(find.semantics.byLabel('Sign out'), findsWidgets);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await pumpMainAppAt(tester, '/settings/account/delete');
      await tapVisible(tester, find.text('I no longer use Collect'));
      await tapVisible(tester, find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.text('Submit delete request?'), findsOneWidget);
      expect(
        find.textContaining('auditable data deletion request'),
        findsOneWidget,
      );
      expect(find.semantics.byLabel('Cancel'), findsOne);
      expect(find.semantics.byLabel('Submit'), findsWidgets);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('privacy route redirects to legal privacy copy', (tester) async {
    await pumpMainAppAt(tester, '/settings/privacy');

    expect(find.text('Privacy Policy'), findsWidgets);
    expect(find.text('Privacy and data'), findsNothing);
    expect(find.textContaining('No names, no phone numbers'), findsNothing);
    expect(find.text('What SMS messages are read'), findsNothing);
    expect(find.text('What is parsed locally'), findsNothing);
    expect(find.text('What is sent to Supabase'), findsNothing);
    expect(find.text('Retention and audit boundary'), findsNothing);
    expect(find.text('Data boundary'), findsNothing);
    await scrollToVisible(tester, find.text('Data we collect'));
    expect(find.text('Data we collect'), findsOneWidget);
    expect(find.text('How we use data'), findsOneWidget);
    await scrollToVisible(tester, find.text('What stays private'));
    expect(find.text('What stays private'), findsOneWidget);
    expect(find.textContaining('raw receiver MoMo'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('offline route returns to groups', (tester) async {
    await pumpMainAppAt(tester, '/offline');

    expect(find.text('Groups'), findsWidgets);
    expect(find.text('Connection issue'), findsNothing);
    expect(find.text('Offline-safe behavior'), findsNothing);
    expect(find.text('Retry sync'), findsNothing);
    expect(find.textContaining('New contributions'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('manage route opens settings and member search', (tester) async {
    await pumpMainAppAt(tester, '/groups/col-church/manage');

    expect(find.text('Group settings'), findsWidgets);
    expect(find.text('Group needs attention'), findsNothing);
    expect(find.text('Group profile'), findsOneWidget);

    final router = GoRouter.of(
      tester.element(find.text('Group settings').first),
    );
    router.go('/groups/col-church/members');
    await pumpLaunchFrames(tester);

    expect(find.text('Members'), findsWidgets);
    expect(find.text('Search Collect ID'), findsOneWidget);
    expect(find.text('038491'), findsOneWidget);
    expect(find.text('1 shown'), findsNothing);
    expect(find.text('1 total'), findsNothing);
    expect(find.text('1 owner'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'no-match');
    await pumpLaunchFrames(tester);
    expect(find.text('No members found'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('manage route keeps unsupported owner actions bounded', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups/col-church/manage');

    expect(find.text('Group settings'), findsWidgets);
    final router = GoRouter.of(
      tester.element(find.text('Group settings').first),
    );
    await scrollToVisible(tester, find.text('Group profile'));
    expect(find.text('Group profile'), findsOneWidget);
    expect(find.text('SMS readiness'), findsNothing);
    expect(find.textContaining('Not configured for this model'), findsNothing);
    expect(find.text('Target amount'), findsNothing);
    expect(find.textContaining('manual'), findsNothing);
    expect(find.textContaining('allocation'), findsNothing);

    expect(find.text('Close group'), findsNothing);
    expect(find.textContaining('Use share, ledger, and support'), findsNothing);
    await scrollToVisible(tester, find.text('Archive group'));
    expect(find.text('Archive group'), findsOneWidget);
    await scrollToVisible(tester, find.text('Transfer ownership'));
    expect(find.text('Transfer ownership'), findsOneWidget);
    await scrollToVisible(tester, find.text('Add admin'));
    expect(find.text('Add admin'), findsOneWidget);
    await scrollToVisible(tester, find.text('Support'));
    expect(
      find.text('Request help with closing or receiver changes.'),
      findsNothing,
    );
    expect(find.text('MoMo payments'), findsNothing);

    router.go('/groups/col-church/profile');
    await pumpLaunchFrames(tester);

    expect(find.text('Group profile'), findsWidgets);
    await scrollToVisible(tester, find.text('Recurring contribution'));
    expect(find.text('Recurring contribution'), findsWidgets);
    await scrollToVisible(tester, find.text('Number'));
    expect(find.text('Number'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('Receiver name'), findsNothing);
    expect(find.text('St Michel treasury'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('ledger shows validated activity without status controls', (
    tester,
  ) async {
    await pumpMainAppAt(
      tester,
      '/groups/col-church/ledger',
      repository: _LedgerScenarioRepository(),
    );

    expect(find.text('Ledger'), findsWidgets);
    expect(find.text('038491'), findsWidgets);
    expect(find.text('Pending'), findsNothing);
    expect(find.text('Needs review'), findsNothing);
    expect(find.textContaining('intent-pending'), findsNothing);
    expect(find.textContaining('intent-review'), findsNothing);

    expect(find.text('Pending'), findsNothing);
    expect(find.text('Needs review'), findsNothing);
    expect(find.text('Awaiting MoMo confirmation'), findsNothing);
    expect(find.textContaining('intent-pending'), findsNothing);
    expect(find.textContaining('intent-review'), findsNothing);

    expect(find.text('Awaiting MoMo confirmation'), findsNothing);
    expect(find.textContaining('intent-review'), findsNothing);
    expect(find.textContaining('intent-pending'), findsNothing);

    expect(find.textContaining('MTN12345'), findsWidgets);
    expect(find.text('STATUS'), findsNothing);
    expect(find.text('GROUP'), findsOneWidget);
    expect(find.textContaining('intent-pending'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('help route returns to settings without support screen', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings/help');

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('WhatsApp support'), findsNothing);
    expect(find.text('Support without secrets'), findsNothing);
    expect(find.text('Contact support on WhatsApp.'), findsNothing);
    expect(find.text('+250795588248'), findsNothing);
    expect(find.text('Open WhatsApp'), findsNothing);
    expect(find.text('Subject'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('legal pages explain privacy and terms boundaries', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings/legal/privacy');

    expect(find.text('Privacy Policy'), findsWidgets);
    final router = GoRouter.of(
      tester.element(find.text('Privacy Policy').first),
    );
    expect(find.text('Data boundary'), findsNothing);
    await scrollToVisible(tester, find.text('Data we collect'));
    expect(find.text('Data we collect'), findsOneWidget);
    expect(find.text('How we use data'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await pumpLaunchFrames(tester);
    expect(find.textContaining('+250788'), findsNothing);
    expect(find.textContaining('MoMo PIN'), findsNothing);
    expect(find.textContaining('OTP'), findsNothing);

    router.go('/settings/legal/terms');
    await pumpLaunchFrames(tester);
    expect(find.text('Terms & Conditions'), findsWidgets);
    expect(find.text('Trust boundary'), findsNothing);
    await scrollToVisible(tester, find.text('Using Collect'));
    expect(find.text('Using Collect'), findsOneWidget);
    expect(find.text('MoMo payments'), findsOneWidget);
    expect(find.text('Group ownership'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await pumpLaunchFrames(tester);
    expect(find.textContaining('will never ask for a MoMo PIN'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets(
    'representative mobile route matrix renders on compact viewport',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const routes = [
        '/auth',
        '/settings/profile',
        '/home',
        '/groups',
        '/groups/scan',
        '/groups/create',
        '/groups/col-church',
        '/groups/col-church/share',
        '/groups/col-church/contribute',
        '/groups/col-church/ledger',
        '/groups/col-church/manage',
        '/groups/col-church/profile',
        '/groups/col-church/members',
        '/settings',
        '/settings/legal/privacy',
      ];

      for (final route in routes) {
        await pumpMainAppAt(
          tester,
          route,
          repository: _LedgerScenarioRepository(),
        );
        expect(tester.takeException(), isNull, reason: route);
        expect(find.byType(CollectApp), findsOneWidget, reason: route);
      }

      expectNoGlobalSecrets();
    },
  );

  testWidgets('admin app opens at login for default non-admin state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAuthGuardProvider.overrideWithValue(
            const AdminAuthGuard(isAuthorized: false),
          ),
        ],
        child: const CollectAdminApp(),
      ),
    );
    await pumpLaunchFrames(tester);

    expect(find.text('Collect admin login'), findsOneWidget);
    expect(find.text('Operations overview'), findsNothing);
    expect(find.textContaining('service_role'), findsNothing);
  });

  testWidgets(
    'admin personas review group operations, payment, compliance, audit, and health routes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _FakeAdminRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAuthGuardProvider.overrideWithValue(
              const AdminAuthGuard(isAuthorized: true),
            ),
            adminRepositoryProvider.overrideWithValue(repository),
            adminIdentityProvider.overrideWith(
              (ref) async => _platformOwnerIdentity,
            ),
          ],
          child: const CollectAdminApp(),
        ),
      );
      await pumpLaunchFrames(tester);

      expect(find.text('Operations overview'), findsOneWidget);
      expect(find.text('Collect Admin'), findsWidgets);
      expect(find.textContaining('service_role'), findsNothing);

      final router = GoRouter.of(
        tester.element(find.text('Operations overview')),
      );
      router.go('/admin/groups');
      await pumpLaunchFrames(tester);
      expect(find.text('Groups'), findsWidgets);

      router.go('/admin/allocations');
      await pumpLaunchFrames(tester);
      expect(find.text('Allocations'), findsWidgets);
      expect(find.text('Allocated MOMO event'), findsOneWidget);

      router.go('/admin/exceptions');
      await pumpLaunchFrames(tester);
      expect(find.text('Exceptions'), findsWidgets);
      expect(find.text('Ambiguous MOMO event'), findsOneWidget);
      await tapTableAction(tester, 'Reparse');
      await tester.enterText(
        find.byType(TextField).last,
        'Retry parser after support review',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Request reparse'));
      await pumpLaunchFrames(tester);
      expect(
        repository.actions,
        contains(
          'admin_reparse_payment_event:Retry parser after support review',
        ),
      );

      router.go('/admin/sms/sms-1');
      await pumpLaunchFrames(tester);
      expect(find.text('SMS metadata'), findsWidgets);
      expect(find.text('Reveal raw SMS'), findsOneWidget);
      expect(find.textContaining('MOMO payment received'), findsNothing);
      await tapVisible(tester, find.text('Reveal raw SMS'));
      expect(
        find.text('Enter a reason before revealing sensitive data.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Compliance audit sample',
      );
      await tester.tap(find.text('Reveal raw SMS'));
      await pumpLaunchFrames(tester);
      expect(find.text('MOMO payment received from REDACTED.'), findsOneWidget);
      expect(
        repository.actions,
        contains('admin_reveal_raw_sms:Compliance audit sample'),
      );

      router.go('/admin/audit-logs');
      await pumpLaunchFrames(tester);
      expect(find.text('Audit logs'), findsWidgets);
      expect(find.text('Raw SMS reveal audited'), findsOneWidget);

      router.go('/admin/system-health');
      await pumpLaunchFrames(tester);
      expect(find.text('System health'), findsWidgets);
      expect(find.textContaining('"status": "ok"'), findsOneWidget);
      expectNoGlobalSecrets();
    },
  );
}

const _platformOwnerIdentity = AdminIdentity(
  userId: '00000000-0000-0000-0000-000000000001',
  displayName: 'Collect platform owner',
  roles: ['platform_owner'],
  permissions: [
    'overview.read',
    'collections.read',
    'payment_events.read',
    'payment_events.reparse',
    'sms.metadata.read',
    'sms.raw.reveal',
    'audit.read',
    'system_health.read',
  ],
);

class _DenySmsAccessChannel extends SmsAccessChannel {
  @override
  Future<bool> setEnabled(bool enabled) async => false;

  @override
  Future<bool> isEnabled() async => false;
}

class _LedgerScenarioRepository extends CollectRepository {
  _LedgerScenarioRepository() : super.fixture() {
    final now = DateTime.now();
    state = state.copyWith(
      paymentIntents: [
        ...state.paymentIntents,
        PaymentIntentModel(
          id: 'intent-pending',
          collectionId: 'col-church',
          expectedAmountRwf: 7500,
          receiverMomoNumber: '+250789123456',
          receiverLabel: 'St Michel treasury',
          status: 'pending',
          createdAt: now.subtract(const Duration(minutes: 15)),
          expiresAt: now.add(const Duration(hours: 23)),
        ),
        PaymentIntentModel(
          id: 'intent-review',
          collectionId: 'col-church',
          expectedAmountRwf: 12500,
          receiverMomoNumber: '+250789123456',
          receiverLabel: 'St Michel treasury',
          status: 'needs_review',
          createdAt: now.subtract(const Duration(minutes: 30)),
          expiresAt: now.add(const Duration(hours: 22)),
        ),
      ],
    );
  }
}

class _FakeAdminRepository extends AdminRepository {
  _FakeAdminRepository() : super(null);

  final actions = <String>[];

  @override
  Future<AdminIdentity?> currentIdentity() async => _platformOwnerIdentity;

  @override
  Future<List<AdminMetric>> overviewMetrics() async => const [
    AdminMetric(label: 'Review queue', value: '2', status: 'needs_review'),
  ];

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
  }) async {
    return AdminListResult(
      rows: switch (rpcName) {
        'admin_list_allocations' => const [
          AdminTableRowData(
            id: 'event-allocated',
            title: 'Allocated MOMO event',
            subtitle: 'Matched to pending intent',
            status: 'allocated',
            amount: 'RWF 5,000',
          ),
        ],
        'admin_list_unallocated' => const [
          AdminTableRowData(
            id: 'event-1',
            title: 'Ambiguous MOMO event',
            subtitle: 'Amount requires review before allocation',
            status: 'needs_review',
            amount: 'RWF 10,000',
          ),
        ],
        'admin_list_audit_logs' => const [
          AdminTableRowData(
            id: 'audit-1',
            title: 'Raw SMS reveal audited',
            subtitle: 'Compliance audit sample',
            status: 'recorded',
            amount: '',
          ),
        ],
        _ => const [],
      },
    );
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    return switch (rpcName) {
      'admin_get_sms_metadata' => {
        'id': id,
        'sender_masked': '+250***3456',
        'receiver_masked': '+250***2222',
        'raw_body': 'hidden',
        'status': 'needs_review',
      },
      'admin_system_health' => {
        'status': 'ok',
        'database': 'reachable',
        'edge_functions': 'contract_checked',
      },
      _ => {'id': id, 'status': 'ok'},
    };
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    final reason = (params['p_reason'] as String?) ?? '';
    actions.add('$rpcName:$reason');
    if (rpcName == 'admin_reveal_raw_sms') {
      return {'message': 'MOMO payment received from REDACTED.'};
    }
    return {'status': 'ok'};
  }
}
