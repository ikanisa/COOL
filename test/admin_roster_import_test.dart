import 'support/recorded_auth_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:collect_app/admin/core/admin_roster_models.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'support/admin_roster_fixture.dart';

Future<void> installRosterSession(
  CollectCloudflareClient client,
  String nonce,
) async {
  final token =
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': rosterActorA, 'session_id': rosterSessionA, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.$nonce';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'refresh_token': 'synthetic',
      'token_type': 'bearer',
      'user': {
        'id': rosterActorA,
        'aud': 'authenticated',
        'app_metadata': {},
        'user_metadata': {},
        'created_at': '2026-09-30T00:00:00Z',
      },
    }),
  );
}

class StatusRosterGateway extends FakeRosterGateway {
  final reads = <String>[];
  Future<Object?> Function(String)? onRead;
  Map<String, dynamic> status({Map<String, dynamic>? commit}) => {
    'contract_version': 1,
    'ok': true,
    'import_id': rosterImportId,
    'state': commit == null ? 'preview_ready' : 'committed',
    'expires_at': latest!['expires_at'],
    'preview': {...latest!, if (commit != null) 'can_submit': false},
    'commit': commit,
    'error_code': null,
  };
  @override
  Future<Object?> read(String importId) async {
    reads.add(importId);
    return onRead != null ? onRead!(importId) : status();
  }
}

