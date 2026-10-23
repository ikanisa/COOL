import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_notification_management_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/admin_theme.dart';
import 'package:collect_app/admin/shared/components/admin_data_listing.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';
import '../core/supabase_backend_test.dart' as backend;

part 'cloudflare_admin_notification_management_page_cases/commands.dart';
part 'cloudflare_admin_notification_management_page_cases/recovery.dart';
part 'cloudflare_admin_notification_management_page_cases/history_authority.dart';
part 'cloudflare_admin_notification_management_page_cases/paging_responsive.dart';

const _admin = '30000000-0000-4000-8000-000000000001';
const _principal = '30000000-0000-4000-8000-000000000002';
const _public = '30000000-0000-4000-8000-000000000003';
const _canonical = '30000000-0000-4000-8000-000000000004';
const _collection = '30000000-0000-4000-8000-000000000005';
const _transaction = '30000000-0000-4000-8000-000000000006';
const _otherPrincipal = '30000000-0000-4000-8000-000000000007';
const _secondCollection = '30000000-0000-4000-8000-000000000008';
const _accessPath = '/api/admin/notification-operator/access';
const _policyPath = '/api/admin/notification-operator/policies/$_collection';
const _historyPath = '/api/admin/notification-operator/operations';
const _historyAccessId = '50000000-0000-4000-8000-000000000050';
const _historyPolicyId = '50000000-0000-4000-8000-000000000049';
const _historyPlanId = '50000000-0000-4000-8000-000000000048';
const _accessCheckbox =
    'Allow my account to view jobs and manage assisted SMS.';
const _policyCheckbox =
    'I confirm disabling receipt SMS for this exact collection and revision';
const _markers = {
  'contract_version': 1,
  'legal_release_approved': false,
  'provider_approved': false,
  'delivery_confirmed': false,
};

String _stable(Object? value) {
  if (value is Map<String, dynamic>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${_stable(value[key])}').join(',')}}';
  }
  if (value is List) {
    return '[${value.map(_stable).join(',')}]';
  }
  return jsonEncode(value);
}

String _digest(Object value) =>
    sha256.convert(utf8.encode(_stable(value))).toString();
http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json'},
);
http.Response _result(Map<String, dynamic> value) =>
    _json({'ok': true, 'result': value});

