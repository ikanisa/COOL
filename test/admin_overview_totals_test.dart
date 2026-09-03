import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PagedOverviewRepository extends AdminEvidenceRepository {
  final calls = <String>[];

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
        'admin_list_collect_reconciliations' => 125,
        'admin_list_collect_transactions' => 237,
        'admin_list_collect_ledgers' => 1024,
        'admin_list_collect_payees' => 314,
        _ => 0,
      },
    );
  }
}

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
      expect(find.text('1024'), findsOneWidget);
      expect(find.text('314'), findsOneWidget);
      expect(
        repository.calls,
        contains('admin_list_collect_transactions:unallocated:1:RW'),
      );
      expect(
        repository.calls,
        contains('admin_list_collect_ledgers:balanced:1:RW'),
      );
      expect(
        repository.calls,
        contains('admin_list_collect_payees:active:1:RW'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
