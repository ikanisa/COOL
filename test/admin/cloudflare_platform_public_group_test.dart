import 'dart:convert';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_public_group.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_request_identity.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../core/supabase_backend_test.dart' as fixtures;
import 'cloudflare_canonical_reconciliation_support.dart';

const _group = '30000000-0000-4000-8000-000000000019';
const _draft = <String, dynamic>{
  'p_title': 'Synthetic sponsored group',
  'p_description': 'Synthetic description',
  'p_collection_type': 'ikimina',
  'p_category_subtype': 'community',
  'p_purpose_label': 'Synthetic savings',
  'p_receiver_label': 'Synthetic route label',
  'p_momo_code': '0001',
  'p_network': 'mtn_momo',
  'p_reason': 'Synthetic approved sponsorship',
};

String _key(http.Request request) =>
    request.headers['Idempotency-Key'] ?? request.headers['idempotency-key']!;
Map<String, dynamic> _receipt(FinancialHarness h, String key) => {
  'status': 'succeeded',
  'request_id': canonicalAdminRequestId(
    (h.auth['user'] as Map)['principalId'] as String,
    key,
  ),
  'resource_type': 'groups',
  'resource_id': _group,
  'version': 1,
};

Future<
  ({FinancialHarness harness, ProviderContainer container, int Function() done})
>
_mount(
  WidgetTester tester, {
  String role = 'owner',
  bool fresh = true,
  Future<http.Response> Function(http.Request, FinancialHarness)? reply,
}) async {
  late FinancialHarness h;
  h = (await tester.runAsync(
    () => FinancialHarness.create(
      ownsSession: false,
      auth: canonicalSupabaseFinancialSession(role: role),
      environment: fixtures.environment(),
      origin: Uri.parse('https://admin.collect.ikanisa.com'),
      emailVerification: financialSupabaseEmailProof(
        fresh
            ? DateTime.now()
                  .toUtc()
                  .subtract(const Duration(seconds: 1))
                  .toIso8601String()
            : null,
      ),
      reply: (request) async => reply != null
          ? reply(request, h)
          : financialResponse(_receipt(h, _key(request))),
    ),
  ))!;
  expect(h.session.user!.usesCanonicalEvidence, true);
  expect(h.session.user!.hasRecentSensitiveVerification(), fresh);
  var done = 0;
  final overrides = [
    cloudflareAdminSessionProvider.overrideWith((_) => h.session),
    adminRepositoryProvider.overrideWithValue(
      CloudflareAdminRepository(h.session),
    ),
    adminPendingAttemptStorageProvider.overrideWithValue(h.storage),
  ];
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Scaffold(
          body: CloudflarePublicGroupCreateButton(
            onCreatePrivate: () {},
            onDone: () => done++,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CloudflarePublicGroupCreateButton)),
  );
  return (harness: h, container: container, done: () => done);
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create public group'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester) async {
  for (final field in <String, String>{
    'Group name': _draft['p_title'] as String,
    'Description': _draft['p_description'] as String,
    'Category key': _draft['p_category_subtype'] as String,
    'Purpose label': _draft['p_purpose_label'] as String,
    'Official payee name': _draft['p_receiver_label'] as String,
    'MoMo number or code': _draft['p_momo_code'] as String,
    'Creation reason': _draft['p_reason'] as String,
  }.entries) {
    final finder = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == field.key,
    );
    await tester.ensureVisible(finder);
    await tester.enterText(finder, field.value);
    await tester.pump();
  }
}

