import 'dart:async';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/contribution_command_repository_fixture.dart';

class _RouteChangingRepository extends ContributionFixtureRepository {
  int createCalls = 0;

  @override
  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    createCalls++;
    return super.createPaymentIntent(draft);
  }

  @override
  Future<PaymentIntentModel> currentReviewIntent(
    PaymentIntentModel intent,
  ) async {
    return PaymentIntentModel(
      id: intent.id,
      collectionId: intent.collectionId,
      expectedAmountRwf: intent.expectedAmountRwf,
      receiverMomoNumber: '0788999999',
      receiverMomoNumberHash: 'new-active-route',
      receiverMomoLabel: 'Changed receiver',
      momoNetwork: intent.momoNetwork,
      senderPhoneHash: intent.senderPhoneHash,
      status: intent.status,
      createdAt: intent.createdAt,
      expiresAt: intent.expiresAt,
    );
  }
}

class _CountingRepository extends ContributionFixtureRepository {
  int createCalls = 0;

  @override
  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    createCalls++;
    return super.createPaymentIntent(draft);
  }
}

class _UnavailablePreflightRepository extends ContributionFixtureRepository {
  int createCalls = 0;

  @override
  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    createCalls++;
    return super.createPaymentIntent(draft);
  }

  @override
  Future<PaymentIntentModel> currentReviewIntent(
    PaymentIntentModel intent,
  ) async {
    throw StateError('Synthetic preflight unavailable');
  }
}

class _ExpiredPermitRepository extends ContributionFixtureRepository {
  @override
  Future<ContributionLaunchPermit> claimContributionHandoff(
    PaymentIntentModel prepared,
    ContributionIntentReview review,
  ) async {
    handoffCalls++;
    return ContributionLaunchPermit(review: review, isCurrent: () => false);
  }
}

class _SwitchingRepository extends ContributionFixtureRepository {
  void switchAccount() {
    state = state.copyWith(
      currentProfile: const CollectProfile(
        id: 'different-account',
        publicId: '123456',
        whatsappPhone: '+250788999999',
        countryCode: 'RW',
        currencyCode: 'RWF',
        momoProvider: 'mtn_momo',
        momoNumber: '0788999999',
      ),
    );
  }
}

