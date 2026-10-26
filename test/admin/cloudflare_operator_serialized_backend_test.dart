import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const _directory = 'test/admin/fixtures/cloudflare_operator_exchange';

List<int> _bytes(String name, String expectedHash) {
  final bytes = File('$_directory/$name.response.json').readAsBytesSync();
  if (sha256.convert(bytes).toString() != expectedHash) {
    throw StateError('The retained serialized backend fixture hash differs.');
  }
  return bytes;
}

void main() {
  // These are unchanged Response.text() bytes emitted by the final private
  // router and real D1 fixture, not handwritten client DTOs or hosted records.
  final listBytes = _bytes(
    'core-users-list',
    '171dd7d3044aeef2dbcea9ab3e9c29e0e9791bf172fd62ebca8e801019f665ab',
  );
  final detailBytes = _bytes(
    'unlinked-operator-detail',
    'c246be3a63820c752261917b13f375268d19e37f720326a2c756e48dd9563b96',
  );
  final list = jsonDecode(utf8.decode(listBytes)) as Map<String, dynamic>;
  final detail = jsonDecode(utf8.decode(detailBytes)) as Map<String, dynamic>;
  final rawRows = (list['rows'] as List).cast<Map<String, dynamic>>();
  final unlinked = detail['resource'] as Map<String, dynamic>;

  test(
    'all eight real serialized fixture identities satisfy the Dart contract',
    () {
      expect(list['total'], 8);
      expect(rawRows, hasLength(8));
      final parsed = [
        for (final row in rawRows)
          parseCanonicalEvidenceRecord(CloudflareCoreArea.users, row),
      ];
      expect(
        parsed
            .expand((row) => (row['user_types'] as List).cast<String>())
            .toSet(),
        {'Admin', 'Staff', 'App', 'Direct', 'Operator'},
      );
      final operator = parsed.singleWhere((row) => row['id'] == unlinked['id']);
      expect(operator['user_types'], ['Operator']);
      expect(operator['member_type'], 'operator');
      for (final field in [
        'operator_admin_id',
        'operator_role',
        'operator_status',
        'operator_public_id',
      ]) {
        expect(operator[field], isNull, reason: field);
      }
    },
  );

  test(
    'actual repository consumes unchanged backend list/detail bytes read-only',
    () async {
      final actor = detail['current_actor_id'];
      final principal = rawRows.singleWhere(
        (row) => row['operator_role'] == 'owner',
      )['collect_user_id'];
      final requests = <http.Request>[];
      final now = DateTime.now().toUtc();
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path == '/api/admin/auth/session') {
            return http.Response(
              jsonEncode({
                'user': {
                  'id': actor,
                  'principalId': principal,
                  'role': 'owner',
                  'email': 'controlled@example.test',
                  'sessionId': '60000000-0000-4000-8000-000000000001',
                  'financialModel': 'canonical_evidence_ledger',
                  'permissions': [
                    'users.read',
                    'users.manage',
                    'collections.read',
                    'collections.manage',
                  ],
                },
                'expiresAt': now
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          requests.add(request);
          expect(request.method, 'GET');
          if (request.url.path == '/api/admin/core/users') {
            return http.Response.bytes(
              listBytes,
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path ==
              '/api/admin/operations/users/${unlinked['id']}') {
            return http.Response.bytes(
              detailBytes,
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          throw StateError('Unexpected controlled contract-exchange read');
        }),
        origin: Uri.parse('https://admin.example.test'),
        environment: legacyBackendFixtureEnvironment,
      );
      addTearDown(session.dispose);
      await session.refresh();
      final repository = CloudflareAdminRepository(session);
      final page = await repository.list('admin_list_users');
      expect(page.rows, hasLength(8));
      final observed = await repository.operatingDetail(
        'users',
        unlinked['id'] as String,
      );
      expect(observed.resource['user_types'], ['Operator']);
      expect(observed.canManage, isFalse);
      expect(observed.allowedOperations, isEmpty);
      expect(observed.allows(CloudflareOperation.updateUser), isFalse);
      expect(observed.allows(CloudflareOperation.createMembership), isFalse);
      expect(requests, hasLength(2));
    },
  );
}
