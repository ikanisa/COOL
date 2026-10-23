import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_controller.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_models.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_execution_sdk.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_models.dart';
import 'package:collect_app/admin/core/admin_receipt_successor_sdk.dart';
import 'support/execution_fixture.dart';
import 'support/successor_fixture.dart';
import 'support/successor_retry_fixture.dart';

AdminReceiptSuccessorController controller(RetryFixture f, MemoryStore store) =>
    AdminReceiptSuccessorController(
      api: f.sdk,
      ownerDigest: f.owner,
      store: store,
      isCurrent: () => f.current,
    );

void main() {
  test('retained SQL fixtures remain exactly hash bound to 0700 proof', () {
    final bindings =
        jsonDecode(
              File(
                'test/fixtures/receipt_successor_retry_v2/producer-bindings.json',
              ).readAsStringSync(),
            )
            as Map;
    for (final entry in bindings.entries) {
      final bytes = File(
        'test/fixtures/receipt_successor_retry_v2/${entry.key}',
      ).readAsBytesSync();
      expect(sha256.convert(bytes).toString(), (entry.value as Map)['sha256']);
    }
  });

  test(
    'exact second and third SQL v2 previews receipts and original lookup parse',
    () {
      for (final prefix in ['retry', 'third']) {
        final raw = retryObserved('$prefix-inspection-v2');
        final preview = AdminReceiptSuccessorInspection.parse(
          raw,
          raw['outbox_id'] as String,
          raw['source_snapshot_id'] as String,
          predecessorJobId: raw['predecessor_job_id'] as String,
        );
        expect(preview.isRetiredRetry, isTrue);
        expect(preview.retiredJobs, prefix == 'retry' ? 1 : 2);
        expect(preview.preview!.recipient, '+250***201');
        final receiptRaw = retryObserved('$prefix-approval-v2');
        final receipt = AdminReceiptSuccessorReceipt.parse(
          receiptRaw,
          retryBinding(receiptRaw),
        );
        expect(
          receipt.row['predecessor_proof_sha256'],
          preview.predecessorProofHash,
        );
        expect(receipt.row['send_action'], isFalse);
        expect(receipt.row.containsKey('body'), isFalse);
      }
      final receipt = retryObserved('retry-approval-v2');
      expect(
        AdminReceiptSuccessorLookup.parse(
          retryObserved('original-request-v2'),
          retryBinding(receipt),
        ).receipt!.approvalId,
        receipt['approval_id'],
      );
    },
  );

  test(
    'actual v5 execution producer parses only with explicit v5 contract',
    () {
      final raw = retryObserved('second-revoked-investigation-v5');
      final approval = raw['approval_id'] as String;
      final root = raw['primary_receipt_id'] as String;
      final read = AdminReceiptSuccessorExecutionSnapshot.parse(
        raw,
        approval,
        root,
        executionVersion: 5,
      );
      expect(read.state, 'unarmed_revoked');
      expect(
        () => AdminReceiptSuccessorExecutionSnapshot.parse(raw, approval, root),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptSuccessorExecutionSnapshot.parse(
          raw,
          approval,
          root,
          executionVersion: 6,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'strict v2 preview rejects added destination contract and predecessor drift',
    () {
      final f = RetryFixture();
      final mutations = <void Function(Map<String, dynamic>)>[
        (r) => r['destination_e164'] = '+250788000000',
        (r) => r['scope'] = 'rw_receipt_successors',
        (r) => r['contract_version'] = 1,
        (r) => r['predecessor_job_id'] = nextRequest,
        (r) => r['predecessor_proof_sha256'] = 'bad-proof',
        (r) => r['send_action'] = true,
        (r) => r['primary_receipt_retained'] = false,
        (r) => r['preview_sha256'] = null,
      ];
      for (final mutate in mutations) {
        final raw = clone(f.inspection);
        mutate(raw);
        expect(
          () => AdminReceiptSuccessorInspection.parse(
            raw,
            f.root,
            f.source,
            predecessorJobId: f.predecessor,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'retired count is exact bounded integer and denied preview erases proof',
    () {
      final f = RetryFixture();
      for (final count in [0, 26, 1.5, '2', null]) {
        final raw = clone(f.inspection)..['retired_jobs'] = count;
        expect(
          () => AdminReceiptSuccessorInspection.parse(
            raw,
            f.root,
            f.source,
            predecessorJobId: f.predecessor,
          ),
          throwsFormatException,
        );
      }
      for (final reason in [
        'predecessor_transport_refused',
        'predecessor_revocation_required',
        'predecessor_not_latest',
        'predecessor_proof_invalid',
        'lineage_limit',
        'predecessor_unavailable',
        'policy_disabled',
      ]) {
        final raw = clone(f.inspection)
          ..['can_approve'] = false
          ..['reason_code'] = reason
          ..['preview'] = null
          ..['preview_sha256'] = null
          ..['predecessor_proof_sha256'] = null
          ..['retired_jobs'] = null;
        expect(
          AdminReceiptSuccessorInspection.parse(
            raw,
            f.root,
            f.source,
            predecessorJobId: f.predecessor,
          ).canApprove,
          isFalse,
        );
        raw['predecessor_proof_sha256'] =
            f.inspection['predecessor_proof_sha256'];
        expect(
          () => AdminReceiptSuccessorInspection.parse(
            raw,
            f.root,
            f.source,
            predecessorJobId: f.predecessor,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'SDK derives preceding job from validated v5 route and exact v2 parameters',
    () async {
      final f = RetryFixture();
      final api = f.sdk;
      final inspection = await api.inspectRetry(f.root, f.source, f.approval);
      expect(f.calls.map((c) => c.name), [
        'admin_get_receipt_successor_execution_v5',
        'admin_inspect_receipt_successor_retry_v2',
      ]);
      expect(f.calls.last.params, {
        'p_outbox_id': f.root,
        'p_source_snapshot_id': f.source,
        'p_predecessor_job_id': f.predecessor,
      });
      final intent = api.prepareApproval(
        request,
        inspection,
        'Reviewed stopped lineage and recorded copy',
      );
      expect(intent.rpcName, 'admin_approve_receipt_successor_retry_v2');
      expect(intent.binding.isRetiredRetry, isTrue);
      expect(intent.parameters.keys.toSet(), {
        'p_request_id',
        'p_outbox_id',
        'p_source_snapshot_id',
        'p_predecessor_job_id',
        'p_predecessor_proof_sha256',
        'p_expected_root_revision',
        'p_expected_lineage_revision',
        'p_preview_sha256',
        'p_sample_valid_until',
        'p_reason',
      });
      final receipt = await api.submit(intent);
      expect(receipt.row['request_id'], request);
      expect(receipt.approvalId, isNotNull);
      expect(
        f.calls.where(
          (c) => c.name.contains('grant') || c.name.contains('send'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'new checkpoint persists proof IDs but no recipient text body reason or authority',
    () async {
      final f = RetryFixture();
      final api = f.sdk;
      final intent = api.prepareApproval(
        request,
        await api.inspectRetry(f.root, f.source, f.approval),
        'Reviewed stopped lineage and exact current copy',
      );
      final encoded = AdminReceiptSuccessorCheckpoint(
        f.owner,
        intent.binding,
      ).encode();
      expect(encoded, contains(f.predecessor));
      for (final forbidden in [
        '+250',
        'body',
        'reason',
        'destination',
        'grant',
        'receipt text',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }
      final decoded = AdminReceiptSuccessorCheckpoint.parse(encoded, f.owner);
      expect(decoded.binding.encode(), intent.binding.encode());
      final partial = jsonDecode(encoded) as Map;
      ((partial['binding'] as Map)['expected'] as Map).remove(
        'predecessor_job_id',
      );
      expect(
        () =>
            AdminReceiptSuccessorCheckpoint.parse(jsonEncode(partial), f.owner),
        throwsFormatException,
      );
    },
  );

  test(
    'lost v2 approval response recovers only original UUID and never reapproves',
    () async {
      final f = RetryFixture()..lostResponse = true;
      final store = MemoryStore();
      final api = f.sdk;
      final c = controller(f, store);
      final intent = api.prepareApproval(
        request,
        await api.inspectRetry(f.root, f.source, f.approval),
        'Reviewed current stopped predecessor and copy',
      );
      await c.submit(intent);
      expect(c.pending!.isRetiredRetry, isTrue);
      expect(c.canSubmit, isFalse);
      final stored = store.read(f.owner)!;
      c.dispose();
      final restored = controller(f, store);
      addTearDown(restored.dispose);
      expect(store.read(f.owner), stored);
      await restored.recover();
      expect(restored.receipt!.row['request_id'], request);
      expect(restored.pending, isNull);
      expect(store.read(f.owner), isNull);
      expect(
        f.calls.where(
          (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
        ),
        hasLength(1),
      );
      expect(f.calls.last.name, 'admin_get_receipt_successor_retry_request_v2');
      expect(f.calls.last.params, {'p_request_id': request});
    },
  );

  test(
    'not recorded and in progress original lookup retain checkpoint and block retry',
    () async {
      for (final outcome in ['not_recorded', 'in_progress']) {
        final f = RetryFixture()
          ..lostResponse = true
          ..outcome = outcome;
        final store = MemoryStore();
        final c = controller(f, store);
        addTearDown(c.dispose);
        final api = f.sdk;
        await c.submit(
          api.prepareApproval(
            request,
            await api.inspectRetry(f.root, f.source, f.approval),
            'Reviewed original current stopped predecessor',
          ),
        );
        await c.recover();
        await c.recover();
        expect(c.pending!.requestId, request);
        expect(c.canSubmit, isFalse);
        expect(store.read(f.owner), isNotNull);
        expect(
          f.calls.where(
            (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
          ),
          hasLength(1),
        );
      }
    },
  );

  test(
    'backend original-session denial retains original unknown request',
    () async {
      final f = RetryFixture()..lostResponse = true;
      final store = MemoryStore();
      final c = controller(f, store);
      addTearDown(c.dispose);
      final api = f.sdk;
      await c.submit(
        api.prepareApproval(
          request,
          await api.inspectRetry(f.root, f.source, f.approval),
          'Reviewed current retired predecessor and text',
        ),
      );
      f.lookupError = const CollectApiException(
        message: 'Synthetic original session mismatch',
        code: '42501',
      );
      await c.recover();
      expect(c.pending!.requestId, request);
      expect(c.receipt, isNull);
      expect(c.canSubmit, isFalse);
      expect(store.read(f.owner), isNotNull);
    },
  );

  test('storage failure prevents new approval RPC', () async {
    final f = RetryFixture();
    final c = controller(f, MemoryStore()..failWrite = true);
    addTearDown(c.dispose);
    final api = f.sdk;
    await c.submit(
      api.prepareApproval(
        request,
        await api.inspectRetry(f.root, f.source, f.approval),
        'Reviewed safe predecessor and immutable preview',
      ),
    );
    expect(c.storageFailed, isTrue);
    expect(
      f.calls.where(
        (c) => c.name == 'admin_approve_receipt_successor_retry_v2',
      ),
      isEmpty,
    );
  });

  test(
    'late v5 execution loses current session before any retry inspection',
    () async {
      final f = RetryFixture()
        ..executionEntered = Completer<void>()
        ..executionRelease = Completer<void>();
      final future = f.sdk.inspectRetry(f.root, f.source, f.approval);
      await f.executionEntered!.future;
      f.session = (userId: f.session!.userId, sessionId: nextRequest);
      f.executionRelease!.complete();
      await expectLater(future, throwsA(isA<AdminSessionChanged>()));
      expect(f.calls, hasLength(1));
    },
  );

  test(
    'late v2 inspection loses current session and erases approval eligibility',
    () async {
      final f = RetryFixture()
        ..inspectionEntered = Completer<void>()
        ..inspectionRelease = Completer<void>();
      final future = f.sdk.inspectRetry(f.root, f.source, f.approval);
      await f.inspectionEntered!.future;
      f.session = (userId: f.session!.userId, sessionId: nextRequest);
      f.inspectionRelease!.complete();
      await expectLater(future, throwsA(isA<AdminSessionChanged>()));
    },
  );

  test(
    'armed unknown uncertain and unrevoked attempts never reach retry inspection',
    () async {
      for (final producer in [armedUnknownRaw, lateUncertainRaw, unarmedRaw]) {
        final f = RetryFixture();
        final raw = decoded(producer);
        raw['contract_version'] = 5;
        raw['approval_id'] = f.approval;
        raw['primary_receipt_id'] = f.root;
        // Keep the original state/expiry sample internally consistent. This
        // refusal ends before the newer financial inspection is requested.
        f.now = DateTime.parse(raw['checked_at'] as String);
        final route = (raw['execution'] as Map)['route'] as Map;
        route['approval_id'] = f.approval;
        route['primary_receipt_id'] = f.root;
        final archive = (raw['execution'] as Map)['archive'] as Map?;
        if (archive != null) {
          (archive['route'] as Map)['approval_id'] = f.approval;
          (archive['route'] as Map)['primary_receipt_id'] = f.root;
        }
        f.executionOverride = raw;
        await expectLater(
          f.sdk.inspectRetry(f.root, f.source, f.approval),
          throwsA(isA<AdminReceiptSuccessorRejected>()),
        );
        expect(f.calls, hasLength(1));
      }
    },
  );

  test(
    'expired or clock-regressed inspection prevents approval preparation',
    () async {
      final f = RetryFixture();
      final api = f.sdk;
      final inspection = await api.inspectRetry(f.root, f.source, f.approval);
      f.now = inspection.validUntil;
      expect(
        () => api.prepareApproval(
          request,
          inspection,
          'Reviewed old predecessor and outdated copy',
        ),
        throwsFormatException,
      );
      final regressed = RetryFixture();
      regressed.executionOverride = clone(regressed.producerSummary);
      await expectLater(
        regressed.sdk.inspectRetry(
          regressed.root,
          regressed.source,
          regressed.approval,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'v2 lookup cannot substitute old envelope or mismatched retained proof',
    () {
      final receipt = retryObserved('retry-approval-v2');
      final binding = retryBinding(receipt);
      final original = retryObserved('original-request-v2');
      final old = clone(original)
        ..['contract_version'] = 1
        ..['scope'] = 'rw_receipt_successors';
      expect(
        () => AdminReceiptSuccessorLookup.parse(old, binding),
        throwsFormatException,
      );
      final drift = clone(original);
      (drift['result'] as Map)['predecessor_job_id'] = nextRequest;
      expect(
        () => AdminReceiptSuccessorLookup.parse(drift, binding),
        throwsFormatException,
      );
    },
  );

  test(
    'v5 observation parser binds approval cutoff and version to execution',
    () async {
      final f = RetryFixture();
      final sdk = AdminReceiptSuccessorExecutionSdk(
        rpc: f.rpc,
        isCurrent: () => f.current,
        now: () => f.now,
        executionVersion: 5,
      );
      final snapshot = await sdk.inspect(f.approval, f.root);
      final page = await sdk.observations(snapshot);
      expect(page.row['contract_version'], 5);
      expect(page.items, isEmpty);
      expect(f.calls.last.name, 'admin_list_receipt_successor_observations_v5');
      final mixed = Map<String, dynamic>.from(page.row)
        ..['contract_version'] = 4;
      expect(
        () => AdminReceiptSuccessorObservationPage.parse(
          mixed,
          snapshot,
          null,
          20,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminReceiptSuccessorObservationPage.parse(
          retryObserved('actual-child-observations-v5'),
          snapshot,
          null,
          20,
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets('v2 probe applies actual fifteen-second deadline once', (
    tester,
  ) async {
    final f = RetryFixture()
      ..inspectionEntered = Completer<void>()
      ..inspectionRelease = Completer<void>();
    Object? failure;
    final done = f.sdk
        .inspectRetry(f.root, f.source, f.approval)
        .then<void>(
          (_) => fail('An unresolved probe must not authorize a review'),
          onError: (Object error) => failure = error,
        );
    await tester.pump();
    expect(f.inspectionEntered!.isCompleted, isTrue);
    await tester.pump(const Duration(seconds: 15));
    await done;
    expect(failure, isA<TimeoutException>());
    expect(f.calls.map((c) => c.name), [
      'admin_get_receipt_successor_execution_v5',
      'admin_inspect_receipt_successor_retry_v2',
    ]);
    f.inspectionRelease!.complete();
    await tester.pump();
  });
}
