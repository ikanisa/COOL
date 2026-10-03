import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_roster_checkpoint.dart';
import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:collect_app/admin/core/admin_roster_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_roster_fixture.dart';

const _destination = '99890000-0000-4000-8000-000000000102';
const _lookup = '99890000-0000-4000-8000-000000000103';
const _revision = '99890000-0000-4000-8000-000000000104';
const _checkpoint = '99890000-0000-4000-8000-000000000105';
const _etag =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

class _Bookmarks implements RosterBookmarkStore {
  String? value;
  @override
  String? read() => value;
  @override
  void write(String text) {
    value = text;
  }

  @override
  void clear() {
    value = null;
  }
}

class _FreshGateway extends FakeRosterGateway {
  _FreshGateway() {
    body = AdminRosterUpload.pasted('synthetic149 original').body;
    initial = previewFixture(body!);
    originalDraft = jsonEncode({
      'parent_revision_id': rosterRevisionId,
      'rows': [
        {
          'member_name': 'Private recovery member',
          'momo_name': 'PRIVATE RECOVERY MEMBER',
          'momo_number': '+250788989001',
        },
      ],
      'title': 'Private recovery title',
      'reason': 'Private recovery reason',
    });
    proof = jsonEncode({
      'contract_version': 1,
      'root_import_id': rosterImportId,
      'upload_request_id': body!['request_id'],
      'actor_id': rosterActorA,
      'session_id': rosterSessionA,
      'source_kind': 'text',
      'source_sha256': initial['source_sha256'],
      'input_sha256': 'c' * 64,
      'expires_at': initial['expires_at'],
      'source_receipt': initial['source_receipt'],
      'resource_reservation_id': null,
      'decoder_receipt_sha256': null,
      'decoder_build_sha256': null,
    });
  }
  @override
  bool get supportsRecovery => true;
  @override
  String get ownerDigest =>
      rosterTextDigest('collect-roster-owner-v1:$rosterActorA:$rosterSessionB');
  late Map<String, dynamic> initial, ack, branch;
  late String originalDraft, rebasedDraft, proof;
  final calls = <String>[];
  bool loseTransferResponse = false, missingStatus = false;
  Future<Object?> Function(String, Map<String, dynamic>)? overrideRpc;
  Map<String, dynamic> get item => {
    'import_id': rosterImportId,
    'source_sha256': initial['source_sha256'],
    'source_kind': 'text',
    'state': 'interrupted',
    'etag': _etag,
    'created_at': '2026-09-30T12:00:00Z',
    'expires_at': initial['expires_at'],
  };
  @override
  Future<Object?> recoveryRpc(String name, Map<String, dynamic> p) async {
    calls.add(name);
    if (overrideRpc != null) return overrideRpc!(name, p);
    if (name == 'admin_list_interrupted_roster_imports') {
      return {
        'contract_version': 1,
        'ok': true,
        'actor_id': rosterActorA,
        'destination_session_id': rosterSessionB,
        'items': [item],
      };
    }
    if (name == 'admin_inspect_interrupted_roster_import') {
      return {
        'contract_version': 1,
        'ok': true,
        'import_id': rosterImportId,
        'actor_id': rosterActorA,
        'destination_session_id': rosterSessionB,
        'etag': _etag,
        'initial_preview': initial,
        'latest_preview': initial,
        'draft_payload': originalDraft,
        'draft_sha256': rosterTextDigest(originalDraft),
        'expires_at': initial['expires_at'],
      };
    }
    if (name == 'admin_transfer_interrupted_roster_import') {
      rebasedDraft = jsonEncode({
        ...rosterObject(jsonDecode(originalDraft)),
        'parent_revision_id': _revision,
      });
      ack = {
        'contract_version': 1,
        'ok': true,
        'state': 'transferred',
        'request_id': p['p_request_id'],
        'from_import_id': rosterImportId,
        'root_import_id': rosterImportId,
        'to_import_id': _destination,
        'actor_id': rosterActorA,
        'destination_session_id': rosterSessionB,
        'destination_reference_id': _lookup,
        'initial_revision_id': _revision,
        'checkpoint_id': _checkpoint,
        'draft_sha256': rosterTextDigest(rebasedDraft),
        'source_etag': _etag,
        'original_proof_sha256': rosterTextDigest(proof),
        'expires_at': initial['expires_at'],
      };
      branch = {
        ...initial,
        'import_id': _destination,
        'revision_id': _revision,
        'recovery_lineage': {
          'contract_version': 1,
          'transfer_request_id': p['p_request_id'],
          'root_import_id': rosterImportId,
          'from_import_id': rosterImportId,
          'to_import_id': _destination,
          'actor_id': rosterActorA,
          'destination_session_id': rosterSessionB,
          'destination_reference_id': _lookup,
          'initial_revision_id': _revision,
          'original_proof': proof,
          'original_proof_sha256': rosterTextDigest(proof),
        },
      };
      if (loseTransferResponse) throw StateError('synthetic response loss');
      return ack;
    }
    if (name == 'admin_get_roster_transfer_status') {
      return missingStatus
          ? {
              'contract_version': 1,
              'ok': true,
              'state': 'missing',
              'request_id': p['p_request_id'],
            }
          : ack;
    }
    if (name == 'admin_recover_roster_import') {
      return {
        'contract_version': 1,
        'ok': true,
        'upload_request_id': _lookup,
        'import_id': _destination,
        'source_sha256': initial['source_sha256'],
        'state': 'preview_ready',
        'initial_preview': branch,
        'status': {
          'contract_version': 1,
          'ok': true,
          'import_id': _destination,
          'state': 'preview_ready',
          'expires_at': initial['expires_at'],
          'preview': branch,
          'commit': null,
          'error_code': null,
        },
        'requested_intent_id': null,
        'intent': null,
        'draft': {
          'checkpoint_id': _checkpoint,
          'payload_sha256': rosterTextDigest(rebasedDraft),
          'payload': rebasedDraft,
        },
      };
    }
    throw StateError('Unexpected fixture RPC');
  }
}

