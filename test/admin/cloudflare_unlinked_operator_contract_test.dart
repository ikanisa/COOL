import 'dart:convert';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/admin_theme.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const _person = '40000000-0000-4000-8000-000000000001';
const _actor = '40000000-0000-4000-8000-000000000002';
const _principal = '40000000-0000-4000-8000-000000000003';
const _linkedAdmin = '40000000-0000-4000-8000-000000000004';
const _date = '2026-10-16T10:00:00.000Z';

// Scalar identity/contact values are synthetic. Only the observed unlinked
// tuple structure is reproduced; this is not the hosted row's identity.
Map<String, dynamic> _operatorRow() => {
  'id': _person,
  'title': '000321',
  'subtitle': 'Synthetic unlinked Operator',
  'amount': '0 groups',
  'status': 'active',
  'created_at': _date,
  'country_code': 'RW',
  'currency_code': 'RWF',
  'public_id': '000321',
  'display_name': 'Synthetic unlinked Operator',
  'display_name_recorded': true,
  'person_id': _person,
  'collect_user_id': _person,
  'operator_admin_id': null,
  'operator_public_id': null,
  'operator_role': null,
  'operator_status': null,
  'user_types': ['Operator'],
  'member_type': 'operator',
  'phone_e164': null,
  'email': null,
  'whatsapp_number': null,
  'momo_provider': null,
  'momo_number': null,
  'momo_pay_code': null,
  'total_contributed_rwf': 0,
  'posted_contributed_rwf': null,
  'contribution_basis': 'reconciled_evidence_entries',
  'name_verification': 'recorded_not_provider_verified',
  'phone_masked': null,
  'email_masked': null,
  'active_groups': 0,
  'account_status': 'active',
  'version': 1,
  'updated_at': _date,
};

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: const {'content-type': 'application/json'},
);

class _Harness {
  _Harness(this.session, this.repository, this.requests);
  final CloudflareAdminSession session;
  final CloudflareAdminRepository repository;
  final List<http.Request> requests;

  static Future<_Harness> create({
    List<String> allowedOperations = const [],
    bool canManage = false,
    bool ownsSession = true,
  }) async {
    final requests = <http.Request>[];
    final now = DateTime.now().toUtc();
    final session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path == '/api/admin/auth/session') {
          return _json({
            'user': {
              'id': _actor,
              'principalId': _principal,
              'email': 'controlled@example.test',
              'role': 'owner',
              'sessionId': 'unlinked-operator-controlled-session',
              'financialModel': 'canonical_evidence_ledger',
              'assuranceLevel': 2,
              'mfaAt': now.toIso8601String(),
              // Full generic mutation grants make the row policy decisive.
              'permissions': [
                'users.read',
                'users.manage',
                'collections.read',
                'collections.manage',
                'admin_users.manage',
              ],
            },
            'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
          });
        }
        requests.add(request);
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/core/users') {
          return _json({
            'contract_version': 2,
            'model': 'canonical_evidence_ledger',
            'rows': [_operatorRow()],
            'total': 1,
          });
        }
        if (request.url.path == '/api/admin/operations/users/$_person') {
          return _json({
            'contract_version': 2,
            'model': 'canonical_evidence_ledger',
            'resource_type': 'users',
            'resource': _operatorRow(),
            'current_actor_id': _actor,
            'can_manage': canManage,
            'allowed_operations': allowedOperations,
            'related': <String, dynamic>{},
            'related_pages': <String, dynamic>{},
            'related_truncated': false,
          });
        }
        if (request.url.path == '/api/admin/operations/users/$_person/notes') {
          return _json({
            'contract_version': 1,
            'entity_type': 'profile',
            'entity_id': _person,
            'rows': <Object>[],
            'total': 0,
            'limit': 25,
            'offset': 0,
          });
        }
        if (request.url.path == '/api/admin/operations/lookups') {
          return _json({
            'contract_version': 2,
            'model': 'canonical_evidence_ledger',
            'kind': 'users',
            'group_id': null,
            'rows': [
              {
                ..._operatorRow(),
                'name': 'Synthetic unlinked Operator',
                'label': 'Synthetic unlinked Operator',
              },
            ],
            'total': 1,
          });
        }
        throw StateError('Unexpected controlled read ${request.url.path}');
      }),
      origin: Uri.parse('https://admin.example.test'),
      environment: legacyBackendFixtureEnvironment,
    );
    if (ownsSession) {
      addTearDown(session.dispose);
    }
    await session.refresh();
    return _Harness(session, CloudflareAdminRepository(session), requests);
  }
}

