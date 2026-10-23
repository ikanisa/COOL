import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_notification_management_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';
import '../core/supabase_backend_test.dart' as backend;

part 'cloudflare_admin_notification_management_api_cases/history.dart';
part 'cloudflare_admin_notification_management_api_cases/status.dart';
part 'cloudflare_admin_notification_management_api_cases/authority.dart';
part 'cloudflare_admin_notification_management_api_cases/recovery.dart';

const _admin = '30000000-0000-4000-8000-000000000001';
const _principal = '30000000-0000-4000-8000-000000000002';
const _publicSession = '30000000-0000-4000-8000-000000000003';
const _canonicalSession = '30000000-0000-4000-8000-000000000004';
const _collection = '30000000-0000-4000-8000-000000000005';
const _request = '30000000-0000-4000-8000-000000000006';
const _transaction = '30000000-0000-4000-8000-000000000007';
const _other = '30000000-0000-4000-8000-000000000008';
const _permissions = ['assisted_sms.read', 'assisted_sms.manage'];
const _template = 'collect.recorded_contribution.v1';

Map<String, dynamic> _marker(String scope) => {
  'contract_version': 1,
  'scope': scope,
  'legal_release_approved': false,
  'provider_approved': false,
  'delivery_confirmed': false,
};
http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
String _stable(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_stable(value[key])}').join(',')}}';
  }
  if (value is List) return '[${value.map(_stable).join(',')}]';
  return jsonEncode(value);
}

String _digest(Object? value) =>
    sha256.convert(utf8.encode(_stable(value))).toString();

class _Fixture {
  _Fixture({this.supabase = false}) {
    if (supabase) assurance = 1;
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path.endsWith('/api/admin/auth/session')) {
          return _json({
            'user': {
              'id': _admin,
              'email': email,
              'role': role,
              'sessionId': publicSession,
              'principalId': principal,
              'permissions': permissions,
              'assuranceLevel': assurance,
              if (assurance == 2) 'mfaAt': mfaAt.toIso8601String(),
            },
            'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
            if (supabase) 'csrfToken': 'd' * 64,
          });
        }
        if (supabase &&
            request.url.path.endsWith('/api/admin/auth/email-verification')) {
          return _json({
            'contractVersion': 1,
            'sessionId': proofSession ?? publicSession,
            'emailVerifiedAt': emailVerifiedAt?.toIso8601String(),
          });
        }
        requests.add(request);
        if (handler != null) return handler!(request);
        return _json({'ok': true, 'result': result(request)});
      }),
      origin: Uri.parse('https://admin.example.test/'),
      environment: supabase
          ? backend.environment(admin: 'https://admin.example.test')
          : legacyBackendFixtureEnvironment,
    );
  }
  final now = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
  late DateTime clock = now, mfaAt = now;
  final bool supabase;
  late DateTime? emailVerifiedAt = now;
  String? proofSession;
  String role = 'owner',
      email = 'info@ikanisa.com',
      publicSession = _publicSession;
  String? principal = _principal;
  int assurance = 2, policyRevision = 3, decisionRevision = 0;
  bool readGranted = false,
      manageGranted = false,
      policyEnabled = false,
      collectionActive = true;
  List<String> permissions = ['admin_users.manage', ..._permissions];
  final requests = <http.Request>[];
  final retained = <String, Map<String, dynamic>>{};
  Future<http.Response> Function(http.Request)? handler;
  late CloudflareAdminSession session;
  late CloudflareAdminNotificationManagementApi api;
  Future<void> open() async {
    await session.refresh();
    api = CloudflareAdminNotificationManagementApi(session, now: () => clock);
  }

  Map<String, dynamic> access() => {
    ..._marker('owner_receipt_sms_access'),
    'current_admin_id': _admin,
    'current_principal_id': _principal,
    'decision_revision': decisionRevision,
    'read_granted': readGranted,
    'manage_granted': manageGranted,
    'can_operate': readGranted && manageGranted,
    'permissions': _permissions,
  };
  Map<String, dynamic> policy() => {
    ..._marker('owner_receipt_sms_configuration'),
    'collection_id': _collection,
    'configured': policyRevision > 0,
    'enabled': policyEnabled,
    'revision': policyRevision,
    'template_key': _template,
    'recorded_owner_decision_sha256': policyRevision > 0 ? 'b' * 64 : null,
    'recorded_at': policyRevision > 0 ? now.toIso8601String() : null,
    'collection_active': collectionActive,
  };
  Map<String, dynamic> accessReceipt(Map<String, dynamic> body) {
    final decision = <String, dynamic>{
      'kind': 'authenticated_owner_receipt_sms_access',
      'request_id': body['request_id'],
      'grant_transaction_id': _transaction,
      'current_admin_id': _admin,
      'current_principal_id': _principal,
      'decision_revision':
          (body['expected_decision_revision'] as int? ?? decisionRevision) + 1,
      'originating_session_id': _canonicalSession,
      'public_session_id': _publicSession,
      'enabled': body['enabled'],
      'permissions': _permissions,
      'recorded_at': now.toIso8601String(),
    };
    return {
      ..._marker('owner_receipt_sms_access'),
      ...decision,
      'read_granted': body['enabled'],
      'manage_granted': body['enabled'],
      'can_operate': body['enabled'],
      'decision_sha256': _digest(decision),
      'recorded_state_only': true,
      'replay': false,
    };
  }

  Map<String, dynamic> policyReceipt(Map<String, dynamic> body) {
    final decision = <String, dynamic>{
      'kind': 'authenticated_owner_receipt_sms_policy',
      'request_id': body['request_id'],
      'collection_id': _collection,
      'revision': (body['expected_revision'] as int) + 1,
      'enabled': body['enabled'],
      'template_key': _template,
      'owner_user_id': _principal,
      'originating_session_id': _canonicalSession,
      'public_session_id': _publicSession,
      'recorded_at': now.toIso8601String(),
      'legal_release_approved': false,
      'provider_approved': false,
    };
    return {
      ..._marker('owner_receipt_sms_configuration'),
      ...decision,
      'recorded_owner_decision_sha256': _digest(decision),
    };
  }

  Map<String, dynamic> lookup(String rid, Map<String, dynamic>? receipt) => {
    'contract_version': 1,
    'scope': 'assisted_sms_internal_record',
    'delivery_confirmed': false,
    'provider_confirmation': false,
    'settlement_status': 'not_asserted',
    'request_id': rid,
    'observed': receipt != null,
    'receipt': receipt,
    'may_send': false,
  };
  Map<String, dynamic> result(http.Request request) {
    if (request.method == 'GET') {
      if (request.url.path.endsWith('/access')) return access();
      if (request.url.path.endsWith('/policies/$_collection')) return policy();
    }
    final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
    final rid = body['request_id'] as String;
    if (request.url.path.endsWith('/access')) {
      final previous = retained[rid];
      if (previous != null) return {...previous, 'replay': true};
      final receipt = accessReceipt(body);
      decisionRevision = receipt['decision_revision'] as int;
      return retained[rid] = receipt;
    }
    if (request.url.path.endsWith('/policies/$_collection')) {
      return retained.putIfAbsent(rid, () => policyReceipt(body));
    }
    if (request.url.path == '/api/admin/notification-operator' &&
        body['action'] == 'get_operation') {
      return lookup(rid, retained[rid]);
    }
    throw StateError('Unexpected management request');
  }

  Future<NotificationManagementOperation> accessOperation({
    bool enabled = true,
  }) async => api.prepareAccess(
    expected: await api.getAccess(),
    enabled: enabled,
    ownerConfirmation: enabled,
    requestId: _request,
  );
  Future<NotificationManagementOperation> policyOperation({
    bool enabled = false,
  }) async => api.preparePolicy(
    expected: await api.getPolicy(_collection),
    enabled: enabled,
    ownerConfirmation: enabled,
    requestId: _request,
  );
  void dispose() => session.dispose();
}

