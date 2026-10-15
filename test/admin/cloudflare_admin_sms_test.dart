import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/core/cloudflare_admin_sms_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_sms_pages.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _actor = '00000000-0000-4000-8000-000000000001';
const _sourceId = '00000000-0000-4000-8000-000000000002';
const _otherId = '00000000-0000-4000-8000-000000000003';
const _factId = '00000000-0000-4000-8000-000000000004';
const _requestId = '00000000-0000-4000-8000-000000000005';
final _digest = 'a' * 64;
Map<String, dynamic> _source({
  String kind = 'member',
  String id = _sourceId,
  bool extracted = true,
}) => {
  'source_kind': kind,
  'id': id,
  'user_id': kind == 'member' ? _actor : null,
  'payee_id': kind == 'receiver' ? _actor : null,
  'source_sha256': _digest,
  'status': kind == 'member' ? 'needs_review' : 'parsed',
  'version': 1,
  'received_at': 1791200000,
  'created_at': 1791200000,
  'public_id': kind == 'member' ? '938491' : null,
  'display_name': 'Recorded name',
  'transaction_id': null,
  'evidence_level': kind == 'member'
      ? 'member_submitted'
      : 'receiver_ingress_unverified',
  'source_fact_id': extracted ? _factId : null,
  'parser_version': extracted ? smsParserVersion : null,
  'extraction_status': extracted ? 'parsed' : 'not_extracted',
  'source_body_sha256': extracted ? _digest : null,
  'source_payload_sha256': extracted ? _digest : null,
  'parsed_at': extracted ? 1791200100 : null,
  'payer_name': extracted ? 'EVIDENCE PAYER' : null,
  'payer_phone': null,
  'payer_masked_phone': extracted ? '***321' : null,
  'payer_last3': extracted ? '321' : null,
  'payee_momo_number': null,
  'payee_momo_code': extracted ? '008000' : null,
  'momo_transaction_reference': extracted ? 'QA-MOMO-001' : null,
  'momo_timestamp_local': extracted ? '2026-10-05T08:25:00' : null,
  'momo_timezone_offset': null,
  'amount_rwf': extracted ? 25000 : null,
  'wallet_balance_rwf': extracted ? 250000 : null,
  'network': extracted ? 'mtn_momo' : null,
  'direction': extracted ? 'incoming' : null,
  'is_payment': extracted ? 1 : null,
  'transaction_reference': null,
  'duplicate_reference_count': 0,
  'conflicting_reference_count': 0,
  'provider_confirmation': false,
  'settlement_status': 'not_asserted',
  'timezone_known': false,
  'payer_last3_known': extracted,
  'source_content_reveal_required': true,
};
Map<String, dynamic> _page(
  List<Map<String, dynamic>> rows, {
  int offset = 0,
  int limit = 25,
  int? total,
}) => {
  'rows': rows,
  'total': total ?? rows.length,
  'limit': limit,
  'offset': offset,
  'next_offset': offset + rows.length < (total ?? rows.length)
      ? offset + rows.length
      : null,
};
Map<String, dynamic> _detail({
  String kind = 'member',
  bool canExtract = true,
  String id = _sourceId,
}) => {
  'resource_type': 'sms_receipts',
  'resource': _source(kind: kind, id: id),
  'current_actor_id': _actor,
  'can_extract': canExtract,
  'related': {'duplicate_references': _page([])},
};
Map<String, dynamic> _receipt({String sourceId = _sourceId}) => {
  'request_id': _requestId,
  'status': 'succeeded',
  'resource_type': 'sms_facts',
  'resource_id': _factId,
  'source_kind': 'member',
  'source_id': sourceId,
  'parser_version': smsParserVersion,
};

