import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_models.dart';
import 'package:collect_app/admin/core/admin_receipt_operational_history_sdk.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'admin_receipt_operational_history_test.dart' as history;

Map<String, dynamic> actual(String name) => Map<String, dynamic>.from(
  jsonDecode(
        File(
          'test/fixtures/admin_receipt_operational_recovery_actual/$name.json',
        ).readAsStringSync(),
      )
      as Map,
);
Map<String, dynamic> clone(Map<String, dynamic> raw) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(raw)) as Map);
AdminReceiptHistoryQuery query(Map<String, dynamic> raw) =>
    AdminReceiptHistoryQuery(
      runId: raw['run_id'] as String,
      section: AdminReceiptHistorySection.reservations,
      limit: raw['limit'] as int,
    );
void main() {
  for (final name in ['mapped-reservations', 'legacy-reservations']) {
    test('actual800 $name remains a closed read-only SDK page', () async {
      final raw = actual(name), calls = <String>[];
      final api = AdminReceiptOperationalHistoryApi(
        rpc: (name, parameters) async {
          calls.add(name);
          expect(parameters['p_run_id'], raw['run_id']);
          expect(parameters['p_section'], 'reservations');
          return raw;
        },
      );
      final page = await api.page(query(raw));
      final repeated = await api.page(query(raw));
      expect(page.rows.single.data, repeated.rows.single.data);
      expect(calls, everyElement('admin_list_receipt_operation_evidence_v1'));
      final row = page.rows.single.data;
      expect(row['actions'], 1);
      expect(row['sms_segments'], 0);
      expect(
        row['snapshot_id'] == row['evidence_id'],
        name == 'legacy-reservations',
      );
    });
  }
  for (final fault in [
    'run',
    'snapshot',
    'namespace',
    'snapshot_uuid',
    'evidence_uuid',
    'charge',
    'actions_bound',
    'sms_bound',
  ]) {
    test('new mapped reservation rejects $fault without weakening bounds', () {
      final raw = clone(actual('mapped-reservations'));
      final row = (raw['rows'] as List).single as Map;
      switch (fault) {
        case 'run':
          raw['run_id'] = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
        case 'snapshot':
          row['snapshot_id'] = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
        case 'namespace':
          row['evidence_id'] = const Uuid().v5(
            'c1c49625-b8d9-4278-998e-6758a0b945d5',
            '${raw['run_id']}:${row['snapshot_id']}',
          );
        case 'snapshot_uuid':
          row['snapshot_id'] = 'not-a-canonical-uuid';
        case 'evidence_uuid':
          row['evidence_id'] = 'not-a-canonical-uuid';
        case 'charge':
          row['actions'] = 0;
          row['sms_segments'] = 1;
        case 'actions_bound':
          row['actions'] = 2;
        case 'sms_bound':
          row['sms_segments'] = 11;
      }
      expect(
        () => AdminReceiptHistoryPage.parse(raw, query: query(raw)),
        throwsFormatException,
      );
    });
  }
  test('legacy equality and generic original bounds stay unchanged', () {
    final raw = clone(actual('legacy-reservations'));
    final row = (raw['rows'] as List).single as Map;
    row['actions'] = 0;
    row['sms_segments'] = 1;
    expect(
      AdminReceiptHistoryPage.parse(raw, query: query(raw)).rows.single.data,
      row,
    );
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'actual mapped reservation renders through provider at $width',
      (tester) async {
        final raw = actual('mapped-reservations');
        final repo = history.Repository()..evidenceOverride = raw;
        tester.view.physicalSize = Size(width, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repo),
            adminIdentityProvider.overrideWith((_) async => history.owner),
            adminAuthSessionScopeProvider.overrideWith(
              (_) => history.Sessions(),
            ),
            adminClockProvider.overrideWithValue(
              () => historyInstant(raw['checked_at']),
            ),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: CollectTheme.light(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AdminReceiptHistoryPager(
                    runId: raw['run_id'] as String,
                    section: AdminReceiptHistorySection.reservations,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = (raw['rows'] as List).single as Map;
        expect(find.text('Reservation ${row['evidence_id']}'), findsOneWidget);
        expect(
          find.text('Original backlog snapshot ${row['snapshot_id']}'),
          findsOneWidget,
        );
        expect(repo.calls, ['admin_list_receipt_operation_evidence_v1']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
