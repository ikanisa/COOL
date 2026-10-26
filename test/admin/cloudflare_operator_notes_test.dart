import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_request_identity.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const target = '11111111-1111-4111-8111-111111111111';
const principal = '22222222-2222-4222-8222-222222222222';
const noteId = '33333333-3333-4333-8333-333333333333';
const key = '44444444-4444-4444-8444-444444444444';
http.Response response(Object value, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> page({String? body, int offset = 0}) => {
  'contract_version': 1,
  'entity_type': 'profile',
  'entity_id': target,
  'total': body == null ? 0 : 1,
  'limit': 25,
  'offset': offset,
  'rows': [
    if (body != null)
      {
        'id': noteId,
        'created_by': principal,
        'body': body,
        'author_name': 'Synthetic staff',
        'created_at': '2026-10-15T12:00:00.000Z',
      },
  ],
};
Map<String, dynamic> receipt(String requestKey) => {
  'status': 'succeeded',
  'request_id': canonicalAdminRequestId(principal, requestKey),
  'resource_type': 'operator_notes',
  'resource_id': noteId,
  'version': 1,
};
Future<CloudflareAdminRepository> repository(
  Future<http.Response> Function(http.Request) action,
) async {
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return response({
          'user': {
            'id': target,
            'email': 'notes-staff@example.test',
            'role': 'staff',
            'principalId': principal,
            'sessionId': 'notes-current-session',
            'financialModel': 'canonical_evidence_ledger',
            'permissions': ['users.read', 'overview.read', 'account.manage'],
          },
          'expiresAt': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        });
      }
      return action(request);
    }),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  // A mounted provider owns its notifier; repository-only tests own it here.
  addTearDown(() {
    if (session.mounted) session.dispose();
  });
  await session.refresh();
  return CloudflareAdminRepository(session);
}