void main() {
  test(
    'observed unlinked structure needs the explicit Operator label without inventing a link',
    () {
      final invalidObservedShape = _operatorRow()..['user_types'] = <String>[];
      expect(
        () => parseCanonicalEvidenceRecord(
          CloudflareCoreArea.users,
          invalidObservedShape,
        ),
        throwsFormatException,
      );
      // Run this exact positive assertion against the pinned old contract to
      // demonstrate its blanket rejection, then against the private successor.
      final parsed = parseCanonicalEvidenceRecord(
        CloudflareCoreArea.users,
        _operatorRow(),
      );
      expect(parsed['user_types'], ['Operator']);
      expect(parsed['id'], _person);
      expect(parsed['collect_user_id'], _person);
      for (final field in [
        'operator_admin_id',
        'operator_public_id',
        'operator_role',
        'operator_status',
      ]) {
        expect(parsed[field], isNull, reason: field);
      }
      expect(parsed['whatsapp_number'], isNull);
      expect(
        () => parsed['operator_admin_id'] = _linkedAdmin,
        throwsUnsupportedError,
      );
    },
  );

  test(
    'list and detail consume the corrected row as generic read-only data',
    () async {
      final harness = await _Harness.create();
      final list = await harness.repository.list('admin_list_users');
      expect(list.sourceModel, 'canonical_evidence_ledger');
      expect(list.total, 1);
      expect(list.rows.single.extra['user_types'], ['Operator']);
      final detail = await harness.repository.operatingDetail('users', _person);
      expect(detail.resource['collect_user_id'], _person);
      expect(detail.resource['operator_admin_id'], isNull);
      expect(detail.canManage, isFalse);
      expect(detail.allowedOperations, isEmpty);
      expect(detail.allows(CloudflareOperation.updateUser), isFalse);
      expect(detail.allows(CloudflareOperation.createMembership), isFalse);
      expect(harness.requests, hasLength(2));
      expect(
        harness.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
    },
  );

  test('unlinked Operator accepts exactly its single type label', () {
    for (final labels in <Object?>[
      <String>[],
      ['App'],
      ['Direct'],
      ['Admin'],
      ['Staff'],
      ['Operator', 'App'],
      ['Admin', 'Operator'],
      ['Operator', 'Operator'],
      ['operator'],
      'Operator',
    ]) {
      expect(
        () => parseCanonicalEvidenceRecord(
          CloudflareCoreArea.users,
          _operatorRow()..['user_types'] = labels,
        ),
        throwsFormatException,
        reason: '$labels',
      );
    }
  });

  test(
    'missing or contradictory identity and linkage tuples still fail closed',
    () {
      for (final change in <Map<String, dynamic>>[
        {'collect_user_id': null},
        {'collect_user_id': 'not-a-uuid'},
        {'person_id': _linkedAdmin},
        {'operator_admin_id': _linkedAdmin},
        {'operator_role': 'owner'},
        {'operator_status': 'active'},
        {'operator_public_id': '000654'},
        {
          'operator_admin_id': 'not-a-uuid',
          'operator_role': 'admin',
          'operator_status': 'active',
          'operator_public_id': '000654',
          'user_types': ['Admin'],
        },
        {
          'operator_admin_id': _linkedAdmin,
          'operator_role': 'operator',
          'operator_status': 'active',
          'operator_public_id': '000654',
          'user_types': ['Admin'],
        },
        {
          'operator_admin_id': _linkedAdmin,
          'operator_role': 'staff',
          'operator_status': 'unknown',
          'operator_public_id': '000654',
          'user_types': ['Staff'],
        },
        {
          'operator_admin_id': _linkedAdmin,
          'operator_role': 'staff',
          'operator_status': 'active',
          'operator_public_id': '654',
          'user_types': ['Staff'],
        },
        {'member_type': 'unknown'},
        {'whatsapp_number': '+250788123456'},
      ]) {
        expect(
          () => parseCanonicalEvidenceRecord(
            CloudflareCoreArea.users,
            _operatorRow()..addAll(change),
          ),
          throwsFormatException,
          reason: '$change',
        );
      }
    },
  );

  test(
    'all existing linked roles retain App Direct and operator type ordering',
    () {
      for (final role in ['owner', 'admin', 'staff']) {
        for (final memberType in ['app', 'direct', 'operator']) {
          final expectedTypes = [
            role == 'staff' ? 'Staff' : 'Admin',
            if (memberType == 'app') 'App',
            if (memberType == 'direct') 'Direct',
          ];
          final row = _operatorRow()
            ..addAll({
              'operator_admin_id': _linkedAdmin,
              'operator_role': role,
              'operator_status': 'active',
              'operator_public_id': '000654',
              'member_type': memberType,
              'user_types': expectedTypes,
            });
          final parsed = parseCanonicalEvidenceRecord(
            CloudflareCoreArea.users,
            row,
          );
          expect(
            parsed['user_types'],
            expectedTypes,
            reason: '$role/$memberType',
          );
          expect(parsed['operator_admin_id'], _linkedAdmin);
        }
      }
    },
  );

  test(
    'the operator row cannot become a member or a user lookup candidate',
    () async {
      final memberShape = _operatorRow()
        ..addAll({'active_groups': 1, 'amount': '1 groups'});
      expect(
        () => parseCanonicalEvidenceRecord(
          CloudflareCoreArea.members,
          memberShape,
        ),
        throwsFormatException,
      );
      final harness = await _Harness.create();
      await expectLater(
        harness.repository.operatingLookups('users'),
        throwsFormatException,
      );
      expect(harness.requests.single.method, 'GET');
    },
  );

  test(
    'generic action claims for an Operator are rejected even for a fully granted Owner',
    () async {
      for (final actions in [
        ['updateUser'],
        ['createMembership'],
        <String>[],
      ]) {
        final harness = await _Harness.create(
          allowedOperations: actions,
          canManage: true,
        );
        await expectLater(
          harness.repository.operatingDetail('users', _person),
          throwsFormatException,
          reason: '$actions',
        );
        expect(harness.requests.single.method, 'GET');
      }
    },
  );

  testWidgets(
    'actual Operator detail and direct edit page present no generic mutation control',
    (tester) async {
      final harness = (await tester.runAsync(
        () => _Harness.create(ownsSession: false),
      ))!;
      final container = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(harness.repository),
          cloudflareAdminSessionProvider.overrideWith((_) => harness.session),
          adminPendingAttemptStorageProvider.overrideWithValue(
            MemoryAdminPendingAttemptStorage(),
          ),
        ],
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AdminTheme.adapt(AppTheme.dark()),
              home: const Scaffold(
                body: CloudflareOperatingDetailPage(
                  type: 'users',
                  id: _person,
                  backPath: '/admin/users',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Operator'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Edit person'),
          findsNothing,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Add group member'),
          findsNothing,
        );
        expect(find.byType(CloudflareOperatingForm), findsNothing);
        final refresh = find.byTooltip('Refresh record');
        expect(refresh.hitTestable(), findsOneWidget);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(OutlinedButton, 'Edit person'),
          findsNothing,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Add group member'),
          findsNothing,
        );
        expect(
          harness.requests.where(
            (request) =>
                request.url.path == '/api/admin/operations/users/$_person',
          ),
          hasLength(2),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AdminTheme.adapt(AppTheme.dark()),
              home: const Scaffold(
                body: CloudflareOperatingEditPage(
                  type: 'users',
                  id: _person,
                  backPath: '/admin/users',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Your account can view this record but cannot perform this action.',
          ),
          findsOneWidget,
        );
        expect(find.text('Review change'), findsNothing);
        expect(
          find.widgetWithText(TextFormField, 'Recorded full name'),
          findsNothing,
        );
        expect(
          harness.requests.every((request) => request.method == 'GET'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
}
