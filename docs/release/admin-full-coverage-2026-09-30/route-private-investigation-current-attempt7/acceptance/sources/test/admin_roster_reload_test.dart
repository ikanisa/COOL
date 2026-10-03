import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/admin/core/admin_roster_dialog.dart';
import 'package:collect_app/admin/core/admin_roster_checkpoint.dart';
import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:collect_app/admin/core/admin_roster_models.dart';
import 'support/admin_roster_fixture.dart';

class MemoryBookmarks implements RosterBookmarkStore {
  String? value;
  bool fail = false;
  @override
  String? read() {
    if (fail) throw StateError('private browser error');
    return value;
  }

  @override
  void write(String text) {
    if (fail) throw StateError('private browser error');
    value = text;
  }

  @override
  void clear() {
    if (fail) throw StateError('private browser error');
    value = null;
  }
}

class RecoveryGateway extends FakeRosterGateway {
  @override
  bool get supportsRecovery => true;
  @override
  String get ownerDigest => rosterTextDigest('test-owner-A');
  final calls = <String>[];
  Map<String, dynamic>? draftPayload;
  String? checkpoint, draftText, draftHash;
  final intents = <String, Map<String, dynamic>>{};
  final results = <String, Object?>{};
  Future<Object?> Function(String, Map<String, dynamic>)? overrideRpc;
  String? phase;
  @override
  Future<Object?> recoveryRpc(String name, Map<String, dynamic> p) async {
    calls.add(name);
    if (overrideRpc != null) return overrideRpc!(name, p);
    if (name == 'admin_save_roster_import_draft') {
      if (p['p_previous_checkpoint_id'] != checkpoint) {
        throw const AdminRosterRequestError('roster_draft_superseded');
      }
      checkpoint = p['p_checkpoint_id'] as String;
      draftText = p['p_payload'] as String;
      draftHash = p['p_payload_sha256'] as String;
      draftPayload = decodeRosterRecoveryPayload(
        draftText!,
        draftHash!,
        kind: 'draft',
      );
      return {
        'contract_version': 1,
        'ok': true,
        'import_id': rosterImportId,
        'checkpoint_id': checkpoint,
        'payload_sha256': draftHash,
        'expires_at': latest!['expires_at'],
      };
    }
    if (name == 'admin_stage_roster_import_intent') {
      intents[p['p_request_id'] as String] = {...p};
      return {
        'contract_version': 1,
        'ok': true,
        'import_id': rosterImportId,
        'request_id': p['p_request_id'],
        'kind': p['p_kind'],
        'payload_sha256': p['p_payload_sha256'],
        'expires_at': latest!['expires_at'],
      };
    }
    if (name == 'admin_execute_roster_import_intent') {
      final i = intents[p['p_request_id']]!;
      final args = decodeRosterRecoveryPayload(
        i['p_payload'] as String,
        i['p_payload_sha256'] as String,
        kind: i['p_kind'] as String,
      );
      final result = i['p_kind'] == 'review'
          ? await review(args)
          : await commit(args);
      results[p['p_request_id'] as String] = result;
      return {
        'contract_version': 1,
        'ok': true,
        'request_id': p['p_request_id'],
        'import_id': rosterImportId,
        'kind': i['p_kind'],
        'payload_sha256': p['p_payload_sha256'],
        'result': result,
      };
    }
    if (name == 'admin_recover_roster_import') {
      final i = intents[p['p_pending_request_id']];
      final outcome = results[p['p_pending_request_id']];
      final committed = outcome is Map && outcome['mode'] != null
          ? Map<String, dynamic>.from(outcome)
          : null;
      final initial = body == null ? null : previewFixture(body!, count: count);
      final status = body == null
          ? null
          : {
              'contract_version': 1,
              'ok': true,
              'import_id': rosterImportId,
              'state': committed != null
                  ? 'committed'
                  : phase ?? 'preview_ready',
              'expires_at': initial!['expires_at'],
              'preview': phase == 'awaiting_preview' || phase == 'failed'
                  ? null
                  : {...latest!, if (committed != null) 'can_submit': false},
              'commit': committed,
              'error_code': null,
            };
      return {
        'contract_version': 1,
        'ok': true,
        'upload_request_id': p['p_upload_request_id'],
        'import_id': body == null ? null : rosterImportId,
        'source_sha256': body == null ? null : initial!['source_sha256'],
        'state': body == null
            ? 'missing_source'
            : committed != null
            ? 'committed'
            : phase ?? 'preview_ready',
        'initial_preview':
            phase == 'expired' ||
                phase == 'awaiting_preview' ||
                phase == 'failed'
            ? null
            : initial,
        'status': phase == 'expired' ? null : status,
        'requested_intent_id': p['p_pending_request_id'],
        'intent': i == null
            ? null
            : {
                'request_id': i['p_request_id'],
                'kind': i['p_kind'],
                'payload_sha256': i['p_payload_sha256'],
                'payload': i['p_payload'],
                'result': outcome,
                'expired': false,
              },
        'draft': draftText == null
            ? null
            : {
                'checkpoint_id': checkpoint,
                'payload_sha256': draftHash,
                'payload': draftText,
              },
      };
    }
    throw StateError('unexpected RPC');
  }
}

