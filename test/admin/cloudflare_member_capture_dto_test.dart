import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

// Required input is the actual Node/workerd/D1 response export. This test never
// creates a replacement success fixture. Only negative cases mutate those rows.
late Map<String, dynamic> captured;
Map<String, dynamic> copyMap(Object? value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
http.Response response(Object? value) => http.Response.bytes(
  utf8.encode(jsonEncode(value)),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
Future<CloudflareAdminRepository> repository(
  Future<http.Response> Function(http.Request) respond, {
  bool admin = false,
}) async {
  final sessionData = copyMap(captured['session']!);
  // Refresh only the synthetic transport session expiry for replay. Source
  // receipt rows, detail envelopes, actors and response bytes stay unchanged.
  final expiry = DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String();
  sessionData['expiresAt'] = expiry;
  final user = sessionData['user'] as Map;
  user['expiresAt'] = expiry;
  if (admin) {
    user['role'] = 'admin';
    user['permissions'] = [...user['permissions'] as List, 'payments.manage'];
  }
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return response(sessionData);
      }
      return respond(request);
    }),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  addTearDown(session.dispose);
  await session.refresh();
  return CloudflareAdminRepository(session);
}

void main() {
  setUpAll(() {
    final path =
        Platform.environment['COLLECT_MEMBER_CAPTURE_DTO_FILE'] ??
        'test/fixtures/admin-member-capture-dto-examples.json';
    if (!File(path).existsSync()) {
      throw TestFailure(
        'The actual focused Node response fixture is missing at '
        '$path. No replacement fixture is generated.',
      );
    }
    captured = Map<String, dynamic>.from(
      jsonDecode(File(path).readAsStringSync()) as Map,
    );
    expect(captured.keys.toSet(), {
      'scope',
      'session',
      'list',
      'list_next',
      'list_all',
      'detail',
      'details',
    });
  });

  test(
    'actual HTTP list pages and details pass the real Member DTO methods',
    () async {
      final repo = await repository((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/gateway/receipts') {
          expect(request.url.queryParameters['limit'], '25');
          final offset = request.url.queryParameters['offset'];
          expect({'0', '25'}, contains(offset));
          return response(captured[offset == '25' ? 'list_next' : 'list']!);
        }
        final detail = (captured['details'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (value) =>
                  request.url.path ==
                  '/api/admin/gateway/receipts/${(value['resource'] as Map)['id']}',
            );
        return response(detail);
      });
      final first = await repo.memberReceiptList();
      final next = await repo.memberReceiptList(offset: 25);
      expect(first.rows.length, 25);
      expect(next.rows.length, 3);
      expect(first.total, 28);
      expect(next.total, 28);
      final all = [...first.rows, ...next.rows];
      expect(
        all.map((row) => row.values).toList(),
        (captured['list_all'] as Map)['rows'],
      );
      expect(all.map((row) => row.status).toSet(), {
        'received',
        'under_review',
        'rejected',
        'linked',
      });
      for (final value in captured['details'] as List) {
        final expected = Map<String, dynamic>.from(value as Map);
        final detail = await repo.memberReceiptDetail(
          (expected['resource'] as Map)['id'] as String,
        );
        expect(detail.receipt.values, expected['resource']);
        expect(detail.receipt.isCapture, isTrue);
        expect(detail.canManage, isFalse);
        expect(detail.reviews, isEmpty);
      }
    },
  );

  test(
    'all actual opaque, signed and expanded-year source-time rows parse',
    () {
      final rows = ((captured['list_all'] as Map)['rows'] as List)
          .cast<Map<String, dynamic>>();
      for (final row in rows) {
        final parsed = CloudflareMemberReceipt.parse(
          Map<String, dynamic>.from(row),
        );
        expect(parsed.values, row);
        expect(parsed.values['transaction_id'], isNull);
        expect(parsed.values['reviewed_at'], isNull);
        expect(parsed.values['provider_confirmation'], isFalse);
      }
      expect(rows[1]['received_at'], isNull);
      expect(rows[1]['received_at_device'], '2026-10-15T12:00:00');
      expect(rows[2]['received_at_device'], isNull);
      expect(rows[3]['received_at'], '1969-12-31T23:59:59.000Z');
      expect(rows[4]['received_at'], '-000001-12-31T23:59:00.000Z');
      expect(rows[5]['received_at'], '1970-01-01T00:00:00.000Z');
      expect(rows[6]['received_at_device'], '2026-10-16');
      expect(rows[6]['received_at'], isNull);
      expect(rows[7]['received_at'], isNull);
    },
  );

  test(
    'capture parser rejects invented facts, finality, revisions and actions',
    () {
      final original = copyMap((captured['detail'] as Map)['resource']!);
      final mutations = <void Function(Map<String, dynamic>)>[
        (row) => row['source_kind'] = 'member',
        (row) => row['version'] = 2,
        (row) => row['version'] = 1.0,
        (row) => row['status'] = 'reviewed',
        (row) => row['received_at'] = '2026-10-16T14:00:00.000Z',
        (row) => row['received_at_device'] = List.filled(65, 'x').join(),
        (row) => row['reviewed_at'] = row['created_at'],
        (row) => row['transaction_id'] = row['id'],
        (row) => row['provider_confirmation'] = true,
        (row) => row['settlement_status'] = 'confirmed',
        (row) => row['source_content_reveal_required'] = false,
        (row) => row['evidence_level'] = 'member_submitted',
        (row) => row['actions'] = ['review'],
      ];
      for (final mutate in mutations) {
        final row = copyMap(original);
        mutate(row);
        expect(() => CloudflareMemberReceipt.parse(row), throwsFormatException);
      }
    },
  );

  test(
    'even an Admin rejects capture manage flags, fake history and actions',
    () async {
      final original = copyMap(captured['detail']!);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (body) => body['can_manage'] = true,
        (body) => (body['related'] as Map)['reviews'] = [{}],
        (body) => body['actions'] = ['review'],
      ]) {
        final body = copyMap(original);
        mutate(body);
        final repo = await repository((_) async => response(body), admin: true);
        await expectLater(
          repo.memberReceiptDetail(
            (original['resource'] as Map)['id'] as String,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'capture source reveal and review fail locally before a business request',
    () async {
      var businessCalls = 0;
      final repo = await repository((_) async {
        businessCalls++;
        throw TestFailure('Capture source review must not dispatch.');
      }, admin: true);
      final receipt = CloudflareMemberReceipt.parse(
        copyMap((captured['detail'] as Map)['resource']!),
      );
      await expectLater(
        repo.memberReceiptContent(
          receipt,
          reason: 'Synthetic forbidden source access',
        ),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        repo.reviewMemberReceipt(
          receipt,
          key: 'synthetic-capture-review',
          outcome: 'reviewed',
          reason: 'Synthetic forbidden review',
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(businessCalls, 0);
    },
  );

  test('legacy review variant retains its own original validation', () {
    final capture = copyMap((captured['detail'] as Map)['resource']!);
    final legacy = {...capture}
      ..remove('source_kind')
      ..remove('received_at_device')
      ..remove('evidence_level')
      ..remove('provider_confirmation')
      ..remove('settlement_status')
      ..remove('source_content_reveal_required')
      ..['status'] = 'needs_review';
    final parsed = CloudflareMemberReceipt.parse(legacy);
    expect(parsed.isCapture, isFalse);
    expect(parsed.values, legacy);
    expect(
      () => CloudflareMemberReceipt.parse({...legacy, 'status': 'reviewed'}),
      throwsFormatException,
    );
  });
}