class _Fixture {
  _Fixture({
    this.role = 'owner',
    this.assurance = 2,
    this.supabase = false,
    this.emailProofAge = Duration.zero,
    this.emailProofPresent = true,
    this.adminManage = true,
    this.readGranted = false,
    this.manageGranted = false,
    this.decisionRevision = 0,
    this.handler,
  }) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        final path = request.url.path.replaceFirst(
          '/functions/v1/admin-api',
          '',
        );
        if (path == '/api/admin/auth/session') {
          sessionReads++;
          return _json({
            'user': {
              'id': _admin,
              'email': 'info@ikanisa.com',
              'role': role,
              'sessionId': _public,
              'principalId': principal,
              'permissions': [
                if (adminManage) 'admin_users.manage',
                if (readGranted) 'assisted_sms.read',
                if (manageGranted) 'assisted_sms.manage',
              ],
              'assuranceLevel': assurance,
              if (assurance == 2) 'mfaAt': now.toIso8601String(),
            },
            'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
            if (supabase) 'csrfToken': 'd' * 64,
          });
        }
        if (supabase && path == '/api/admin/auth/email-verification') {
          return _json({
            'contractVersion': 1,
            'sessionId': _public,
            'emailVerifiedAt': emailProofPresent
                ? now.subtract(emailProofAge).toIso8601String()
                : null,
          });
        }
        requests.add(request);
        final response = await handler?.call(request);
        if (response != null) {
          return response;
        }
        if (path == _accessPath && request.method == 'GET') {
          return _result(access());
        }
        if (path == _accessPath && request.method == 'POST') {
          final body = _body(request);
          readGranted = body['enabled'] as bool;
          manageGranted = body['enabled'] as bool;
          decisionRevision = (body['expected_decision_revision'] as int) + 1;
          return _result(accessReceipt(body));
        }
        if (path == _policyPath && request.method == 'GET') {
          return _result(policy());
        }
        if (path == _policyPath && request.method == 'POST') {
          final body = _body(request);
          policyEnabled = body['enabled'] as bool;
          policyRevision = (body['expected_revision'] as int) + 1;
          return _result(policyReceipt(body));
        }
        if (path == _historyPath && request.method == 'GET') {
          return _result(_historyResponse());
        }
        if (path.startsWith('$_accessPath/operations/') &&
            request.method == 'GET') {
          return _result(accessOperation(request.url.pathSegments.last));
        }
        if (path.startsWith(
              '/api/admin/notification-operator/policies/operations/',
            ) &&
            request.method == 'GET') {
          return _result(policyOperation(request.url.pathSegments.last));
        }
        if (path == '/api/admin/notification-operator') {
          return _result({
            'contract_version': 1,
            'scope': 'assisted_sms_internal_record',
            'delivery_confirmed': false,
            'provider_confirmation': false,
            'settlement_status': 'not_asserted',
            'request_id': _body(request)['request_id'],
            'observed': false,
            'receipt': null,
            'may_send': false,
          });
        }
        throw StateError('Unexpected management request ${request.url.path}');
      }),
      origin: Uri.parse('https://admin.example.test'),
      environment: supabase
          ? backend.environment(admin: 'https://admin.example.test')
          : legacyBackendFixtureEnvironment,
    );
  }
  final String role;
  final bool supabase, emailProofPresent;
  final Duration emailProofAge;
  final int assurance;
  final bool adminManage;
  bool readGranted, manageGranted;
  int decisionRevision;
  String principal = _principal;
  int sessionReads = 0, policyRevision = 3;
  bool policyEnabled = true;
  final now = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
  final Future<http.Response?> Function(http.Request)? handler;
  late final CloudflareAdminSession session;
  final requests = <http.Request>[];
  Iterable<http.Request> get writes => requests.where(
    (request) =>
        request.method == 'POST' &&
        request.url.path != '/api/admin/notification-operator',
  );
  Map<String, dynamic> access() => {
    ..._markers, 'scope': 'owner_receipt_sms_access',
    'current_admin_id': _admin, 'current_principal_id': principal,
    'read_granted': readGranted, 'manage_granted': manageGranted,
    'can_operate': readGranted && manageGranted,
    'decision_revision': decisionRevision,
    // These names are role definitions, even when both actual grants are false.
    'permissions': ['assisted_sms.read', 'assisted_sms.manage'],
  };
  Map<String, dynamic> accessReceipt(
    Map<String, dynamic> body, {
    bool replay = false,
  }) {
    final decision = <String, dynamic>{
      'kind': 'authenticated_owner_receipt_sms_access',
      'request_id': body['request_id'],
      'grant_transaction_id': _transaction,
      'current_admin_id': _admin,
      'current_principal_id': _principal,
      'originating_session_id': _canonical,
      'public_session_id': _public,
      'enabled': body['enabled'],
      'decision_revision': (body['expected_decision_revision'] as int) + 1,
      'permissions': ['assisted_sms.read', 'assisted_sms.manage'],
      'recorded_at': now.toIso8601String(),
    };
    return {
      ..._markers,
      'scope': 'owner_receipt_sms_access',
      ...decision,
      'read_granted': body['enabled'],
      'manage_granted': body['enabled'],
      'can_operate': body['enabled'],
      'decision_sha256': _digest(decision),
      'recorded_state_only': true,
      'replay': replay,
    };
  }

  Map<String, dynamic> accessOperation(
    String requestId, {
    Map<String, dynamic>? recorded,
  }) => {
    ..._markers,
    'scope': 'owner_receipt_sms_access_operation',
    'request_id': requestId,
    'observed': recorded != null,
    'status': recorded == null ? 'not_recorded' : 'recorded',
    'may_be_in_flight': recorded == null,
    'recorded_decision': recorded,
    'current_access': access(),
    'recorded_state_only': true,
    'may_send': false,
    'replay_authorized': false,
  };

  Map<String, dynamic> policyOperation(
    String requestId, {
    Map<String, dynamic>? recorded,
  }) => {
    ..._markers,
    'scope': 'owner_receipt_sms_policy_operation',
    'request_id': requestId,
    'observed': recorded != null,
    'status': recorded == null ? 'not_recorded' : 'recorded',
    'may_be_in_flight': recorded == null,
    'recorded_decision': recorded,
    'recorded_state_only': true,
    'may_send': false,
    'replay_authorized': false,
  };

  Map<String, dynamic> policy({String collectionId = _collection}) => {
    ..._markers,
    'scope': 'owner_receipt_sms_configuration',
    'collection_id': collectionId,
    'configured': true,
    'enabled': policyEnabled,
    'revision': policyRevision,
    'template_key': 'collect.recorded_contribution.v1',
    'recorded_owner_decision_sha256': 'a' * 64,
    'recorded_at': now.toIso8601String(),
    'collection_active': true,
  };
  Map<String, dynamic> policyReceipt(
    Map<String, dynamic> body, {
    String collectionId = _collection,
  }) {
    final decision = <String, dynamic>{
      'kind': 'authenticated_owner_receipt_sms_policy',
      'request_id': body['request_id'],
      'collection_id': collectionId,
      'revision': (body['expected_revision'] as int) + 1,
      'enabled': body['enabled'],
      'template_key': 'collect.recorded_contribution.v1',
      'owner_user_id': _principal,
      'originating_session_id': _canonical,
      'public_session_id': _public,
      'recorded_at': now.toIso8601String(),
      'legal_release_approved': false,
      'provider_approved': false,
    };
    return {
      ..._markers,
      'scope': 'owner_receipt_sms_configuration',
      ...decision,
      'recorded_owner_decision_sha256': _digest(decision),
    };
  }
}

