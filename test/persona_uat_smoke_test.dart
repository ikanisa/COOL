import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
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
  }) async {
    final router = createAppRouter(initialLocation: initialLocation);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          if (repository != null)
            collectRepositoryProvider.overrideWith((ref) => repository),
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
    final verticalScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    );
    if (finder.evaluate().isEmpty) {
      if (verticalScrollable.evaluate().isEmpty) {
        await tester.scrollUntilVisible(finder, delta);
      } else {
        await tester.scrollUntilVisible(
          finder,
          delta,
          scrollable: verticalScrollable.first,
        );
      }
    }
    await tester.ensureVisible(finder);
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

    expect(find.text('Collect'), findsWidgets);
    expect(find.text('Platform admin'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('member browses groups without receiver data leakage', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups');

    expect(find.text('Groups'), findsWidgets);
    expect(find.text('St Michel building fund'), findsOneWidget);
    expect(find.text('Auto allocation'), findsNothing);
    expect(find.textContaining('SMS matched'), findsNothing);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('contributor creates intent and waits for SMS allocation', (
    tester,
  ) async {
    final repository = CollectRepository.seeded();
    await pumpMainAppAt(
      tester,
      '/groups/col-church/contribute',
      repository: repository,
    );

    expect(find.text('Contribute'), findsWidgets);
    expect(find.text('Automated SMS match'), findsNothing);
    expect(find.text('Collect ID'), findsNothing);
    expect(find.textContaining('manual'), findsNothing);

    final intent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
    );
    final router = GoRouter.of(tester.element(find.text('Contribute').first));
    router.go('/groups/col-church/pay/${intent.id}');
    await pumpLaunchFrames(tester);

    expect(find.text('Waiting for MoMo SMS'), findsNothing);
    expect(find.text('Payment'), findsWidgets);
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.textContaining('+250788123456'), findsWidgets);
    router.go('/groups/col-church/ledger');
    await pumpLaunchFrames(tester);

    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Private'), findsNothing);
    expect(find.text('Safe ledger'), findsNothing);
    expect(find.text('#038491'), findsWidgets);
    expectNoGlobalSecrets();
  });

  testWidgets('creator share routes preserve group boundaries', (tester) async {
    await pumpMainAppAt(tester, '/groups/col-church/share');

    expect(find.text('Share'), findsWidgets);
    expect(find.text('Group sharing'), findsNothing);
    expect(find.text('Private receiver'), findsWidgets);
    expect(
      find.textContaining('does not expose the receiver MoMo number'),
      findsOneWidget,
    );
    expect(find.textContaining('+250788'), findsNothing);

    final router = GoRouter.of(tester.element(find.text('Share').first));
    router.go('/groups/col-church/invite');
    await pumpLaunchFrames(tester);

    expect(find.text('Share'), findsWidgets);
    expect(find.text('SMS'), findsWidgets);
    expect(find.text('WhatsApp'), findsWidgets);
    expect(find.text('Copy deep link'), findsWidgets);
    expect(find.text('Private receiver'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('/c/'), findsWidgets);
    expectNoGlobalSecrets();
  });

  testWidgets('invalid shared links offer privacy-safe recovery', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/share/invalid');

    expect(find.text('Link unavailable'), findsWidgets);
    expect(find.text('Receiver privacy'), findsOneWidget);
    await scrollToVisible(tester, find.text('Try another link'));
    expect(find.text('Try another link'), findsOneWidget);
    await scrollToVisible(tester, find.text('Open groups'));
    expect(find.text('Open groups'), findsOneWidget);
    await scrollToVisible(tester, find.text('Get help'));
    expect(find.text('Get help'), findsOneWidget);
    expect(find.textContaining('receiver MoMo details'), findsOneWidget);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('expired shared links keep join recovery actionable', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/share/expired');

    expect(find.text('Link expired'), findsWidgets);
    expect(find.textContaining('fresh private link'), findsOneWidget);
    await scrollToVisible(tester, find.text('Try another link'));
    expect(find.text('Try another link'), findsOneWidget);
    expect(find.text('Receiver privacy'), findsOneWidget);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('member opens shared group link by slug', (tester) async {
    await pumpMainAppAt(tester, '/c/st-michel-building-fund');
    await pumpLaunchFrames(tester);

    expect(find.text('Group joined'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('Open group'), findsWidgets);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('member joins group from portal without receiver leakage', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups/join');

    expect(find.text('Join group'), findsWidgets);
    expect(find.text('Group code or link'), findsOneWidget);
    expect(find.textContaining('+250788'), findsNothing);

    await tester.enterText(
      find.byType(TextField).first,
      'https://collect.rw/c/st-michel-building-fund',
    );
    await tapVisible(tester, find.text('Join group').last);

    expect(find.text('Group joined'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.textContaining('+250788'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('iPhone create group entry shows Android-only warning', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pumpMainAppAt(tester, '/home');

      await tapVisible(tester, find.byTooltip('Create group'));

      expect(
        find.text('group creation is available only on Android'),
        findsWidgets,
      );
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

      expect(find.text('Create group'), findsWidgets);
      expect(find.text('Group name'), findsNothing);
      expect(find.text('Receiver MoMo number'), findsNothing);
      expect(
        find.text('group creation is available only on Android'),
        findsWidgets,
      );
      expectNoGlobalSecrets();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android SMS denial routes create group to retry screen', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpMainAppAt(
        tester,
        '/groups/create',
        repository: CollectRepository.seeded(
          smsAccessChannel: _DenySmsAccessChannel(),
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'New parish fund');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await pumpLaunchFrames(tester);
      await tapVisible(tester, find.byType(FilledButton).last);

      expect(find.text('SMS access needed'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expectNoGlobalSecrets();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('new profile does not prefill a sample MoMo number', (
    tester,
  ) async {
    await pumpMainAppAt(
      tester,
      '/settings/profile',
      repository: CollectRepository(),
    );

    expect(find.text('Profile setup'), findsWidgets);
    expect(find.text('Sign in first.'), findsOneWidget);
    expect(find.textContaining('+250788123456'), findsNothing);
    expect(find.text('MoMo number'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('auth phone and OTP flow uses Rwanda-first WhatsApp copy', (
    tester,
  ) async {
    final repository = CollectRepository();
    await pumpMainAppAt(tester, '/auth', repository: repository);

    expect(find.text('Collect'), findsWidgets);
    expect(find.text('WhatsApp phone'), findsOneWidget);
    expect(find.text('Send WhatsApp code'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '+250788123456');
    await tapVisible(tester, find.text('Send WhatsApp code'));

    expect(find.text('Verify WhatsApp'), findsWidgets);
    expect(find.text('Verification code'), findsOneWidget);
    expect(find.text('Use another number'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tapVisible(tester, find.text('Verify and continue'));

    expect(find.text('OTP verified'), findsOneWidget);
    expect(repository.state.currentProfile?.publicId, isNotNull);
    expectNoGlobalSecrets();
  });

  testWidgets('profile setup walks Collect ID, MoMo, and device readiness', (
    tester,
  ) async {
    await pumpMainAppAt(
      tester,
      '/settings/profile',
      repository: CollectRepository.seeded(),
    );

    expect(find.text('Profile setup'), findsWidgets);
    expect(find.text('COLLECT ID'), findsOneWidget);
    expect(find.text('038491'), findsOneWidget);

    await tapVisible(tester, find.text('Continue'));

    expect(find.text('Link MoMo number'), findsOneWidget);
    expect(find.text('MoMo number'), findsOneWidget);
    expect(find.textContaining('public share links'), findsOneWidget);

    await tapVisible(tester, find.text('Save MoMo number'));

    expect(find.text('Stay ready for group activity.'), findsOneWidget);
    expect(find.text('Device permissions'), findsOneWidget);
    expect(find.text('Finish setup'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('device permissions expose notification readiness rows', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/permissions/device');

    expect(find.text('Device permissions'), findsWidgets);
    expect(find.text('Review readiness.'), findsWidgets);
    expect(find.text('Contribution confirmations'), findsOneWidget);
    await scrollToVisible(tester, find.text('Payment reminders'));
    expect(find.text('Payment reminders'), findsOneWidget);
    await scrollToVisible(tester, find.text('Group updates'));
    expect(find.text('Group updates'), findsOneWidget);
    await scrollToVisible(tester, find.text('Security notices'));
    expect(find.text('Security notices'), findsOneWidget);
    await scrollToVisible(tester, find.text('Notification boundary'));
    expect(find.text('Notification boundary'), findsOneWidget);
    await scrollToVisible(tester, find.text('SMS access details'));
    expect(find.text('SMS access details'), findsOneWidget);
    await scrollToVisible(tester, find.text('Open updates'));
    expect(find.text('Open updates'), findsOneWidget);
    await scrollToVisible(tester, find.text('Finish setup'));
    expect(find.text('Finish setup'), findsOneWidget);
    expect(find.textContaining('raw SMS text'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('contribution review creates intent before MoMo handoff', (
    tester,
  ) async {
    final repository = CollectRepository.seeded();
    await pumpMainAppAt(
      tester,
      '/groups/col-church/contribute',
      repository: repository,
    );

    expect(find.text('Contribute'), findsWidgets);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await pumpLaunchFrames(tester);
    expect(find.text('Target account'), findsOneWidget);

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Review contribution'),
    );

    expect(find.text('Review contribution'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('+250788123456'), findsOneWidget);
    expect(find.text('038491'), findsOneWidget);

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Confirm and open MoMo'),
    );

    expect(repository.state.paymentIntents, isNotEmpty);
    expect(find.text('Open MoMo'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await pumpLaunchFrames(tester);
    expect(find.text('Open MoMo USSD'), findsOneWidget);
    expect(find.textContaining('paste SMS'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('waiting for SMS route shows payment detail and recovery paths', (
    tester,
  ) async {
    final repository = CollectRepository.seeded();
    final intent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 12000),
    );

    await pumpMainAppAt(
      tester,
      '/groups/col-church/pay/${intent.id}/waiting',
      repository: repository,
    );

    expect(find.text('Waiting for SMS'), findsOneWidget);
    expect(find.text('St Michel building fund'), findsWidgets);
    expect(find.text('RWF 12,000'), findsWidgets);
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('+250788123456'), findsOneWidget);
    expect(find.byTooltip('Refresh payment status'), findsOneWidget);

    await scrollToVisible(tester, find.text('Listening for MoMo SMS'));
    expect(find.text('Listening for MoMo SMS'), findsOneWidget);
    await scrollToVisible(tester, find.text('Expected timing'));
    expect(find.text('Expected timing'), findsOneWidget);
    await scrollToVisible(tester, find.text('Reference'));
    expect(find.textContaining(intent.id), findsWidgets);
    await scrollToVisible(tester, find.text('Refresh status'));
    expect(find.text('Refresh status'), findsOneWidget);

    await scrollToVisible(tester, find.text('View status'));
    expect(find.text('View status'), findsOneWidget);
    await scrollToVisible(tester, find.text('Open MoMo again'));
    expect(find.text('Open MoMo again'), findsOneWidget);
    await scrollToVisible(tester, find.text('Get help'));
    expect(find.text('Get help'), findsOneWidget);
    expect(find.textContaining('raw SMS'), findsNothing);
    expect(find.textContaining('manual'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets(
    'contribution attempt without profile MoMo routes to link state',
    (tester) async {
      final repository = CollectRepository();
      await repository.signInWithOtp(phone: '+250788123456', otp: '123456');
      final collection = await repository.createCollection(
        title: 'Family group',
        description: 'Family support',
        receiverMomoNumber: '+250788123456',
      );

      await pumpMainAppAt(
        tester,
        '/groups/${collection.id}/contribute',
        repository: repository,
      );

      expect(find.text('Profile required'), findsOneWidget);
      expect(find.text('Link your MoMo number first.'), findsOneWidget);
      expect(find.text('Link MoMo number'), findsOneWidget);
      expect(find.text('Review contribution'), findsNothing);
      expect(repository.state.paymentIntents, isEmpty);
      expectNoGlobalSecrets();
    },
  );

  testWidgets('ledger filters show confirmed and pending activity safely', (
    tester,
  ) async {
    final repository = CollectRepository.seeded();
    final intent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 7000),
    );
    await pumpMainAppAt(
      tester,
      '/groups/col-church/ledger',
      repository: repository,
    );

    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('Confirmed ledger'), findsOneWidget);
    expect(find.text('RWF 35,000'), findsOneWidget);
    expect(find.text('MTN12345'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Pending'));

    expect(find.text('Pending'), findsWidgets);
    expect(find.text('RWF 7,000'), findsOneWidget);
    expect(find.text('Intent ${intent.id}'), findsOneWidget);
    expect(find.text('MTN12345'), findsNothing);
    expect(find.textContaining('raw SMS'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('payment state detail routes provide retry and review copy', (
    tester,
  ) async {
    final repository = CollectRepository.seeded();
    final intent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5000),
    );
    await pumpMainAppAt(
      tester,
      '/groups/col-church/pay/${intent.id}/state/expired',
      repository: repository,
    );

    expect(find.text('Payment expired'), findsWidgets);
    final router = GoRouter.of(
      tester.element(find.text('Payment expired').first),
    );
    expect(find.text('RWF 5,000'), findsWidgets);
    expect(find.text('St Michel treasury'), findsOneWidget);
    await scrollToVisible(tester, find.text('Reference'));
    expect(find.textContaining(intent.id), findsWidgets);
    await scrollToVisible(tester, find.text('Contribute again'));
    expect(find.text('Contribute again'), findsOneWidget);

    router.go('/groups/col-church/pay/${intent.id}/state/needs-review');
    await pumpLaunchFrames(tester);

    await scrollToVisible(
      tester,
      find.text('Payment needs review'),
      delta: -240,
    );
    expect(find.text('Payment needs review'), findsWidgets);
    expect(find.text('RWF 5,000'), findsWidgets);
    await scrollToVisible(tester, find.text('Support review'));
    expect(find.text('Support review'), findsOneWidget);
    await scrollToVisible(tester, find.text('Open ledger'));
    expect(find.text('Open ledger'), findsOneWidget);
    await scrollToVisible(tester, find.text('Get help'));
    expect(find.text('Get help'), findsOneWidget);
    expect(find.textContaining('public raw SMS details'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('settings exposes SMS access without manual paste', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings');

    expect(find.text('Settings'), findsWidgets);
    expect(find.text('SMS access'), findsOneWidget);
    expect(find.textContaining('manual'), findsNothing);
    expectNoGlobalSecrets();
  });

  testWidgets('privacy, notifications, and terms routes have useful copy', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings/privacy');

    expect(find.text('Privacy and data'), findsWidgets);
    final router = GoRouter.of(
      tester.element(find.text('Privacy and data').first),
    );
    expect(find.text('Collect ID first.'), findsOneWidget);
    expect(find.text('What SMS messages are read'), findsOneWidget);
    await scrollToVisible(tester, find.text('What is parsed locally'));
    expect(find.text('What is parsed locally'), findsOneWidget);
    await scrollToVisible(tester, find.text('What is sent to Supabase'));
    expect(find.text('What is sent to Supabase'), findsOneWidget);
    await scrollToVisible(tester, find.text('Retention and audit boundary'));
    expect(find.text('Retention and audit boundary'), findsOneWidget);
    await scrollToVisible(tester, find.text('Owner-only Android capture'));
    expect(find.text('Owner-only Android capture'), findsOneWidget);
    await scrollToVisible(
      tester,
      find.textContaining('Members and iPhone users can join and contribute'),
    );
    expect(
      find.textContaining('Members and iPhone users can join and contribute'),
      findsOneWidget,
    );

    router.go('/permissions/sms');
    await pumpLaunchFrames(tester);

    expect(find.text('SMS access'), findsWidgets);
    expect(find.text('What Collect reads'), findsOneWidget);
    await scrollToVisible(tester, find.text('What is parsed'));
    expect(find.text('What is parsed'), findsOneWidget);
    await scrollToVisible(tester, find.text('What is synced'));
    expect(find.text('What is synced'), findsOneWidget);
    await scrollToVisible(tester, find.text('Privacy details'));
    expect(find.text('Privacy details'), findsOneWidget);

    router.go('/notifications');
    await pumpLaunchFrames(tester);

    expect(find.text('Updates'), findsOneWidget);
    expect(find.text('Security notice'), findsOneWidget);

    router.go('/settings/legal/privacy');
    await pumpLaunchFrames(tester);

    expect(find.text('Privacy policy'), findsWidgets);
    expect(find.text('Profile data'), findsOneWidget);
    expect(find.text('Payment data'), findsOneWidget);
    expect(find.text('SMS evidence'), findsOneWidget);
    expect(find.textContaining('receiver MoMo details'), findsWidgets);
    expectNoGlobalSecrets();
  });

  testWidgets('offline route explains safe retry behavior', (tester) async {
    await pumpMainAppAt(tester, '/offline');

    expect(find.text('Connection issue'), findsWidgets);
    expect(find.text('Offline-safe behavior'), findsOneWidget);
    await scrollToVisible(tester, find.text('Retry sync'));
    expect(find.text('Retry sync'), findsOneWidget);
    await scrollToVisible(tester, find.textContaining('New contributions'));
    expect(find.textContaining('New contributions'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('owner dashboard and member search expose operational health', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups/col-church/owner');

    expect(find.text('Owner dashboard'), findsOneWidget);
    expect(find.text('Pending'), findsWidgets);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('SMS'), findsWidgets);

    final router = GoRouter.of(tester.element(find.text('Owner').first));
    router.go('/groups/col-church/members');
    await pumpLaunchFrames(tester);

    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Search Collect ID'), findsOneWidget);
    expect(find.text('#038491'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'no-match');
    await pumpLaunchFrames(tester);
    expect(find.text('No members found'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('manage route keeps unsupported owner actions bounded', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/groups/col-church/manage');

    expect(find.text('Manage'), findsWidgets);
    expect(find.text('Owner controls'), findsOneWidget);
    await scrollToVisible(tester, find.text('Target tracking'));
    expect(find.text('Target tracking'), findsOneWidget);
    expect(
      find.textContaining('Not configured for this model'),
      findsOneWidget,
    );
    expect(find.text('Target amount'), findsNothing);
    expect(find.textContaining('manual'), findsNothing);
    expect(find.textContaining('allocation'), findsNothing);

    await scrollToVisible(tester, find.text('Close group'));
    expect(
      find.textContaining('Use share, ledger, and support'),
      findsOneWidget,
    );
    await scrollToVisible(tester, find.text('Support'));
    expect(
      find.text('Request help with closing or receiver changes.'),
      findsOneWidget,
    );

    await tapVisible(tester, find.text('Close group'));

    expect(find.text('Help'), findsOneWidget);
    expect(find.text('MoMo payments'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('ledger filters confirmed, pending, review, and mine activity', (
    tester,
  ) async {
    await pumpMainAppAt(
      tester,
      '/groups/col-church/ledger',
      repository: _LedgerScenarioRepository(),
    );

    expect(find.text('Ledger'), findsOneWidget);
    expect(find.text('#038491'), findsWidgets);
    expect(find.textContaining('intent-pending'), findsWidgets);
    expect(find.textContaining('intent-review'), findsWidgets);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Pending'));
    expect(find.textContaining('intent-pending'), findsWidgets);
    expect(find.textContaining('intent-review'), findsNothing);
    expect(find.textContaining('MTN12345'), findsNothing);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Needs review'));
    expect(find.textContaining('intent-review'), findsWidgets);
    expect(find.textContaining('intent-pending'), findsNothing);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Confirmed'));
    expect(find.textContaining('MTN12345'), findsWidgets);
    expect(find.textContaining('intent-pending'), findsNothing);

    await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Mine'));
    expect(find.text('#038491'), findsWidgets);
    expectNoGlobalSecrets();
  });

  testWidgets('payment state routes render clear recovery actions', (
    tester,
  ) async {
    final repository = CollectRepository.seeded();
    final intent = await repository.createPaymentIntent(
      const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 9000),
    );
    await pumpMainAppAt(
      tester,
      '/groups/col-church/pay/${intent.id}/state/pending',
      repository: repository,
    );
    expect(find.text('Payment pending'), findsWidgets);
    final router = GoRouter.of(
      tester.element(find.text('Payment pending').first),
    );
    expect(find.text('RWF 9,000'), findsWidgets);
    await scrollToVisible(tester, find.text('Reference'));
    expect(find.textContaining(intent.id), findsWidgets);
    await scrollToVisible(tester, find.text('Open ledger'));
    expect(find.text('Open ledger'), findsOneWidget);
    await scrollToVisible(tester, find.text('View status'));
    expect(find.text('View status'), findsOneWidget);

    router.go('/groups/col-church/pay/${intent.id}/state/needs-review');
    await pumpLaunchFrames(tester);
    await scrollToVisible(
      tester,
      find.text('Payment needs review'),
      delta: -240,
    );
    expect(find.text('Payment needs review'), findsWidgets);
    expect(find.text('RWF 9,000'), findsWidgets);
    await scrollToVisible(tester, find.text('Support review'));
    expect(find.text('Support review'), findsOneWidget);
    expect(find.textContaining('public raw SMS'), findsWidgets);

    router.go('/groups/col-church/pay/${intent.id}/state/expired');
    await pumpLaunchFrames(tester);
    await scrollToVisible(tester, find.text('Payment expired'), delta: -240);
    expect(find.text('Payment expired'), findsWidgets);
    await scrollToVisible(tester, find.text('Contribute again'));
    expect(find.text('Contribute again'), findsOneWidget);
    await scrollToVisible(tester, find.text('Get help'));
    expect(find.text('Get help'), findsOneWidget);

    router.go('/groups/col-church/pay/${intent.id}/state/confirmed');
    await pumpLaunchFrames(tester);
    await scrollToVisible(tester, find.text('Payment confirmed'), delta: -240);
    expect(find.text('Payment confirmed'), findsOneWidget);
    expect(find.text('RWF 9,000'), findsWidgets);
    await scrollToVisible(tester, find.text('Ledger updated'));
    expect(find.text('Ledger updated'), findsOneWidget);
    await scrollToVisible(tester, find.text('Open ledger'));
    expect(find.text('Open ledger'), findsOneWidget);
    await scrollToVisible(tester, find.text('Open group'));
    expect(find.text('Open group'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('help center includes support categories and request form', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings/help');

    expect(find.text('Help'), findsOneWidget);
    expect(find.text('MoMo payments'), findsOneWidget);
    expect(find.text('SMS verification'), findsOneWidget);
    expect(find.text('Privacy and data'), findsOneWidget);
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expectNoGlobalSecrets();
  });

  testWidgets('legal pages explain privacy and terms boundaries', (
    tester,
  ) async {
    await pumpMainAppAt(tester, '/settings/legal/privacy');

    expect(find.text('Privacy policy'), findsWidgets);
    expect(find.text('Profile data'), findsOneWidget);
    expect(find.text('Payment data'), findsOneWidget);
    expect(find.text('SMS evidence'), findsOneWidget);
    final router = GoRouter.of(
      tester.element(find.text('Privacy policy').first),
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await pumpLaunchFrames(tester);
    expect(find.textContaining('not public group content'), findsWidgets);

    router.go('/settings/legal/terms');
    await pumpLaunchFrames(tester);
    expect(find.text('Terms'), findsWidgets);
    expect(find.text('MoMo approval'), findsOneWidget);
    expect(find.text('Ledger status'), findsOneWidget);
    expect(find.text('Group ownership'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await pumpLaunchFrames(tester);
    expect(
      find.textContaining('will never ask for a MoMo PIN'),
      findsOneWidget,
    );
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
        '/onboarding',
        '/auth',
        '/settings/profile',
        '/home',
        '/groups',
        '/groups/join',
        '/groups/create',
        '/platform/iphone-create-unavailable',
        '/groups/col-church',
        '/groups/col-church/share',
        '/groups/col-church/invite',
        '/groups/col-church/contribute',
        '/groups/col-church/pay/intent-pending/handoff',
        '/groups/col-church/pay/intent-pending/waiting',
        '/groups/col-church/pay/intent-pending',
        '/groups/col-church/pay/intent-pending/state/pending',
        '/groups/col-church/pay/intent-pending/state/expired',
        '/groups/col-church/pay/intent-review/state/needs-review',
        '/groups/col-church/ledger',
        '/groups/col-church/owner',
        '/groups/col-church/manage',
        '/groups/col-church/members',
        '/settings',
        '/settings/privacy',
        '/settings/help',
        '/notifications',
        '/offline',
        '/sync',
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
    'payment_events.reparse',
    'sms.reveal_raw',
    'audit_logs.read',
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
  _LedgerScenarioRepository() : super.seeded() {
    final now = DateTime.now();
    state = state.copyWith(
      paymentIntents: [
        ...state.paymentIntents,
        PaymentIntentModel(
          id: 'intent-pending',
          collectionId: 'col-church',
          expectedAmountRwf: 7500,
          receiverMomoNumber: '+250788123456',
          receiverLabel: 'St Michel treasury',
          status: 'pending',
          createdAt: now.subtract(const Duration(minutes: 15)),
          expiresAt: now.add(const Duration(hours: 23)),
        ),
        PaymentIntentModel(
          id: 'intent-review',
          collectionId: 'col-church',
          expectedAmountRwf: 12500,
          receiverMomoNumber: '+250788123456',
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
