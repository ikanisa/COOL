import 'dart:convert';

import 'package:collect_app/admin/core/admin_error_boundary.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/shared/components/admin_loading_state.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as sdk;
import 'support/admin_read_fixture.dart';

const _kigali = '1 Mar 2024 · 01:30 · Africa/Kigali';
const _timestamp = '2024-02-29T23:30:00Z';

Future<void> _page(
  WidgetTester tester, {
  required Widget page,
  required Map<String, dynamic> payload,
  double width = 1440,
  required void Function(ProviderContainer) verify,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  late final SupabaseClient client;
  final reads = <http.Request>[];
  await tester.runAsync(() async {
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final endpoint = request.url.path.split('/').last;
        Map<String, dynamic> response;
        if (endpoint == 'verify') {
          final values = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          response = sdk.authReceipt(values[0], values[1]);
        } else if (endpoint == 'admin_runtime_config') {
          response = adminRuntimeFixture();
        } else if (endpoint == 'admin_get_queue_sla') {
          response = {
            'queue_key': jsonDecode(request.body)['p_queue_key'],
            'target': 'Synthetic review',
            'owner': 'Synthetic operator',
            'escalation': 'Synthetic owner',
            'updated_at': adminReadDate,
          };
        } else {
          reads.add(request);
          response = payload;
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await sdk.session(client, 'value-integrity-session');
  });
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      adminIdentityProvider.overrideWith(
        (_) async => const AdminIdentity(
          userId: sdk.actor,
          displayName: 'Synthetic operator',
          roles: ['admin'],
          permissions: [
            'collections.read',
            'users.read',
            'transactions.read',
            'notifications.read',
            'admin_users.read',
          ],
        ),
      ),
    ],
  );
  await container.read(adminIdentityProvider.future);
  var disposed = false;
  addTearDown(() async {
    if (!disposed) container.dispose();
    await tester.runAsync(client.dispose);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: page),
      ),
    ),
  );
  for (var index = 0; index < 50; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (reads.isNotEmpty &&
        find.byType(AdminLoadingState).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
  expect(reads, isNotEmpty);
  expect(
    reads.every(
      (request) =>
          request.headers['Authorization'] ==
          'Bearer ${client.auth.currentSession!.accessToken}',
    ),
    isTrue,
  );
  verify(container);
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  disposed = true;
}

Map<String, dynamic> _listRow(Map<String, dynamic> extra) => {
  'id': sdk.target,
  'title': 'Synthetic value record',
  'subtitle': '',
  'status': 'active',
  'amount': '',
  'country_code': 'RW',
  'created_at': _timestamp,
  ...extra,
};

void main() {
  for (final width in [390.0, 1440.0]) {
    for (final item in [
      (
        rpc: 'admin_list_collections',
        field: 'active_members',
        extra: <String, dynamic>{'active_members': 0, 'amount': '42 members'},
        expected: '0',
      ),
      (
        rpc: 'admin_list_collections',
        field: 'active_members',
        extra: <String, dynamic>{},
        expected: '—',
      ),
      (
        rpc: 'admin_list_collections',
        field: 'active_members',
        extra: <String, dynamic>{
          'active_members': null,
          'amount': '42 members',
        },
        expected: '—',
      ),
      (
        rpc: 'admin_list_collections',
        field: 'active_members',
        extra: <String, dynamic>{'amount': '0 members'},
        expected: '0',
      ),
      (
        rpc: 'admin_list_members',
        field: 'active_groups',
        extra: <String, dynamic>{'active_groups': 0},
        expected: '0',
      ),
      (
        rpc: 'admin_list_members',
        field: 'active_groups',
        extra: <String, dynamic>{},
        expected: '—',
      ),
    ]) {
      testWidgets(
        'production ${item.rpc} ${item.field} ${item.extra} at $width',
        (tester) async {
          await _page(
            tester,
            width: width,
            page: AdminRpcListPage(
              title: 'Synthetic values',
              rpcName: item.rpc,
            ),
            payload: {
              'rows': [_listRow(item.extra)],
              'total': 1,
            },
            verify: (_) {
              final records = find.byWidgetPredicate(
                (widget) =>
                    widget.runtimeType.toString() == '_AdminOperationsCard' ||
                    widget is DataTable,
              );
              expect(
                records,
                findsOneWidget,
                reason: find
                    .byType(Text)
                    .evaluate()
                    .map((element) => (element.widget as Text).data)
                    .join(' | '),
              );
              expect(
                find.descendant(
                  of: records,
                  matching: find.text(item.expected),
                ),
                findsWidgets,
              );
              expect(
                find.descendant(of: records, matching: find.text('42')),
                findsNothing,
              );
            },
          );
        },
      );
    }
    for (final amount in [
      'RWF 9007199254740993',
      '9007199254740993',
      'RWF -9007199254740993',
    ]) {
      testWidgets(
        'production transaction preserves exact amount $amount at $width',
        (tester) async {
          final sign = amount.contains('-') ? '-' : '';
          await _page(
            tester,
            width: width,
            page: const AdminRpcListPage(
              title: 'Transactions',
              rpcName: 'admin_list_collect_transactions',
            ),
            payload: {
              'rows': [
                _listRow({'amount': amount, 'rail': 'rw_momo'}),
              ],
              'total': 1,
            },
            verify: (_) {
              expect(
                find.text('RWF ${sign}9,007,199,254,740,993'),
                findsOneWidget,
              );
              if (width < 1180) {
                expect(find.text(_kigali), findsOneWidget);
              } else {
                expect(find.text('1 Mar 2024'), findsOneWidget);
                expect(find.text('01:30 · Africa/Kigali'), findsOneWidget);
              }
            },
          );
        },
      );
    }
  }
  for (final rpc in [
    'admin_get_collection',
    'admin_get_user',
    'admin_get_member_record',
    'admin_get_notification',
    'admin_get_hybrid_sms_receipt',
    'admin_get_admin_user',
  ]) {
    for (final timestamp in [_timestamp, '2024-03-01T01:30:00+02:00']) {
      testWidgets('production $rpc displays Kigali instant $timestamp', (
        tester,
      ) async {
        await _page(
          tester,
          page: AdminDetailPage(
            title: 'Synthetic detail',
            rpcName: rpc,
            id: sdk.target,
          ),
          payload: {
            ...adminDetailFixture(rpc, sdk.target),
            'created_at': timestamp,
          },
          verify: (_) => expect(find.text(_kigali), findsWidgets),
        );
      });
    }
  }
  for (final extra in [
    {'created_at': '2026-02-29T12:00:00Z'},
    {'created_at': '2026-09-30T12:00:00'},
    {'updated_at': '2026-04-31T12:00:00Z'},
    {'active_members': 1.5},
    {'active_members': '9007199254740992'},
  ]) {
    testWidgets(
      'actual list decode fails closed without publishing malformed $extra',
      (tester) async {
        await _page(
          tester,
          page: const AdminRpcListPage(
            title: 'Groups',
            rpcName: 'admin_list_collections',
          ),
          payload: {
            'rows': [_listRow(extra)],
            'total': 1,
          },
          verify: (container) {
            expect(find.byType(AdminSafeErrorPanel), findsOneWidget);
            expect(find.text('Synthetic value record'), findsNothing);
            expect(container.read(adminLastSuccessfulRefreshProvider), isNull);
          },
        );
      },
    );
  }
}
