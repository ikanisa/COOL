import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

Map<String, dynamic> fixture(String name) => Map<String, dynamic>.from(
  (jsonDecode(
            File(
              'test/admin/admin-operating-dto-examples.json',
            ).readAsStringSync(),
          )
          as Map)[name]
      as Map,
);

Future<CloudflareAdminRepository> repository(
  Map<String, dynamic> body, {
  String role = 'owner',
  Future<http.Response> Function(http.Request)? read,
}) async {
  final session = CloudflareAdminSession(
    MockClient((request) async {
      final value = request.url.path.endsWith('/auth/session')
          ? {
              'user': {
                'id': fixture('group')['current_actor_id'],
                'email': 'controlled@example.test',
                'principalId': fixture('session')['user']['principalId'],
                'role': role,
                'sessionId': 'canonical-operating-session',
                'financialModel': 'canonical_evidence_ledger',
                'permissions': [
                  'overview.read',
                  'account.manage',
                  'collections.read',
                  'collections.manage',
                  'users.read',
                  'users.manage',
                  'receivers.read',
                  'receivers.manage',
                  'payments.read',
                  'payments.manage',
                  'payments.reconcile',
                  'ledger.read',
                ],
              },
              'expiresAt': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 1))
                  .toIso8601String(),
            }
          : body;
      if (!request.url.path.endsWith('/auth/session') && read != null) {
        return read(request);
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(value)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
    origin: Uri.parse('https://admin.example.test/'),
    environment: legacyBackendFixtureEnvironment,
  );
  addTearDown(session.dispose);
  await session.refresh();
  return CloudflareAdminRepository(session);
}

void main() {
  for (final kind in ['groups', 'users', 'members', 'payees']) {
    test('$kind consumes an actual Worker scoped lookup', () async {
      final data = fixture('lookup_$kind'),
          repo = await repository(
            fixture('group'),
            read: (request) async {
              expect(request.url.path, '/api/admin/operations/lookups');
              return http.Response.bytes(
                utf8.encode(jsonEncode(data)),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            },
          );
      final groupId = {'members', 'payees'}.contains(kind)
          ? fixture('group')['resource']['id'] as String
          : null;
      final rows = await repo.operatingLookups(kind, groupId: groupId);
      expect(rows.length, (data['rows'] as List).length);
      expect(rows.length, data['total']);
    });
  }
  test(
    'current request history and exact lookup consume the retained, principal-bound Worker receipts',
    () async {
      final history = fixture('history'),
          key =
              ((history['rows'] as List).single as Map)['idempotency_key']
                  as String;
      final repo = await repository(
        fixture('group'),
        read: (request) async => http.Response.bytes(
          utf8.encode(
            jsonEncode(
              request.url.path.endsWith('/$key') ? fixture('lookup') : history,
            ),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final rows = await repo.operatingRequests();
      expect(rows.total, 1);
      expect(rows.rows.single['scope'], 'groups.post');
      final result = await repo.operatingRequest(key);
      expect(result['status'], 'succeeded');
      expect(
        (result['receipt'] as Map)['resource_id'],
        fixture('group')['resource']['id'],
      );
    },
  );
  for (final name in ['group', 'group_next', 'user', 'payee']) {
    test('$name consumes actual isolated workerd/D1 operating data', () async {
      final data = fixture(name),
          resource = Map<String, dynamic>.from(data['resource'] as Map);
      final repo = await repository(data);
      final result = await repo.operatingDetail(
        data['resource_type'] as String,
        resource['id'] as String,
        relation: name == 'group_next' ? 'memberships' : null,
        offset: name == 'group_next' ? 25 : 0,
        limit: 25,
      );
      expect(result.sourceModel, 'canonical_evidence_ledger');
      expect(result.resource, resource);
      expect(result.truncated, isFalse);
      expect(
        result.allowedOperations.any(
          (o) => o == CloudflareOperation.createJournal,
        ),
        isFalse,
      );
      expect(() => result.resource['version'] = 900, throwsUnsupportedError);
      if (name.startsWith('group')) {
        expect(result.relatedPages['memberships']!.total, 28);
      }
    });
  }
  for (final damage in [
    'actor',
    'foreign_member',
    'foreign_receiver',
    'page_total',
    'page_next',
    'duplicate_member',
    'unsupported_action',
    'duplicate_action',
    'staff_action',
    'timestamp',
    'money_type',
    'marker',
    'private_payload',
  ]) {
    test('rejects operating response damage: $damage', () async {
      final data = fixture('group'), related = data['related'] as Map;
      switch (damage) {
        case 'actor':
          data['current_actor_id'] = '11111111-1111-4111-8111-111111111111';
        case 'foreign_member':
          ((related['memberships'] as List).first as Map)['group_id'] =
              '11111111-1111-4111-8111-111111111111';
        case 'foreign_receiver':
          ((related['payees'] as List).first as Map)['group_id'] =
              '11111111-1111-4111-8111-111111111111';
        case 'page_total':
          ((data['related_pages'] as Map)['memberships'] as Map)['total'] = 1;
        case 'page_next':
          ((data['related_pages'] as Map)['memberships']
                  as Map)['next_offset'] =
              26;
        case 'duplicate_member':
          (related['memberships'] as List)[1] =
              (related['memberships'] as List).first;
        case 'unsupported_action':
          (data['allowed_operations'] as List).add('createJournal');
        case 'duplicate_action':
          (data['allowed_operations'] as List).add(
            (data['allowed_operations'] as List).first,
          );
        case 'staff_action':
          break;
        case 'timestamp':
          (data['resource'] as Map)['created_at'] = 1792065600;
        case 'money_type':
          ((related['payees'] as List).first as Map)['version'] = '1';
        case 'marker':
          data['contract_version'] = 1;
        case 'private_payload':
          (data['resource'] as Map)['password_hash'] = 'unexpected';
      }
      final repo = await repository(
        data,
        role: damage == 'staff_action' ? 'staff' : 'owner',
      );
      await expectLater(
        repo.operatingDetail(
          'groups',
          (data['resource'] as Map)['id'] as String,
        ),
        throwsFormatException,
      );
    });
  }
}