Future<void> _submit(WidgetTester tester) async {
  final button = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, 'Create group'),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'public draft maps to owner-less canonical intent without identity or secret fields',
    () {
      final body = platformPublicGroupBody(_draft);
      expect(body['visibility'], 'public_approved');
      expect(body['is_platform_sponsored'], true);
      expect(body['receiver'], {
        'label': 'Synthetic route label',
        'network': 'mtn_momo',
        'momo_number_or_code': '0001',
      });
      expect(body.containsKey('owner_user_id'), false);
      expect(body.containsKey('slug'), false);
      expect(
        body.keys.any(
          (k) => RegExp('phone|pin|password|secret|token|cookie').hasMatch(k),
        ),
        false,
      );
      expect(
        operatingRecoverySchema(
          CloudflareOperation.createGroup,
        ).canonical(body),
        body,
      );
    },
  );

  testWidgets(
    'existing public form submits the real canonical command with current AAL1 email proof',
    (tester) async {
      final sent = <http.Request>[];
      final mounted = await _mount(
        tester,
        reply: (request, h) async {
          sent.add(request);
          return financialResponse(_receipt(h, _key(request)));
        },
      );
      await _open(tester);
      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .join(' | '),
      );
      expect(find.text('Group slug'), findsNothing);
      expect(find.text('Recorded full name'), findsNothing);
      expect(find.text('Group owner'), findsNothing);
      await _fill(tester);
      await _submit(tester);
      expect(sent, hasLength(1));
      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, endsWith('/api/admin/operations/groups'));
      expect(jsonDecode(sent.single.body), platformPublicGroupBody(_draft));
      expect(mounted.harness.session.user!.assuranceLevel, 1);
      expect(mounted.done(), 1);
      expect(find.text('Public group created and activated'), findsOneWidget);
      expect(
        mounted.container
            .read(adminPendingAttemptStoreProvider)
            .restore(
              family: 'operating-creategroup',
              resourceId: 'new',
              schema: operatingRecoverySchema(CloudflareOperation.createGroup),
            ),
        isNull,
      );
    },
  );

  for (final role in ['admin', 'staff']) {
    testWidgets('$role cannot enter the Owner platform-public action', (
      tester,
    ) async {
      await _mount(tester, role: role);
      await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
      await tester.pumpAndSettle();
      expect(find.text('Create public group'), findsNothing);
      expect(find.text('Create private group'), findsOneWidget);
    });
  }

  testWidgets(
    'missing email proof cannot open the public form or issue a command',
    (tester) async {
      var sent = 0;
      await _mount(
        tester,
        fresh: false,
        reply: (r, h) async {
          sent++;
          return financialResponse({});
        },
      );
      await _open(tester);
      expect(find.text('Official payee name'), findsNothing);
      expect(
        find.text('Verify your current Admin email before continuing.'),
        findsOneWidget,
      );
      expect(sent, 0);
    },
  );

  testWidgets(
    'lost response restores original GET and never creates another group',
    (tester) async {
      final calls = <http.Request>[];
      String? originalKey;
      final mounted = await _mount(
        tester,
        reply: (request, h) async {
          calls.add(request);
          if (request.method == 'POST') {
            originalKey = _key(request);
            return financialResponse({
              'error': {
                'code': 'synthetic_unknown',
                'message': 'Synthetic lost reply',
              },
            }, 503);
          }
          return financialResponse({
            'contract_version': 2,
            'model': 'canonical_evidence_ledger',
            'status': 'succeeded',
            'request_id': _receipt(h, originalKey!)['request_id'],
            'receipt': _receipt(h, originalKey!),
          });
        },
      );
      await _open(tester);
      await _fill(tester);
      await _submit(tester);
      expect(mounted.done(), 0);
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      await _open(tester);
      expect(calls.map((r) => r.method), ['POST', 'GET']);
      expect(
        calls.last.url.path,
        endsWith('/operations/requests/$originalKey'),
      );
      expect(mounted.done(), 1);
      expect(find.text('Official payee name'), findsNothing);
    },
  );

  testWidgets('not_found outcome remains retained and cannot replay POST', (
    tester,
  ) async {
    final methods = <String>[];
    await _mount(
      tester,
      reply: (request, h) async {
        methods.add(request.method);
        return request.method == 'POST'
            ? financialResponse({
                'error': {
                  'code': 'synthetic_unknown',
                  'message': 'Synthetic lost reply',
                },
              }, 503)
            : financialResponse({
                'contract_version': 2,
                'model': 'canonical_evidence_ledger',
                'status': 'not_found',
              });
      },
    );
    await _open(tester);
    await _fill(tester);
    await _submit(tester);
    await _open(tester);
    await _open(tester);
    expect(methods, ['POST', 'GET', 'GET']);
    expect(find.text('Official payee name'), findsNothing);
  });

  testWidgets(
    'a change of actual authority removes the existing public draft before submission',
    (tester) async {
      var sent = 0;
      final mounted = await _mount(
        tester,
        reply: (r, h) async {
          sent++;
          return financialResponse({});
        },
      );
      await _open(tester);
      expect(find.text('Official payee name'), findsOneWidget);
      mounted.harness.auth = canonicalSupabaseFinancialSession(role: 'staff');
      await tester.runAsync(() => mounted.harness.session.refresh());
      await tester.pumpAndSettle();
      expect(find.text('Official payee name'), findsNothing);
      expect(sent, 0);
      expect(mounted.done(), 0);
    },
  );
}
