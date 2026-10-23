import 'dart:convert';
import 'dart:io';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_canonical_reconciliation_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

Map<String, dynamic> financialFixture(String name) => Map<String, dynamic>.from(
  (jsonDecode(
            File(
              'test/admin/admin-canonical-reconciliation-dto-examples.json',
            ).readAsStringSync(),
          )
          as Map)[name]
      as Map,
);

Map<String, dynamic> canonicalSession({String role = 'owner'}) {
  final detail = financialFixture('detail');
  return {
    'user': {
      'id': detail['current_actor_id'],
      'principalId': detail['current_principal_id'],
      'sessionId': 'canonical-controlled-session',
      'email': 'controlled@example.test',
      'role': role,
      'financialModel': 'canonical_evidence_ledger',
      'assuranceLevel': 2,
      'mfaAt': DateTime.now().toUtc().toIso8601String(),
      'permissions': [
        'account.manage',
        'overview.read',
        'collections.read',
        'collections.create',
        'collections.manage',
        'users.read',
        'users.manage',
        'receivers.read',
        'receivers.manage',
        'payments.read',
        'payments.manage',
        'payments.write',
        'payments.reconcile',
        'payments.evidence.read',
        'ledger.read',
        'reconciliations.read',
        'reconciliations.propose',
        if (role != 'staff') 'reconciliations.review',
      ],
    },
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(hours: 1))
        .toIso8601String(),
  };
}

http.Response financialResponse(Object value, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(value)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class FinancialHarness {
  FinancialHarness._(this.session, this.storage, this.store, this.auth);
  final CloudflareAdminSession session;
  final MemoryAdminPendingAttemptStorage storage;
  final AdminPendingAttemptStore store;
  Map<String, dynamic> auth;
  CanonicalReconciliationApi get api =>
      CanonicalReconciliationApi(session, pendingStore: store);
  static Future<FinancialHarness> create({
    Future<http.Response> Function(http.Request)? reply,
    MemoryAdminPendingAttemptStorage? storage,
    Map<String, dynamic>? auth,
    bool ownsSession = true,
    AppEnv? environment,
    Uri? origin,
    Map<String, dynamic>? emailVerification,
  }) async {
    late FinancialHarness harness;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return financialResponse(harness.auth);
      }
      if (environment?.usesSupabase == true &&
          request.url.path.endsWith('/auth/email-verification')) {
        return financialResponse(
          emailVerification ??
              {
                'contractVersion': 1,
                'sessionId': (harness.auth['user'] as Map)['sessionId'],
                'emailVerifiedAt': null,
              },
        );
      }
      return reply != null ? reply(request) : defaultRead(request);
    });
    final session = CloudflareAdminSession(
      client,
      origin: origin ?? Uri.parse('https://admin.example.test/'),
      environment: environment ?? legacyBackendFixtureEnvironment,
    );
    final persisted = storage ?? MemoryAdminPendingAttemptStorage(),
        store = AdminPendingAttemptStore(storage: persisted);
    harness = FinancialHarness._(
      session,
      persisted,
      store,
      auth ?? canonicalSession(),
    );
    addTearDown(store.dispose);
    if (ownsSession) addTearDown(session.dispose);
    await session.refresh();
    store.bind(session.user);
    return harness;
  }

  static http.Response defaultRead(http.Request request) {
    if (request.url.path.endsWith('/members')) {
      return financialResponse(financialFixture('members'));
    }
    if (request.url.path == '/api/admin/reconciliations') {
      return financialResponse(financialFixture('queue'));
    }
    return financialResponse(financialFixture('detail'));
  }
}

// Same current AAL1/session+CSRF/sidecar DTO contract used by the existing
// Supabase Admin email verification tests. This is synthetic client input only.
const financialSupabaseSessionId = '00000000-0000-4000-8000-000000000001';
Map<String, dynamic> canonicalSupabaseFinancialSession({
  String role = 'owner',
}) {
  final legacy = canonicalSession(role: role);
  return {
    ...legacy,
    'user': {
      ...legacy['user'] as Map<String, dynamic>,
      'sessionId': financialSupabaseSessionId,
      'assuranceLevel': 1,
      'mfaAt': null,
    },
    'ownerEmail': 'info@ikanisa.com',
    'csrfToken': 'a' * 64,
  };
}

Map<String, dynamic> financialSupabaseEmailProof(Object? verifiedAt) => {
  'contractVersion': 1,
  'sessionId': financialSupabaseSessionId,
  'emailVerifiedAt': verifiedAt,
};
