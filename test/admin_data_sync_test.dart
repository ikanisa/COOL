import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ServerPagedRepository extends AdminEvidenceRepository {
  final requests = <({int? limit, int? offset, String? country})>[];

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;

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
    requests.add((limit: limit, offset: offset, country: countryCode));
    return AdminListResult(
      total: 125,
      rows: [
        for (
          var i = offset ?? 0;
          i < (offset ?? 0) + (limit ?? 25) && i < 125;
          i++
        )
          AdminTableRowData(
            id: 'row-$i',
            title: 'Group $i',
            subtitle: '',
            status: 'active',
            amount: '0',
            extra: const {'country_code': 'RW'},
          ),
      ],
    );
  }
}

class _MissingHealthRepository extends AdminEvidenceRepository {
  @override
  Future<List<AdminMetric>> overviewMetrics() async => const [
    AdminMetric(
      label: 'Open reconciliations',
      value: '3',
      status: 'needs_review',
    ),
  ];

  @override
  Future<AdminQueueSla?> queueSla(String queueKey) async => null;
}

void main() {
  Future<void> open(
    WidgetTester tester,
    AdminRepositoryBase repository,
    Widget child,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(repository),
          adminCountryScopeProvider.overrideWith(
            (ref) => AdminCountryScope.rwanda,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'country lists preserve server total and can reach past 100 rows',
    (tester) async {
      final repository = _ServerPagedRepository();
      await open(
        tester,
        repository,
        const AdminRpcListPage(
          title: 'Groups',
          rpcName: 'admin_list_collections',
          minimal: true,
        ),
      );
      expect(find.text('Showing 1-25 of 125'), findsOneWidget);
      for (var page = 1; page <= 4; page++) {
        await tester.ensureVisible(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Showing 101-125 of 125'), findsOneWidget);
      expect(repository.requests.last, (limit: 25, offset: 100, country: 'RW'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing queue health values do not invent approvals or an SLA', (
    tester,
  ) async {
    await open(
      tester,
      _MissingHealthRepository(),
      const AdminOverviewContent(),
    );
    expect(find.text('Not available'), findsNWidgets(2));
    expect(find.text('< 4h'), findsNothing);
    expect(find.text('Oldest visible item'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
