import 'package:collect_app/admin/core/admin_transaction_lifecycle.dart';
import 'package:collect_app/admin/core/admin_models.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _lifecycle({String notification = 'uncertain'}) => {
  'contract_version': 1,
  'verification': 'pending',
  'allocation': 'allocated',
  'ledger': 'not_posted',
  'notification': notification,
  'evidence_limit': 'confirmation_record_is_not_external_settlement_proof',
};

Map<String, dynamic> _row({bool legacy = false}) => {
  'id': 'momo:99720000-0000-4000-8000-000000000001',
  'title': 'SYNTHETIC-REFERENCE',
  'subtitle': 'Rwanda MoMo',
  'status': 'allocated',
  'amount': 'RWF 2,500',
  'created_at': '2026-09-30T14:00:00Z',
  'country_code': 'RW',
  'rail': 'rw_momo',
  'group_name': 'Synthetic group',
  'reference': 'SYNTHETIC-REFERENCE',
  'sender_masked': 'M-Money',
  if (!legacy) 'lifecycle': _lifecycle(),
};

class _Repository extends AdminEvidenceRepository {
  _Repository({this.legacy = false});
  final bool legacy;
  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) async => AdminListResult(
    rows: [AdminTableRowData.fromJson(_row(legacy: legacy))],
    total: 1,
  );
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;
}

void main() {
  test('allocation cannot imply verified, posted or notified', () {
    final observation = AdminTransactionLifecycle.parse(_lifecycle())!;
    expect(observation.allocation, 'allocated');
    expect(observation.verification, 'pending');
    expect(observation.ledger, 'not_posted');
    expect(observation.notification, 'uncertain');
    expect(
      AdminTransactionLifecycle.label(observation.notification),
      'Unknown send outcome',
    );
  });
  test(
    'older server absence stays unavailable without aggregate inference',
    () {
      expect(AdminTransactionLifecycle.parse(null), isNull);
      final row = AdminTableRowData.fromJson(_row(legacy: true));
      expect(row.extra.containsKey('lifecycle'), isFalse);
      expect(AdminTransactionLifecycle.label(null), 'Unavailable');
    },
  );
  test('unknown versions, partial state and injected extras fail closed', () {
    for (final invalid in [
      {..._lifecycle(), 'contract_version': 2},
      {..._lifecycle(), 'contract_version': 1.0},
      {..._lifecycle()}..remove('ledger'),
      {..._lifecycle(), 'notification': 'delivered'},
      {..._lifecycle(), 'ledger': 'balanced_by_ai'},
      {..._lifecycle(), 'destination': '+250788000000'},
      {..._lifecycle(), 'evidence_limit': 'provider_verified'},
    ]) {
      expect(
        () => AdminTransactionLifecycle.parse(invalid),
        throwsFormatException,
      );
      expect(
        () => AdminTableRowData.fromJson({..._row(), 'lifecycle': invalid}),
        throwsFormatException,
      );
    }
    expect(
      () => AdminTableRowData.fromJson({..._row(), 'lifecycle': null}),
      throwsFormatException,
    );
  });
  test('notification permission boundary is distinct from no receipt', () {
    expect(
      AdminTransactionLifecycle.parse(
        _lifecycle(notification: 'access_required'),
      )!.notification,
      'access_required',
    );
    expect(
      AdminTransactionLifecycle.label('access_required'),
      'Access required',
    );
    expect(
      AdminTransactionLifecycle.label('not_created'),
      'No receipt evidence',
    );
    expect(
      AdminTransactionLifecycle.label('observed_sent'),
      'Operator observed sent',
    );
  });

  for (final width in [320.0, 1440.0, 2048.0]) {
    for (final legacy in [false, true]) {
      testWidgets(
        'transaction lifecycle ${legacy ? "unavailable" : "independent"} at ${width.toInt()}px',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final container = ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(null),
              adminAuthGuardProvider.overrideWithValue(
                const AdminAuthGuard(isAuthorized: true),
              ),
              adminAuthUserIdProvider.overrideWithValue(
                '00000000-0000-0000-0000-00000000e001',
              ),
              adminReconciliationSessionKeyProvider.overrideWithValue(
                '00000000-0000-0000-0000-00000000e001/synthetic-session',
              ),
              adminRepositoryProvider.overrideWithValue(
                _Repository(legacy: legacy),
              ),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: CollectTheme.light(),
                home: const Scaffold(
                  body: AdminCollectOperationsPage(
                    operation: CollectAdminOperation.transactions,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Verification'), findsWidgets);
          expect(find.text('Allocation'), findsWidgets);
          expect(find.text('Ledger'), findsWidgets);
          expect(find.text('Notification'), findsWidgets);
          expect(find.text('Receipt sender'), findsWidgets);
          expect(find.text('MoMo number'), findsNothing);
          if (legacy) {
            expect(find.text('Unavailable'), findsWidgets);
            expect(find.text('Allocated'), findsNothing);
            expect(find.text('Posted'), findsNothing);
          } else {
            expect(find.text('Awaiting verification'), findsWidgets);
            expect(find.text('Not posted'), findsWidgets);
            expect(find.text('Unknown send outcome'), findsWidgets);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