void main() {
  Future<AdminRosterDraft> inspected(
    _FreshGateway g, {
    _Bookmarks? store,
  }) async {
    final d = AdminRosterDraft(g, bookmarkStore: store);
    await d.listFreshRecovery();
    await d.inspectFreshRecovery(d.interruptedImports.single);
    return d;
  }

  test(
    'lookup/inspection are read-only and transfer requires explicit affirmation',
    () async {
      final g = _FreshGateway(), d = await inspected(_FreshGateway());
      expect(d.preview, isNull);
      expect(d.interruptedInspection, isNotNull);
      await d.transferFreshRecovery();
      expect(d.gateway, (isA<_FreshGateway>()));
      expect((d.gateway as _FreshGateway).calls, [
        'admin_list_interrupted_roster_imports',
        'admin_inspect_interrupted_roster_import',
      ]);
      expect(g.prepares, isEmpty);
      d.dispose();
      g.dispose();
    },
  );
  test(
    'explicit recovery preserves upload proof and resets approval, with references-only bookmark',
    () async {
      final g = _FreshGateway(),
          s = _Bookmarks(),
          d = await inspected(_FreshGateway());
      d.dispose();
      final fresh = await inspected(g, store: s);
      fresh.affirmFreshRecovery(true);
      await fresh.transferFreshRecovery();
      expect(fresh.error, isNull);
      expect(fresh.preview!.importId, _destination);
      expect(fresh.preview!.canSubmit, isFalse);
      expect(fresh.preview!.sourceReceipt.requestId, g.body!['request_id']);
      expect(fresh.preview!.recoveryLineage!.destinationReferenceId, _lookup);
      expect(fresh.affirmed, isFalse);
      expect(fresh.canCommit, isFalse);
      expect(fresh.edited, isTrue);
      expect(fresh.reviewPending, isFalse);
      expect(fresh.commitPending, isFalse);
      expect(fresh.rows.single['member_name'], 'Private recovery member');
      expect(fresh.editorTitle, 'Private recovery title');
      expect(s.value, isNot(contains('Private recovery')));
      expect(s.value, isNot(contains('788989001')));
      expect(g.prepares, isEmpty);
      expect(g.reviews, isEmpty);
      expect(g.commits, isEmpty);
      fresh.dispose();
    },
  );
  test(
    'response loss only permits status read, never implicit transfer retry',
    () async {
      final g = _FreshGateway()..loseTransferResponse = true,
          d = await inspected(_FreshGateway());
      d.dispose();
      final fresh = await inspected(g);
      fresh.affirmFreshRecovery(true);
      await fresh.transferFreshRecovery();
      expect(fresh.transferOutcomePending, isTrue);
      await fresh.transferFreshRecovery();
      expect(
        g.calls.where((c) => c == 'admin_transfer_interrupted_roster_import'),
        hasLength(1),
      );
      await fresh.checkFreshTransferStatus();
      expect(fresh.preview!.importId, _destination);
      expect(fresh.error, isNull);
      expect(
        g.calls.where((c) => c == 'admin_transfer_interrupted_roster_import'),
        hasLength(1),
      );
      fresh.dispose();
    },
  );
  test(
    'missing transfer status cannot adopt or issue a second write',
    () async {
      final g = _FreshGateway()
        ..loseTransferResponse = true
        ..missingStatus = true;
      final d = await inspected(g);
      d.affirmFreshRecovery(true);
      await d.transferFreshRecovery();
      await d.checkFreshTransferStatus();
      expect(d.preview, isNull);
      expect(d.transferOutcomePending, isTrue);
      expect(d.recoveryMessage, contains('No write was repeated'));
      expect(
        g.calls.where((c) => c == 'admin_transfer_interrupted_roster_import'),
        hasLength(1),
      );
      d.dispose();
    },
  );
  test(
    'malformed missing transfer acknowledgements retain pending state without retry',
    () async {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (v) => v['unexpected'] = true,
        (v) => v.remove('ok'),
        (v) => v['request_id'] = _lookup,
      ]) {
        final g = _FreshGateway()..loseTransferResponse = true;
        final d = await inspected(g);
        d.affirmFreshRecovery(true);
        await d.transferFreshRecovery();
        final previousMessage = d.recoveryMessage;
        g.overrideRpc = (name, p) async {
          expect(name, 'admin_get_roster_transfer_status');
          final ack = <String, dynamic>{
            'contract_version': 1,
            'ok': true,
            'state': 'missing',
            'request_id': p['p_request_id'],
          };
          mutate(ack);
          return ack;
        };
        await d.checkFreshTransferStatus();
        expect(d.error, isNotNull);
        expect(d.preview, isNull);
        expect(d.transferOutcomePending, isTrue);
        expect(d.recoveryMessage, previousMessage);
        await d.transferFreshRecovery();
        expect(
          g.calls.where((c) => c == 'admin_transfer_interrupted_roster_import'),
          hasLength(1),
        );
        expect(g.calls, isNot(contains('admin_recover_roster_import')));
        d.dispose();
      }
    },
  );
  test(
    'Auth invalidation clears inspected private rows and prevents late adoption',
    () async {
      final g = _FreshGateway();
      final d = await inspected(g);
      final barrier = Completer<Object?>();
      g.overrideRpc = (name, p) => barrier.future;
      d.affirmFreshRecovery(true);
      final pending = d.transferFreshRecovery();
      g.invalidate();
      barrier.complete({});
      await pending;
      expect(d.invalidated, isTrue);
      expect(d.interruptedInspection, isNull);
      expect(d.selectedInterruption, isNull);
      expect(d.rows, isEmpty);
      d.dispose();
    },
  );
  test(
    'lineage corruption cannot masquerade as an original upload or recovered source',
    () async {
      final g = _FreshGateway();
      final d = await inspected(g);
      d.affirmFreshRecovery(true);
      await d.transferFreshRecovery();
      final source = AdminRosterPreview.fromJson(g.branch);
      expect(
        () => source.validateInitial(
          sourceKind: 'text',
          sourceSha256: source.sourceSha256,
          requestId: source.sourceReceipt.requestId,
          sourceSize: source.sourceReceipt.sourceSize,
          filename: source.sourceReceipt.filename,
          declaredMime: source.sourceReceipt.declaredMime,
        ),
        throwsFormatException,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (v) => v['recovery_lineage']['to_import_id'] = rosterImportId,
        (v) => v['recovery_lineage']['original_proof_sha256'] = '0' * 64,
        (v) => v['source_receipt']['request_id'] = _lookup,
        (v) => v['recovery_lineage']['initial_revision_id'] = rosterRevisionId,
        (v) => v['recovery_lineage']['unexpected'] = true,
      ]) {
        final v = _copy(g.branch);
        mutate(v);
        expect(() => AdminRosterPreview.fromJson(v), throwsFormatException);
      }
      d.dispose();
    },
  );
}
