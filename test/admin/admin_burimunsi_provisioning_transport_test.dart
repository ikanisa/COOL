// Actual existing managed Admin session and production provisioning transport.
// HTTP/provider responses below are synthetic; no network or real credential.
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as configuration;
import 'admin_burimunsi_provisioning_test.dart' as fixtures;
import 'admin_burimunsi_test.dart' as shared;

http.Response response(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
Map<String, dynamic> account() => {
  'user': {
    'id': shared.owner.adminId,
    'principalId': shared.owner.principalId,
    'email': shared.owner.email,
    'role': 'owner',
    'sessionId': 'c1000000-0000-4000-8000-000000000001',
    'permissions': ['admin_users.manage', 'receivers.read', 'receivers.manage'],
    'assuranceLevel': 1,
    'mfaAt': null,
    'financialModel': 'canonical_evidence_ledger',
  },
  'expiresAt': DateTime.now()
      .toUtc()
      .add(const Duration(hours: 1))
      .toIso8601String(),
  'ownerEmail': shared.owner.email,
  'csrfToken': 'a' * 64,
};
Map<String, dynamic> pinReceipt(String requestId) => {
  'contractVersion': 1,
  'collectionId': shared.group,
  'requestId': requestId,
  'operation': 'set_pin',
  'principalId': shared.staff.principalId,
  'accountId': fixtures.accountId,
  'accountVersion': 1,
  'credentialVersion': 1,
  'approvalVersion': 1,
  'scopeVersion': 1,
  'applied': true,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'existing shared cookie/CSRF transport uses exact source routes; lost response recovers original UUID',
    () async {
      final calls = <http.Request>[];
      final intent = fixtures.pinIntent();
      final session = CloudflareAdminSession(
        MockClient((request) async {
          calls.add(request);
          final path = request.url.path;
          if (path.endsWith('/auth/session')) return response(account());
          if (path.endsWith('/auth/email-verification')) {
            return response({
              'contractVersion': 1,
              'sessionId': (account()['user'] as Map)['sessionId'],
              'emailVerifiedAt': DateTime.now()
                  .toUtc()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String(),
            });
          }
          if (path.endsWith('/momo/native-setup')) {
            expect(request.method, 'GET');
            return response({
              'contractVersion': 1,
              'collections': [
                {'id': shared.group, 'title': 'Existing Collect group'},
              ],
              'scopes': [
                {'collectionId': shared.group},
              ],
            });
          }
          if (path.endsWith('/burimunsi/provisioning') &&
              request.method == 'GET') {
            expect(request.url.queryParameters, {'collectionId': shared.group});
            return response(fixtures.nativeDirectory());
          }
          if (path.endsWith('/burimunsi/provisioning') &&
              request.method == 'POST') {
            expect(jsonDecode(request.body), intent.body(pin: '8492'));
            return response({
              'error': {
                'code': 'burimunsi_provisioning_unknown',
                'message': 'Original outcome unknown.',
              },
            }, 503);
          }
          if (path.endsWith(
            '/burimunsi/provisioning/requests/${intent.requestId}',
          )) {
            expect(request.method, 'GET');
            expect(request.url.queryParameters, {'collectionId': shared.group});
            return response({
              'contractVersion': 1,
              'collectionId': shared.group,
              'requestId': intent.requestId,
              'found': true,
              'receipt': pinReceipt(intent.requestId),
            });
          }
          throw StateError('Unexpected synthetic provisioning route.');
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: configuration.environment(),
      );
      addTearDown(session.dispose);
      await session.refresh();
      final api = CloudflareAdminAccountApi(session),
          fence = api.buriAuthorityFence;
      expect(api.buriAuthorized, true);
      expect((await api.loadBuriScopes()).single.id, shared.group);
      expect(
        (await api.loadBuriProvisioning(collectionId: shared.group)).accounts,
        hasLength(1),
      );
      await expectLater(
        api.submitBuriProvisioning(intent, fence, pin: '8492'),
        throwsA(isA<AdminAccountException>()),
      );
      final receipt = await api.lookupBuriProvisioning(intent, fence);
      intent.verify(receipt!);
      final writes = calls.where((r) => r.method == 'POST').toList();
      expect(writes, hasLength(1));
      final write = writes.single;
      expect(
        write.url.toString(),
        'https://backend.collect.ikanisa.com/functions/v1/admin-api/api/admin/burimunsi/provisioning',
      );
      expect(write.headers['X-Collect-CSRF'], 'a' * 64);
      expect(write.headers['X-Collect-Requested-With'], 'collect-admin');
      expect(write.headers['Idempotency-Key'], intent.requestId);
      expect(write.headers.containsKey('authorization'), false);
      expect(write.headers.containsKey('cookie'), false);
    },
  );
  test(
    'a current email proof is required before new provisioning transport can dispatch',
    () async {
      var mutations = 0;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.method != 'GET') mutations++;
          if (request.url.path.endsWith('/auth/session')) {
            return response(account());
          }
          return response({
            'contractVersion': 1,
            'sessionId': (account()['user'] as Map)['sessionId'],
            'emailVerifiedAt': null,
          });
        }),
        origin: Uri.parse('https://admin.collect.ikanisa.com'),
        environment: configuration.environment(),
      );
      addTearDown(session.dispose);
      await session.refresh();
      final api = CloudflareAdminAccountApi(session);
      expect(api.buriAuthorized, false);
      await expectLater(
        api.submitBuriProvisioning(
          fixtures.pinIntent(),
          api.buriAuthorityFence,
          pin: '8492',
        ),
        throwsA(isA<AdminAccountException>()),
      );
      expect(mutations, 0);
    },
  );
}