Future<ProviderContainer> mount(
  WidgetTester tester,
  CloudflareAdminRepository repo, {
  MemoryAdminPendingAttemptStorage? storage,
}) async {
  tester.view.physicalSize = const Size(1440, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      adminRepositoryProvider.overrideWithValue(repo),
      cloudflareAdminSessionProvider.overrideWith((_) => repo.session),
      if (storage != null)
        adminPendingAttemptStorageProvider.overrideWithValue(storage),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CloudflareOperatorNotes(type: 'users', id: target),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'live invalidation refreshes notes without erasing the private draft or sending it',
    (tester) async {
      var reads = 0, writes = 0;
      final repo = (await tester.runAsync(
        () => repository((request) async {
          if (request.method == 'POST') {
            writes++;
            return response(receipt(key));
          }
          reads++;
          return response(
            page(body: reads > 1 ? 'New recorded follow-up' : null),
          );
        }),
      ))!;
      final container = await mount(tester, repo);
      await tester.enterText(find.byType(TextField), 'Private unsent draft');
      container.read(adminRealtimeTickProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(writes, 0);
      expect(find.text('Private unsent draft'), findsOneWidget);
      expect(find.text('New recorded follow-up'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'staff notes use an exact scope, typed receipt and original request identity',
    () async {
      var writes = 0;
      final repo = await repository((request) async {
        expect(request.url.path, '/api/admin/operations/users/$target/notes');
        if (request.method == 'POST') {
          writes++;
          expect(request.headers['Idempotency-Key'], key);
          expect(jsonDecode(request.body), {'body': 'Recorded note'});
          return response(receipt(key));
        }
        expect(request.url.queryParameters, {'limit': '25', 'offset': '0'});
        return response(page(body: 'Recorded note'));
      });
      expect(
        (await repo.operatorNotes('users', target)).rows.single['body'],
        'Recorded note',
      );
      expect(
        (await repo.recordOperatorNote(
          'users',
          target,
          key: key,
          body: ' Recorded note ',
        )).resourceId,
        noteId,
      );
      expect(writes, 1);
    },
  );
  for (final defect in [
    'wrong entity',
    'duplicate rows',
    'raw extra',
    'bad date',
    'wrong count',
  ]) {
    test('note reader rejects $defect before exposing text', () async {
      final value = page(body: 'Private synthetic canary');
      switch (defect) {
        case 'wrong entity':
          value['entity_id'] = principal;
        case 'duplicate rows':
          (value['rows'] as List).add((value['rows'] as List).first);
          value['total'] = 2;
        case 'raw extra':
          ((value['rows'] as List).first as Map)['body_ciphertext'] =
              'unexpected';
        case 'bad date':
          ((value['rows'] as List).first as Map)['created_at'] = 'yesterday';
        case 'wrong count':
          value['total'] = 25;
      }
      final repo = await repository((_) async => response(value));
      await expectLater(
        repo.operatorNotes('users', target),
        throwsFormatException,
      );
    });
  }
  test('note writer rejects a receipt for another request', () async {
    final repo = await repository(
      (_) async => response({...receipt(key), 'request_id': target}),
    );
    await expectLater(
      repo.recordOperatorNote('users', target, key: key, body: 'A valid note'),
      throwsFormatException,
    );
  });
  test(
    'session loss while a note read is pending releases no private result',
    () async {
      final waiting = Completer<http.Response>(),
          repo = await repository((_) => waiting.future);
      final future = repo.operatorNotes('users', target);
      final check = expectLater(future, throwsA(isA<Exception>()));
      repo.session.clear();
      waiting.complete(response(page(body: 'Private synthetic canary')));
      await check;
    },
  );
  testWidgets(
    'real notes control records once, refreshes the table and clears its reference',
    (tester) async {
      String? saved;
      var writes = 0;
      final repo = (await tester.runAsync(
        () => repository((request) async {
          if (request.method == 'POST') {
            writes++;
            saved = (jsonDecode(request.body) as Map)['body'] as String;
            return response(receipt(request.headers['Idempotency-Key']!));
          }
          return response(page(body: saved));
        }),
      ))!;
      final container = await mount(
        tester,
        repo,
        storage: MemoryAdminPendingAttemptStorage(),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'Synthetic support follow-up',
      );
      await tap(tester, 'Record note');
      expect(writes, 1);
      expect(find.text('Operator note recorded'), findsOneWidget);
      expect(find.text('Synthetic support follow-up'), findsOneWidget);
      expect(
        container
            .read(adminPendingAttemptStoreProvider)
            .restoreFamily(
              family: 'operator-note',
              permission: 'users.read',
              schema: const AdminPendingAttemptSchema(fields: {'body_sha256'}),
            ),
        isEmpty,
      );
      repo.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'lost response retains only a digest; original receipt recovery never posts twice',
    (tester) async {
      var writes = 0;
      String? requestKey;
      bool posted = false;
      final storage = MemoryAdminPendingAttemptStorage();
      final repo = (await tester.runAsync(
        () => repository((request) async {
          if (request.method == 'POST') {
            writes++;
            requestKey = request.headers['Idempotency-Key'];
            posted = true;
            throw http.ClientException('Controlled lost response');
          }
          if (request.url.path.contains('/requests/')) {
            return response({
              'contract_version': 2,
              'model': 'canonical_evidence_ledger',
              'status': 'succeeded',
              'request_id': canonicalAdminRequestId(principal, requestKey!),
              'receipt': receipt(requestKey!),
            });
          }
          return response(page(body: posted ? 'Private synthetic note' : null));
        }),
      ))!;
      final container = await mount(tester, repo, storage: storage);
      await tester.enterText(
        find.byType(TextField).first,
        'Private synthetic note',
      );
      await tap(tester, 'Record note');
      expect(writes, 1);
      final retained = container
          .read(adminPendingAttemptStoreProvider)
          .restoreFamily(
            family: 'operator-note',
            permission: 'users.read',
            schema: const AdminPendingAttemptSchema(fields: {'body_sha256'}),
          );
      expect(retained.single.intent.keys, ['body_sha256']);
      expect(
        jsonEncode(retained.single.intent),
        isNot(contains('Private synthetic note')),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CloudflareOperatorNotes(type: 'users', id: target),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(writes, 1);
      await tap(tester, 'Check original note request');
      expect(writes, 1);
      expect(find.text('Operator note recorded'), findsOneWidget);
      repo.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'same-key retry requires the exact original text after an explicit not-found lookup',
    (tester) async {
      var writes = 0;
      String? originalKey;
      final repo = (await tester.runAsync(
        () => repository((request) async {
          if (request.method == 'POST') {
            writes++;
            if (writes == 1) {
              originalKey = request.headers['Idempotency-Key'];
              throw http.ClientException('Controlled pre-commit outage');
            }
            expect(request.headers['Idempotency-Key'], originalKey);
            return response(receipt(originalKey!));
          }
          if (request.url.path.contains('/requests/')) {
            return response({
              'contract_version': 2,
              'model': 'canonical_evidence_ledger',
              'status': 'not_found',
            });
          }
          return response(page());
        }),
      ))!;
      await mount(tester, repo, storage: MemoryAdminPendingAttemptStorage());
      await tester.enterText(
        find.byType(TextField).first,
        'Exact synthetic original',
      );
      await tap(tester, 'Record note');
      await tap(tester, 'Check original note request');
      await tester.enterText(
        find.byType(TextField).first,
        'Changed synthetic content',
      );
      await tap(tester, 'Retry original note');
      expect(writes, 1);
      await tester.enterText(
        find.byType(TextField).first,
        'Exact synthetic original',
      );
      await tap(tester, 'Retry original note');
      expect(writes, 2);
      repo.session.clear();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'logout immediately hides loaded notes and disables all note actions',
    (tester) async {
      final repo = (await tester.runAsync(
        () => repository(
          (_) async => response(page(body: 'Private synthetic canary')),
        ),
      ))!;
      await mount(tester, repo);
      expect(find.text('Private synthetic canary'), findsOneWidget);
      repo.session.clear();
      await tester.pumpAndSettle();
      expect(find.text('Private synthetic canary'), findsNothing);
      expect(find.text('Record note'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
