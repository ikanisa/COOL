import 'dart:async';

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/security/hash_utils.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/contribution_command_repository_fixture.dart';
import '../fixtures/contribution_command_values.dart';

class _RecoveryRepository extends ContributionFixtureRepository {
  _RecoveryRepository({
    this.restored = false,
    this.readFails = false,
    this.lossDuringPrepare = false,
  });
  bool restored, readFails, lossDuringPrepare;
  int prepares = 0, checks = 0;
  final record = ContributionCommandCheckpoint.prepared(
    commandBody(),
    commandWitness(),
  ).dispatched();
  void changeGroup(String change) {
    final group = state.collections.firstWhere(
      (g) => g.id == contributionFixtureGroup,
    );
    final changed = switch (change) {
      'archived' => group.copyWith(moderationStatus: 'archived'),
      'membership removed' => group.copyWith(
        creatorUserId: 'other-owner',
        isCurrentUserMember: false,
      ),
      'route unavailable' => group.copyWith(primaryPaymentRail: 'unavailable'),
      _ => group,
    };
    state = state.copyWith(
      collections: change == 'group missing' ? [] : [changed],
    );
  }

  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) async {
    if (readFails) throw StateError('Synthetic protected key failure');
    return restored ? record : null;
  }

  @override
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  ) async {
    prepares++;
    if (lossDuringPrepare) {
      restored = true;
      throw StateError('Synthetic lost local prepare ACK');
    }
    restored = true;
    throw ContributionRecoveryRequired(record);
  }

  @override
  Future<ContributionCommandCheckpoint> checkContributionCommand(
    String requestId,
  ) async {
    expect(requestId, commandRequestId);
    checks++;
    return record;
  }
}

class _FoundRecoveryRepository extends _RecoveryRepository {
  _FoundRecoveryRepository() : super(restored: true);
  int statusReads = 0;
  @override
  Future<ContributionCommandCheckpoint> checkContributionCommand(
    String requestId,
  ) async {
    checks++;
    return record.received(contributionFixtureIntent);
  }

  @override
  Future<PaymentIntentModel> refreshPaymentIntent(String id) async {
    statusReads++;
    final result = PaymentIntentModel(
      id: contributionFixtureIntent,
      collectionId: contributionFixtureGroup,
      expectedAmountRwf: commandBody().amountRwf,
      receiverMomoNumber: '0788999999',
      receiverMomoLabel: 'Different receiver',
      senderPhoneHash: HashUtils.phoneHash('0788123456'),
      status: 'pending',
      createdAt: DateTime.utc(2026),
      expiresAt: DateTime.utc(2030),
    );
    state = state.copyWith(paymentIntents: [result]);
    return result;
  }
}

const _otherGroup = '30000000-0000-0000-0000-000000000002';

class _RouteRecoveryRepository extends ContributionFixtureRepository {
  final reads = <String>[];
  final otherRecord = ContributionCommandCheckpoint.prepared(
    commandBody(group: _otherGroup),
    commandWitness(),
  ).dispatched();

  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) async {
    reads.add(collectionId);
    return collectionId == _otherGroup ? otherRecord : null;
  }
}

