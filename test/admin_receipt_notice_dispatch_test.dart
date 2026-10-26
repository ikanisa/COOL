import 'dart:async';
import 'dart:convert';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_dispatch_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/receipt_notice_dispatch_fixtures.dart';

AdminReceiptNoticePreparedReference prepared({bool compensation = false}) {
  final name = compensation ? 'compensation' : 'copy',
      raw = dispatchFixture('content-$name'),
      candidate = raw['candidate'] as Map;
  final inspection = AdminReceiptNoticeInspection.content(
    raw,
    raw['outbox_id'] as String,
    candidate['source_snapshot_id'] as String,
    candidate['collection_id'] as String,
    AdminReceiptNoticeFamily.parse(candidate['notice_family']),
  );
  final result = dispatchFixture('prepared-$name');
  final original = AdminReceiptNoticeIntent.create(
    inspection: inspection,
    requestId: result['request_id'] as String,
    actorId: dispatchActor,
    sessionId: dispatchSession,
    reason: 'Synthetic current owner preparation',
    now: inspection.checkedAt.add(const Duration(milliseconds: 1)),
  );
  return AdminReceiptNoticePreparedReference.fromRecorded(
    inspection: inspection,
    recorded: AdminReceiptNoticeRequest.recorded(result, original),
    original: original,
    actorId: dispatchActor,
    sessionId: dispatchSession,
  );
}

AdminReceiptNoticeDispatchInspection inspected(
  AdminReceiptNoticePreparedReference ref, [
  String? name,
]) => AdminReceiptNoticeDispatchInspection.parse(
  dispatchFixture(
    name ??
        'dispatch-${ref.family == AdminReceiptNoticeFamily.duplicateCopy ? 'copy' : 'compensation'}',
  ),
  ref,
);
AdminReceiptNoticeDispatchIntent approveIntent(
  AdminReceiptNoticePreparedReference ref, {
  String? requestId,
  String? sample,
}) {
  final inspection = inspected(ref, sample),
      result = dispatchFixture(
        'approved-${ref.family == AdminReceiptNoticeFamily.duplicateCopy ? 'copy' : 'compensation'}',
      );
  return AdminReceiptNoticeDispatchIntent.create(
    action: AdminReceiptNoticeDispatchAction.approve,
    actorId: dispatchActor,
    sessionId: dispatchSession,
    requestId: requestId ?? result['request_id'] as String,
    reason: 'Synthetic current owner dispatch approval',
    now: inspection.checkedAt.add(const Duration(milliseconds: 1)),
    reference: ref,
    inspection: inspection,
  );
}

class DispatchMemory {
  final values = <String, String>{};
  bool failWrite = false, dropWrite = false;
  late final store = AdminReceiptNoticeDispatchJournalStore(
    readRaw: (key) => values[key],
    writeRaw: (key, value) {
      if (failWrite) throw StateError('Synthetic storage quota');
      if (!dropWrite) values[key] = value;
    },
    exclusive: (key, work) async => work(),
  );
}

class DispatchApi implements AdminReceiptNoticeDispatchApi {
  DispatchApi(this.ref);
  final AdminReceiptNoticePreparedReference ref;
  bool loseReply = false, missing = false;
  int writes = 0, lookups = 0, reads = 0;
  Completer<AdminReceiptNoticeDispatchInspection>? delayed;
  AdminReceiptNoticeDispatchIntent? written;
  @override
  Future<AdminReceiptNoticeDispatchConfiguration> configuration() async =>
      AdminReceiptNoticeDispatchConfiguration.parse(
        dispatchFixture('configuration-default'),
      );
  @override
  Future<AdminReceiptNoticeDispatchInspection> inspect(
    AdminReceiptNoticePreparedReference reference,
  ) async {
    reads++;
    return delayed == null ? inspected(reference) : delayed!.future;
  }

  @override
  Future<AdminReceiptNoticeDispatchRequest> record(
    AdminReceiptNoticeDispatchIntent intent,
  ) async {
    writes++;
    written = intent;
    if (loseReply) throw TimeoutException('Synthetic committed reply lost');
    return AdminReceiptNoticeDispatchRequest.recorded(
      dispatchFixture('approved-copy')..['request_id'] = intent.requestId,
      intent,
    );
  }

  @override
  Future<AdminReceiptNoticeDispatchRequest> recover(
    AdminReceiptNoticeDispatchIntent intent,
  ) async {
    lookups++;
    final row = dispatchFixture('lookup-copy')
      ..['request_id'] = intent.requestId;
    if (missing) {
      row['status'] = 'not_recorded';
      row['result'] = null;
    } else {
      (row['result'] as Map)['request_id'] = intent.requestId;
    }
    return AdminReceiptNoticeDispatchRequest.lookup(row, intent);
  }
}

