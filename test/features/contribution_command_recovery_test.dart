import 'dart:async';

import 'package:collect_app/app/theme/app_theme.dart';
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
