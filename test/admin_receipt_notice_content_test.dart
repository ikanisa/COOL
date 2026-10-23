import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_models.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_notice_content_controller.dart';

const fixtureRoot = String.fromEnvironment(
  'COLLECT_NOTICE_FIXTURE_ROOT',
  defaultValue: 'test/fixtures/receipt_notice_content',
);
Map<String, dynamic> fixture(String n) =>
    jsonDecode(File('$fixtureRoot/$n.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> copy(Object? r) =>
    jsonDecode(jsonEncode(r)) as Map<String, dynamic>;
const actor = '99780000-0000-4000-8000-000000000001',
    session = '99780000-0000-4000-8000-000000010001';
AdminReceiptNoticeInspection inspection(String n) {
  final r = fixture(n),
      c = r['candidate'] as Map<String, dynamic>,
      f = AdminReceiptNoticeFamily.parse(c['notice_family']);
  if (n.startsWith('policy')) {
    return AdminReceiptNoticeInspection.policy(
      r,
      c['collection_id'] as String,
      f,
      (c['template'] as Map)['language'] as String,
      c['enabled'] as bool,
    );
  }
  return AdminReceiptNoticeInspection.content(
    r,
    r['outbox_id'] as String,
    (c['source_snapshot_id'] ??
            (c['source_evidence'] as Map)['source_snapshot_id'])
        as String,
    ((c['collection_id'] ??
                ((c['source_evidence'] as Map)['source_facts']
                    as Map?)?['collection_id']) ??
            '99780000-0000-4000-8000-000000030001')
        as String,
    f,
  );
}

AdminReceiptNoticeIntent intent(String n, String? request) {
  final s = inspection(n);
  return AdminReceiptNoticeIntent.create(
    inspection: s,
    requestId: request ?? '99780000-0000-4000-8000-000000009001',
    actorId: actor,
    sessionId: session,
    reason: 'Reviewed immutable notice evidence',
    now: s.checkedAt.add(const Duration(seconds: 1)),
  );
}

class Store implements AdminReceiptNoticeContentStore {
  AdminReceiptNoticeIntent? value;
  bool failWrite = false, failClear = false;
  final events = <String>[];
  @override
  Future<AdminReceiptNoticeIntent?> read(String a, String s) async => value;
  @override
  Future<void> write(AdminReceiptNoticeIntent i) async {
    events.add('write');
    if (failWrite) throw StateError('quota');
    if (value != null && value!.fingerprint != i.fingerprint) {
      throw StateError('occupied');
    }
    value = i;
  }

  @override
  Future<void> clear(AdminReceiptNoticeIntent i) async {
    events.add('clear');
    if (failClear) throw StateError('quota');
    if (value?.fingerprint != i.fingerprint) throw StateError('changed');
    value = null;
  }
}

class Api implements AdminReceiptNoticeContentApi {
  Api(this.sample, this.result);
  AdminReceiptNoticeInspection sample;
  Object? result;
  Object? lookup;
  int mutations = 0, recoveries = 0;
  Object? mutateError;
  Completer<AdminReceiptNoticeInspection>? readFuture;
  final events = <String>[];
  @override
  Future<AdminReceiptNoticeInspection> inspectPolicy(
    String c,
    AdminReceiptNoticeFamily f,
    String l,
    bool e,
  ) async => readFuture == null ? sample : readFuture!.future;
  @override
  Future<AdminReceiptNoticeInspection> inspectContent(
    String o,
    String s,
    String c,
    AdminReceiptNoticeFamily f,
  ) async => sample;
  @override
  Future<AdminReceiptNoticeRequest> record(AdminReceiptNoticeIntent i) async {
    mutations++;
    events.add('mutate');
    if (mutateError != null) throw mutateError!;
    return AdminReceiptNoticeRequest.recorded(result, i);
  }

  @override
  Future<AdminReceiptNoticeRequest> recover(AdminReceiptNoticeIntent i) async {
    recoveries++;
    return AdminReceiptNoticeRequest.lookup(lookup, i);
  }
}

void main() {
  for (final family in ['duplicate_copy', 'reversal_notice']) {
    for (final language in ['rw', 'en', 'fr']) {
      test(
        'actual $family $language policy preview and original result validate',
        () {
          final n = 'policy-preview-$family-$language',
              r = fixture('actual-approved-policy-$family-$language'),
              i = intent(n, r['request_id'] as String);
          expect(AdminReceiptNoticeRequest.recorded(r, i).recorded, isTrue);
          expect(i.parameters.containsKey('p_body'), isFalse);
          expect(i.parameters.containsKey('p_destination'), isFalse);
        },
      );
      test(
        'actual $family $language content preview and retained original validate',
        () {
          final n = 'content-preview-$family-$language',
              r = fixture('actual-prepared-$family-$language'),
              i = intent(n, r['request_id'] as String);
          expect(AdminReceiptNoticeRequest.recorded(r, i).recorded, isTrue);
          expect(i.inspection.candidate['send_authority'], isFalse);
          expect(i.inspection.canPrepare, isTrue);
        },
      );
    }
  }
  for (final n in [
    'explicit-correction-refusal',
    'explicit-approved_resend-refusal',
  ]) {
    test('actual $n remains a blocked prerequisite', () {
      final s = inspection(n);
      expect(s.canPrepare, isFalse);
      expect(
        () => AdminReceiptNoticeIntent.create(
          inspection: s,
          requestId: '99780000-0000-4000-8000-000000009001',
          actorId: actor,
          sessionId: session,
          reason: 'Required prerequisite absent',
          now: s.checkedAt.add(const Duration(seconds: 1)),
        ),
        throwsFormatException,
      );
    });
  }
  for (var k = 0; k < 12; k++) {
    test(
      'actual original lookup $k binds exact immutable input and output',
      () {
        final r = fixture('actual-lookup-recorded-$k'),
            o = r['result'] as Map,
            policy = o['action'] == 'policy',
            family = o['notice_family'],
            language = policy
                ? o['language']
                : (r['prepared_preview'] as Map)['language'],
            i = intent(
              '${policy ? 'policy' : 'content'}-preview-$family-$language',
              r['request_id'] as String,
            );
        expect(AdminReceiptNoticeRequest.lookup(r, i).recorded, isTrue);
      },
    );
  }
  for (final k in [12, 13]) {
    test('actual missing lookup $k does not imply safe replacement', () {
      final r = fixture(
        'actual-lookup-${k == 12 ? 'not_recorded' : 'recorded'}-$k',
      );
      if (r['status'] == 'recorded') {
        final o = r['result'] as Map,
            policy = o['action'] == 'policy',
            language = policy
                ? o['language']
                : (r['prepared_preview'] as Map)['language'],
            i = intent(
              '${policy ? 'policy' : 'content'}-preview-${o['notice_family']}-$language',
              r['request_id'] as String,
            );
        expect(AdminReceiptNoticeRequest.lookup(r, i).recorded, isTrue);
      } else {
        final i = intent(
          'policy-preview-duplicate_copy-rw',
          r['request_id'] as String,
        );
        expect(AdminReceiptNoticeRequest.lookup(r, i).recorded, isFalse);
      }
    });
  }
  test(
    'content rejects body, source, recipient, fractional revision and authority inflation',
    () {
      final original = fixture('content-preview-duplicate_copy-en'),
          c = original['candidate'] as Map,
          outbox = original['outbox_id'] as String,
          source = c['source_snapshot_id'] as String,
          collection = c['collection_id'] as String;
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (r) => (r['candidate'] as Map)['body'] = 'different',
        (r) => (r['candidate'] as Map)['send_authority'] = true,
        (r) => (r['candidate'] as Map)['content_review_revision'] = 1.5,
        (r) => (r['candidate'] as Map)['destination_masked'] = '+250788971001',
        (r) =>
            ((r['candidate'] as Map)['source_evidence']
                    as Map)['financial_action'] =
                true,
        (r) =>
            (((r['candidate'] as Map)['source_evidence'] as Map)['source_facts']
                    as Map)['bank_settlement_inferred'] =
                true,
        (r) => r['outbox_id'] = '99780000-0000-4000-8000-000000009999',
        (r) => (r['candidate'] as Map)['extra'] = 'unauthorized',
      ]) {
        final r = copy(original);
        mutate(r);
        expect(
          () => AdminReceiptNoticeInspection.content(
            r,
            outbox,
            source,
            collection,
            AdminReceiptNoticeFamily.duplicateCopy,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'checkpoint is immutable, rejects drift and cannot change actor/session',
    () {
      final i = intent('policy-preview-duplicate_copy-rw', null);
      expect(() => i.row['reason'] = 'replace', throwsUnsupportedError);
      final r = copy(i.row)
        ..['actor_id'] = '99780000-0000-4000-8000-000000009999';
      expect(() => AdminReceiptNoticeIntent.parse(r), throwsFormatException);
    },
  );
  test('lookup refuses unrelated original, revision, content or template', () {
    final r = fixture('actual-lookup-recorded-1'),
        o = r['result'] as Map,
        i = intent(
          'content-preview-duplicate_copy-rw',
          r['request_id'] as String,
        );
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (v) => v['request_id'] = '99780000-0000-4000-8000-000000009999',
      (v) => (v['result'] as Map)['body_sha256'] = 'a' * 64,
      (v) => (v['prepared_preview'] as Map)['body'] = 'changed',
      (v) => (v['result'] as Map)['policy_revision'] =
          (o['policy_revision'] as int) + 1,
    ]) {
      final v = copy(r);
      mutate(v);
      expect(
        () => AdminReceiptNoticeRequest.lookup(v, i),
        throwsFormatException,
      );
    }
  });
  test(
    'SDK uses five constrained RPCs without caller content or destination',
    () async {
      final s = inspection('policy-preview-duplicate_copy-rw'),
          r = fixture('actual-approved-policy-duplicate_copy-rw'),
          i = intent(
            'policy-preview-duplicate_copy-rw',
            r['request_id'] as String,
          ),
          calls = <String>[],
          cs = inspection('content-preview-duplicate_copy-rw'),
          cr = fixture('actual-prepared-duplicate_copy-rw'),
          ci = intent(
            'content-preview-duplicate_copy-rw',
            fixture('actual-prepared-duplicate_copy-rw')['request_id']
                as String,
          );
      var now = s.checkedAt.add(const Duration(seconds: 1));
      final api = AdminReceiptNoticeContentSdk(
        rpc: (n, p) async {
          calls.add(n);
          expect(
            p.keys.any((k) => k.contains('body') || k.contains('destination')),
            isFalse,
          );
          if (n.startsWith('admin_inspect_receipt_notice_policy')) return s.row;
          if (n.startsWith('admin_approve')) return r;
          if (n == 'admin_inspect_receipt_notice_content_v1') return cs.row;
          if (n == 'admin_prepare_receipt_notice_content_v1') return cr;
          return fixture('actual-lookup-recorded-0');
        },
        actorId: actor,
        sessionId: session,
        isCurrent: () => true,
        canManage: () => true,
        now: () => now,
      );
      await api.inspectPolicy(s.collectionId, s.family, 'rw', true);
      await api.record(i);
      await api.recover(i);
      now = cs.checkedAt.add(const Duration(seconds: 1));
      await api.inspectContent(
        cs.outboxId!,
        cs.sourceSnapshotId!,
        cs.collectionId,
        cs.family,
      );
      await api.record(ci);
      expect(calls, [
        'admin_inspect_receipt_notice_policy_v1',
        'admin_approve_receipt_notice_policy_v1',
        'admin_get_receipt_notice_content_request_v1',
        'admin_inspect_receipt_notice_content_v1',
        'admin_prepare_receipt_notice_content_v1',
      ]);
    },
  );
  test(
    'SDK refuses expired, denied and stale-session input before mutation',
    () async {
      final s = inspection('policy-preview-duplicate_copy-rw'),
          i = intent('policy-preview-duplicate_copy-rw', null);
      var current = true, manage = true;
      var now = s.validUntil;
      var calls = 0;
      final api = AdminReceiptNoticeContentSdk(
        rpc: (n, p) async {
          calls++;
          throw StateError('unreachable');
        },
        actorId: actor,
        sessionId: session,
        isCurrent: () => current,
        canManage: () => manage,
        now: () => now,
      );
      await expectLater(api.record(i), throwsFormatException);
      now = s.checkedAt;
      manage = false;
      await expectLater(api.record(i), throwsA(isA<AdminSessionChanged>()));
      manage = true;
      current = false;
      await expectLater(api.recover(i), throwsA(isA<AdminSessionChanged>()));
      expect(calls, 0);
    },
  );
  test(
    'SDK discards late response and errors after session revocation',
    () async {
      final s = inspection('policy-preview-duplicate_copy-rw');
      for (final fail in [false, true]) {
        var current = true;
        final wait = Completer<Object?>(),
            api = AdminReceiptNoticeContentSdk(
              rpc: (n, p) => wait.future,
              actorId: actor,
              sessionId: session,
              isCurrent: () => current,
              canManage: () => true,
              now: () => s.checkedAt,
            );
        final future = api.inspectPolicy(s.collectionId, s.family, 'rw', true),
            check = expectLater(future, throwsA(isA<AdminSessionChanged>()));
        current = false;
        if (fail) {
          wait.completeError(StateError('outage'));
        } else {
          wait.complete(s.row);
        }
        await check;
      }
    },
  );
  test('SDK denial propagates and performs one call', () async {
    final s = inspection('policy-preview-duplicate_copy-rw');
    var calls = 0;
    final api = AdminReceiptNoticeContentSdk(
      rpc: (n, p) async {
        calls++;
        throw const CollectApiException(message: 'refused', code: '42501');
      },
      actorId: actor,
      sessionId: session,
      isCurrent: () => true,
      canManage: () => true,
      now: () => s.checkedAt,
    );
    await expectLater(
      api.inspectPolicy(s.collectionId, s.family, 'rw', true),
      throwsA(isA<CollectApiException>()),
    );
    expect(calls, 1);
  });
  test('controller checkpoints before mutation and records once', () async {
    final s = inspection('policy-preview-duplicate_copy-rw'),
        r = fixture('actual-approved-policy-duplicate_copy-rw'),
        api = Api(s, r),
        store = Store();
    var recorded = 0;
    final c = AdminReceiptNoticeContentController(
      api: api,
      actorId: actor,
      sessionId: session,
      collectionId: s.collectionId,
      policy: true,
      store: store,
      now: () => s.checkedAt.add(const Duration(seconds: 1)),
      isCurrent: () => true,
      canManage: () => true,
      newRequestId: () => r['request_id'] as String,
      onRecorded: () => recorded++,
    );
    await c.refresh(family: s.family);
    await c.record('Reviewed immutable notice evidence');
    expect(store.events, ['write', 'clear']);
    expect(api.mutations, 1);
    expect(c.pending, isNull);
    expect(recorded, 1);
    await c.record('Reviewed immutable notice evidence');
    expect(api.mutations, 1);
    c.dispose();
  });
  test(
    'storage refusal prevents mutation and retains original checkpoint',
    () async {
      final s = inspection('policy-preview-duplicate_copy-rw'),
          api = Api(s, null),
          store = Store()..failWrite = true;
      final c = AdminReceiptNoticeContentController(
        api: api,
        actorId: actor,
        sessionId: session,
        collectionId: s.collectionId,
        policy: true,
        store: store,
        now: () => s.checkedAt,
        isCurrent: () => true,
        canManage: () => true,
        newRequestId: () => '99780000-0000-4000-8000-000000009001',
      );
      await c.refresh(family: s.family);
      await c.record('Reviewed immutable notice evidence');
      expect(api.mutations, 0);
      expect(c.pending, isNotNull);
      expect(c.canRecord, isFalse);
      c.dispose();
    },
  );
  test(
    'lost response/restart and not-recorded outcome retain UUID without blind retries',
    () async {
      final s = inspection('policy-preview-duplicate_copy-rw'),
          i = intent(
            'policy-preview-duplicate_copy-rw',
            fixture('actual-lookup-not_recorded-12')['request_id'] as String,
          ),
          api = Api(s, null)..lookup = fixture('actual-lookup-not_recorded-12'),
          store = Store()..value = i;
      final c = AdminReceiptNoticeContentController(
        api: api,
        actorId: actor,
        sessionId: session,
        collectionId: s.collectionId,
        policy: true,
        store: store,
        now: () => s.validUntil.add(const Duration(days: 1)),
        isCurrent: () => true,
        canManage: () => true,
        newRequestId: () => throw StateError('must retain original'),
      );
      await c.refresh(family: s.family);
      await c.recover();
      expect(c.pending?.requestId, i.requestId);
      expect(store.value?.requestId, i.requestId);
      expect(c.canRecord, isFalse);
      expect(api.mutations, 0);
      expect(api.recoveries, 1);
      c.dispose();
    },
  );
  test(
    'restart recovers actual recorded original and clears exact checkpoint only',
    () async {
      final s = inspection('policy-preview-duplicate_copy-rw'),
          lookup = fixture('actual-lookup-recorded-0'),
          i = intent(
            'policy-preview-duplicate_copy-rw',
            lookup['request_id'] as String,
          ),
          store = Store()..value = i,
          api = Api(s, null)..lookup = lookup;
      var recorded = 0;
      final c = AdminReceiptNoticeContentController(
        api: api,
        actorId: actor,
        sessionId: session,
        collectionId: s.collectionId,
        policy: true,
        store: store,
        now: () => s.validUntil.add(const Duration(days: 1)),
        isCurrent: () => true,
        canManage: () => true,
        newRequestId: () => throw StateError('not needed'),
        onRecorded: () => recorded++,
      );
      await c.refresh(family: s.family);
      await c.recover();
      expect(c.pending, isNull);
      expect(store.value, isNull);
      expect(recorded, 1);
      expect(api.mutations, 0);
      c.dispose();
    },
  );
}
