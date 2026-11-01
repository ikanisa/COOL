import 'dart:async';

import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PagedOverviewRepository extends AdminEvidenceRepository {
  final calls = <String>[];

  @override
  Future<List<AdminMetric>> overviewMetrics() async => const [
    AdminMetric(label: 'Open reconciliations', value: '125', status: 'active'),
    AdminMetric(
      label: 'Unallocated transactions',
      value: '237',
      status: 'active',
    ),
    AdminMetric(label: 'Ledger entries', value: '1024', status: 'active'),
    AdminMetric(label: 'Active payees', value: '314', status: 'active'),
  ];

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async {
    calls.add('$rpcName:$status:$limit:$countryCode');
    final sample = await super.list(
      rpcName,
      search: search,
      status: status,
      limit: limit,
      offset: offset,
      sortBy: sortBy,
      countryCode: countryCode,
    );
    return AdminListResult(
      rows: sample.rows,
      total: switch (rpcName) {
        'admin_list_collect_reconciliations' => 9125,
        'admin_list_collect_transactions' => 9237,
        'admin_list_collect_ledgers' => 9024,
        'admin_list_collect_payees' => 9314,
        _ => 0,
      },
    );
  }
}

class _DelayedOverviewRepository extends _PagedOverviewRepository {
  final release = Completer<void>();
  @override
  Future<List<AdminMetric>> overviewMetrics() async {
    await release.future;
    return super.overviewMetrics();
  }
}

class _UnavailableSlaRepository extends _PagedOverviewRepository {
  bool fail = true;
  int reads = 0;
  final recovery = Completer<void>();

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async {
    reads++;
    if (fail) {
      throw const CollectApiException(
        code: 'queue_sla_unavailable',
        httpStatusCode: 503,
      );
    }
    await recovery.future;
    return const AdminQueueSla(
      target: 'at least 4 business hours',
      owner: 'Collect operations',
      escalation: 'Contact the operations owner',
    );
  }
}

class _MissingSlaRepository extends _PagedOverviewRepository {
  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async => null;
}

final _testOverviewRepositoryProvider = StateProvider<AdminRepositoryBase>(
  (_) => throw StateError('A synthetic repository must be supplied.'),
);

void main() {
  testWidgets('an unavailable SLA is visible and can be retried', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _UnavailableSlaRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          adminRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AdminOverviewContent()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final sla = find.byKey(const Key('admin-overview-sla-state'));
    expect(
      find.descendant(of: sla, matching: find.text('Could not load')),
      findsOneWidget,
    );
    expect(find.text('Needs attention'), findsWidgets);
    final retry = find.widgetWithText(TextButton, 'Retry SLA');
    expect(retry, findsOneWidget);

    repository.fail = false;
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pump();
    final retrying = find.widgetWithText(TextButton, 'Retrying SLA');
    expect(retrying, findsOneWidget);
    expect(tester.widget<TextButton>(retrying).onPressed, isNull);
    expect(
      find.descendant(of: sla, matching: find.text('Loading')),
      findsOneWidget,
    );
    repository.recovery.complete();
    await tester.pumpAndSettle();
    expect(repository.reads, greaterThanOrEqualTo(2));
    expect(
      find.descendant(
        of: sla,
        matching: find.text('at least 4 business hours'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Retry SLA'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an absent SLA is neutral and does not offer a retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectBackendClientProvider.overrideWithValue(null),
          adminRepositoryProvider.overrideWithValue(_MissingSlaRepository()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AdminOverviewContent()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final value = find.descendant(
      of: find.byKey(const Key('admin-overview-sla-state')),
      matching: find.text('Not available'),
    );
    expect(value, findsOneWidget);
    expect(
      tester.widget<Text>(value).style?.color,
      tester.element(value).collectColors.textSecondary,
    );
    expect(find.widgetWithText(TextButton, 'Retry SLA'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'country overview uses filtered server totals beyond the first page',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _PagedOverviewRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(null),
            adminRepositoryProvider.overrideWithValue(repository),
            adminCountryScopeProvider.overrideWith(
              (ref) => AdminCountryScope.rwanda,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: AdminOverviewContent()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('125'), findsWidgets);
      expect(find.text('237'), findsOneWidget);
      expect(find.text('1,024'), findsOneWidget);
      expect(find.text('314'), findsOneWidget);
      expect(
        repository.calls,
        contains('admin_list_collect_reconciliations:null:3:RW'),
      );
      expect(
        repository.calls,
        contains('admin_list_collect_ledgers:null:4:RW'),
      );
      for (final sample in ['9,125', '9,237', '9,024', '9,314']) {
        expect(find.text(sample), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('superseded overview cannot mark a new workspace fresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final old = _DelayedOverviewRepository();
    var clock = DateTime.utc(2026, 9, 30, 10);
    final container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        _testOverviewRepositoryProvider.overrideWith((_) => old),
        adminRepositoryProvider.overrideWith(
          (ref) => ref.watch(_testOverviewRepositoryProvider),
        ),
        adminClockProvider.overrideWithValue(() => clock),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AdminOverviewContent()),
        ),
      ),
    );
    await tester.pump();
    expect(container.read(adminLastSuccessfulRefreshProvider), isNull);
    container.read(_testOverviewRepositoryProvider.notifier).state =
        _PagedOverviewRepository();
    await tester.pumpAndSettle();
    final acknowledged = container.read(adminLastSuccessfulRefreshProvider);
    expect(acknowledged, clock);
    clock = clock.add(const Duration(minutes: 5));
    old.release.complete();
    await tester.pumpAndSettle();
    expect(container.read(adminLastSuccessfulRefreshProvider), acknowledged);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
