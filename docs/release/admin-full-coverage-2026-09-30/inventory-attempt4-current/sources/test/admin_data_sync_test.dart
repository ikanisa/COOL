import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ServerPagedRepository extends AdminEvidenceRepository {
  final requests = <({int? limit, int? offset, String? country})>[];
  final searches = <String?>[];
  int total = 125;

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
    searches.add(search);
    return AdminListResult(
      total: total,
      rows: [
        for (
          var i = offset ?? 0;
          i < (offset ?? 0) + (limit ?? 25) && i < total;
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

  Future<void> nextPage(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Next page'),
      300,
      scrollable: find
          .ancestor(
            of: find.byTooltip('Next page'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
  }

  void invalidate(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminRpcListPage)),
    );
    container.read(adminRealtimeTickProvider.notifier).state += 1;
  }

  testWidgets('a vanished page is refetched at its real last offset', (
    tester,
  ) async {
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
    for (var page = 0; page < 4; page++) {
      await nextPage(tester);
    }
    repository.total = 53;
    final before = repository.requests.length;
    invalidate(tester);
    await tester.pumpAndSettle();
    expect(repository.requests.skip(before).map((r) => r.offset), [100, 50]);
    expect(find.text('Showing 51-53 of 53'), findsOneWidget);
    expect(find.text('No groups in Rwanda'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty results reset the actual page before new rows arrive', (
    tester,
  ) async {
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
    await nextPage(tester);
    repository.total = 0;
    invalidate(tester);
    await tester.pumpAndSettle();
    expect(find.text('No groups in Rwanda'), findsOneWidget);
    repository.total = 27;
    invalidate(tester);
    await tester.pumpAndSettle();
    expect(repository.requests.last.offset, 0);
    expect(find.text('Showing 1-25 of 27'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'typing a draft does not change paging or realtime query filters',
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
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Search',
      );
      await tester.enterText(field, 'Unsubmitted draft');
      await nextPage(tester);
      expect(repository.searches.last, '');
      expect(repository.requests.last.offset, 25);
      invalidate(tester);
      await tester.pumpAndSettle();
      expect(repository.searches.last, '');
      expect(repository.requests.last.offset, 25);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repository.searches.last, 'Unsubmitted draft');
      expect(repository.requests.last.offset, 0);
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
