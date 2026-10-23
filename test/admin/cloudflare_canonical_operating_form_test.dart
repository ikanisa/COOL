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

import 'cloudflare_canonical_reconciliation_support.dart';

Future<void> enter(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

Future<({FinancialHarness harness, List<Map<String, dynamic>> sent})>
_groupForm(
  WidgetTester tester, {
  String role = 'owner',
  String? withoutPermission,
  bool freshMfa = true,
  CloudflareOperatingDetail? detail,
  String route = '0788123456',
  String? initialVisibility,
}) async {
  final auth = canonicalSession(role: role);
  final user = auth['user'] as Map<String, dynamic>;
  (user['permissions'] as List).remove(withoutPermission);
  if (!freshMfa) {
    user['mfaAt'] = DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 6))
        .toIso8601String();
  }
  final sent = <Map<String, dynamic>>[];
  final h = await FinancialHarness.create(
    ownsSession: false,
    auth: auth,
    reply: (request) async {
      sent.add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      final key =
          request.headers['Idempotency-Key'] ??
          request.headers['idempotency-key']!;
      return financialResponse({
        'status': 'succeeded',
        'request_id': canonicalAdminRequestId(
          user['principalId'] as String,
          key,
        ),
        'resource_type': 'groups',
        'resource_id': financialFixture('detail')['resource']['group_id'],
        'version': detail == null ? 1 : detail.version! + 1,
      });
    },
  );
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => h.session),
      adminRepositoryProvider.overrideWithValue(
        CloudflareAdminRepository(h.session),
      ),
      adminPendingAttemptStorageProvider.overrideWithValue(h.storage),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CloudflareOperatingForm(
              operation: detail == null
                  ? CloudflareOperation.createGroup
                  : CloudflareOperation.updateGroup,
              detail: detail,
              initial: {
                if (detail == null) ...{
                  'title': 'Recorded public group',
                  'slug': 'recorded-public-group',
                  'collection_type': 'ikimina',
                  'receiver_label': 'Recorded receiver',
                  'receiver_network': 'mtn_momo',
                  'receiver_route': route,
                },
                if (initialVisibility != null) ...{
                  'visibility': initialVisibility,
                  'is_platform_sponsored': true,
                },
              },
              fixed: detail == null
                  ? {
                      'owner_user_id': financialFixture(
                        'detail',
                      )['resource']['group_id'],
                    }
                  : const {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (harness: h, sent: sent);
}

CloudflareOperatingDetail _groupDetail({
  String visibility = 'private',
  bool sponsored = false,
  bool receiver = true,
}) {
  final data = financialFixture('detail');
  final id = data['resource']['group_id'] as String;
  return CloudflareOperatingDetail(
    type: 'groups',
    resource: {
      'id': id,
      'version': 7,
      'title': 'Existing recorded group',
      'collection_type': 'ikimina',
      'description': '',
      'status': 'active',
      'visibility': visibility,
      'is_platform_sponsored': sponsored,
      'owner_user_id': id,
    },
    actorId: data['current_actor_id'] as String,
    canManage: true,
    related: {
      'payees': [
        if (receiver)
          {
            'status': 'active',
            'network': 'mtn_momo',
            'momo_number_or_code': '0788123456',
          },
      ],
    },
    truncated: false,
    sourceModel: 'canonical_evidence_ledger',
    allowedOperations: const {CloudflareOperation.updateGroup},
  );
}

Future<void> _selectPublic(WidgetTester tester) async {
  final visibility = find.widgetWithText(
    DropdownButtonFormField<String>,
    'Visibility',
  );
  await tester.ensureVisible(visibility);
  await tester.tap(visibility);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Public Approved').last);
  await tester.pumpAndSettle();
}

Future<void> _reviewGroup(WidgetTester tester) async {
  await enter(
    tester,
    'Reason for this change',
    'Reviewed the recorded owner and Rwanda MoMo receiver',
  );
  await tester.ensureVisible(find.text('Review change'));
  await tester.tap(find.text('Review change'));
  await tester.pumpAndSettle();
}

Future<void> _finishGroup(WidgetTester tester, FinancialHarness harness) async {
  harness.session.clear();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('canonical group creation defaults to private and unsponsored', (
    tester,
  ) async {
    final form = await _groupForm(tester);
    await _reviewGroup(tester);
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(form.sent.single['visibility'], 'private');
    expect(form.sent.single['is_platform_sponsored'], isFalse);
    expect(form.sent.single['receiver']['momo_number_or_code'], '0788123456');
    await _finishGroup(tester, form.harness);
  });
  for (final role in ['owner', 'admin']) {
    testWidgets('$role can publish a sponsored group with a merchant code', (
      tester,
    ) async {
      final form = await _groupForm(tester, role: role, route: '008000');
      await _selectPublic(tester);
      expect(find.text('Platform sponsored'), findsNothing);
      await _reviewGroup(tester);
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();
      expect(form.sent.single['visibility'], 'public_approved');
      expect(form.sent.single['is_platform_sponsored'], isTrue);
      expect(form.sent.single['receiver']['momo_number_or_code'], '008000');
      expect(form.sent.single['owner_user_id'], isNotEmpty);
      expect(tester.takeException(), isNull);
      await _finishGroup(tester, form.harness);
    });
  }
  for (final restriction in [
    'staff',
    'receivers.manage',
    'collections.manage',
  ]) {
    testWidgets(
      '$restriction cannot publish even with a public initial value',
      (tester) async {
        final form = await _groupForm(
          tester,
          role: restriction == 'staff' ? 'staff' : 'admin',
          withoutPermission: restriction == 'staff' ? null : restriction,
          initialVisibility: 'public_approved',
        );
        expect(find.text('Visibility'), findsNothing);
        await _reviewGroup(tester);
        await tester.tap(find.text('Confirm change'));
        await tester.pumpAndSettle();
        expect(form.sent.single['visibility'], 'private');
        expect(form.sent.single['is_platform_sponsored'], isFalse);
        await _finishGroup(tester, form.harness);
      },
    );
  }
  testWidgets('a merchant code is rejected while a new group remains private', (
    tester,
  ) async {
    final form = await _groupForm(tester, route: '008000');
    await _reviewGroup(tester);
    expect(form.sent, isEmpty);
    expect(find.text('Enter the recorded Rwanda MoMo number.'), findsOneWidget);
    expect(find.text('Confirm change'), findsNothing);
    await _finishGroup(tester, form.harness);
  });
  testWidgets('publication requires a fresh authenticator verification', (
    tester,
  ) async {
    final form = await _groupForm(tester, freshMfa: false);
    await _selectPublic(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Review change'),
          )
          .onPressed,
      isNull,
    );
    expect(form.sent, isEmpty);
    expect(find.text('Verify authenticator'), findsOneWidget);
    await _finishGroup(tester, form.harness);
  });
  for (final visibility in ['private', 'public_pending']) {
    testWidgets(
      'publishing $visibility preserves the recorded owner and receiver',
      (tester) async {
        final form = await _groupForm(
          tester,
          detail: _groupDetail(visibility: visibility),
        );
        await _selectPublic(tester);
        await _reviewGroup(tester);
        await tester.tap(find.text('Confirm change'));
        await tester.pumpAndSettle();
        expect(form.sent.single['expected_version'], 7);
        expect(form.sent.single['visibility'], 'public_approved');
        expect(form.sent.single['is_platform_sponsored'], isTrue);
        expect(form.sent.single.containsKey('owner_user_id'), isFalse);
        expect(form.sent.single.containsKey('receiver'), isFalse);
        expect(form.sent.single.containsKey('receiver_route'), isFalse);
        await _finishGroup(tester, form.harness);
      },
    );
  }
  testWidgets('ordinary group edits omit visibility and sponsored keys', (
    tester,
  ) async {
    final form = await _groupForm(tester, detail: _groupDetail());
    await _reviewGroup(tester);
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(form.sent.single.containsKey('visibility'), isFalse);
    expect(form.sent.single.containsKey('is_platform_sponsored'), isFalse);
    await _finishGroup(tester, form.harness);
  });
  testWidgets('publication requires the recorded active receiver', (
    tester,
  ) async {
    final form = await _groupForm(
      tester,
      detail: _groupDetail(receiver: false),
    );
    await _selectPublic(tester);
    await _reviewGroup(tester);
    expect(form.sent, isEmpty);
    expect(
      find.text(
        'Refresh the recorded group owner and active MoMo receiver before publishing.',
      ),
      findsOneWidget,
    );
    expect(find.text('Confirm change'), findsNothing);
    await _finishGroup(tester, form.harness);
  });
  testWidgets('public group edits cannot demote or unlock its receiver', (
    tester,
  ) async {
    final form = await _groupForm(
      tester,
      detail: _groupDetail(visibility: 'public_approved', sponsored: true),
      initialVisibility: 'private',
    );
    expect(find.text('Visibility'), findsNothing);
    expect(
      find.text(
        'The recorded receiver is permanently locked for this public or platform-sponsored group.',
      ),
      findsOneWidget,
    );
    await _reviewGroup(tester);
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(form.sent.single.containsKey('visibility'), isFalse);
    expect(form.sent.single.containsKey('is_platform_sponsored'), isFalse);
    await _finishGroup(tester, form.harness);
  });
  testWidgets(
    'canonical evidence recovery stores only a digest and requires exact text before a same-key retry',
    (tester) async {
      final sent = <String>[];
      final keys = <String>[];
      late String principal;
      var first = true;
      final h = await FinancialHarness.create(
        ownsSession: false,
        reply: (request) async {
          if (request.method == 'POST') {
            final key =
                request.headers['Idempotency-Key'] ??
                request.headers['idempotency-key']!;
            keys.add(key);
            sent.add(request.body);
            if (first) {
              first = false;
              return financialResponse({
                'error': {'code': 'service_unavailable'},
              }, 503);
            }
            return financialResponse({
              'status': 'succeeded',
              'request_id': canonicalAdminRequestId(principal, key),
              'resource_type': 'transactions',
              'resource_id': financialFixture('detail')['resource']['id'],
              'version': 1,
            });
          }
          return financialResponse({
            'contract_version': 2,
            'model': 'canonical_evidence_ledger',
            'status': 'not_found',
          });
        },
      );
      principal = h.session.user!.principalId!;
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          cloudflareAdminSessionProvider.overrideWith((_) => h.session),
          adminRepositoryProvider.overrideWithValue(
            CloudflareAdminRepository(h.session),
          ),
          adminPendingAttemptStorageProvider.overrideWithValue(h.storage),
        ],
      );
      var disposed = false;
      void dispose() {
        if (!disposed) {
          disposed = true;
          container.dispose();
        }
      }

      addTearDown(dispose);
      Future<void> show(String key) async {
        final groupId = financialFixture('detail')['resource']['group_id'];
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: CloudflareOperatingForm(
                    key: ValueKey(key),
                    operation: CloudflareOperation.createTransaction,
                    fixed: {'group_id': groupId, 'payee_id': groupId},
                    initial: const {
                      'group_id_label': 'Controlled group',
                      'payee_id_label': 'Recorded receiver',
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show('first');
      const raw =
          'Exact controlled financial evidence that must not persist in browser recovery storage.';
      await enter(tester, 'Evidence reference', 'controlled-reference');
      await enter(tester, 'Recorded amount (RWF)', '1500');
      final observed = DateTime.now()
          .toUtc()
          .subtract(const Duration(seconds: 30))
          .toIso8601String();
      await enter(tester, 'Observed at (UTC)', observed);
      await enter(tester, 'Exact evidence text', raw);
      await enter(
        tester,
        'Reason for this change',
        'Retain the exact reviewed payment evidence',
      );
      await tester.ensureVisible(find.text('Review change'));
      await tester.tap(find.text('Review change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(
        h.storage.values.values.single,
        contains('retained_operator_text'),
      );
      expect(h.storage.values.values.single, isNot(contains(raw)));
      await show('replacement');
      await tester.ensureVisible(find.text('Check request status'));
      await tester.tap(find.text('Check request status'));
      await tester.pumpAndSettle();
      final reentry = find.widgetWithText(
        TextField,
        'Re-enter original evidence text',
      );
      await tester.ensureVisible(reentry);
      await tester.enterText(reentry, 'Wrong replacement evidence');
      await tester.ensureVisible(find.text('Retry identical request'));
      await tester.tap(find.text('Retry identical request'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(1));
      expect(
        find.text(
          'Re-enter the exact original evidence text. Its digest must match before this request can be retried.',
        ),
        findsOneWidget,
      );
      await tester.enterText(reentry, raw);
      await tester.ensureVisible(find.text('Retry identical request'));
      await tester.tap(find.text('Retry identical request'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm identical retry'));
      await tester.pumpAndSettle();
      expect(sent, hasLength(2));
      expect(keys.last, keys.first);
      expect(sent.last, sent.first);
      expect(jsonDecode(sent.first)['evidence'], raw);
      expect(h.storage.values, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      dispose();
      await tester.pumpAndSettle();
    },
  );
}