void main() {
  const sqlReceipts = String.fromEnvironment('ROSTER_SQL_RECEIPTS');
  test(
    'actual SQL deterministic and AI status receipts bind their source, revision and commit',
    () {
      final lines = File(sqlReceipts)
          .readAsLinesSync()
          .where((line) => line.startsWith('ROSTER_RECEIPT_JSON|'))
          .toList();
      expect(lines, hasLength(2));
      for (final line in lines) {
        final data = rosterObject(
          jsonDecode(line.substring('ROSTER_RECEIPT_JSON|'.length)),
        );
        final source = AdminRosterPreview.fromJson(
          rosterObject(data['initial_preview']),
        );
        final current = AdminRosterPreview.fromJson(
          rosterObject(data['reviewed_preview']),
        );
        final status = AdminRosterStatus.fromJson(
          rosterObject(data['read']),
          source: source,
          current: current,
        );
        final commit = AdminRosterCommit.fromJson(
          status.commit!,
          request: rosterObject(data['commit_request']),
          expectedCount: current.rowCount,
        );
        expect(status.state, 'committed');
        expect(commit.rosterCount, current.rowCount);
      }
    },
    skip: sqlReceipts.isEmpty
        ? 'Requires root-executed rollback-only SQL receipt output.'
        : false,
  );
  Future<AdminRosterDraft> reviewed(StatusRosterGateway gateway) async {
    final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
    await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
    await draft.saveReview('Reviewed every source row');
    draft.affirm(true);
    return draft;
  }

  test(
    'lost commit is recovered from matching server receipt without a second write',
    () async {
      final gateway = StatusRosterGateway();
      final draft = await reviewed(gateway);
      gateway.onCommit = (_) async => throw TimeoutException('lost');
      await draft.commit(title: '', reason: 'Reviewed source rows');
      gateway.onRead = (_) async =>
          gateway.status(commit: commitFixture(gateway.commits.single));
      final result = await draft.commit(title: 'Ignored', reason: 'Ignored');
      expect(result!.collectionId, rosterCollectionId);
      expect(gateway.commits, hasLength(1));
      expect(gateway.reads, [rosterImportId]);
      expect(draft.canRetryCommit, false);
      draft.dispose();
    },
  );

  test(
    'a consumed import with another request receipt is terminal, never fallback success',
    () async {
      final gateway = StatusRosterGateway();
      final draft = await reviewed(gateway);
      gateway.onCommit = (_) async =>
          throw const AdminRosterRequestError('roster_import_committed');
      await draft.commit(title: '', reason: 'Reviewed source rows');
      gateway.onRead = (_) async => gateway.status(
        commit: {
          ...commitFixture(gateway.commits.single),
          'request_id': rosterActorB,
        },
      );
      expect(await draft.recoverStatus(), isNull);
      expect(draft.error, contains('submitted by another request'));
      expect(draft.canRetryCommit, false);
      await draft.commit(title: '', reason: 'Reviewed source rows');
      expect(gateway.commits, hasLength(1));
      draft.dispose();
    },
  );

  for (final (field, value) in <(String, Object?)>[
    ('import_id', rosterActorB),
    ('state', 'awaiting_preview'),
    ('expires_at', '2026-10-01T12:00:00'),
    ('commit', {}),
    ('error_code', 'roster_extraction_failed'),
  ]) {
    test('status $field mismatch keeps uncertain commit locked', () async {
      final gateway = StatusRosterGateway();
      final draft = await reviewed(gateway);
      gateway.onCommit = (_) async => null;
      await draft.commit(title: '', reason: 'Reviewed source rows');
      gateway.onRead = (_) async => {...gateway.status(), field: value};
      expect(await draft.recoverStatus(), isNull);
      expect(draft.statusRequired, true);
      expect(draft.canRetryCommit, false);
      expect(gateway.commits, hasLength(1));
      draft.dispose();
    });
  }

  test(
    'status cannot substitute source lineage or a mismatched commit acknowledgement',
    () async {
      final gateway = StatusRosterGateway();
      final draft = await reviewed(gateway);
      gateway.onCommit = (_) async => null;
      await draft.commit(title: '', reason: 'Reviewed source rows');
      gateway.onRead = (_) async => {
        ...gateway.status(),
        'preview': {...gateway.latest!, 'source_sha256': 'f' * 64},
      };
      expect(await draft.recoverStatus(), isNull);
      expect(draft.statusRequired, true);
      gateway.onRead = (_) async => gateway.status(
        commit: {...commitFixture(gateway.commits.single), 'roster_count': 1},
      );
      expect(await draft.recoverStatus(), isNull);
      expect(draft.statusRequired, true);
      expect(draft.canRetryCommit, false);
      draft.dispose();
    },
  );

  test(
    'session change during status recovery hides private state and suppresses acknowledgement',
    () async {
      final gateway = StatusRosterGateway();
      final draft = await reviewed(gateway);
      gateway.onCommit = (_) async => null;
      await draft.commit(title: '', reason: 'Reviewed source rows');
      final response = Completer<Object?>();
      gateway.onRead = (_) => response.future;
      final pending = draft.recoverStatus();
      gateway.invalidate();
      response.complete(
        gateway.status(commit: commitFixture(gateway.commits.single)),
      );
      expect(await pending, isNull);
      expect(draft.invalidated, true);
      expect(draft.rows, isEmpty);
      expect(draft.preview, isNull);
      draft.dispose();
    },
  );

  for (final code in [
    'roster_revision_limit',
    'roster_request_conflict',
    'roster_revision_superseded',
  ]) {
    test(
      '$code stops review writes and checks status without replacing the pending request',
      () async {
        final gateway = StatusRosterGateway();
        final draft = AdminRosterDraft(gateway);
        await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
        final source = draft.initialPreview;
        gateway.onReview = (_) async => throw AdminRosterRequestError(code);
        await draft.saveReview('Reviewed source rows');
        await draft.saveReview('Changed source rows');
        expect(gateway.reviews, hasLength(1));
        expect(draft.statusRequired, true);
        await draft.recoverStatus();
        expect(gateway.reads, [rosterImportId]);
        expect(draft.canSaveReview, false);
        expect(draft.reviewPending, true);
        expect(draft.initialPreview, same(source));
        expect(draft.error, contains('no completed submission'));
        draft.dispose();
      },
    );
  }

  for (final code in [
    'roster_actor_unavailable',
    'roster_session_required',
    'roster_feature_disabled',
    'roster_import_unavailable',
  ]) {
    test('$code clears PII and prevents every further draft action', () async {
      final gateway = StatusRosterGateway();
      final draft = await reviewed(gateway);
      gateway.onCommit = (_) async => throw AdminRosterRequestError(code);
      await draft.commit(title: '', reason: 'Reviewed source rows');
      expect(draft.invalidated, true);
      expect(draft.errorCode, code);
      expect(draft.error, contains('cleared'));
      expect(draft.rows, isEmpty);
      expect(draft.initialPreview, isNull);
      expect(draft.commitPending, false);
      await draft.prepare(() async => AdminRosterUpload.pasted('Never send'));
      await draft.recoverStatus();
      expect(gateway.prepares, hasLength(1));
      expect(gateway.reads, isEmpty);
      draft.dispose();
    });
  }

  test(
    'upload request conflict never blindly repeats or changes its request ID',
    () async {
      final gateway = StatusRosterGateway();
      final draft = AdminRosterDraft(gateway);
      gateway.onPrepare = (_) async =>
          throw const AdminRosterRequestError('roster_request_conflict');
      await draft.prepare(
        () async => AdminRosterUpload.pasted('Original bytes'),
      );
      await draft.prepare(
        () async => AdminRosterUpload.pasted('Different bytes'),
      );
      expect(gateway.prepares, hasLength(1));
      expect(draft.sourceLocked, true);
      expect(draft.terminalUploadFailure, true);
      expect(
        draft.canCheckStatus,
        false,
      ); // Current API requires a received import ID.
      draft.dispose();
    },
  );

  test(
    'real gateway status read pins refreshed same-session token and maps SQL denial safely',
    () async {
      final requests = <http.Request>[];
      final client = recordedFixtureClient(
        'https://synthetic.invalid',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({'message': 'roster_feature_disabled', 'code': '55000'}),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await installRosterSession(client, 'initial');
      final gateway = CollectAdminRosterGateway(client);
      await installRosterSession(client, 'refreshed');
      final token = client.auth.currentSession!.accessToken;
      await expectLater(
        gateway.read(rosterImportId),
        throwsA(
          isA<AdminRosterRequestError>().having(
            (e) => e.code,
            'safe code',
            'roster_feature_disabled',
          ),
        ),
      );
      expect(requests.single.url.path, '/v1/rpc/admin_get_roster_import');
      expect(jsonDecode(requests.single.body), {'p_import_id': rosterImportId});
      expect(requests.single.headers['Authorization'], 'Bearer $token');
      gateway.dispose();
      await client.dispose();
    },
  );
  test(
    'real signed-in A to B to A session events invalidate an in-flight status read permanently',
    () async {
      final waiting = Completer<http.Response>();
      var nextSession = rosterSessionB;
      final client = recordedFixtureClient(
        'https://synthetic.invalid',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/verify')) {
            final jwt =
                'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': rosterActorA, 'session_id': nextSession, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.verified';
            return http.Response(
              jsonEncode({
                'access_token': jwt,
                'refresh_token': 'synthetic',
                'token_type': 'bearer',
                'user': {
                  'id': rosterActorA,
                  'aud': 'authenticated',
                  'app_metadata': {},
                  'user_metadata': {},
                  'created_at': '2026-09-30T00:00:00Z',
                },
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          final response = await waiting.future;
          return http.Response(
            response.body,
            response.statusCode,
            request: request,
            headers: response.headers,
          );
        }),
      );
      await installRosterSession(client, 'initial');
      final gateway = CollectAdminRosterGateway(client);
      final pending = gateway.read(rosterImportId);
      await Future<void>.delayed(Duration.zero);
      await installRecordedAuthFixture(
        client,
        type: CollectOtpType.sms,
        phone: '+250788100000',
        token: '123456',
      );
      nextSession = rosterSessionA;
      await installRecordedAuthFixture(
        client,
        type: CollectOtpType.sms,
        phone: '+250788100000',
        token: '123456',
      );
      expect(gateway.isCurrent, false);
      waiting.complete(
        http.Response('{}', 200, headers: {'content-type': 'application/json'}),
      );
      await expectLater(pending, throwsStateError);
      await expectLater(gateway.read(rosterImportId), throwsStateError);
      gateway.dispose();
      await client.dispose();
    },
  );
  test(
    'same-session refresh during upload succeeds and does not change the in-flight Authorization',
    () async {
      final waiting = Completer<http.Response>();
      final requests = <http.Request>[];
      final client = recordedFixtureClient(
        'https://synthetic.invalid',
        httpClient: MockClient((request) {
          requests.add(request);
          return waiting.future.then(
            (response) => http.Response.bytes(
              response.bodyBytes,
              response.statusCode,
              headers: response.headers,
              request: request,
            ),
          );
        }),
      );
      await installRosterSession(client, 'initial');
      final gateway = CollectAdminRosterGateway(client);
      await installRosterSession(client, 'before-upload');
      final dispatchToken = client.auth.currentSession!.accessToken;
      final upload = AdminRosterUpload.pasted('Roster');
      final pending = gateway.prepare(upload.body);
      await Future<void>.delayed(Duration.zero);
      await installRosterSession(client, 'during-upload');
      waiting.complete(
        http.Response(
          jsonEncode(previewFixture(upload.body)),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(await pending, isA<Map<String, dynamic>>());
      expect(gateway.isCurrent, true);
      expect(requests.single.headers['Authorization'], 'Bearer $dispatchToken');
      expect(requests.single.url.path, '/v1/functions/prepare-roster-import');
      gateway.dispose();
      await client.dispose();
    },
  );
  for (final code in [
    'roster_extraction_timeout',
    'roster_extraction_refused',
    'roster_extraction_incomplete',
    'roster_provider_response_invalid',
    'roster_provider_response_too_large',
    'roster_extraction_unavailable',
  ]) {
    test(
      'terminal $code calls for explicit new upload, keeps old draft',
      () async {
        final gateway = FakeRosterGateway();
        final draft = AdminRosterDraft(gateway);
        gateway.onPrepare = (_) async => throw AdminRosterRequestError(code);
        await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
        expect(draft.error, contains('start a new upload'));
        expect(draft.sourceLocked, true);
        expect(draft.terminalUploadFailure, true);
        expect(gateway.prepares.length, 1);
        draft.dispose();
      },
    );
  }

  test(
    'uploads preserve original CSV/TXT/AI bytes and distinguish pasted text',
    () {
      for (final ext in ['csv', 'txt', 'pdf', 'png', 'jpg', 'webp']) {
        final bytes = Uint8List.fromList(
          utf8.encode('Original\r\nsource bytes $ext'),
        );
        final upload = AdminRosterUpload.fromBytes(
          'Roster.$ext',
          ext,
          bytes,
          aiConsent: true,
        );
        expect(base64Decode(upload.body['content_base64'] as String), bytes);
        expect(upload.body.containsKey('content'), false);
        expect(upload.body['contract_version'], 1);
        expect(upload.body.containsKey('derived_content'), false);
        expect(
          upload.body['ai_consent'],
          const ['csv', 'txt'].contains(ext) ? null : true,
        );
      }
      final pasted = AdminRosterUpload.pasted(' Member,MoMo,Number\n');
      expect(pasted.body['source_type'], 'text');
      expect(pasted.body['content'], ' Member,MoMo,Number\n');
      expect(pasted.body.containsKey('content_base64'), false);
    },
  );
  test(
    'XLSX transmits workbook bytes and separately identified TSV after preflight',
    () {
      final workbook = Excel.createExcel();
      workbook['Sheet1'].appendRow([
        TextCellValue('Member name'),
        TextCellValue('MoMo name'),
        TextCellValue('MoMo number'),
      ]);
      workbook['Sheet1'].appendRow([
        TextCellValue('Alice One'),
        TextCellValue('ALICE ONE'),
        TextCellValue('0788100000'),
      ]);
      final bytes = Uint8List.fromList(workbook.encode()!);
      final upload = AdminRosterUpload.fromBytes(
        'Roster.xlsx',
        'xlsx',
        bytes,
        aiConsent: false,
      );
      expect(base64Decode(upload.body['content_base64'] as String), bytes);
      expect(upload.body['source_type'], 'xlsx');
      expect(
        upload.body['derived_content'],
        contains('Alice One\tALICE ONE\t0788100000'),
      );
      expect(upload.body.containsKey('content'), false);
      workbook['Sheet1'].cell(CellIndex.indexByString('A2')).value =
          const FormulaCellValue('1+1');
      expect(
        () => AdminRosterUpload.fromBytes(
          'Bad.xlsx',
          'xlsx',
          Uint8List.fromList(workbook.encode()!),
          aiConsent: false,
        ),
        throwsStateError,
      );
    },
  );
  test('unsafe filename is bounded without dropping the extension', () {
    expect(
      safeRosterFilename('école/../Roster.xlsx'),
      matches(RegExp(r'^[A-Za-z0-9][A-Za-z0-9._ -]{0,159}$')),
    );
    expect(safeRosterFilename('${'A' * 200}.xlsx'), endsWith('.xlsx'));
  });
  test(
    'AI edits retain initial source, model and confidence through a parent-linked review',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await draft.prepare(
        () async => AdminRosterUpload.fromBytes(
          'roster.pdf',
          'pdf',
          Uint8List.fromList([1, 2, 3]),
          aiConsent: true,
        ),
      );
      final initial = draft.initialPreview!;
      draft.edit(1, 'member_name', 'Corrected Member');
      await draft.saveReview('Verified every source row');
      expect(draft.preview!.isHumanReview, true);
      expect(draft.preview!.parentRevisionId, initial.revisionId);
      expect(draft.initialPreview, same(initial));
      expect(draft.initialPreview!.rows[1].confidence, 0.71);
      expect(draft.initialPreview!.model, 'synthetic-extractor');
      expect(draft.preview!.sourceReceipt.raw, initial.sourceReceipt.raw);
      expect(
        gateway.reviews.single['p_rows'],
        contains(containsPair('member_name', 'Corrected Member')),
      );
      expect(draft.canCommit, false);
      draft.affirm(true);
      expect(draft.canCommit, true);
      draft.edit(0, 'member_name', 'Later Correction');
      expect(draft.canCommit, false);
      draft.dispose();
    },
  );
  test(
    'lost upload response retries identical request and bytes without rereading source',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      var reads = 0;
      gateway.onPrepare = (body) async {
        if (gateway.prepares.length == 1) throw TimeoutException('lost');
        return previewFixture(body);
      };
      Future<AdminRosterUpload> read() async {
        reads++;
        return AdminRosterUpload.pasted('Alice,ALICE,0788100000');
      }

      await draft.prepare(read);
      expect(draft.preview, isNull);
      await draft.prepare(read);
      expect(reads, 1);
      expect(gateway.prepares[0], gateway.prepares[1]);
      expect(draft.preview, isNotNull);
      draft.dispose();
    },
  );
  test(
    'lost review response freezes payload and retries same parent/request',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await draft.prepare(
        () async => AdminRosterUpload.pasted('Alice,ALICE,0788100000'),
      );
      gateway.onReview = (params) async {
        if (gateway.reviews.length == 1) throw TimeoutException('lost');
        return previewFixture(
          gateway.body!,
          parent: gateway.latest,
          reviewed: params['p_rows'] as List,
        );
      };
      await draft.saveReview('Confirmed rows once');
      draft.edit(0, 'member_name', 'Should not change');
      await draft.saveReview('Different reason must be ignored');
      expect(gateway.reviews[1], gateway.reviews[0]);
      expect(draft.preview!.rows.first.memberName, 'Member 1');
      draft.dispose();
    },
  );
  for (final mode in ['create', 'existing']) {
    test(
      '$mode uncertain commit preserves exact reference payload and stable request; rejects null success',
      () async {
        final gateway = StatusRosterGateway();
        final draft = AdminRosterDraft(
          gateway,
          collectionId: mode == 'existing' ? rosterCollectionId : null,
        );
        await draft.prepare(
          () async => AdminRosterUpload.pasted('Alice,ALICE,0788100000'),
        );
        await draft.saveReview('Verified every source row');
        draft.affirm(true);
        gateway.onCommit = (params) async => gateway.commits.length == 1
            ? null
            : commitFixture(params, replayed: true);
        expect(
          await draft.commit(
            title: 'Test Group',
            reason: 'Verified source rows',
          ),
          isNull,
        );
        expect(draft.commitPending, true);
        expect(draft.rows.length, 2);
        expect(draft.statusRequired, true);
        expect(await draft.recoverStatus(), isNull);
        expect(gateway.commits, hasLength(1));
        expect(gateway.reads, [rosterImportId]);
        final result = await draft.commit(
          title: 'Changed title',
          reason: 'Changed reason',
        );
        expect(result!.replayed, true);
        expect(gateway.commits[0], gateway.commits[1]);
        expect(gateway.commits.first.containsKey('p_rows'), false);
        expect(gateway.commits.first['p_mode'], mode);
        expect(
          gateway.commits.first['p_title'],
          mode == 'create' ? 'Test Group' : null,
        );
        draft.dispose();
      },
    );
  }
  for (final (field, value) in <(String, Object?)>[
    ('request_id', rosterActorB),
    ('import_id', rosterActorB),
    ('revision_id', rosterActorB),
    ('reviewed_rows_sha256', 'c' * 64),
    ('collection_id', rosterActorB),
    ('roster_count', 1),
    ('mode', 'create'),
    ('ok', null),
    ('share_code_ready', 'true'),
    ('replayed', null),
  ]) {
    test('rejects commit ACK $field mismatch and retains retry', () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway, collectionId: rosterCollectionId);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      await draft.saveReview('Verified all rows');
      draft.affirm(true);
      gateway.onCommit = (params) async => {
        ...commitFixture(params),
        field: value,
      };
      expect(
        await draft.commit(title: '', reason: 'Verified all rows'),
        isNull,
      );
      expect(draft.commitPending, true);
      expect(draft.error, isNotNull);
      draft.dispose();
    });
  }
  for (final field in [
    'source_receipt',
    'source_sha256',
    'source_kind',
    'row_count',
    'can_submit',
    'normalized_rows',
  ]) {
    test('rejects invalid initial provenance $field', () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      gateway.onPrepare = (body) async => {
        ...previewFixture(body),
        field: null,
      };
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      expect(draft.preview, isNull);
      expect(draft.sourceLocked, true);
      draft.dispose();
    });
  }
  test(
    'review cannot replace immutable source/consent/extraction receipt',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      gateway.onReview = (params) async {
        final receipt = previewFixture(
          gateway.body!,
          parent: gateway.latest,
          reviewed: params['p_rows'] as List,
        );
        (receipt['source_receipt'] as Map)['request_id'] = rosterActorB;
        return receipt;
      };
      await draft.saveReview('Verified every row');
      expect(draft.preview!.isHumanReview, false);
      expect(draft.reviewPending, true);
      draft.dispose();
    },
  );
  test(
    'account change during file read prevents any upload and clears all draft data',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      final file = Completer<AdminRosterUpload>();
      final pending = draft.prepare(() => file.future);
      gateway.invalidate();
      file.complete(AdminRosterUpload.pasted('Secret Alice'));
      await pending;
      expect(gateway.prepares, isEmpty);
      expect(draft.rows, isEmpty);
      expect(draft.initialPreview, isNull);
      expect(draft.invalidated, true);
      draft.dispose();
    },
  );
  for (final phase in ['prepare', 'review', 'commit']) {
    test('session change during $phase suppresses stale response', () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      final pending = Completer<Object?>();
      if (phase == 'prepare') {
        gateway.onPrepare = (_) => pending.future;
      } else {
        await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      }
      if (phase == 'review') gateway.onReview = (_) => pending.future;
      if (phase == 'commit') {
        await draft.saveReview('Reviewed source rows');
        draft.affirm(true);
        gateway.onCommit = (_) => pending.future;
      }
      final operation = switch (phase) {
        'prepare' => draft.prepare(
          () async => AdminRosterUpload.pasted('Roster'),
        ),
        'review' => draft.saveReview('Reviewed source rows'),
        _ => draft.commit(title: 'Group', reason: 'Reviewed source rows'),
      };
      await Future<void>.delayed(Duration.zero);
      gateway.invalidate();
      pending.complete({});
      await operation;
      expect(draft.preview, isNull);
      expect(draft.rows, isEmpty);
      expect(draft.invalidated, true);
      draft.dispose();
    });
  }
  test(
    'local row errors are actionable without creating a frozen review request',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      draft.edit(1, 'momo_number', '+250788100000');
      await draft.saveReview('Reviewed every row');
      expect(gateway.reviews, isEmpty);
      expect(draft.reviewPending, false);
      expect(draft.reviewIssues[1], contains('more than once'));
      draft.edit(1, 'momo_number', '+250788100001');
      await draft.saveReview('Reviewed every row');
      expect(draft.preview!.isHumanReview, true);
      draft.dispose();
    },
  );
  test(
    'definitive rejected review requires explicit discard; preserves source and allocates a new request',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      final source = draft.initialPreview;
      gateway.onReview = (_) async =>
          throw const AdminRosterRequestError('roster_rows_invalid');
      await draft.saveReview('Reviewed every row');
      final rejected = gateway.reviews.single['p_request_id'];
      expect(draft.canDiscardPendingReview, true);
      expect(draft.canEdit, false);
      await draft.saveReview('Repeating rejected request must not dispatch');
      expect(gateway.reviews, hasLength(1));
      draft.discardRejectedReview();
      draft.edit(0, 'member_name', 'Corrected Name');
      gateway.onReview = null;
      await draft.saveReview('Corrected rejected row');
      expect(gateway.reviews.last['p_request_id'], isNot(rejected));
      expect(draft.initialPreview, same(source));
      expect(draft.preview!.isHumanReview, true);
      draft.dispose();
    },
  );
  test(
    'acknowledged human revision that is no longer committable remains visible and disabled',
    () async {
      final gateway = FakeRosterGateway();
      final draft = AdminRosterDraft(gateway);
      await draft.prepare(() async => AdminRosterUpload.pasted('Roster'));
      gateway.onReview = (params) async => {
        ...previewFixture(
          gateway.body!,
          parent: gateway.latest,
          reviewed: params['p_rows'] as List,
        ),
        'can_submit': false,
      };
      await draft.saveReview('Reviewed every row');
      draft.affirm(true);
      expect(draft.preview!.isHumanReview, true);
      expect(draft.reviewPending, false);
      expect(draft.canCommit, false);
      draft.dispose();
    },
  );
  test(
    'real gateway pins the refreshed dispatch token and rejects a new same-user session response',
    () async {
      final requests = <http.Request>[];
      final waiting = Completer<http.Response>();
      final client = recordedFixtureClient(
        'https://synthetic.invalid',
        httpClient: MockClient((request) {
          requests.add(request);
          return waiting.future.then(
            (response) => http.Response.bytes(
              response.bodyBytes,
              response.statusCode,
              headers: response.headers,
              request: request,
            ),
          );
        }),
      );
      Future<String> install(String session, String nonce) async {
        final token =
            'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': rosterActorA, 'session_id': session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.$nonce';
        await client.auth.recoverSession(
          jsonEncode({
            'access_token': token,
            'refresh_token': 'synthetic',
            'token_type': 'bearer',
            'user': {
              'id': rosterActorA,
              'aud': 'authenticated',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-09-30T00:00:00Z',
            },
          }),
        );
        return token;
      }

      await install(rosterSessionA, 'first');
      final gateway = CollectAdminRosterGateway(client);
      final refreshed = await install(rosterSessionA, 'refreshed');
      final request = gateway.review({'p_import_id': rosterImportId});
      await Future<void>.delayed(Duration.zero);
      expect(requests.single.headers['Authorization'], 'Bearer $refreshed');
      await install(rosterSessionB, 'new-session');
      waiting.complete(
        http.Response('{}', 200, headers: {'content-type': 'application/json'}),
      );
      await expectLater(request, throwsStateError);
      expect(gateway.isCurrent, false);
      await expectLater(gateway.commit({}), throwsStateError);
      expect(requests.length, 1);
      gateway.dispose();
      await client.dispose();
    },
  );
}
