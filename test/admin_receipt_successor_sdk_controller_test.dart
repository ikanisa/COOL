import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_controller.dart';
import 'support/successor_fixture.dart';

void main() {
  test(
    'SDK sends only exact source proof and checks current sample and session',
    () async {
      final f = SuccessorFixture();
      final api = f.sdk;
      final sample = await api.inspect(f.outbox, f.source);
      final intent = api.prepareApproval(
        request,
        sample,
        'Reviewed unchanged source and copy',
      );
      await api.submit(intent);
      final p = f.calls.last.params;
      expect(p.containsKey('p_body'), isFalse);
      expect(p.containsKey('p_destination'), isFalse);
      expect(p['p_preview_sha256'], sample.previewHash);
      f.now = f.now.add(const Duration(seconds: 61));
      expect(
        () => api.prepareApproval(
          nextRequest,
          sample,
          'Reviewed unchanged source and copy',
        ),
        throwsFormatException,
      );
      f.session = (userId: f.session!.userId, sessionId: nextRequest);
      await expectLater(
        api.submit(intent),
        throwsA(isA<AdminSessionChanged>()),
      );
    },
  );
  test('late SDK read is refused after an observed scope change', () async {
    final f = SuccessorFixture();
    final done = Completer<Object?>();
    final api = AdminReceiptSuccessorSdk(
      rpc: (_, _) => done.future,
      isCurrent: () => f.current,
      currentSession: () => f.session,
      canManage: () => true,
      now: () => f.now,
    );
    final future = api.inspect(f.outbox, f.source);
    f.current = false;
    done.complete(f.previewRow());
    await expectLater(future, throwsA(isA<AdminSessionChanged>()));
  });
  test(
    'original binding is persisted and read back before any mutation',
    () async {
      final f = SuccessorFixture();
      final store = MemoryStore();
      final api = AdminReceiptSuccessorSdk(
        rpc: (name, params) async {
          if (name == 'admin_approve_receipt_successor_v1') {
            expect(store.read(f.owner), contains(request));
          }
          return f.rpc(name, params);
        },
        isCurrent: () => f.current,
        currentSession: () => f.session,
        canManage: () => true,
        now: () => f.now,
      );
      final c = AdminReceiptSuccessorController(
        api: api,
        ownerDigest: f.owner,
        store: store,
        isCurrent: () => f.current,
      );
      addTearDown(c.dispose);
      final i = await api.inspect(f.outbox, f.source);
      await c.submit(
        api.prepareApproval(request, i, 'Reviewed current financial evidence'),
      );
      expect(c.receipt?.approvalId, isNotNull);
      expect(store.read(f.owner), isNull);
      expect(c.canSubmit, isTrue);
    },
  );
  test('storage quota prevents RPC and retains safe blocked state', () async {
    final f = SuccessorFixture();
    final store = MemoryStore()..failWrite = true;
    final api = f.sdk;
    final c = AdminReceiptSuccessorController(
      api: api,
      ownerDigest: f.owner,
      store: store,
      isCurrent: () => true,
    );
    addTearDown(c.dispose);
    final i = await api.inspect(f.outbox, f.source);
    await c.submit(
      api.prepareApproval(request, i, 'Reviewed current financial evidence'),
    );
    expect(
      f.calls.where((c) => c.name == 'admin_approve_receipt_successor_v1'),
      isEmpty,
    );
    expect(c.storageFailed, isTrue);
    expect(c.canSubmit, isFalse);
  });
  test(
    'unknown response and not_recorded lookup never choose new UUID or retry mutation',
    () async {
      final f = SuccessorFixture()..timeout = true;
      final store = MemoryStore();
      final api = f.sdk;
      final c = AdminReceiptSuccessorController(
        api: api,
        ownerDigest: f.owner,
        store: store,
        isCurrent: () => true,
      );
      addTearDown(c.dispose);
      final i = await api.inspect(f.outbox, f.source);
      await c.submit(
        api.prepareApproval(request, i, 'Reviewed current financial evidence'),
      );
      expect(c.pending!.requestId, request);
      await c.recover();
      expect(c.pending!.requestId, request);
      expect(c.canSubmit, isFalse);
      expect(
        f.calls
            .where((c) => c.name == 'admin_approve_receipt_successor_v1')
            .length,
        1,
      );
      expect(f.calls.last.params, {'p_request_id': request});
    },
  );
  test(
    'same-tab replacement controller recovers original result without mutation',
    () async {
      final f = SuccessorFixture()..timeout = true;
      final store = MemoryStore();
      final api = f.sdk;
      final c = AdminReceiptSuccessorController(
        api: api,
        ownerDigest: f.owner,
        store: store,
        isCurrent: () => true,
      );
      final i = await api.inspect(f.outbox, f.source);
      await c.submit(
        api.prepareApproval(request, i, 'Reviewed current financial evidence'),
      );
      c.dispose();
      f.outcome = 'recorded';
      final recovered = AdminReceiptSuccessorController(
        api: api,
        ownerDigest: f.owner,
        store: store,
        isCurrent: () => true,
      );
      addTearDown(recovered.dispose);
      expect(recovered.pending!.requestId, request);
      await recovered.recover();
      expect(recovered.receipt!.row['request_id'], request);
      expect(recovered.pending, isNull);
      expect(
        f.calls
            .where((c) => c.name == 'admin_approve_receipt_successor_v1')
            .length,
        1,
      );
    },
  );
  test(
    'confirmed database transaction refusal releases bookmark without blind resubmission',
    () async {
      final f = SuccessorFixture();
      final api = AdminReceiptSuccessorSdk(
        rpc: (name, params) {
          if (name == 'admin_approve_receipt_successor_v1') {
            throw const CollectApiException(
              message: 'Synthetic source changed',
              code: '55000',
            );
          }
          return f.rpc(name, params);
        },
        isCurrent: () => true,
        currentSession: () => f.session,
        canManage: () => true,
        now: () => f.now,
      );
      final store = MemoryStore();
      final c = AdminReceiptSuccessorController(
        api: api,
        ownerDigest: f.owner,
        store: store,
        isCurrent: () => true,
      );
      addTearDown(c.dispose);
      final i = await api.inspect(f.outbox, f.source);
      await c.submit(
        api.prepareApproval(request, i, 'Reviewed current financial evidence'),
      );
      expect(c.pending, isNull);
      expect(c.receipt, isNull);
      expect(c.message, contains('server refused'));
      expect(store.values, isEmpty);
    },
  );
}