Map<String, dynamic> _historyItem(
  String requestId,
  String kind,
  DateTime at,
) => {
  'request_id': requestId,
  'kind': kind,
  'recorded_at': at.toUtc().toIso8601String(),
  'recorded_outcome': kind == 'materialization'
      ? 'plan_recorded'
      : 'decision_recorded',
  'status_path': switch (kind) {
    'access' => '/api/admin/notification-operator/access/operations/$requestId',
    'policy' =>
      '/api/admin/notification-operator/policies/operations/$requestId',
    _ => '/api/admin/notification-operator/materialize/$requestId',
  },
  'recorded_state_only': true,
  'may_send': false,
};

Map<String, dynamic> _history(
  List<Map<String, dynamic>> items, {
  Map<String, dynamic>? next,
}) => {
  ..._marker('own_receipt_sms_request_history'),
  'items': items,
  'next_cursor': next,
  'original_session_only': true,
  'recorded_state_only': true,
  'may_send': false,
  'replay_authorized': false,
};

Map<String, dynamic> _operationStatus(
  String kind,
  String requestId,
  Map<String, dynamic>? receipt, {
  Map<String, dynamic>? current,
}) => {
  ..._marker('owner_receipt_sms_${kind}_operation'),
  'request_id': requestId,
  'observed': receipt != null,
  'status': receipt == null ? 'not_recorded' : 'recorded',
  'may_be_in_flight': receipt == null,
  'recorded_decision': receipt,
  if (kind == 'access') 'current_access': current,
  'recorded_state_only': true,
  'may_send': false,
  'replay_authorized': false,
};

Map<String, dynamic> _resignStatusReceipt(Map<String, dynamic> receipt) {
  final access = receipt['kind'] == 'authenticated_owner_receipt_sms_access';
  final fields = access
      ? <String>{
          'kind',
          'request_id',
          'grant_transaction_id',
          'current_admin_id',
          'current_principal_id',
          'decision_revision',
          'originating_session_id',
          'public_session_id',
          'enabled',
          'permissions',
          'recorded_at',
        }
      : <String>{
          'kind',
          'request_id',
          'collection_id',
          'revision',
          'enabled',
          'template_key',
          'owner_user_id',
          'originating_session_id',
          'public_session_id',
          'recorded_at',
          'legal_release_approved',
          'provider_approved',
        };
  final hashField = access
      ? 'decision_sha256'
      : 'recorded_owner_decision_sha256';
  return {
    ...receipt,
    hashField: _digest({for (final field in fields) field: receipt[field]}),
  };
}

class _NotificationManagementApiSuite {
  late _Fixture fixture;

  void register() {
    setUp(() async {
      fixture = _Fixture();
      await fixture.open();
    });
    tearDown(() => fixture.dispose());

    _registerNotificationHistoryCases();
    _registerNotificationStatusCases();
    _registerNotificationAuthorityCases();
    _registerNotificationRecoveryCases();
  }
}

void main() => _NotificationManagementApiSuite().register();