Map<String, dynamic> _historyItem(
  String requestId, {
  String kind = 'access',
  String recordedAt = '2026-10-16T10:00:00.000Z',
}) => {
  'request_id': requestId,
  'kind': kind,
  'recorded_at': recordedAt,
  'recorded_outcome': kind == 'materialization'
      ? 'plan_recorded'
      : 'decision_recorded',
  'status_path': switch (kind) {
    'access' => '$_accessPath/operations/$requestId',
    'policy' =>
      '/api/admin/notification-operator/policies/operations/$requestId',
    'materialization' =>
      '/api/admin/notification-operator/materialize/$requestId',
    _ => throw ArgumentError('Unknown controlled history kind'),
  },
  'recorded_state_only': true,
  'may_send': false,
};

Map<String, dynamic> _historyResponse({
  List<Map<String, dynamic>> items = const [],
  Map<String, dynamic>? nextCursor,
}) => {
  ..._markers,
  'scope': 'own_receipt_sms_request_history',
  'items': items,
  'next_cursor': nextCursor,
  'original_session_only': true,
  'recorded_state_only': true,
  'may_send': false,
  'replay_authorized': false,
};

Finder _serverHistory() => find.byWidgetPredicate(
  (widget) =>
      widget is AdminDataTable &&
      widget.tableLabel == 'Server-recorded assisted SMS request history',
);

Finder _facts(String label) => find.byWidgetPredicate(
  (widget) => widget is AdminRecordFactsTable && widget.semanticLabel == label,
);

