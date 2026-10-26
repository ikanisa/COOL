import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/cloudflare_admin_momo_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/shared/components/admin_data_listing.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'cloudflare_core_fixtures.dart' show coreRow;
import '../support/legacy_backend_fixture.dart';

part 'cloudflare_admin_momo_page_cases/layout_source.dart';
part 'cloudflare_admin_momo_page_cases/gateway.dart';
part 'cloudflare_admin_momo_page_cases/source_review.dart';

const txId = '11111111-1111-4111-8111-111111111111';
const accountId = '22222222-2222-4222-8222-222222222222';
const groupId = '33333333-3333-4333-8333-333333333333';
const memberId = '44444444-4444-4444-8444-444444444444';
const paymentId = '55555555-5555-4555-8555-555555555555';
const rawSmsId = '66666666-6666-4666-8666-666666666666';
Map<String, dynamic> sourceJob({String? binding, String? account}) => {
  'raw_sms_id': rawSmsId,
  'state': 'source_unresolved',
  'binding_id': binding,
  'receiving_account_id': account,
  'received_at': '2026-10-18T08:01:00.000Z',
  'last_error': 'historical_source_unresolved',
};
Map<String, dynamic> sourceResolution() => {
  'raw_sms_id': rawSmsId,
  'receiving_account_id': accountId,
  'status': 'pending',
  'mode': 'historical',
  'financial_effects': 0,
};
Map<String, dynamic> transaction({String status = 'needs_allocation'}) => {
  'id': txId,
  'receiving_account_id': accountId,
  'provider_transaction_id': 'MOMO-SYNTHETIC-001',
  'recipient_name': 'Collect synthetic receiver',
  'public_code': '123456',
  'payer_name': 'Synthetic payer',
  'payer_last3': '007',
  'member_name': null,
  'group_name': null,
  'group_id': null,
  'beneficiary_member_id': null,
  'payment_id': null,
  'amount_minor': 5000,
  'has_conflict': 0,
  'credited_amount_minor': 0,
  'version': 1,
  'currency': 'RWF',
  'status': status,
  'transaction_at': '2026-10-18T08:00:00.000Z',
  'created_at': '2026-10-18T08:01:00.000Z',
};
Map<String, dynamic> page({String status = 'needs_allocation'}) => {
  'contract_version': 1,
  'currency': 'RWF',
  'date_basis': 'provider_transaction_time',
  'rows': [transaction(status: status)],
  'total': 1,
  'offset': 0,
  'limit': 25,
  'totals': {
    'received_minor': 5000,
    'credited_minor': 0,
    'unallocated_minor': 5000,
  },
  'as_of': '2026-10-18T08:02:00.000Z',
};
http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

class _FailingGatewayStorage extends MemoryAdminPendingAttemptStorage {
  bool failWrites = true;
  @override
  void write(String key, String value) {
    if (failWrites) throw StateError('Synthetic recovery storage failure');
    super.write(key, value);
  }
}

Future<({CloudflareAdminSession session, GlobalKey key, VoidCallback dispose})>
pump(
  WidgetTester tester, {
  double width = 1400,
  double textScale = 1,
  bool reduceMotion = false,
  List<String>? permissions,
  bool incoming = false,
  Map<String, dynamic>? records,
  Map<String, dynamic>? detailRecord,
  List<String> conflictingAttempts = const [],
  List<Map<String, dynamic>> sourceJobs = const [],
  List<Map<String, dynamic>> transactionSources = const [],
  List<Map<String, dynamic>>? receivingAccounts,
  AdminPendingAttemptStorage? pendingStorage,
  Map<String, dynamic> Function(http.Request)? transactionRecords,
  Future<http.Response> Function(http.Request)? respond,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final grants =
      permissions ??
      [
        'payments.read',
        'payments.write',
        'users.read',
        'collections.read',
        'sms.read',
        'sms.extract',
        'sms.reveal',
        'receivers.read',
        'receivers.manage',
        'reconciliations.read',
      ];
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return jsonResponse({
          'user': {
            'id': memberId,
            'email': 'operator@example.test',
            'role': 'admin',
            'sessionId': 'synthetic-momo-session',
            'permissions': grants,
            'assuranceLevel': 2,
            'mfaAt': DateTime.now().toUtc().toIso8601String(),
            'principalId': memberId,
          },
          'expiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
        });
      }
      if (request.url.path.endsWith('/sms/receipts')) {
        return jsonResponse({
          'rows': [],
          'total': 0,
          'offset': 0,
          'limit': 25,
          'next_offset': null,
        });
      }
      if (request.url.path.endsWith('/momo/transactions')) {
        if (transactionRecords != null) {
          return jsonResponse(transactionRecords(request));
        }
        if (records != null) return jsonResponse(records);
        return jsonResponse(
          page(
            status: request.url.queryParameters['status']?.isNotEmpty == true
                ? request.url.queryParameters['status']!
                : 'needs_allocation',
          ),
        );
      }
      if (request.url.path.endsWith('/momo/transactions/$txId')) {
        return jsonResponse({
          'transaction': detailRecord ?? transaction(),
          'sources': transactionSources,
          'conflicting_attempt_ids': conflictingAttempts,
        });
      }
      if (request.url.path.endsWith('/candidates')) {
        return jsonResponse({
          'rows': [
            {
              'group_id': groupId,
              'group_name': 'Synthetic savings group',
              'member_id': memberId,
              'member_name': 'Synthetic beneficiary',
              'member_public_id': '123456',
            },
          ],
          'total': 1,
          'offset': 0,
          'limit': 25,
        });
      }
      if (request.url.path.endsWith('/momo/sources')) {
        final sources = sourceJobs
            .where(
              (job) => job['state'] == request.url.queryParameters['status'],
            )
            .toList();
        return jsonResponse({
          'rows': sources,
          'total': sources.length,
          'offset': 0,
          'limit': 25,
        });
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/momo/accounts')) {
        return jsonResponse({
          'rows':
              receivingAccounts ??
              [
                {
                  'id': accountId,
                  'recipient_name': 'Collect synthetic receiver',
                  'public_code': '123456',
                  'profile_status': 'unverified',
                  'provider': 'mtn_momo',
                  'status': 'active',
                },
              ],
        });
      }
      if (request.url.path.endsWith('/core/groups')) {
        return jsonResponse({
          'rows': [
            {
              ...coreRow(CloudflareCoreArea.groups),
              'id': groupId,
              'title': 'Synthetic savings group',
            },
          ],
          'total': 1,
        });
      }
      if (respond != null) return respond(request);
      return http.Response('{}', 404);
    }),
    origin: Uri.parse('https://admin.example.test'),
    environment: legacyBackendFixtureEnvironment,
  );
  await session.refresh();
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((_) => session),
      adminPendingAttemptStorageProvider.overrideWithValue(
        pendingStorage ?? MemoryAdminPendingAttemptStorage(),
      ),
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
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: child!,
          ),
          home: const Scaffold(body: CloudflareAdminMomoPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!incoming &&
      grants.contains('sms.read') &&
      grants.contains('payments.read')) {
    await tester.tap(find.text('Transactions'));
    await tester.pumpAndSettle();
  }
  return (session: session, key: key, dispose: dispose);
}

