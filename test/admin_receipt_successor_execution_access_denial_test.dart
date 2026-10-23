import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_view.dart';
import 'support/execution_fixture.dart';
import 'support/execution_api_fixture.dart';

class ReadServer {
  final fixture = ExecutionApiFixture();
  Object? denial;
  bool unavailable = false, denyAll = false;
  bool current = true;
  Completer<Object?>? pending;
  int requests = 0;
  DateTime now = snapshot(knownSentRaw).checkedAt;
  late final sdk = AdminReceiptSuccessorExecutionSdk(
    rpc: read,
    isCurrent: () => current,
    now: () => now,
  );
  late final controller = AdminReceiptSuccessorExecutionController(
    api: sdk,
    approvalId: fixture.currentSnapshot.approvalId,
    primaryReceiptId: fixture.currentSnapshot.primaryReceiptId!,
    isCurrent: () => current,
  );
  Future<Object?> read(String name, Map<String, dynamic> args) async {
    requests++;
    if (denyAll && denial != null) throw denial!;
    if (args['p_after_revision'] != null) {
      if (pending != null) return pending!.future;
      if (denial != null) throw denial!;
      if (unavailable) {
        final row = <String, dynamic>{
          ...decoded(unavailablePageRaw),
          'approval_id': args['p_approval_id'],
          'cutoff_revision': args['p_cutoff_revision'],
          'after_revision': args['p_after_revision'],
          'limit': args['p_limit'],
        };
        now = DateTime.parse(row['checked_at'] as String);
        return row;
      }
    }
    final row = name == 'admin_get_receipt_successor_execution_v4'
        ? decoded(knownSentRaw)
        : fixture
              .fixturePage(
                fixture.currentSnapshot,
                args['p_after_revision'] as int?,
                args['p_limit'] as int,
              )
              .row;
    now = DateTime.parse(row['checked_at'] as String);
    return row;
  }
}

void cleared(ReadServer server) {
  expect(server.controller.snapshot, isNull);
  expect(server.controller.observations, isEmpty);
  expect(server.controller.next, isNull);
  expect(server.controller.loading, isFalse);
  expect(server.controller.historyBusy, isFalse);
  expect(server.controller.error, contains('access'));
}

void main() {
  test(
    'server permission denial during more clears protected evidence despite cached identity',
    () async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await server.controller.refresh();
      expect(server.controller.observations, hasLength(20));
      expect(server.controller.next, isNotNull);
      server.denial = const CollectApiException(
        message: 'runtime_control_permission_required',
        code: '42501',
      );
      await server.controller.more();
      expect(server.current, isTrue);
      cleared(server);
      expect(server.requests, 3);
      await server.controller.more();
      expect(server.requests, 3);
      server.denial = null;
      await server.controller.refresh();
      expect(server.controller.error, isNull);
      expect(server.controller.observations, hasLength(20));
      expect(server.controller.snapshot, isNotNull);
      expect(server.requests, 5);
    },
  );
  for (final code in [
    'authentication_required',
    'invalid_token',
    'access_revoked',
    'session_changed',
    'recent_email_sign_in_required',
  ]) {
    test(
      'authoritative auth denial $code clears the current cutoff and private page',
      () async {
        final server = ReadServer();
        addTearDown(server.controller.dispose);
        await server.controller.refresh();
        server.denial = CollectApiException(
          message: 'session denied',
          code: code,
        );
        await server.controller.more();
        cleared(server);
        expect(server.requests, 3);
      },
    );
  }
  test(
    'AuthException expired session clears private evidence and does not retry',
    () async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await server.controller.refresh();
      server.denial = const CollectAuthException('Session expired');
      await server.controller.more();
      cleared(server);
      expect(server.requests, 3);
    },
  );
  test(
    'an authoritative unavailable page removes protected source evidence and cursor',
    () async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await server.controller.refresh();
      server.unavailable = true;
      await server.controller.more();
      expect(server.controller.snapshot, isNull);
      expect(server.controller.observations, isEmpty);
      expect(server.controller.next, isNull);
      expect(server.controller.historyBusy, isFalse);
      expect(server.controller.error, contains('unavailable'));
      expect(server.requests, 3);
      server.unavailable = false;
      await server.controller.refresh();
      expect(server.controller.error, isNull);
      expect(server.controller.observations, hasLength(20));
    },
  );
  test(
    'explicit refresh permission denial clears source data and skips the page read',
    () async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await server.controller.refresh();
      server.denial = const CollectApiException(
        message: 'runtime_control_session_required',
        code: '42501',
      );
      server.denyAll = true;
      await server.controller.refresh();
      cleared(server);
      expect(server.requests, 3);
    },
  );
  test(
    'an authorized transient timeout retains the current page and original cutoff',
    () async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await server.controller.refresh();
      final before = server.controller.snapshot;
      final rows = server.controller.observations;
      final next = server.controller.next;
      server.denial = TimeoutException('temporary read timeout');
      await server.controller.more();
      expect(identical(server.controller.snapshot, before), isTrue);
      expect(identical(server.controller.observations, rows), isTrue);
      expect(server.controller.next, next);
      expect(server.controller.error, contains('retained'));
      expect(server.requests, 3);
    },
  );
  test(
    'a departed in-flight session clears its own page even without cached identity notification',
    () async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await server.controller.refresh();
      final pending = Completer<Object?>();
      server.pending = pending;
      var notifications = 0;
      server.controller.addListener(() => notifications++);
      final future = server.controller.more();
      server.current = false;
      pending.completeError(
        const CollectApiException(message: 'session expired', code: '42501'),
      );
      await future;
      cleared(server);
      expect(notifications, 2);
    },
  );
  test(
    'old in-flight denial after explicit refresh cannot clear new generation evidence',
    () async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await server.controller.refresh();
      final pending = Completer<Object?>();
      server.pending = pending;
      final future = server.controller.more();
      server.pending = null;
      await server.controller.refresh();
      final current = server.controller.snapshot;
      pending.completeError(
        const CollectApiException(message: 'old denial', code: '42501'),
      );
      await future;
      expect(identical(server.controller.snapshot, current), isTrue);
      expect(server.controller.observations, hasLength(20));
      expect(server.controller.error, isNull);
      expect(server.controller.historyBusy, isFalse);
    },
  );
  test('disposed controller cannot publish a completed denial', () async {
    final server = ReadServer();
    await server.controller.refresh();
    final pending = Completer<Object?>();
    server.pending = pending;
    var notifications = 0;
    server.controller.addListener(() => notifications++);
    final future = server.controller.more();
    server.controller.dispose();
    pending.completeError(
      const CollectApiException(message: 'old denial', code: '42501'),
    );
    await future;
    expect(notifications, 1);
  });
  testWidgets(
    'actual view removes loaded private route and paging after denial and restores only on fresh read',
    (tester) async {
      final server = ReadServer();
      addTearDown(server.controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: CollectTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdminReceiptSuccessorExecutionView(
                controller: server.controller,
                now: () => server.now,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final root = server.fixture.currentSnapshot.primaryReceiptId!;
      expect(find.text(root), findsOneWidget);
      expect(find.text('Load more callback evidence'), findsOneWidget);
      server.denial = const CollectApiException(
        message: 'permission denied',
        code: '42501',
      );
      await server.controller.more();
      await tester.pump();
      expect(find.text(root), findsNothing);
      expect(find.text('Load more callback evidence'), findsNothing);
      expect(find.textContaining('access'), findsOneWidget);
      server.denial = null;
      await server.controller.refresh();
      await tester.pump();
      expect(find.text(root), findsOneWidget);
      expect(find.text('Load more callback evidence'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