Future<void> _prepare(WidgetTester tester, CollectRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [collectRepositoryProvider.overrideWith((ref) => repo)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ContributionFlowScreen(
          collectionId: contributionFixtureGroup,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, '6000');
  await tester.pump();
  await tester.scrollUntilVisible(
    find.widgetWithText(FilledButton, 'Continue to MoMo'),
    80,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Continue to MoMo'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.widgetWithText(FilledButton, 'Open MoMo USSD'),
    80,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  expect(find.text('Open MoMo USSD'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('separate current review precedes opening MoMo USSD', (
    tester,
  ) async {
    final repo = _CountingRepository();
    var launchCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('collect/momo_ussd');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launchCalls++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _prepare(tester, repo);
    final openAction = find.widgetWithText(FilledButton, 'Open MoMo USSD');
    await tester.ensureVisible(openAction);
    await tester.pumpAndSettle();
    await tester.tap(openAction);
    await tester.pumpAndSettle();

    expect(repo.createCalls, 1);
    expect(repo.reviewCalls, 1);
    expect(launchCalls, 1);
    expect(find.text('MoMo request opened'), findsOneWidget);
  });

  testWidgets('changed receiver blocks USSD and returns to preparation', (
    tester,
  ) async {
    final repo = _RouteChangingRepository();
    var launchCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('collect/momo_ussd');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launchCalls++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _prepare(tester, repo);
    final openAction = find.widgetWithText(FilledButton, 'Open MoMo USSD');
    await tester.ensureVisible(openAction);
    await tester.pumpAndSettle();
    await tester.tap(openAction);
    await tester.pumpAndSettle();

    expect(repo.createCalls, 1);
    expect(repo.reviewCalls, 1);
    expect(launchCalls, 0);
    final continueAction = find.widgetWithText(
      FilledButton,
      'Continue to MoMo',
      skipOffstage: false,
    );
    final actionScrollOwner = find
        .ancestor(
          of: continueAction,
          matching: find.byType(Scrollable, skipOffstage: false),
        )
        .first;
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Continue to MoMo'),
      80,
      scrollable: actionScrollOwner,
    );
    await tester.pumpAndSettle();
    expect(continueAction.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(continueAction).onPressed, isNotNull);
    expect(find.text('Continue to MoMo'), findsOneWidget);
    expect(
      find.text(
        'Payment details changed. If you may have paid, check with your mobile money provider before another transfer.',
      ),
      findsOneWidget,
    );
    expect(repo.createCalls, 1);
    expect(repo.reviewCalls, 1);
    expect(launchCalls, 0);
  });

  testWidgets('unavailable preflight blocks USSD and preserves payment caution', (
    tester,
  ) async {
    final repo = _UnavailablePreflightRepository();
    final balances = Map<String, CollectionSummary>.unmodifiable(
      repo.state.collectionSummaries,
    );
    final contributions = List<Contribution>.unmodifiable(
      repo.state.contributions,
    );
    var launchCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('collect/momo_ussd');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launchCalls++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _prepare(tester, repo);
    expect(repo.createCalls, 1);
    expect(launchCalls, 0);
    final openAction = find.widgetWithText(FilledButton, 'Open MoMo USSD');
    await tester.ensureVisible(openAction);
    await tester.pumpAndSettle();
    await tester.tap(openAction);
    await tester.pumpAndSettle();

    expect(repo.createCalls, 1);
    expect(repo.reviewCalls, 1);
    expect(launchCalls, 0);
    expect(find.text('Open MoMo USSD'), findsNothing);
    expect(find.text('MoMo request opened'), findsNothing);
    expect(
      find.text(
        'Payment details could not be confirmed. If you may have paid, check with your mobile money provider before another transfer.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Synthetic preflight unavailable'),
      findsNothing,
    );
    expect(repo.state.collectionSummaries, balances);
    expect(repo.state.contributions, contributions);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired handoff permit never launches and returns to recovery', (
    tester,
  ) async {
    final repo = _ExpiredPermitRepository();
    var launchCalls = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('collect/momo_ussd');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') launchCalls++;
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await _prepare(tester, repo);
    final openAction = find.widgetWithText(FilledButton, 'Open MoMo USSD');
    await tester.ensureVisible(openAction);
    await tester.pumpAndSettle();
    await tester.tap(openAction);
    await tester.pumpAndSettle();

    expect(repo.handoffCalls, 1);
    expect(launchCalls, 0);
    expect(find.text('Open MoMo USSD'), findsNothing);
    expect(find.text('MoMo request opened'), findsNothing);
    expect(
      find.text(
        'Payment details could not be confirmed. If you may have paid, check with your mobile money provider before another transfer.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android permission completes before review and handoff', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repo = _CountingRepository();
      final permission = Completer<bool>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('collect/momo_ussd');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'ensurePermission') return permission.future;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _prepare(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
      await tester.pump();
      expect(calls, ['ensurePermission']);
      expect(repo.reviewCalls, 0);
      expect(repo.handoffCalls, 0);
      permission.complete(true);
      await tester.pumpAndSettle();
      expect(repo.reviewCalls, 1);
      expect(repo.handoffCalls, 1);
      expect(calls, ['ensurePermission', 'launch']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('account switch while permission is pending prevents handoff', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repo = _SwitchingRepository();
      final permission = Completer<bool>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('collect/momo_ussd');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'ensurePermission') return permission.future;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _prepare(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
      await tester.pump();
      repo.switchAccount();
      await tester.pump();
      permission.complete(true);
      await tester.pumpAndSettle();
      expect(repo.reviewCalls, 0);
      expect(repo.handoffCalls, 0);
      expect(calls, ['ensurePermission']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'denied permission keeps manual payment details without handoff',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final repo = _CountingRepository();
        final calls = <String>[];
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('collect/momo_ussd');
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return false;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await _prepare(tester, repo);
        await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
        await tester.pumpAndSettle();
        expect(repo.reviewCalls, 0);
        expect(repo.handoffCalls, 0);
        expect(calls, ['ensurePermission']);
        expect(find.text('Copy payment code'), findsOneWidget);
        expect(
          find.textContaining('Phone permission is required'),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('permission channel exception leaves manual option available', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repo = _CountingRepository();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('collect/momo_ussd');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        throw PlatformException(code: 'permission_unavailable');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _prepare(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
      await tester.pumpAndSettle();
      expect(repo.reviewCalls, 0);
      expect(repo.handoffCalls, 0);
      expect(calls, ['ensurePermission']);
      expect(find.text('Copy payment code'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('manual copy on Android does not request phone permission', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repo = _CountingRepository();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('collect/momo_ussd');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _prepare(tester, repo);
      final copy = find.text('Copy payment code');
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(repo.reviewCalls, 1);
      expect(repo.handoffCalls, 1);
      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('non-Android opening retains the existing channel flow', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final repo = _CountingRepository();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('collect/momo_ussd');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _prepare(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
      await tester.pumpAndSettle();
      expect(repo.reviewCalls, 1);
      expect(repo.handoffCalls, 1);
      expect(calls, ['launch']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('native launch failure after claim prevents repeat handoff', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repo = _CountingRepository();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('collect/momo_ussd');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'ensurePermission') return true;
        throw PlatformException(code: 'permission_revoked');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _prepare(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
      await tester.pumpAndSettle();
      expect(repo.reviewCalls, 1);
      expect(repo.handoffCalls, 1);
      expect(calls, ['ensurePermission', 'launch']);
      expect(
        find.textContaining('This does not indicate a failed payment.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Check payment'),
        80,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Check payment'), findsOneWidget);
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(repo.handoffCalls, 1);
      expect(calls, ['ensurePermission', 'launch']);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('disposing while permission is pending prevents handoff', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repo = _CountingRepository();
      final permission = Completer<bool>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('collect/momo_ussd');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'ensurePermission') return permission.future;
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _prepare(tester, repo);
      await tester.tap(find.widgetWithText(FilledButton, 'Open MoMo USSD'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      permission.complete(true);
      await tester.pumpAndSettle();
      expect(repo.reviewCalls, 0);
      expect(repo.handoffCalls, 0);
      expect(calls, ['ensurePermission']);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('account switch clears prepared receiver before launch', (
    tester,
  ) async {
    final repo = _SwitchingRepository();
    await _prepare(tester, repo);

    repo.switchAccount();
    await tester.pumpAndSettle();

    expect(find.text('Open MoMo USSD'), findsNothing);
    final continueAction = find.widgetWithText(
      FilledButton,
      'Continue to MoMo',
      skipOffstage: false,
    );
    await tester.ensureVisible(continueAction);
    await tester.pumpAndSettle();
    expect(continueAction.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(continueAction).onPressed, isNull);
  });
}