Future<void> _tapKey(WidgetTester tester, Key key) async {
  final control = find.byKey(key);
  await _reveal(tester, control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _loadHistory(WidgetTester tester) =>
    _tapKey(tester, const Key('notification-management-history-load'));

Map<String, dynamic> _body(http.Request request) =>
    Map<String, dynamic>.from(jsonDecode(request.body) as Map);

Map<String, dynamic> _retainedReference(
  MemoryAdminPendingAttemptStorage storage,
) {
  final envelope = Map<String, dynamic>.from(
    jsonDecode(storage.values.values.single) as Map,
  );
  return Map<String, dynamic>.from((envelope['entries'] as List).single as Map);
}

class _RejectedStorage implements AdminPendingAttemptStorage {
  @override
  String? read(String key) => null;
  @override
  void remove(String key) {}
  @override
  void write(String key, String value) =>
      throw StateError('Storage unavailable');
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Fixture fixture,
  AdminPendingAttemptStorage storage, {
  Size size = const Size(1440, 1100),
  double scale = 1,
  bool reduceMotion = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.runAsync(fixture.session.refresh);
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => fixture.session),
      adminPendingAttemptStorageProvider.overrideWithValue(storage),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AdminTheme.adapt(AppTheme.dark()),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: const Scaffold(body: CloudflareAdminNotificationManagementPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
}

Future<void> _tap(WidgetTester tester, String label) async {
  final finder = find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      )
      .first;
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _refreshCurrentAccess(WidgetTester tester) async {
  final anchor = find.byKey(const Key('notification-management-history-load'));
  final outer = find.byKey(const Key('admin-page-scroll-view'));
  expect(tester.widget(outer), isA<ListView>());
  expect(find.ancestor(of: anchor, matching: outer), findsOneWidget);
  Scrollable.of(tester.element(anchor), axis: Axis.vertical).position.jumpTo(0);
  await tester.pumpAndSettle();
  final refresh = find.byTooltip('Refresh current assisted SMS access');
  await _reveal(tester, refresh);
  await tester.tap(refresh);
  await tester.pumpAndSettle();
}

Future<void> _toggleDetails(WidgetTester tester, Key key) async {
  final header = find
      .descendant(of: find.byKey(key), matching: find.byType(ListTile))
      .first;
  await _reveal(tester, header);
  await tester.tap(header);
  await tester.pumpAndSettle();
}

Future<void> _expectCollapsedDetailsName(
  WidgetTester tester,
  Key key,
  String label,
) async {
  final header = find
      .descendant(of: find.byKey(key), matching: find.byType(ListTile))
      .first;
  await _reveal(tester, header);
  expect(find.bySemanticsLabel(label), findsOneWidget);
}

Future<void> _checkBox(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(CheckboxListTile, label);
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _lookupPolicy(
  WidgetTester tester, {
  String collectionId = _collection,
}) async {
  final field = find.widgetWithText(TextField, 'Collection UUID');
  await _reveal(tester, field);
  await tester.enterText(field, collectionId);
  await _tap(tester, 'Check current collection policy');
}

void main() {
  testWidgets('Supabase email-verified AAL1 Owner opens management controls', (
    tester,
  ) async {
    final fixture = _Fixture(supabase: true, assurance: 1);
    final container = await _mount(
      tester,
      fixture,
      MemoryAdminPendingAttemptStorage(),
    );
    try {
      expect(fixture.session.user!.assuranceLevel, 1);
      expect(fixture.session.user!.mfaAt, isNull);
      expect(fixture.session.user!.usesEmailVerification, isTrue);
      expect(find.text('Verify email'), findsNothing);
      expect(
        fixture.requests.any(
          (request) =>
              request.url.path.endsWith('/notification-operator/access'),
        ),
        isTrue,
      );
      expect(fixture.writes, isEmpty);
    } finally {
      await _close(tester, container);
    }
  });

  testWidgets(
    'Supabase missing proof offers email verification without a send',
    (tester) async {
      final fixture = _Fixture(
        supabase: true,
        assurance: 1,
        emailProofPresent: false,
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      try {
        expect(find.text('Verify email'), findsOneWidget);
        expect(find.textContaining('fresh authenticator'), findsNothing);
        expect(fixture.requests, isEmpty);
      } finally {
        await _close(tester, container);
      }
    },
  );

  testWidgets(
    'email proof deadline closes management controls before session expiry',
    (tester) async {
      final fixture = _Fixture(
        supabase: true,
        assurance: 1,
        emailProofAge: const Duration(minutes: 4, seconds: 30),
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      try {
        expect(find.text('Verify email'), findsNothing);
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
        expect(find.text('Verify email'), findsOneWidget);
        expect(fixture.writes, isEmpty);
      } finally {
        await _close(tester, container);
      }
    },
  );

  _registerNotificationCommandPageCases();
  _registerNotificationRecoveryPageCases();
  _registerNotificationHistoryAuthorityPageCases();
  _registerNotificationPagingResponsivePageCases();
}
