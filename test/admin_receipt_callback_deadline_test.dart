import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_callback_deadline_models.dart';
import 'package:collect_app/admin/core/admin_receipt_callback_deadline_runtime.dart';
import 'package:collect_app/admin/core/admin_receipt_callback_deadline_view.dart';
import 'package:collect_app/admin/core/admin_runtime.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'callback_deadline_mount_support.dart' as mount;

Map<String, dynamic> raw(String name) => mount.sqlFixture(name);
Map<String, dynamic> clone(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
CallbackDeadlineQuery query(
  Map<String, dynamic> r, {
  CallbackDeadlineCursor? cursor,
}) => CallbackDeadlineQuery(
  family: r['protocol_family'] as String,
  active: r['active_filter'] as bool?,
  limit: r['limit'] as int,
  cursor: cursor,
);
CallbackDeadlinePage page(String name, {CallbackDeadlineCursor? cursor}) {
  final r = raw(name);
  return CallbackDeadlinePage.parse(r, query(r, cursor: cursor));
}

void main() {
  test(
    'actual elapsed, clear and late contradiction histories preserve strict immutable observation shape',
    () {
      for (final name in [
        'aged-primary-list',
        'aged-successor-list',
        'clear-primary-list',
        'clear-successor-list',
        'late-primary-list',
        'late-successor-list',
      ]) {
        final p = page(name);
        expect(p.row['delivery_proven'], false);
        for (final item in p.items) {
          if (name.startsWith('late-')) {
            final r = raw('detail-${item.id}');
            final d = CallbackDeadlineDetail.parse(r, item.id, limit: 1);
            expect(d.cutoff, greaterThan(1));
            expect(d.row['items'], hasLength(1));
          }
        }
      }
      expect(page('aged-primary-list').items.every((r) => r.active), true);
      expect(page('clear-primary-list').items.any((r) => r.active), false);
    },
  );

  test(
    'strict positive lists are exact actual SQL responses, including same-time cursor pages',
    () {
      for (final name in [
        'empty-primary-list',
        'fresh-primary-list',
        'fresh-successor-list',
        'tie-first',
      ]) {
        expect(page(name).row['status'], 'available');
      }
      final first = page('tie-first'),
          second = page('tie-second', cursor: first.next);
      expect(first.items.single.id, isNot(second.items.single.id));
      expect(second.next, isNull);
    },
  );
  test(
    'absent detail and unknown worker evidence remain explicitly unavailable',
    () {
      final r = raw('missing-detail');
      final parsed = CallbackDeadlineDetail.parse(r, r['case_id'] as String);
      expect(parsed.head, isNull);
      expect(parsed.cutoff, isNull);
      expect(page('empty-primary-list').row['last_worker'], isNull);
    },
  );
  test(
    'closed DTO denies raw payloads, fabricated authority, wrong counts and malformed source IDs',
    () {
      final r = raw('fresh-primary-list');
      for (final change in [
        (Map<String, dynamic> v) => v['signing_payload'] = 'forbidden',
        (Map<String, dynamic> v) => v['delivery_proven'] = true,
        (Map<String, dynamic> v) => v['scanned_count'] = 26,
        (Map<String, dynamic> v) =>
            (v['rows'] as List).first['attempt_id'] = 'not-a-uuid',
        (Map<String, dynamic> v) => (v['rows'] as List).first['approval_id'] =
            '00000000-0000-4000-8000-000000000001',
        (Map<String, dynamic> v) =>
            (v['rows'] as List).first['source']['sent_covered'] = 11,
      ]) {
        final v = clone(r);
        change(v);
        expect(
          () => CallbackDeadlinePage.parse(v, query(r)),
          throwsFormatException,
        );
      }
    },
  );
  test('query identity, descending ties and duplicate rows are strict', () {
    final r = raw('fresh-primary-list'), v = clone(r);
    v['rows'] = (v['rows'] as List).reversed.toList();
    expect(
      () => CallbackDeadlinePage.parse(v, query(r)),
      throwsFormatException,
    );
    final bad = clone(r);
    bad['query_sha256'] = '0' * 64;
    expect(
      () => CallbackDeadlinePage.parse(bad, query(r)),
      throwsFormatException,
    );
    expect(
      () => CallbackDeadlineQuery(family: 'unknown'),
      throwsFormatException,
    );
    expect(() => CallbackDeadlineQuery(limit: 26), throwsFormatException);
  });
  test(
    'canonical single approval query retains exact actual SQL route and refuses malformed/duplicate references',
    () {
      final item = page('fresh-successor-list').items.first;
      expect(
        deadlineApprovalFromUri(Uri.parse(item.receiptPath)),
        item.approval,
      );
      expect(
        () => deadlineApprovalFromUri(
          Uri.parse('${item.receiptPath}&successor_approval=${item.approval}'),
        ),
        throwsFormatException,
      );
      expect(
        () => deadlineApprovalFromUri(
          Uri.parse('/admin/sms-receipts/${item.root}?successor_approval=bad'),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'SDK uses exact bounded readers and stale/session guards before and after the await',
    () async {
      final first = page('fresh-primary-list');
      var current = true;
      final calls = <String>[];
      final sdk = CallbackDeadlineSdk(
        rpc: (name, params) async {
          calls.add(name);
          return raw('fresh-primary-list');
        },
        isCurrent: () => current,
        now: () => first.checkedAt.add(const Duration(seconds: 1)),
      );
      expect((await sdk.list(CallbackDeadlineQuery())).items.length, 2);
      expect(calls, ['admin_list_receipt_callback_deadlines_v1']);
      current = false;
      await expectLater(
        sdk.list(CallbackDeadlineQuery()),
        throwsA(isA<AdminSessionChanged>()),
      );
      expect(calls, hasLength(1));
    },
  );
  test(
    'current server denial clears retained pagination; transient timeout remains recoverable',
    () async {
      final first = page('tie-first');
      Object? failure;
      final sdk = CallbackDeadlineSdk(
        rpc: (name, params) async {
          if (failure != null) throw failure;
          return raw('tie-first');
        },
        isCurrent: () => true,
        now: () => first.checkedAt.add(const Duration(seconds: 1)),
      );
      final controller = CallbackDeadlineController(sdk);
      addTearDown(controller.dispose);
      await controller.load(CallbackDeadlineQuery(limit: 1));
      failure = TimeoutException('synthetic transient');
      await controller.more();
      expect(controller.rows, hasLength(1));
      expect(controller.page, isNotNull);
      failure = const PostgrestException(
        message: 'synthetic authority denial',
        code: '42501',
      );
      await controller.more();
      expect(controller.rows, isEmpty);
      expect(controller.page, isNull);
      failure = null;
      await controller.load(CallbackDeadlineQuery(limit: 1));
      expect(controller.rows, hasLength(1));
    },
  );
  test(
    'departed asynchronous completion cannot repopulate a newer generation',
    () async {
      final p = page('fresh-primary-list'), s = page('fresh-successor-list');
      final pending = Completer<Object?>();
      var count = 0;
      final sdk = CallbackDeadlineSdk(
        rpc: (name, params) async {
          count++;
          return count == 1 ? pending.future : raw('fresh-successor-list');
        },
        isCurrent: () => true,
        now: () => s.checkedAt.add(const Duration(seconds: 1)),
      );
      final controller = CallbackDeadlineController(sdk);
      addTearDown(controller.dispose);
      final old = controller.load(CallbackDeadlineQuery());
      await controller.load(CallbackDeadlineQuery(family: 'receipt_successor'));
      pending.complete(raw('fresh-primary-list'));
      await old;
      expect(controller.rows.first.family, 'receipt_successor');
      expect(controller.rows.first.root, s.items.first.root);
      expect(p.items, hasLength(2));
    },
  );
  testWidgets(
    'one explicit approval outside first history page reaches actual repository/Auth v4 caller without eager fanout',
    (tester) async {
      final h = mount.DeadlineMountedHarness();
      await tester.runAsync(h.start);
      addTearDown(h.close);
      await tester.pumpWidget(h.app(selectedApproval: h.execution.approval));
      await mount.settle(tester);
      expect(h.calls(mount.summaryRpc), hasLength(1));
      expect(jsonDecode(h.calls(mount.summaryRpc).single.body), {
        'p_approval_id': h.execution.approval,
      });
      expect(
        h.calls(mount.summaryRpc).single.headers['authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      expect(find.text('Retry execution'), findsOneWidget);
      await tester.pumpWidget(
        h.app(read: false, selectedApproval: h.execution.approval),
      );
      await mount.settle(tester);
      expect(find.text('Retry execution'), findsNothing);
      expect(h.calls(mount.summaryRpc), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'callback card actual SQL rows show source states and permission-gated navigation',
    (tester) async {
      final p = page('fresh-primary-list');
      final api = CallbackDeadlineSdk(
        rpc: (name, params) async => raw('fresh-primary-list'),
        isCurrent: () => true,
        now: () => p.checkedAt.add(const Duration(seconds: 1)),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminCallbackDeadlineApiProvider.overrideWithValue(api),
            adminClockProvider.overrideWithValue(
              () => p.checkedAt.add(const Duration(seconds: 1)),
            ),
          ],
          child: MaterialApp(
            theme: CollectTheme.light(),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: AdminReceiptCallbackDeadlineCard(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Callback deadlines'), findsOneWidget);
      expect(find.text('Not active'), findsNWidgets(2));
      expect(find.text('Open original receipt'), findsNWidgets(2));
      expect(find.text('View action history'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