Future<void> openGatewayTools(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More MoMo tools'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dedicated gateway (optional)'));
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  final directory = Platform.environment['COLLECT_MOMO_CAPTURE_DIR'];
  if (directory == null) return;
  final prefix = Platform.environment['COLLECT_MOMO_CAPTURE_PREFIX'] ?? '';
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final picture = await boundary.toImage(pixelRatio: 1);
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '$directory/$prefix$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

// A wide first table cell can be partially visible on a compact viewport.
// Tap its visible text area and verify the real hit path, never its offscreen center.
Future<void> tapVisibleSourceTitle(WidgetTester tester, Finder source) async {
  await tester.ensureVisible(source);
  await tester.pumpAndSettle();
  final viewport =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  final visible = tester.getRect(source).intersect(viewport);
  if (visible.isEmpty) {
    throw StateError('Source title is outside the viewport');
  }
  final point = visible.center;
  final target = tester.renderObject(source);
  if (!tester
      .hitTestOnBinding(point)
      .path
      .any((entry) => identical(entry.target, target))) {
    throw StateError('Visible source title is not hit-testable');
  }
  await tester.tapAt(point);
  await tester.pumpAndSettle();
}

Future<void> openUnresolvedSource(
  WidgetTester tester, {
  bool open = true,
}) async {
  await tester.tap(find.text('Needs attention'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Source state'),
    500,
    scrollable: find.byType(Scrollable).first,
  );
  final sourceState = find.byType(DropdownButtonFormField<String>).last;
  await tester.ensureVisible(sourceState);
  await tester.pumpAndSettle();
  await tester.tap(sourceState);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Receiving source unresolved').last);
  await tester.pumpAndSettle();
  final source = find.text('Source message — receiving source unresolved');
  await tester.ensureVisible(source);
  await tester.pumpAndSettle();
  if (open) await tapVisibleSourceTitle(tester, source);
  await tester.pumpAndSettle();
}

Future<void> fillSourceResolution(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.text('Collect synthetic receiver · 123456 · MTN MoMo').last,
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'Evidence'),
    'synthetic-archive/source-001',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Reason'),
    'Verified historical receiver using the retained account evidence',
  );
  await tester.pumpAndSettle();
}

Future<void> fillGatewayAccount(WidgetTester tester) async {
  await tester.tap(find.text('Add receiving account'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(DropdownButtonFormField<String>, 'Provider'),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Airtel Money').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'Actual MoMo number or payment code'),
    '  0788000123  ',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Recipient name shown by MoMo'),
    '  Synthetic Airtel receiver  ',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Account ownership and pairing reason'),
    '  Synthetic owner verified against receiving account evidence  ',
  );
  await tester.pumpAndSettle();
}

Future<void> fillGatewayPair(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>).last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.text('Collect synthetic receiver · 123456 · unverified').last,
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'Account ownership and pairing reason'),
    '  Synthetic dedicated phone and receiving account verified  ',
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Receiving SIM subscription ID (optional)'),
    '7',
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> reviewJob({String outcome = 'validation_failed'}) => {
  ...sourceJob(account: accountId),
  'state': 'needs_review',
  'body_sha256': 'a' * 64,
  'attempt_count': 2,
  'latest_attempt_outcome': outcome,
};
Future<void> openReviewSource(WidgetTester tester) async {
  await tester.tap(find.text('Needs attention'));
  await tester.pumpAndSettle();
  final source = find.text('Source message — extraction needs review');
  await tester.ensureVisible(source);
  await tester.pumpAndSettle();
  await tapVisibleSourceTitle(tester, source);
}

Future<void> selectReview(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = find.widgetWithText(DropdownButtonFormField<String>, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> enterReview(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> reasonReview(WidgetTester tester) async {
  await enterReview(tester, 'Evidence', 'synthetic-retained-evidence-001');
  await enterReview(
    tester,
    'Reason',
    'Reviewed exact source and retained independent evidence',
  );
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  _registerMomoLayoutSourceCases();
  _registerMomoGatewayCases();
  _registerMomoSourceReviewCases();
}