class _DelayedRouteRecoveryRepository extends _RouteRecoveryRepository {
  final firstRead = Completer<ContributionCommandCheckpoint?>();

  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) {
    if (collectionId == contributionFixtureGroup) {
      reads.add(collectionId);
      return firstRead.future;
    }
    return super.restoreContributionCommand(collectionId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var launches = 0;
  setUp(() {
    launches = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('collect/momo_ussd'), (
          _,
        ) async {
          launches++;
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('collect/momo_ussd'),
          null,
        ),
  );
  Future<void> pump(
    WidgetTester tester,
    _RecoveryRepository repo, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const ContributionFlowScreen(
              collectionId: contributionFixtureGroup,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, text),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, text));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'route reuse reads recovery for the new group before a new action',
    (tester) async {
      final repo = _RouteRecoveryRepository();
      Widget screen(String group) => ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ContributionFlowScreen(collectionId: group),
        ),
      );

      await tester.pumpWidget(screen(contributionFixtureGroup));
      await tester.pumpAndSettle();
      expect(repo.reads, [contributionFixtureGroup]);
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.pumpAndSettle();

      await tester.pumpWidget(screen(_otherGroup));
      expect(find.text('Continue to MoMo'), findsNothing);
      await tester.pumpAndSettle();
      expect(repo.reads, [contributionFixtureGroup, _otherGroup]);
      expect(find.text('Check your original request'), findsOneWidget);
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late previous-group recovery cannot replace the current result',
    (tester) async {
      final repo = _DelayedRouteRecoveryRepository();
      Widget screen(String group) => ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ContributionFlowScreen(collectionId: group),
        ),
      );

      await tester.pumpWidget(screen(contributionFixtureGroup));
      await tester.pump();
      expect(repo.reads, [contributionFixtureGroup]);
      await tester.pumpWidget(screen(_otherGroup));
      await tester.pumpAndSettle();
      expect(find.text('Check your original request'), findsOneWidget);
      repo.firstRead.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Check your original request'), findsOneWidget);
      expect(find.text('Continue to MoMo'), findsNothing);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restart restores original unknown request with Check and no send action',
    (tester) async {
      final repo = _RecoveryRepository(restored: true);
      await pump(tester, repo, scale: 2);
      expect(find.text('Check your original request'), findsOneWidget);
      expect(find.textContaining(commandRequestId), findsOneWidget);
      expect(find.text('Continue to MoMo'), findsNothing);
      expect(find.text('Open MoMo USSD'), findsNothing);
      await tap(tester, 'Check request');
      expect(repo.checks, 1);
      expect(repo.prepares, 0);
      expect(launches, 0);
      expect(find.textContaining('outcome is still unknown'), findsOneWidget);
      expect(find.text('Copy request details'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a found noncommitted request stays in neutral recovery', (
    tester,
  ) async {
    final repo = _FoundRecoveryRepository();
    await pump(tester, repo);
    await tap(tester, 'Check request');
    expect(repo.checks, 1);
    expect(repo.statusReads, 1);
    expect(find.textContaining(commandRequestId), findsOneWidget);
    expect(find.textContaining('outcome is not confirmed'), findsOneWidget);
    expect(find.text('Different receiver'), findsNothing);
    expect(find.text('0788999999'), findsNothing);
    expect(find.text('Copy payment code'), findsNothing);
    expect(find.text('Open MoMo USSD'), findsNothing);
    expect(find.text('Payment help'), findsOneWidget);
    expect(repo.prepares, 0);
    expect(launches, 0);
    await tap(tester, 'Check request');
    expect(repo.checks, 2);
    expect(repo.prepares, 0);
    expect(launches, 0);
  });
  testWidgets(
    'scope change retains the request and hides prior payment instructions',
    (tester) async {
      final repo = _ScopeRecoveryRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ContributionFlowScreen(
              collectionId: contributionFixtureGroup,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.pumpAndSettle();
      await tap(tester, 'Continue to MoMo');
      expect(find.text('Open MoMo USSD'), findsOneWidget);
      repo.denyScope();
      await tester.pumpAndSettle();
      expect(find.textContaining(commandRequestId), findsOneWidget);
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(find.text('Copy payment code'), findsNothing);
      repo.publishFreshSnapshot();
      await tester.pumpAndSettle();
      expect(find.textContaining(commandRequestId), findsOneWidget);
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(find.text('Copy payment code'), findsNothing);
      expect(repo.firstCreations, 1);
      expect(launches, 0);
    },
  );
  testWidgets('ordinary group-route refresh hides an active old receiver', (
    tester,
  ) async {
    final repo = _RouteRefreshRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ContributionFlowScreen(
            collectionId: contributionFixtureGroup,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.pumpAndSettle();
    await tap(tester, 'Continue to MoMo');
    expect(find.text('Open MoMo USSD'), findsOneWidget);
    repo.changeReceiver();
    await tester.pumpAndSettle();
    expect(find.textContaining(commandRequestId), findsOneWidget);
    expect(find.text('Open MoMo USSD'), findsNothing);
    expect(find.text('Copy payment code'), findsNothing);
    expect(repo.firstCreations, 1);
    expect(launches, 0);
  });
  testWidgets('resume with a historical receiver uses neutral recovery', (
    tester,
  ) async {
    final repo = _RouteRefreshRepository()
      ..seedHistoricalIntent()
      ..changeReceiver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ContributionFlowScreen(
            collectionId: contributionFixtureGroup,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resume payment request'));
    await tester.pumpAndSettle();
    expect(find.text('Check your original request'), findsOneWidget);
    expect(find.text('Open MoMo USSD'), findsNothing);
    expect(find.text('Copy payment code'), findsNothing);
    expect(launches, 0);
  });
  for (final nested in [false, true]) {
    testWidgets(
      'scope change while ${nested ? 'nested custody read' : 'preparation'} is pending recovers once',
      (tester) async {
        final repo = _HeldScopeRecoveryRepository(holdNestedRead: nested);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ContributionFlowScreen(
                collectionId: contributionFixtureGroup,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '5000');
        await tester.pumpAndSettle();
        final button = find.widgetWithText(FilledButton, 'Continue to MoMo');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(repo.prepares, 1);
        if (nested) {
          repo.preparation.completeError(
            StateError('Synthetic uncertain prepare'),
          );
          await tester.pump();
          expect(repo.reads, 2);
        }
        repo.denyScope();
        await tester.pump();
        if (nested) {
          repo.nestedRead.complete(repo.record);
        } else {
          repo.preparation.completeError(
            ContributionRecoveryRequired(repo.record),
          );
        }
        await tester.pumpAndSettle();
        expect(repo.reads, nested ? 3 : 2);
        expect(find.textContaining(commandRequestId), findsOneWidget);
        expect(find.text('Check request'), findsOneWidget);
        expect(find.text('Checking request'), findsNothing);
        expect(find.text('Open MoMo USSD'), findsNothing);
        expect(repo.prepares, 1);
        expect(launches, 0);
      },
    );
  }
  for (final changed in ['stale cache', 'financial uncertainty', 'sender']) {
    testWidgets(
      '$changed while a status read is pending restores neutral custody',
      (tester) async {
        final repo = _HeldIntentRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const ContributionFlowScreen(
                collectionId: contributionFixtureGroup,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '5000');
        await tester.pumpAndSettle();
        await tap(tester, 'Continue to MoMo');
        final check = find.text('Check payment');
        await tester.ensureVisible(check);
        await tester.tap(check);
        await tester.pump();
        repo.invalidateObservation(changed);
        await tester.pump();
        repo.status.complete(repo.preparedIntent!);
        await tester.pumpAndSettle();
        expect(find.textContaining(commandRequestId), findsOneWidget);
        expect(find.text('Check request'), findsOneWidget);
        expect(find.text('Checking request'), findsNothing);
        expect(find.text('Open MoMo USSD'), findsNothing);
        expect(find.text('Copy payment code'), findsNothing);
        expect(repo.firstCreations, 1);
        expect(launches, 0);
      },
    );
  }
  for (final localAck in [false, true]) {
    testWidgets(
      'uncertain ${localAck ? 'local ACK' : 'creation reply'} restores original request instead of Continue',
      (tester) async {
        final repo = _RecoveryRepository(lossDuringPrepare: localAck);
        await pump(tester, repo);
        await tester.enterText(find.byType(TextField).first, '5000');
        await tester.pumpAndSettle();
        await tap(tester, 'Continue to MoMo');
        expect(repo.prepares, 1);
        expect(find.text('Check your original request'), findsOneWidget);
        expect(find.text('Continue to MoMo'), findsNothing);
        await tap(tester, 'Check request');
        expect(repo.prepares, 1);
        expect(repo.checks, 1);
        expect(launches, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'editing amount returns to Check original without another creation',
    (tester) async {
      final repo = _EditableRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [collectRepositoryProvider.overrideWith((_) => repo)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const ContributionFlowScreen(
              collectionId: contributionFixtureGroup,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5000');
      await tester.pumpAndSettle();
      await tap(tester, 'Continue to MoMo');
      final editAmount = find.widgetWithText(
        TextButton,
        'Edit amount',
        skipOffstage: false,
      );
      await tester.ensureVisible(editAmount);
      await tester.pumpAndSettle();
      expect(editAmount.hitTestable(), findsOneWidget);
      await tester.tap(editAmount);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '8000');
      await tester.pumpAndSettle();
      await tap(tester, 'Continue to MoMo');
      expect(repo.firstCreations, 1);
      expect(find.text('Check your original request'), findsOneWidget);
      expect(find.text('Open MoMo USSD'), findsNothing);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final changed in [
    'archived',
    'membership removed',
    'route unavailable',
    'group missing',
  ]) {
    testWidgets('$changed retains Check original with no creation or launch', (
      tester,
    ) async {
      final repo = _RecoveryRepository(restored: true);
      repo.changeGroup(changed);
      await pump(tester, repo);
      expect(find.text('Check your original request'), findsOneWidget);
      expect(find.text('Continue to MoMo'), findsNothing);
      expect(find.text('Open MoMo USSD'), findsNothing);
      await tap(tester, 'Check request');
      expect(repo.checks, 1);
      expect(repo.prepares, 0);
      expect(launches, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'unreadable protected recovery blocks preparation until a real reread',
    (tester) async {
      final repo = _RecoveryRepository(readFails: true);
      await pump(tester, repo);
      expect(find.text('Saved requests unavailable'), findsOneWidget);
      expect(find.text('Continue to MoMo'), findsNothing);
      await tap(tester, 'Check request');
      expect(repo.prepares, 0);
      expect(launches, 0);
      repo.readFails = false;
      await tap(tester, 'Check request');
      expect(find.text('Continue to MoMo'), findsOneWidget);
      expect(repo.prepares, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

class _EditableRepository extends ContributionFixtureRepository {
  int firstCreations = 0;
  bool prepared = false;
  final record = ContributionCommandCheckpoint.prepared(
    commandBody(),
    commandWitness(),
  ).dispatched();
  @override
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  ) async {
    if (prepared) throw ContributionRecoveryRequired(record);
    firstCreations++;
    prepared = true;
    return super.prepareContributionIntent(draft);
  }
}

class _ScopeRecoveryRepository extends _EditableRepository {
  int _scopeGeneration = 0;
  CollectState? _previous;
  @override
  int get memberScopeGeneration => _scopeGeneration;
  void denyScope() {
    _previous = state;
    _scopeGeneration++;
    state = state.copyWith(memberScopeUncertain: true);
  }

  void publishFreshSnapshot() => state = _previous!;
  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) async => prepared ? record : null;
}

class _RouteRefreshRepository extends _EditableRepository {
  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) async => prepared ? record : null;
  void changeReceiver() {
    state = state.copyWith(
      collections: [
        for (final group in state.collections)
          if (group.id == contributionFixtureGroup)
            group.copyWith(receiverMomoNumber: '0788999999')
          else
            group,
      ],
    );
  }

  void seedHistoricalIntent() {
    state = state.copyWith(
      paymentIntents: [
        PaymentIntentModel(
          id: contributionFixtureIntent,
          collectionId: contributionFixtureGroup,
          expectedAmountRwf: 5000,
          receiverMomoNumber: '0788123456',
          receiverMomoLabel: 'Synthetic recipient',
          momoNetwork: 'mtn_momo',
          senderPhoneHash: HashUtils.phoneHash('0788123456'),
          status: 'pending',
          createdAt: DateTime.utc(2026),
          expiresAt: DateTime.utc(2030),
        ),
      ],
    );
  }
}

class _HeldScopeRecoveryRepository extends ContributionFixtureRepository {
  _HeldScopeRecoveryRepository({required this.holdNestedRead});
  final bool holdNestedRead;
  final preparation = Completer<PaymentIntentModel>();
  final nestedRead = Completer<ContributionCommandCheckpoint?>();
  final record = ContributionCommandCheckpoint.prepared(
    commandBody(),
    commandWitness(),
  ).dispatched();
  int _scopeGeneration = 0, prepares = 0, reads = 0;
  @override
  int get memberScopeGeneration => _scopeGeneration;
  void denyScope() {
    _scopeGeneration++;
    state = state.copyWith(memberScopeUncertain: true);
  }

  @override
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  ) {
    prepares++;
    return preparation.future;
  }

  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) {
    reads++;
    if (holdNestedRead && reads == 2) return nestedRead.future;
    return Future.value(prepares > 0 ? record : null);
  }
}

class _HeldIntentRepository extends _RouteRefreshRepository {
  final status = Completer<PaymentIntentModel>();
  PaymentIntentModel? preparedIntent;
  @override
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  ) async {
    final intent = await super.prepareContributionIntent(draft);
    preparedIntent = intent;
    return intent;
  }

  @override
  Future<PaymentIntentModel> refreshPaymentIntent(String id) => status.future;
  void invalidateObservation(String change) {
    if (change == 'stale cache') {
      state = state.copyWith(usingStaleCache: true);
    } else if (change == 'financial uncertainty') {
      state = state.copyWith(financialObservationUncertain: true);
    } else {
      state = state.copyWith(
        currentProfile: state.currentProfile!.copyWith(
          momoNumber: '0788999999',
        ),
      );
    }
  }
}