class _Fixture {
  _Fixture({
    this.role = 'owner',
    this.permissions = const ['sms.read', 'sms.extract', 'sms.reveal'],
    this.handler,
  }) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path == '/api/admin/auth/session') {
          return _response({
            'user': {
              'id': _actor,
              'email': 'sms-qa@example.test',
              'role': role,
              'sessionId': 'qa-public-session',
              'permissions': permissions,
            },
            'expiresAt': DateTime.now()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          });
        }
        requests.add(request);
        if (handler != null) return handler!(request);
        if (request.url.path == '/api/admin/sms/receipts') {
          return _response(
            _page(
              [_source()],
              offset: int.parse(request.url.queryParameters['offset']!),
              limit: int.parse(request.url.queryParameters['limit']!),
            ),
          );
        }
        return _response(_detail(canExtract: role != 'staff'));
      }),
      origin: Uri.parse('https://admin.example.test/'),
    );
  }
  String role;
  List<String> permissions;
  Future<http.Response> Function(http.Request)? handler;
  late CloudflareAdminSession session;
  final requests = <http.Request>[];
  static http.Response _response(Object body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );
  Future<CloudflareAdminSmsApi> api() async {
    await session.refresh();
    return CloudflareAdminSmsApi(session);
  }
}

Future<({GoRouter router, ProviderContainer container})> _mount(
  WidgetTester tester,
  _Fixture fixture,
  String location,
) async {
  await tester.runAsync(fixture.session.refresh);
  final container = ProviderContainer(
    overrides: [
      cloudflareAdminSessionProvider.overrideWith((ref) => fixture.session),
    ],
  );
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/admin/sms-receipts',
        builder: (_, _) => const CloudflareAdminSmsReceiptsPage(),
      ),
      GoRoute(
        path: '/admin/sms-receipts/:kind/:id',
        builder: (_, state) => CloudflareAdminSmsReceiptDetailPage(
          sourceKind: state.pathParameters['kind']!,
          id: state.pathParameters['id']!,
          returnTo: state.uri.queryParameters['returnTo'],
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (_, child) => Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, container: container);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'source facts keep unknowns null and reject invented or malformed provenance',
    () {
      final source = SmsReceiptSource.parse(_source());
      expect(source.values['payer_phone'], isNull);
      expect(source.values['payer_masked_phone'], '***321');
      expect(source.values['payee_momo_code'], '008000');
      expect(source.values['momo_timezone_offset'], isNull);
      expect(source.values['provider_confirmation'], isFalse);
      for (final changed in <Map<String, dynamic>>[
        {..._source(), 'payer_phone': '+250788000321'},
        {..._source(), 'payer_last3': '000'},
        {..._source(), 'source_body_sha256': 'b' * 64},
        {..._source(), 'provider_confirmation': true},
        {..._source(), 'momo_timestamp_local': '2026-02-31T08:25:00'},
        {..._source(), 'raw_body': 'Unexpected source leakage'},
        {
          ..._source(extracted: false),
          'payer_last3': '000',
          'payer_last3_known': true,
        },
      ]) {
        expect(() => SmsReceiptSource.parse(changed), throwsFormatException);
      }
      expect(
        SmsReceiptSource.parse(_source(extracted: false)).values['amount_rwf'],
        isNull,
      );
    },
  );
  test(
    'Staff cannot extract or reveal even with incorrectly granted permissions',
    () async {
      final fixture = _Fixture(role: 'staff');
      addTearDown(fixture.session.dispose);
      final api = await fixture.api(),
          source = SmsReceiptSource.parse(_source());
      expect(api.canExtract, isFalse);
      expect(api.canReveal, isFalse);
      expect(
        () => api.extract(source, 'Review source facts'),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        api.reveal(source, 'Review source facts'),
        throwsA(isA<AdminAccountException>()),
      );
      expect(fixture.requests, isEmpty);
    },
  );
  test(
    'listing uses authenticated bounded filters and rejects inconsistent pages',
    () async {
      final fixture = _Fixture(
        handler: (request) async {
          expect(request.url.path, '/api/admin/sms/receipts');
          expect(request.url.queryParameters, {
            'limit': '25',
            'offset': '0',
            'search': 'PAYER & 008000',
            'source_kind': 'member',
            'extraction_status': 'parsed',
          });
          return _Fixture._response(_page([_source()]));
        },
      );
      addTearDown(fixture.session.dispose);
      final api = await fixture.api();
      final page = await api.receipts(
        search: 'PAYER & 008000',
        sourceKind: 'member',
        extractionStatus: 'parsed',
      );
      expect(page.rows.single.id, _sourceId);
      await expectLater(api.receipts(limit: 101), throwsFormatException);
      expect(fixture.requests.length, 1);
      fixture.handler = (_) async =>
          _Fixture._response(_page([_source()], total: 26));
      await expectLater(api.receipts(), throwsFormatException);
    },
  );
  test(
    'detail fences source kind, identity and duplicate cross-record relation',
    () async {
      final fixture = _Fixture(
        handler: (_) async => _Fixture._response(_detail(kind: 'receiver')),
      );
      addTearDown(fixture.session.dispose);
      final api = await fixture.api();
      await expectLater(api.detail('member', _sourceId), throwsFormatException);
      fixture.handler = (_) async {
        final detail = _detail();
        (detail['resource'] as Map)['duplicate_reference_count'] = 1;
        detail['related'] = {
          'duplicate_references': _page([
            {
              ..._source(id: _otherId),
              'momo_transaction_reference': 'OTHER-REFERENCE',
            },
          ]),
        };
        return _Fixture._response(detail);
      };
      await expectLater(api.detail('member', _sourceId), throwsFormatException);
    },
  );
  test(
    'restored extraction intent validates source identity and keeps its original key',
    () async {
      final fixture = _Fixture();
      addTearDown(fixture.session.dispose);
      final api = await fixture.api();
      final attempt = api.restoreAttempt(
        key: _requestId,
        sourceKind: 'member',
        sourceId: _sourceId,
        body: {
          'reason': 'Recorded source review',
          'expected_source_sha256': _digest,
        },
      );
      expect(attempt.key, _requestId);
      expect(attempt.identity, 'member/$_sourceId');
      expect(fixture.requests, isEmpty);
      for (final body in [
        {'reason': 'short', 'expected_source_sha256': _digest},
        {'reason': 'Recorded source review', 'expected_source_sha256': 'bad'},
        {
          'reason': 'Recorded source review',
          'expected_source_sha256': _digest,
          'raw_body': 'private',
        },
      ]) {
        expect(
          () => api.restoreAttempt(
            key: _requestId,
            sourceKind: 'member',
            sourceId: _sourceId,
            body: body,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'lost extraction response preserves original immutable key and actor-scoped recovery',
    () async {
      final fixture = _Fixture(
        handler: (_) async => throw http.ClientException('Lost response'),
      );
      addTearDown(fixture.session.dispose);
      final api = await fixture.api();
      final attempt = api.extract(
        SmsReceiptSource.parse(_source()),
        ' Review source facts ',
      );
      expect(() => attempt.body['reason'] = 'Changed', throwsUnsupportedError);
      await expectLater(
        api.submit(attempt),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.outcomeUnknown,
            'outcome unknown',
            isTrue,
          ),
        ),
      );
      final first = fixture.requests.single;
      expect(first.headers['Idempotency-Key'], attempt.key);
      expect(jsonDecode(first.body), {
        'reason': 'Review source facts',
        'expected_source_sha256': _digest,
      });
      fixture.handler = (request) async {
        expect(request.url.path, '/api/admin/sms/requests/${attempt.key}');
        expect(request.method, 'GET');
        return _Fixture._response({
          'status': 'succeeded',
          'request_id': _requestId,
          'receipt': _receipt(),
        });
      };
      expect(
        (await api.lookup(attempt)).receipt?.values['resource_id'],
        _factId,
      );
      fixture.handler = (_) async =>
          _Fixture._response(_receipt(sourceId: _otherId));
      await expectLater(
        api.submit(attempt),
        throwsA(
          isA<CloudflareAdminRequestException>().having(
            (e) => e.outcomeUnknown,
            'mismatched acknowledgement unknown',
            isTrue,
          ),
        ),
      );
      expect(fixture.requests.last.headers['Idempotency-Key'], attempt.key);
      expect(fixture.requests.last.body, first.body);
    },
  );
  test(
    'fresh role change fences pending source response and stale API sends',
    () async {
      final pending = Completer<http.Response>();
      final fixture = _Fixture(handler: (_) => pending.future);
      addTearDown(fixture.session.dispose);
      final api = await fixture.api();
      final response = api.detail('member', _sourceId);
      final rejected = expectLater(
        response,
        throwsA(isA<CloudflareAdminRequestException>()),
      );
      fixture.role = 'staff';
      fixture.permissions = ['sms.read'];
      await fixture.session.refresh();
      pending.complete(_Fixture._response(_detail()));
      await rejected;
      await expectLater(api.receipts(), throwsA(isA<AdminAccountException>()));
      expect(fixture.requests.length, 1);
    },
  );
  test(
    'uncertain attempt store survives expiry refresh but resets on authority change',
    () async {
      final fixture = _Fixture();
      await fixture.session.refresh();
      final container = ProviderContainer(
        overrides: [
          cloudflareAdminSessionProvider.overrideWith((ref) => fixture.session),
        ],
      );
      addTearDown(container.dispose);
      final api = container.read(cloudflareAdminSmsApiProvider),
          attempt = api.extract(
            SmsReceiptSource.parse(_source()),
            'Review source facts',
          );
      container.read(cloudflareAdminSmsAttemptsProvider.notifier).state = {
        attempt.identity: attempt,
      };
      await fixture.session.refresh();
      expect(
        container.read(cloudflareAdminSmsAttemptsProvider)[attempt.identity],
        same(attempt),
      );
      fixture.permissions = ['sms.read'];
      await fixture.session.refresh();
      expect(container.read(cloudflareAdminSmsAttemptsProvider), isEmpty);
    },
  );
  test(
    'raw source reveal requires audit header and exact source hash',
    () async {
      final fixture = _Fixture(
        handler: (request) async {
          expect(
            request.headers['X-Collect-Review-Reason'],
            'Review original source',
          );
          expect(request.url.query, isEmpty);
          return _Fixture._response({
            'source_kind': 'member',
            'source_id': _sourceId,
            'raw_sender': 'MTN',
            'raw_body': 'Source\nbody',
            'source_sha256': 'b' * 64,
            'evidence_level': 'member_submitted',
            'provider_confirmation': false,
          });
        },
      );
      addTearDown(fixture.session.dispose);
      final api = await fixture.api();
      await expectLater(
        api.reveal(SmsReceiptSource.parse(_source()), 'short'),
        throwsFormatException,
      );
      expect(fixture.requests, isEmpty);
      await expectLater(
        api.reveal(SmsReceiptSource.parse(_source()), 'Review original source'),
        throwsFormatException,
      );
    },
  );
  test(
    'return location preserves bounded same-area filters and rejects redirects',
    () {
      const valid =
          '/admin/sms-receipts?search=Jean+Bosco&status=reviewed&source=member&extraction=parsed&duplicates=all&page=2&limit=25';
      expect(smsReturnLocation(valid), valid);
      for (final invalid in [
        'https://evil.test/admin/sms-receipts',
        '//evil.test/admin/sms-receipts',
        '/admin/users',
        '/admin/sms-receipts#other',
        '/admin/sms-receipts?source=member&source=receiver',
        '/admin/sms-receipts?page=0',
        '/admin/sms-receipts?limit=101',
        '/admin/sms-receipts?search=%0a',
        '/admin/sms-receipts?redirect=https%3A%2F%2Fevil.test',
      ]) {
        expect(smsReturnLocation(invalid), '/admin/sms-receipts');
      }
    },
  );
  testWidgets(
    'Staff sees dedicated fact and duplicate tables without operator controls',
    (tester) async {
      final fixture = _Fixture(role: 'staff', permissions: ['sms.read']);
      await _mount(tester, fixture, '/admin/sms-receipts/member/$_sourceId');
      expect(find.byType(AdminDataTable), findsNWidgets(2));
      expect(find.byType(DataTable), findsNWidgets(2));
      expect(find.text('Payer name'), findsNWidgets(2));
      expect(find.text('EVIDENCE PAYER'), findsOneWidget);
      expect(find.text('Confirm extraction'), findsNothing);
      expect(find.text('Open audited source'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '320px listing retains numeric facts and keyboard horizontal scrolling',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = _Fixture(role: 'staff', permissions: ['sms.read']);
      await _mount(tester, fixture, '/admin/sms-receipts?source=member');
      expect(find.byType(AdminDataTable), findsOneWidget);
      expect(find.text('008000'), findsOneWidget);
      final focus = tester
          .widgetList<Focus>(find.byType(Focus))
          .firstWhere(
            (widget) =>
                widget.focusNode?.debugLabel ==
                'Admin table horizontal scrolling',
          );
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final horizontal = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .firstWhere((widget) => widget.scrollDirection == Axis.horizontal);
      expect(horizontal.controller!.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown extraction locks payload across navigation and recovers matching receipt',
    (tester) async {
      final fixture = _Fixture();
      fixture.handler = (request) async {
        if (request.method == 'POST') {
          throw http.ClientException('Lost response');
        }
        if (request.url.path.contains('/requests/')) {
          return _Fixture._response({
            'status': 'succeeded',
            'request_id': _requestId,
            'receipt': _receipt(),
          });
        }
        if (request.url.path == '/api/admin/sms/receipts') {
          return _Fixture._response(_page([_source()]));
        }
        return _Fixture._response(_detail());
      };
      final mounted = await _mount(
        tester,
        fixture,
        '/admin/sms-receipts/member/$_sourceId',
      );
      final reason = find.byKey(const Key('sms-extraction-reason'));
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'Review source facts');
      await tester.pump();
      await _tap(
        tester,
        find.text(
          'I reviewed the source digest and reason for this extraction.',
        ),
      );
      await _tap(tester, find.text('Confirm extraction'));
      final pending = mounted.container.read(
        cloudflareAdminSmsAttemptsProvider,
      )['member/$_sourceId']!;
      expect(
        fixture.requests
            .where((r) => r.method == 'POST')
            .single
            .headers['Idempotency-Key'],
        pending.key,
      );
      expect(tester.widget<TextField>(reason).enabled, isFalse);
      mounted.router.go('/admin/sms-receipts');
      await tester.pumpAndSettle();
      mounted.router.go('/admin/sms-receipts/member/$_sourceId');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(reason).controller!.text,
        'Review source facts',
      );
      expect(tester.widget<TextField>(reason).enabled, isFalse);
      await _tap(tester, find.text('Check original request'));
      expect(
        mounted.container.read(cloudflareAdminSmsAttemptsProvider),
        isEmpty,
      );
      expect(find.text('Saved extraction receipt'), findsOneWidget);
      expect(fixture.requests.where((r) => r.method == 'POST').length, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'audited reveal renders full multiline source and clears on role change',
    (tester) async {
      const body = 'First preserved line\nSecond preserved line';
      final fixture = _Fixture(
        handler: (request) async {
          if (request.url.path.endsWith('/content')) {
            return _Fixture._response({
              'source_kind': 'member',
              'source_id': _sourceId,
              'raw_sender': 'MTN',
              'raw_body': body,
              'source_sha256': _digest,
              'evidence_level': 'member_submitted',
              'provider_confirmation': false,
            });
          }
          return _Fixture._response(
            _detail(canExtract: request.url.path.isNotEmpty),
          );
        },
      );
      await _mount(tester, fixture, '/admin/sms-receipts/member/$_sourceId');
      final reason = find.byKey(const Key('sms-source-review-reason'));
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'Review original source');
      await tester.pump();
      await _tap(
        tester,
        find.text('Record my reason and open the original source.'),
      );
      await _tap(tester, find.text('Open audited source'));
      expect(find.text(body), findsOneWidget);
      expect(find.text('Copy original SMS'), findsOneWidget);
      expect(find.text('Original SMS'), findsOneWidget);
      fixture.role = 'staff';
      fixture.permissions = ['sms.read'];
      fixture.handler = (_) async =>
          _Fixture._response(_detail(canExtract: false));
      await tester.runAsync(fixture.session.refresh);
      await tester.pumpAndSettle();
      expect(find.text(body), findsNothing);
      expect(find.text('Open audited source'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