void main() {
  Future<AdminRosterDraft> prepared(
    RecoveryGateway g,
    MemoryBookmarks store,
  ) async {
    final d = AdminRosterDraft(
      g,
      collectionId: rosterCollectionId,
      bookmarkStore: store,
    );
    await d.prepare(() async => AdminRosterUpload.pasted('synthetic roster'));
    return d;
  }

  RecoveryGateway reloadGateway(RecoveryGateway old) => RecoveryGateway()
    ..body = old.body
    ..latest = old.latest
    ..draftText = old.draftText
    ..draftHash = old.draftHash
    ..checkpoint = old.checkpoint
    ..intents.addAll(old.intents)
    ..results.addAll(old.results)
    ..phase = old.phase;
  test(
    'bookmark serialized schema contains only references/digests; no private values',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.edit(0, 'member_name', 'Sensitive Alice');
      d.setEditorMetadata(title: 'Secret Title', reason: 'Sensitive reason');
      await d.saveRecoveryDraft();
      final persisted = rosterObject(jsonDecode(s.value!));
      expect(persisted.keys.toSet(), {
        'version',
        'owner_digest',
        'upload_request_id',
        'source_sha256',
        'collection_id',
        'import_id',
        'checkpoint_id',
        'pending_request_id',
        'pending_sha256',
      });
      for (final secret in [
        'Sensitive Alice',
        'Secret Title',
        'Sensitive reason',
        'synthetic roster',
        'access_token',
        'refresh_token',
        'momo_number',
      ]) {
        expect(s.value, isNot(contains(secret)));
      }
      expect(g.draftPayload!['reason'], 'Sensitive reason');
      expect(d.hasUnsavedRecoveryChanges, false);
      d.dispose();
    },
  );
  test(
    'reload is read-only until explicit recovery; saved editor values restored without affirmation',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.edit(0, 'member_name', 'Saved Alice');
      d.setEditorMetadata(title: 'Saved title', reason: 'Saved reason');
      await d.saveRecoveryDraft();
      d.edit(0, 'member_name', 'Unsaved Alice');
      d.dispose();
      final next = reloadGateway(g),
          r = AdminRosterDraft(
            next,
            collectionId: rosterCollectionId,
            bookmarkStore: s,
          );
      expect(next.calls, isEmpty);
      expect(r.reloadAvailable, true);
      expect(r.canEdit, false);
      await r.recoverReload();
      expect(next.calls, ['admin_recover_roster_import']);
      expect(r.rows.first['member_name'], 'Saved Alice');
      expect(r.editorTitle, 'Saved title');
      expect(r.editorReason, 'Saved reason');
      expect(r.affirmed, false);
      expect(r.edited, true);
      expect(r.recoveryMessage, contains('Later unsaved'));
      r.dispose();
    },
  );
  test(
    'reload without saved editor draft restores acknowledged rows and warns about unsaved edits',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.edit(0, 'member_name', 'Lost Alice');
      d.dispose();
      final r = AdminRosterDraft(
        reloadGateway(g),
        collectionId: rosterCollectionId,
        bookmarkStore: s,
      );
      await r.recoverReload();
      expect(r.rows.first['member_name'], 'Member 1');
      expect(r.recoveryMessage, contains('Unsaved rows'));
      r.dispose();
    },
  );
  test(
    'staged commit recovered after response loss requires fresh human affirmation; no automatic writes',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      await d.saveReview('Reviewed all source rows');
      d.affirm(true);
      g.onCommit = (_) async => throw TimeoutException('lost before commit');
      await d.commit(title: '', reason: 'Reviewed all source identities');
      expect(g.intents.length, 2);
      d.dispose();
      final next = reloadGateway(g),
          r = AdminRosterDraft(
            next,
            collectionId: rosterCollectionId,
            bookmarkStore: s,
          );
      await r.recoverReload();
      expect(next.calls, ['admin_recover_roster_import']);
      expect(next.commits, isEmpty);
      expect(r.commitPending, true);
      expect(r.canRetryCommit, false);
      expect(r.canReaffirm, true);
      await r.commit(title: 'other', reason: 'other');
      expect(next.commits, isEmpty);
      r.affirm(true);
      final result = await r.commit(title: 'other', reason: 'other');
      expect(result, isNotNull);
      expect(next.commits.single, g.commits.single);
      r.dispose();
    },
  );
  test(
    'lost successful commit acknowledgement recovered with exact matching request and no write',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      await d.saveReview('Reviewed every row');
      d.affirm(true);
      final result = await d.commit(
        title: '',
        reason: 'Reviewed source identities',
      );
      expect(result, isNotNull);
      d.dispose();
      final next = reloadGateway(g),
          r = AdminRosterDraft(
            next,
            collectionId: rosterCollectionId,
            bookmarkStore: s,
          );
      final ack = await r.recoverReload();
      expect(ack!.collectionId, rosterCollectionId);
      expect(next.commits, isEmpty);
      expect(next.calls, ['admin_recover_roster_import']);
      r.dispose();
    },
  );
  test(
    'staged review recovery executes same immutable request only on explicit review',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      g.onReview = (_) async => throw TimeoutException('lost');
      await d.saveReview('Reviewed every row');
      d.dispose();
      final next = reloadGateway(g),
          r = AdminRosterDraft(
            next,
            collectionId: rosterCollectionId,
            bookmarkStore: s,
          );
      await r.recoverReload();
      expect(next.reviews, isEmpty);
      expect(r.reviewPending, true);
      await r.saveReview('Changed reason ignored');
      expect(next.reviews.single, g.reviews.single);
      r.dispose();
    },
  );
  test(
    'missing source cannot reconstruct unsent bytes and never starts extraction',
    () async {
      final g = RecoveryGateway(), s = MemoryBookmarks();
      g.onPrepare = (_) async => throw TimeoutException('unsent');
      final d = await prepared(g, s);
      d.dispose();
      final next = RecoveryGateway(),
          r = AdminRosterDraft(
            next,
            collectionId: rosterCollectionId,
            bookmarkStore: s,
          );
      await r.recoverReload();
      expect(r.preview, isNull);
      expect(r.recoveryMessage, contains('reattach the original source'));
      expect(next.prepares, isEmpty);
      expect(r.canEdit, false);
      r.dispose();
    },
  );
  for (final phase in ['awaiting_preview', 'failed', 'expired']) {
    test('recovery $phase never opens editor or repeats extraction', () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.dispose();
      final next = reloadGateway(g)..phase = phase;
      final r = AdminRosterDraft(
        next,
        collectionId: rosterCollectionId,
        bookmarkStore: s,
      );
      await r.recoverReload();
      expect(r.preview, isNull);
      expect(r.canSaveReview, false);
      expect(next.prepares, isEmpty);
      expect(next.calls, ['admin_recover_roster_import']);
      r.dispose();
    });
  }
  test(
    'different owner digest rejects browser reference and does not call server',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.dispose();
      final m = rosterObject(jsonDecode(s.value!))
        ..['owner_digest'] = rosterTextDigest('another session');
      s.value = jsonEncode(m);
      final r = AdminRosterDraft(
        RecoveryGateway(),
        collectionId: rosterCollectionId,
        bookmarkStore: s,
      );
      expect(r.reloadAvailable, false);
      expect(s.value, isNull);
      expect(r.storageWarning, isNotNull);
      r.dispose();
    },
  );
  test(
    'session invalidation clears reference and private values permanently through A B A',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.edit(0, 'member_name', 'Private Alice');
      g.invalidate();
      g.current = true;
      expect(d.rows, isEmpty);
      expect(s.value, isNull);
      expect(d.invalidated, true);
      await d.recoverReload();
      expect(g.calls, isEmpty);
      d.dispose();
    },
  );
  test(
    'revocation during recovery clears reference, result and private editor values',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.dispose();
      final next = reloadGateway(g)
        ..overrideRpc = (_, _) async =>
            throw const AdminRosterRequestError('roster_feature_disabled');
      final r = AdminRosterDraft(
        next,
        collectionId: rosterCollectionId,
        bookmarkStore: s,
      );
      await r.recoverReload();
      expect(r.invalidated, true);
      expect(s.value, isNull);
      expect(r.rows, isEmpty);
      r.dispose();
    },
  );
  test(
    'storage failure is redacted and does not claim reload durability',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks()..fail = true,
          d = await prepared(g, s);
      expect(d.preview, isNotNull);
      expect(d.storageWarning, contains('could not save'));
      expect(d.storageWarning, isNot(contains('private browser error')));
      d.dispose();
    },
  );
  test('stale bookmark source digest is rejected without a write', () async {
    final g = RecoveryGateway(),
        s = MemoryBookmarks(),
        d = await prepared(g, s);
    d.dispose();
    final m = rosterObject(jsonDecode(s.value!))..['source_sha256'] = 'f' * 64;
    s.value = jsonEncode(m);
    final next = reloadGateway(g),
        r = AdminRosterDraft(
          next,
          collectionId: rosterCollectionId,
          bookmarkStore: s,
        );
    await r.recoverReload();
    expect(r.preview, isNull);
    expect(next.calls, ['admin_recover_roster_import']);
    r.dispose();
  });
  test('incorrect stage ACK must not execute or show review success', () async {
    final g = RecoveryGateway(),
        s = MemoryBookmarks(),
        d = await prepared(g, s);
    g.overrideRpc = (name, p) async => {
      'contract_version': 1,
      'ok': true,
      'import_id': rosterImportId,
      'request_id': rosterActorB,
      'kind': 'review',
      'payload_sha256': p['p_payload_sha256'],
      'expires_at': g.latest!['expires_at'],
    };
    await d.saveReview('Reviewed every row');
    expect(g.calls, ['admin_stage_roster_import_intent']);
    expect(d.preview!.isHumanReview, false);
    d.dispose();
  });
  test(
    'exact UTF8 serialization hash and bounds reject tampered draft payload',
    () {
      final text = jsonEncode({
        'parent_revision_id': rosterRevisionId,
        'rows': [
          {
            'member_name': 'Alice',
            'momo_name': 'ALICE',
            'momo_number': '0788100000',
          },
        ],
        'title': '',
        'reason': '',
      });
      expect(
        decodeRosterRecoveryPayload(
          text,
          rosterTextDigest(text),
          kind: 'draft',
        )['title'],
        '',
      );
      expect(
        () => decodeRosterRecoveryPayload(
          '$text ',
          rosterTextDigest(text),
          kind: 'draft',
        ),
        throwsFormatException,
      );
      expect(
        () => decodeRosterRecoveryPayload(
          text,
          rosterTextDigest(text),
          kind: 'review',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'bookmark rejects private extra fields, malformed IDs, unmatched pending digest',
    () {
      final base = RosterBookmark(
        ownerDigest: rosterTextDigest('test-owner-A'),
        uploadRequestId: rosterActorA,
        sourceSha256: 'a' * 64,
      ).toJson();
      for (final altered in [
        {...base, 'rows': []},
        {...base, 'import_id': 'wrong'},
        {...base, 'pending_request_id': rosterActorA},
      ]) {
        expect(
          () => RosterBookmark.parse(
            jsonEncode(altered),
            base['owner_digest'] as String,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'unknown saved editor ACK retries the same checkpoint and exact immutable bytes',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.setEditorMetadata(
        title: 'Original private title',
        reason: 'Original private reason',
      );
      final sent = <Map<String, dynamic>>[];
      g.overrideRpc = (name, p) async {
        sent.add({...p});
        if (sent.length == 1) throw TimeoutException('lost draft ACK');
        return {
          'contract_version': 1,
          'ok': true,
          'import_id': rosterImportId,
          'checkpoint_id': p['p_checkpoint_id'],
          'payload_sha256': p['p_payload_sha256'],
          'expires_at': g.latest!['expires_at'],
        };
      };
      await d.saveRecoveryDraft();
      expect(d.canEdit, false);
      expect(d.canSaveRecoveryDraft, true);
      d.setEditorMetadata(title: 'Rejected changed title');
      await d.saveRecoveryDraft();
      expect(sent[1], sent[0]);
      expect(d.canEdit, true);
      expect(d.hasUnsavedRecoveryChanges, false);
      d.dispose();
    },
  );
  test(
    'checkpoint conflict retains unsaved values until explicit recovery adopts latest server draft',
    () async {
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          d = await prepared(g, s);
      d.setEditorMetadata(title: 'Server draft');
      await d.saveRecoveryDraft();
      g.checkpoint = rosterActorB;
      d.setEditorMetadata(title: 'Local unsaved title');
      await d.saveRecoveryDraft();
      expect(d.errorCode, 'roster_draft_superseded');
      expect(d.editorTitle, 'Local unsaved title');
      await d.recoverReload();
      expect(d.canEdit, true);
      expect(d.editorTitle, 'Server draft');
      d.dispose();
    },
  );
  testWidgets(
    'operator reload controls restore server draft; enlarged compact UI retains explicit recovery actions',
    (tester) async {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final g = RecoveryGateway(),
          s = MemoryBookmarks(),
          original = await prepared(g, s);
      original.setEditorMetadata(reason: 'Saved private operator reason');
      await original.saveRecoveryDraft();
      original.dispose();
      final next = reloadGateway(g),
          draft = AdminRosterDraft(
            next,
            collectionId: rosterCollectionId,
            bookmarkStore: s,
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: CollectTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: AdminRosterImportDialog(draft: draft)),
        ),
      );
      expect(next.calls, isEmpty);
      expect(find.text('Check recovery for this sign-in'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('roster-recover-reload')),
      );
      await tester.tap(find.byKey(const Key('roster-recover-reload')));
      await tester.pumpAndSettle();
      expect(next.calls, ['admin_recover_roster_import']);
      expect(draft.affirmed, false);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('roster-reason')))
            .controller!
            .text,
        'Saved private operator reason',
      );
      await tester.ensureVisible(find.byKey(const Key('roster-save-recovery')));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(
          ValueKey('roster-${draft.preview!.revisionId}-0-member_name'),
        ),
      );
      await tester.enterText(
        find.byKey(
          ValueKey('roster-${draft.preview!.revisionId}-0-member_name'),
        ),
        'Unsaved operator Alice',
      );
      await tester.pump();
      expect(find.textContaining('Unsaved recovery changes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  const sqlPath = String.fromEnvironment('ROSTER_RELOAD_SQL_RECEIPTS');
  test(
    'actual rollback SQL144 receipts decode staged and completed recovery exactly',
    () {
      final lines = File(sqlPath)
          .readAsLinesSync()
          .where((line) => line.startsWith('ROSTER_RELOAD_RECEIPT_JSON|'))
          .toList();
      expect(lines, hasLength(2));
      for (final line in lines) {
        final data = rosterObject(
          jsonDecode(line.substring('ROSTER_RELOAD_RECEIPT_JSON|'.length)),
        );
        final initial = AdminRosterPreview.fromJson(
          rosterObject(data['initial_preview']),
        );
        final commit = rosterObject(data['commit_request']);
        for (final key in ['recovery_before', 'recovery_after']) {
          final recovered = AdminRosterRecovery.fromJson(
            rosterObject(data[key]),
            uploadRequestId: initial.sourceReceipt.requestId,
            sourceSha256: initial.sourceSha256,
            importId: initial.importId,
            pendingRequestId: commit['p_request_id'] as String,
            pendingSha256: rosterTextDigest(data['commit_payload'] as String),
          );
          expect(recovered.intent, commit);
          expect(recovered.initial!.sourceSha256, initial.sourceSha256);
          expect(
            recovered.state,
            key == 'recovery_before' ? 'preview_ready' : 'committed',
          );
        }
      }
    },
    skip: sqlPath.isEmpty
        ? 'Requires root-executed rollback-only144 fixture output.'
        : false,
  );
}