void main() {
  for (final compensation in [false, true]) {
    test(
      'actual ${compensation ? 'compensation' : 'copy'} prepared→sample→approval→original lookup is strictly bound',
      () {
        final ref = prepared(compensation: compensation),
            intent = approveIntent(ref),
            family = compensation ? 'compensation' : 'copy';
        expect(
          AdminReceiptNoticePreparedReference.parse(ref.row).fingerprint,
          ref.fingerprint,
        );
        expect(
          AdminReceiptNoticeDispatchIntent.parse(intent.row).parameters,
          intent.parameters,
        );
        final recorded = AdminReceiptNoticeDispatchRequest.recorded(
              dispatchFixture('approved-$family'),
              intent,
            ),
            lookup = AdminReceiptNoticeDispatchRequest.lookup(
              dispatchFixture('lookup-$family'),
              intent,
            );
        expect(recorded.result, lookup.result);
        expect(recorded.result!['send_authority'], isFalse);
        expect(recorded.result!['financial_action'], isFalse);
      },
    );
  }
  test(
    'actual configuration revision/freshness and recorded configure output bind without a configuration expiry',
    () {
      final config = AdminReceiptNoticeDispatchConfiguration.parse(
            dispatchFixture('configuration-default'),
          ),
          result = dispatchFixture('configuration-recorded');
      final intent = AdminReceiptNoticeDispatchIntent.create(
        action: AdminReceiptNoticeDispatchAction.configure,
        actorId: dispatchActor,
        sessionId: dispatchSession,
        requestId: result['request_id'] as String,
        reason: 'Synthetic transactional configuration review',
        now: config.checkedAt.add(const Duration(seconds: 1)),
        configuration: config,
        enabled: true,
      );
      expect(
        intent.parameters['p_expires_at'],
        config.row['sample_valid_until'],
      );
      expect(
        AdminReceiptNoticeDispatchRequest.recorded(
          result,
          intent,
        ).result!['configuration_revision'],
        2,
      );
      expect(
        AdminReceiptNoticeDispatchConfiguration.parse(
          dispatchFixture('configuration-changed'),
        ).enabled,
        isTrue,
      );
    },
  );
  test(
    'actual recorded approval plus fresh pending sample produces exact unarmed revocation',
    () {
      final ref = prepared(),
          sample = inspected(ref, 'pending-copy'),
          result = dispatchFixture('revoked-copy');
      final intent = AdminReceiptNoticeDispatchIntent.create(
        action: AdminReceiptNoticeDispatchAction.revoke,
        actorId: dispatchActor,
        sessionId: dispatchSession,
        requestId: result['request_id'] as String,
        reason: 'Synthetic irrevocable stop before invocation',
        now: sample.checkedAt.add(const Duration(milliseconds: 1)),
        reference: ref,
        inspection: sample,
        approval: dispatchFixture('approved-copy'),
      );
      expect(
        AdminReceiptNoticeDispatchRequest.recorded(
          result,
          intent,
        ).result!['status'],
        'revoked_unarmed',
      );
      expect(
        intent.parameters.keys,
        unorderedEquals([
          'p_request_id',
          'p_reason',
          'p_approval_id',
          'p_expected_transport_revision',
        ]),
      );
    },
  );
  for (final field in [
    'prepared_review_id',
    'outbox_id',
    'notice_family',
    'send_authority',
    'can_approve',
    'candidate_sha256',
    'contract_version',
  ]) {
    test('sample rejects hostile $field', () {
      final ref = prepared(), row = dispatchFixture('dispatch-copy');
      row[field] = field == 'send_authority' ? true : 'forged';
      expect(
        () => AdminReceiptNoticeDispatchInspection.parse(row, ref),
        throwsFormatException,
      );
    });
  }
  for (final field in [
    'root_outbox_id',
    'source_snapshot_id',
    'collection_id',
    'member_record_id',
    'body',
    'body_sha256',
    'destination_sha256',
    'source_facts',
    'primary_transport_observation',
    'notice_policy_revision',
    'segment_count',
  ]) {
    test('sample rejects changed prepared candidate $field', () {
      final ref = prepared(), row = dispatchFixture('dispatch-copy');
      (row['candidate'] as Map)[field] = 'foreign';
      expect(
        () => AdminReceiptNoticeDispatchInspection.parse(row, ref),
        throwsFormatException,
      );
    });
  }
  test(
    'configuration refuses unknown/authority fields and a forged lasting expiry',
    () {
      for (final row in [
        dispatchFixture('configuration-default')
          ..['configuration_expires_at'] = '2099-01-01T00:00:00Z',
        dispatchFixture('configuration-default')..['send_authority'] = true,
        dispatchFixture('configuration-default')
          ..['sample_valid_until'] = '2099-01-01T00:00:00Z',
      ]) {
        expect(
          () => AdminReceiptNoticeDispatchConfiguration.parse(row),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'opaque candidate sample hash is retained exactly and not reconstructed from redacted destination',
    () {
      final ref = prepared(), row = dispatchFixture('dispatch-copy');
      expect(
        (row['candidate'] as Map).containsKey('destination_e164'),
        isFalse,
      );
      expect(inspected(ref).candidateSha256, row['candidate_sha256']);
      expect(
        approveIntent(ref).parameters.keys.any(
          (key) => key.contains('body') || key.contains('destination'),
        ),
        isFalse,
      );
    },
  );
  test(
    'stale/expiry boundary and foreign actor/session cannot create an action',
    () {
      final ref = prepared(), sample = inspected(ref);
      expect(
        () => AdminReceiptNoticeDispatchIntent.create(
          action: AdminReceiptNoticeDispatchAction.approve,
          actorId: dispatchActor,
          sessionId: dispatchSession,
          requestId: dispatchFixture('approved-copy')['request_id'] as String,
          reason: 'Reviewed stale dispatch evidence',
          now: sample.validUntil,
          reference: ref,
          inspection: sample,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptNoticePreparedReference.fromRecorded(
          inspection: ref.original.inspection,
          recorded: ref.recorded,
          original: ref.original,
          actorId: '99780000-0000-4000-8000-000000000002',
          sessionId: dispatchSession,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'durable prepared handoff is idempotent and exact original readback precedes clearance',
    () async {
      final memory = DispatchMemory(), ref = prepared();
      await preserveReceiptNoticePreparedHandoff(
        reference: ref,
        store: memory.store,
        isCurrent: () => true,
      );
      await preserveReceiptNoticePreparedHandoff(
        reference: ref,
        store: memory.store,
        isCurrent: () => true,
      );
      expect(
        (await memory.store.readPrepared(
          dispatchActor,
          dispatchSession,
          ref.originalRequestId,
        ))!.fingerprint,
        ref.fingerprint,
      );
      expect(
        (await memory.store.latestPrepared(
          dispatchActor,
          dispatchSession,
          ref.outboxId,
          ref.sourceSnapshotId,
          ref.collectionId,
          ref.family,
        ))!.preparedReviewId,
        ref.preparedReviewId,
      );
      expect(
        await memory.store.readPrepared(
          dispatchActor,
          '99780000-0000-4000-8000-000000010002',
          ref.originalRequestId,
        ),
        isNull,
      );
    },
  );
  for (final failure in ['quota', 'missing-readback', 'session-loss']) {
    test(
      'handoff $failure never reports preserved; old original must remain retained',
      () async {
        final memory = DispatchMemory(), ref = prepared();
        var current = true;
        if (failure == 'quota') memory.failWrite = true;
        if (failure == 'missing-readback') memory.dropWrite = true;
        final store = failure == 'session-loss'
            ? AdminReceiptNoticeDispatchJournalStore(
                readRaw: (key) => memory.values[key],
                writeRaw: (key, value) {
                  memory.values[key] = value;
                  current = false;
                },
                exclusive: (key, work) async => work(),
              )
            : memory.store;
        await expectLater(
          preserveReceiptNoticePreparedHandoff(
            reference: ref,
            store: store,
            isCurrent: () => current,
          ),
          throwsA(anything),
        );
      },
    );
  }
  test(
    'pending checkpoint excludes concurrent replacement, TTL expiry does not clear it',
    () async {
      final memory = DispatchMemory(),
          ref = prepared(),
          first = approveIntent(prepared());
      await memory.store.preservePrepared(ref);
      await memory.store.savePending(first);
      await expectLater(
        memory.store.savePending(
          approveIntent(ref, requestId: '99780000-0000-4000-8000-000000000099'),
        ),
        throwsFormatException,
      );
      expect(
        (await memory.store.pending(dispatchActor, dispatchSession))!.requestId,
        first.requestId,
      );
      expect(first.fresh(DateTime.utc(2099)), isFalse);
      expect(
        (await memory.store.pending(
          dispatchActor,
          dispatchSession,
        ))!.fingerprint,
        first.fingerprint,
      );
    },
  );
  test(
    'atomic completion preserves exact approval, original tombstone, and rejects result conflict',
    () async {
      final memory = DispatchMemory(),
          ref = prepared(),
          intent = approveIntent(prepared()),
          result = AdminReceiptNoticeDispatchRequest.recorded(
            dispatchFixture('approved-copy'),
            approveIntent(prepared()),
          );
      await memory.store.preservePrepared(ref);
      await memory.store.savePending(intent);
      await memory.store.complete(intent, result);
      expect(
        await memory.store.pending(dispatchActor, dispatchSession),
        isNull,
      );
      expect(
        (await memory.store.approval(ref))!['approval_id'],
        result.result!['approval_id'],
      );
      await memory.store.complete(intent, result);
      await expectLater(
        memory.store.savePending(intent),
        throwsFormatException,
      );
      final forged = dispatchFixture('approved-copy')
        ..['audit_id'] = '99780000-0000-4000-8000-000000000098';
      await expectLater(
        memory.store.complete(
          intent,
          AdminReceiptNoticeDispatchRequest.recorded(forged, intent),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'completion storage refusal preserves pending; no approval is inferred from sample',
    () async {
      final memory = DispatchMemory(),
          ref = prepared(),
          intent = approveIntent(prepared());
      await memory.store.preservePrepared(ref);
      await memory.store.savePending(intent);
      memory.failWrite = true;
      await expectLater(
        memory.store.complete(
          intent,
          AdminReceiptNoticeDispatchRequest.recorded(
            dispatchFixture('approved-copy'),
            intent,
          ),
        ),
        throwsStateError,
      );
      expect(
        (await memory.store.pending(
          dispatchActor,
          dispatchSession,
        ))!.fingerprint,
        intent.fingerprint,
      );
      expect(await memory.store.approval(ref), isNull);
    },
  );
  test(
    'SDK six-RPC allowlist, exact parameters and original lookup without repeating writes',
    () async {
      final ref = prepared(),
          intent = approveIntent(prepared()),
          calls = <String>[];
      final sdk = AdminReceiptNoticeDispatchSdk(
        rpc: (name, parameters) async {
          calls.add(name);
          if (name == 'admin_inspect_receipt_notice_dispatch_v1') {
            expect(parameters, {'p_prepared_review_id': ref.preparedReviewId});
            return dispatchFixture('dispatch-copy');
          }
          if (name == 'admin_approve_receipt_notice_dispatch_v1') {
            expect(parameters, intent.parameters);
            return dispatchFixture('approved-copy');
          }
          expect(parameters, {'p_request_id': intent.requestId});
          return dispatchFixture('lookup-copy');
        },
        actorId: dispatchActor,
        sessionId: dispatchSession,
        isCurrent: () => true,
        canManage: () => true,
        now: () => inspected(ref).checkedAt.add(const Duration(seconds: 1)),
      );
      await sdk.inspect(ref);
      await sdk.record(intent);
      await sdk.recover(intent);
      expect(calls, [
        'admin_inspect_receipt_notice_dispatch_v1',
        'admin_approve_receipt_notice_dispatch_v1',
        'admin_get_receipt_notice_dispatch_request_v1',
      ]);
    },
  );
  test(
    'SDK session changes before success or rejection suppress both replies',
    () async {
      for (final fail in [false, true]) {
        var current = true;
        final ref = prepared();
        final sdk = AdminReceiptNoticeDispatchSdk(
          rpc: (name, parameters) async {
            current = false;
            if (fail) throw TimeoutException('Synthetic');
            return dispatchFixture('dispatch-copy');
          },
          actorId: dispatchActor,
          sessionId: dispatchSession,
          isCurrent: () => current,
          canManage: () => true,
          now: () => inspected(ref).checkedAt,
        );
        await expectLater(
          sdk.inspect(ref),
          throwsA(isA<AdminSessionChanged>()),
        );
      }
    },
  );
  test(
    'lost write survives controller restart; only exact original lookup resolves it',
    () async {
      final ref = prepared(),
          memory = DispatchMemory(),
          api = DispatchApi(prepared())..loseReply = true;
      await memory.store.preservePrepared(ref);
      var ids = 0;
      AdminReceiptNoticeDispatchController controller() =>
          AdminReceiptNoticeDispatchController(
            api: api,
            actorId: dispatchActor,
            sessionId: dispatchSession,
            isCurrent: () => true,
            canManage: () => true,
            now: () => inspected(ref).checkedAt.add(const Duration(seconds: 1)),
            newRequestId: () {
              ids++;
              return dispatchFixture('approved-copy')['request_id'] as String;
            },
            store: memory.store,
            reference: ref,
          );
      final first = controller();
      await first.refresh();
      await first.record(
        AdminReceiptNoticeDispatchAction.approve,
        'Synthetic current owner dispatch approval',
      );
      expect(api.writes, 1);
      first.dispose();
      final next = controller();
      addTearDown(next.dispose);
      await next.refresh();
      expect(next.pending!.requestId, api.written!.requestId);
      expect(api.reads, 1);
      api.missing = true;
      await next.recover();
      expect(next.pending, isNotNull);
      await next.record(
        AdminReceiptNoticeDispatchAction.approve,
        'Replacement must stay blocked',
      );
      expect(ids, 1);
      api.missing = false;
      await next.recover();
      expect(next.pending, isNull);
      expect(api.writes, 1);
      expect(api.lookups, 2);
      expect(
        (await memory.store.approval(ref))!['approval_id'],
        dispatchFixture('approved-copy')['approval_id'],
      );
    },
  );
  test(
    'late controller inspection after session loss never becomes actionable',
    () async {
      final ref = prepared(),
          memory = DispatchMemory(),
          api = DispatchApi(prepared())
            ..delayed = Completer<AdminReceiptNoticeDispatchInspection>();
      var current = true;
      await memory.store.preservePrepared(ref);
      final c = AdminReceiptNoticeDispatchController(
        api: api,
        actorId: dispatchActor,
        sessionId: dispatchSession,
        isCurrent: () => current,
        canManage: () => true,
        now: () => inspected(ref).checkedAt,
        newRequestId: () =>
            dispatchFixture('approved-copy')['request_id'] as String,
        store: memory.store,
        reference: ref,
      );
      addTearDown(c.dispose);
      final work = c.refresh();
      await Future<void>.delayed(Duration.zero);
      current = false;
      api.delayed!.complete(inspected(ref));
      await work;
      expect(c.inspection, isNull);
      expect(c.canApprove, isFalse);
    },
  );
  test('hostile journal corruption is refused rather than replaced', () async {
    final memory = DispatchMemory(), ref = prepared();
    await memory.store.preservePrepared(ref);
    final key = memory.values.keys.single;
    final row = jsonDecode(memory.values[key]!) as Map;
    row['actor_id'] = '99780000-0000-4000-8000-000000000002';
    memory.values[key] = jsonEncode(row);
    await expectLater(
      memory.store.pending(dispatchActor, dispatchSession),
      throwsFormatException,
    );
  });
  test(
    'completed64/65 journal preflight refuses a new side effect and never drops an unresolved original',
    () async {
      final memory = DispatchMemory(),
          ref = prepared(),
          original = approveIntent(prepared()),
          done = <Object?>[];
      // Declared synthetic storage cardinality fixture, not64 actual SQL approvals.
      for (var i = 0; i < 64; i++) {
        final row =
            jsonDecode(jsonEncode(original.row)) as Map<String, dynamic>;
        row['request_id'] =
            '99789997-0000-4000-8000-${(i + 1).toString().padLeft(12, '0')}';
        row.remove('fingerprint');
        row['fingerprint'] = noticeFingerprint(row);
        final intent = AdminReceiptNoticeDispatchIntent.parse(row),
            result = dispatchFixture('approved-copy')
              ..['request_id'] = intent.requestId;
        AdminReceiptNoticeDispatchRequest.recorded(result, intent);
        done.add({'intent': intent.row, 'result': result});
      }
      final key = 'collect.notice-dispatch.v1.$dispatchActor.$dispatchSession',
          journal = {
            'version': 1,
            'actor_id': dispatchActor,
            'session_id': dispatchSession,
            'prepared': [ref.row],
            'pending': null,
            'completed': done,
          };
      memory.values[key] = jsonEncode(journal);
      final before = memory.values[key];
      await expectLater(
        memory.store.savePending(original),
        throwsFormatException,
      );
      expect(memory.values[key], before);
      journal['pending'] = original.row;
      memory.values[key] = jsonEncode(journal);
      await expectLater(
        memory.store.complete(
          original,
          AdminReceiptNoticeDispatchRequest.recorded(
            dispatchFixture('approved-copy'),
            original,
          ),
        ),
        throwsFormatException,
      );
      expect(
        (await memory.store.pending(
          dispatchActor,
          dispatchSession,
        ))!.fingerprint,
        original.fingerprint,
      );
      expect((jsonDecode(memory.values[key]!)['completed'] as List).length, 64);
    },
  );
}
