import 'dart:async';

import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
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

final _testOverviewRepositoryProvider = StateProvider<AdminRepositoryBase>(
  (_) => throw StateError('A synthetic repository must be supplied.'),
);

void main() {
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
