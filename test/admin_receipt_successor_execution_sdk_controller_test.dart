import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_models.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_controller.dart';
import 'support/execution_fixture.dart';
import 'support/execution_api_fixture.dart';

void main() {
  test(
    'SDK uses only two closed read RPCs and binds fixed cutoff cursor target without replay',
    () async {
      final f = ExecutionFixture();
      final calls = <(String, Map<String, dynamic>)>[];
      var now = f.now;
      final sdk = AdminReceiptSuccessorExecutionSdk(
        rpc: (name, args) async {
          calls.add((name, args));
          final raw = name.endsWith('execution_v4')
              ? decoded(knownSentRaw)
              : f.pages.first;
          now = DateTime.parse(raw['checked_at'] as String);
          return raw;
        },
        isCurrent: () => true,
        now: () => now,
      );
      final s = await sdk.inspect(f.approval, f.root);
      final page = await sdk.observations(s, limit: 10);
      expect(page.items.length, 10);
      expect(calls.map((c) => c.$1), [
        'admin_get_receipt_successor_execution_v4',
        'admin_list_receipt_successor_observations_v4',
      ]);
      expect(calls.last.$2, {
        'p_approval_id': f.approval,
        'p_cutoff_revision': s.cutoff,
        'p_after_revision': null,
        'p_limit': 10,
      });
      expect(
        calls.last.$2.keys.any(
          (k) => k.contains('destination') || k.contains('body'),
        ),
        isFalse,
      );
    },
  );
  test(
    'SDK rejects late successful and error responses after sticky session invalidation',
    () async {
      final f = ExecutionFixture();
      var current = true;
      final pending = Completer<Object?>();
      final sdk = AdminReceiptSuccessorExecutionSdk(
        rpc: (_, _) => pending.future,
        isCurrent: () => current,
        now: () => f.now,
      );
      final future = sdk.inspect(f.approval, f.root);
      current = false;
      pending.complete(decoded(knownSentRaw));
      await expectLater(future, throwsA(isA<AdminSessionChanged>()));
      final error = Completer<Object?>();
      current = true;
      final second = AdminReceiptSuccessorExecutionSdk(
        rpc: (_, _) => error.future,
        isCurrent: () => current,
        now: () => f.now,
      ).inspect(f.approval, f.root);
      current = false;
      error.completeError(StateError('transport error'));
      await expectLater(second, throwsA(isA<AdminSessionChanged>()));
    },
  );
  test(
    'SDK refuses expired samples and does not automatically retry timeout or failure',
    () async {
      final f = ExecutionFixture();
      var count = 0;
      final sdk = AdminReceiptSuccessorExecutionSdk(
        rpc: (_, _) async {
          count++;
          return decoded(knownSentRaw);
        },
        isCurrent: () => true,
        now: () => f.original.validUntil,
      );
      await expectLater(sdk.inspect(f.approval, f.root), throwsFormatException);
      expect(count, 1);
      final failed = AdminReceiptSuccessorExecutionSdk(
        rpc: (_, _) async {
          count++;
          throw TimeoutException('uncertain read');
        },
        isCurrent: () => true,
        now: () => f.now,
      );
      await expectLater(
        failed.inspect(f.approval, f.root),
        throwsA(isA<TimeoutException>()),
      );
      expect(count, 2);
    },
  );
  test(
    'controller keeps one fixed cutoff and appends only validated ordered pages',
    () async {
      final api = ExecutionApiFixture(), s = api.currentSnapshot;
      final c = AdminReceiptSuccessorExecutionController(
        api: api,
        approvalId: s.approvalId,
        primaryReceiptId: s.primaryReceiptId!,
        isCurrent: () => api.current,
      );
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.observations.length, 20);
      final cutoff = c.snapshot!.cutoff;
      await c.more();
      expect(c.observations.length, 40);
      expect(c.snapshot!.cutoff, cutoff);
      expect(api.calls.last.$2, greaterThan(0));
      expect(c.historyBusy, isFalse);
    },
  );
  test(
    'refresh resets busy history and ignores the cancelled old page generation',
    () async {
      final api = ExecutionApiFixture(), s = api.currentSnapshot;
      final c = AdminReceiptSuccessorExecutionController(
        api: api,
        approvalId: s.approvalId,
        primaryReceiptId: s.primaryReceiptId!,
        isCurrent: () => api.current,
      );
      addTearDown(c.dispose);
      await c.refresh();
      final old = Completer<AdminReceiptSuccessorObservationPage>();
      api.pagePending = old;
      final pending = c.more();
      expect(c.historyBusy, isTrue);
      api.pagePending = null;
      await c.refresh();
      expect(c.historyBusy, isFalse);
      expect(c.observations.length, 20);
      old.complete(api.fixturePage(s, api.calls[2].$2, 20));
      await pending;
      expect(c.observations.length, 20);
      expect(c.historyBusy, isFalse);
    },
  );
  test(
    'disposed or departed controller cannot publish a completed old route read',
    () async {
      final api = ExecutionApiFixture(), s = api.currentSnapshot;
      final pending = Completer<AdminReceiptSuccessorExecutionSnapshot>();
      api.inspectPending = pending;
      final c = AdminReceiptSuccessorExecutionController(
        api: api,
        approvalId: s.approvalId,
        primaryReceiptId: s.primaryReceiptId!,
        isCurrent: () => api.current,
      );
      var events = 0;
      c.addListener(() => events++);
      final read = c.refresh();
      expect(events, 1);
      c.dispose();
      pending.complete(s);
      await read;
      expect(events, 1);
      expect(c.snapshot, isNull);
    },
  );
}
