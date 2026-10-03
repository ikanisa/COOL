import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_investigation.dart';
import 'package:collect_app/admin/core/admin_investigation_view.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;
import 'support/admin_read_fixture.dart';
import 'support/test_capture_paths.dart';

const _transaction = '11111111-1111-4111-8111-111111111111';
const _receipt = '44444444-4444-4444-8444-444444444444';
const _other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
final _now = DateTime.utc(2026, 9, 30, 19, 0, 30);
String _target(String kind) => kind == 'transaction' ? _transaction : _receipt;
String _permission(String kind) =>
    kind == 'transaction' ? 'payments.read' : 'notifications.read';

Map<String, dynamic> _fixture([String kind = 'transaction']) {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/admin_investigation_v1.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  raw['kind'] = kind;
  raw['target_id'] = _target(kind);
  return raw;
}

Map<String, dynamic> _receiptSection(Map<String, dynamic> raw) =>
    raw['receipt'] as Map<String, dynamic>;
Map<String, dynamic> _paymentSection(Map<String, dynamic> raw) =>
    raw['payment'] as Map<String, dynamic>;

Map<String, dynamic> _partialFixture(String kind) {
  final raw = _fixture(kind), section = _receiptSection(raw);
  section['approvals'] = [];
  section['approval_total'] = 0;
  section['attempt_total'] = 51;
  section['attempts'] = [
    for (var number = 51; number >= 2; number--)
      {
        'id':
            '${number.toRadixString(16).padLeft(8, '0')}-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'attempt_number': number,
        'state': 'uncertain',
        'send_started_at': '2026-09-30T19:00:10Z',
        'outcome_at': '2026-09-30T19:00:12Z',
      },
  ];
  return raw;
}

AdminIdentity _identity(List<String> permissions) => AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic reviewer',
  roles: const ['admin'],
  permissions: permissions,
);

class _Transport {
  late final SupabaseClient client;
  late final AdminRepository repository;
  ProviderContainer? container;
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request) respond = (_) async =>
      auth.response(_fixture());

  Future<void> start() async {
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-publishable',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final token = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(token[0], token[1]));
        }
        if (request.url.path.endsWith('/logout')) return auth.response({});
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'session-a');
    repository = AdminRepository(client);
  }

  Future<void> close() {
    container?.dispose();
    container = null;
    return client.dispose();
  }
}

Future<void> _unmount(WidgetTester tester, _Transport transport) async {
  await tester.pumpWidget(const SizedBox.shrink());
  transport.container?.dispose();
  transport.container = null;
  await tester.pump();
}

Future<void> _drainSdk(WidgetTester tester) async {
  for (var turn = 0; turn < 8; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Transport transport,
  String kind, {
  Future<AdminIdentity?> Function()? identity,
  DateTime Function()? clock,
  Size size = const Size(1440, 1100),
  double scale = 1,
  bool detailConsumer = false,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(transport.client),
      adminRepositoryProvider.overrideWithValue(transport.repository),
      adminIdentityProvider.overrideWith(
        (_) =>
            identity?.call() ??
            Future.value(
              _identity([
                'payments.read',
                'notifications.read',
                'collections.read',
                'members.read',
              ]),
            ),
      ),
      adminClockProvider.overrideWithValue(clock ?? () => _now),
    ],
  );
  transport.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: brightness == Brightness.dark
            ? CollectTheme.dark()
            : CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: const Key('investigation-capture'),
            child: detailConsumer
                ? kind == 'transaction'
                      ? const AdminCollectTransactionDetailPage(
                          id: 'momo:$_transaction',
                        )
                      : const AdminDetailPage(
                          title: 'SMS receipt detail',
                          rpcName: 'admin_get_hybrid_sms_receipt',
                          id: _receipt,
                        )
                : SingleChildScrollView(
                    child: AdminInvestigationView(
                      kind: kind,
                      id: _target(kind),
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The locked PostgREST SDK can decode JSON outside the fake widget clock.
  // Drain bounded real asynchronous work without starting a provider that the
  // production view has not itself read (including lazy detail consumers).
  await _drainSdk(tester);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
      await (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  group('investigation exact decoder', () {
    for (final kind in ['transaction', 'receipt']) {
      test('$kind preserves separate posting and current balances', () {
        final snapshot = AdminInvestigationSnapshot.parse(_fixture(kind));
        expect(snapshot.kind, kind);
        expect(snapshot.targetId, _target(kind));
        expect(snapshot.payment!.journals.single.snapshot!.memberRwf, '6700');
        expect(snapshot.payment!.currentBalances.memberRwf, '7900');
        expect(snapshot.receipt!.state, 'uncertain');
        expect(snapshot.isFresh(_now), isTrue);
        expect(
          snapshot.isFresh(_now.add(const Duration(seconds: 60))),
          isFalse,
        );
        expect(() => snapshot.payment!.times.clear(), throwsUnsupportedError);
        expect(
          () => snapshot.receipt!.attempts.clear(),
          throwsUnsupportedError,
        );
      });
      test('$kind distinguishes missing and separately denied sections', () {
        final missing = _fixture(kind)
          ..['payment_state'] = 'missing'
          ..['payment'] = null
          ..['receipt_state'] = 'missing'
          ..['receipt'] = null;
        final absent = AdminInvestigationSnapshot.parse(missing);
        expect(absent.payment, isNull);
        expect(absent.receipt, isNull);
        final denied = _fixture(kind);
        final otherSection = kind == 'transaction' ? 'receipt' : 'payment';
        denied['${otherSection}_state'] = 'denied';
        denied[otherSection] = null;
        expect(() => AdminInvestigationSnapshot.parse(denied), returnsNormally);
        denied['${kind == 'transaction' ? 'payment' : 'receipt'}_state'] =
            'denied';
        denied[kind == 'transaction' ? 'payment' : 'receipt'] = null;
        expect(
          () => AdminInvestigationSnapshot.parse(denied),
          throwsFormatException,
        );
      });
    }
    final mutations = <String, void Function(Map<String, dynamic>)>{
      'unknown version': (raw) => raw['contract_version'] = 2,
      'missing field': (raw) => raw.remove('payment_state'),
      'raw body injected': (raw) => _receiptSection(raw)['message'] = 'private',
      'unmasked destination': (raw) =>
          _receiptSection(raw)['masked_destination'] = '+250788123123',
      'unmasked preview': (raw) =>
          _receiptSection(raw)['masked_snapshot_preview'] = '+250788123123',
      'preview missing snapshot': (raw) =>
          _receiptSection(raw)['snapshot_captured_at'] = null,
      'wrong target': (raw) => raw['target_id'] = _other,
      'cross payment': (raw) => _receiptSection(raw)['payment_id'] = _other,
      'unsafe history total': (raw) =>
          _receiptSection(raw)['attempt_total'] = 9007199254740992,
      'fractional amount': (raw) => _receiptSection(raw)['amount_rwf'] = '1.5',
      'money overflow': (raw) =>
          _receiptSection(raw)['amount_rwf'] = '9223372036854775808',
      'invalid calendar': (raw) => raw['checked_at'] = '2026-02-30T19:00:30Z',
      'year zero': (raw) => raw['checked_at'] = '0000-09-30T19:00:30Z',
      'naive timestamp': (raw) => raw['checked_at'] = '2026-09-30T19:00:30',
      'truncated history': (raw) => _receiptSection(raw)['attempt_total'] = 2,
      'duplicate history': (raw) {
        final section = _receiptSection(raw);
        final list = section['attempts'] as List;
        list.add({...list.single as Map});
        section['attempt_total'] = 2;
      },
      'outcome before send': (raw) =>
          ((_receiptSection(raw)['attempts'] as List).single
                  as Map)['outcome_at'] =
              '2026-09-30T18:00:00Z',
      'journal delta mismatch': (raw) =>
          (((_paymentSection(raw)['journals'] as List).single
                      as Map)['snapshot']
                  as Map)['delta_rwf'] =
              '1201',
      'cross collection': (raw) =>
          _receiptSection(raw)['collection_id'] = _other,
      'cross member': (raw) =>
          _receiptSection(raw)['member_record_id'] = _other,
      'cross snapshot': (raw) => _receiptSection(raw)['snapshot_id'] = _other,
      'snapshot amount conflict': (raw) =>
          _receiptSection(raw)['amount_rwf'] = '1201',
      'snapshot member balance conflict': (raw) =>
          _receiptSection(raw)['member_balance_rwf'] = '6701',
      'snapshot group balance conflict': (raw) =>
          _receiptSection(raw)['group_balance_rwf'] = '25001',
    };
    for (final mutation in mutations.entries) {
      test('rejects ${mutation.key}', () {
        final raw = _fixture();
        mutation.value(raw);
        expect(
          () => AdminInvestigationSnapshot.parse(raw),
          throwsFormatException,
        );
      });
    }
    test('bounded newest50 history explicitly retains omitted total', () {
      final receipt = AdminInvestigationSnapshot.parse(
        _partialFixture('transaction'),
      ).receipt!;
      expect(receipt.attempts, hasLength(50));
      expect(receipt.attemptTotal, 51);
      expect(receipt.partialHistory, isTrue);
    });
  });

  for (final kind in ['transaction', 'receipt']) {
    group('admin_get_collect_investigation_v1 $kind locked SDK', () {
      late _Transport transport;
      setUp(() async {
        transport = _Transport();
        transport.respond = (_) async => auth.response(_fixture(kind));
        await transport.start();
      });
      tearDown(() => transport.close());
      if (kind == 'transaction') {
        for (final brightness in [Brightness.dark, Brightness.light]) {
          testWidgets('synthetic ${brightness.name} investigation capture', (
            tester,
          ) async {
            await _mount(
              tester,
              transport,
              kind,
              size: const Size(1440, 1400),
              brightness: brightness,
            );
            expect(find.text('Masked destination: +250•••123'), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('investigation-capture')),
                );
                final picture = await boundary.toImage(pixelRatio: 1);
                final bytes = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                collectTestCaptureFile(
                  'investigation-sdk-${brightness.name}-synthetic.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
                picture.dispose();
              });
            }
            await _unmount(tester, transport);
          });
        }
      }
      Future<Map<String, dynamic>> read() =>
          transport.repository.investigation(kind: kind, id: _target(kind));
      test('exact target body and current refreshed Bearer', () async {
        await auth.session(transport.client, 'session-a', nonce: 1);
        final token = transport.client.auth.currentSession!.accessToken;
        expect((await read())['kind'], kind);
        final request = transport.requests.single;
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/rest/v1/rpc/admin_get_collect_investigation_v1',
        );
        expect(jsonDecode(request.body), {
          'p_kind': kind,
          'p_id': _target(kind),
        });
        expect(request.headers['Authorization'], 'Bearer $token');
      });
      test('denial never invokes compatibility or another read', () async {
        transport.respond = (_) async =>
            auth.response({'code': '42501', 'message': 'denied'}, 403);
        await expectLater(read(), throwsA(isA<PostgrestException>()));
        expect(transport.requests, hasLength(1));
      });
      test('valid envelope for a different kind is rejected', () async {
        transport.respond = (_) async => auth.response(
          _fixture(kind == 'transaction' ? 'receipt' : 'transaction'),
        );
        await expectLater(read(), throwsFormatException);
        expect(transport.requests, hasLength(1));
      });
      for (final switchBack in [false, true]) {
        test('late session response is suppressed A-B-A=$switchBack', () async {
          final started = Completer<void>(), release = Completer<void>();
          transport.respond = (_) async {
            started.complete();
            await release.future;
            return auth.response(_fixture(kind));
          };
          final pending = read();
          final assertion = expectLater(
            pending,
            throwsA(isA<AdminSessionChanged>()),
          );
          await started.future;
          final pinned = transport.requests.single.headers['Authorization'];
          await auth.session(transport.client, 'session-b');
          if (switchBack) {
            await auth.session(transport.client, 'session-a', nonce: 2);
          }
          release.complete();
          await assertion;
          expect(transport.requests, hasLength(1));
          expect(
            pinned,
            isNot(
              'Bearer ${transport.client.auth.currentSession!.accessToken}',
            ),
          );
        });
      }
      for (final network in [false, true]) {
        test('transport loss has one dispatch network=$network', () async {
          transport.respond = (_) async {
            if (network) throw http.ClientException('synthetic lost response');
            return auth.response({
              'code': '503',
              'message': 'unavailable',
            }, 503);
          };
          await expectLater(read(), throwsA(anything));
          expect(transport.requests, hasLength(1));
        });
      }
      test('invalid target and logout never dispatch', () async {
        await expectLater(
          transport.repository.investigation(kind: kind, id: 'not-a-uuid'),
          throwsFormatException,
        );
        await expectLater(
          transport.repository.investigation(
            kind: 'unsupported',
            id: _target(kind),
          ),
          throwsFormatException,
        );
        await transport.client.auth.signOut();
        await expectLater(read(), throwsA(isA<AdminSessionChanged>()));
        expect(transport.requests, isEmpty);
      });
    });
    group('investigation $kind production provider and view', () {
      late _Transport transport;
      setUp(() async {
        transport = _Transport();
        transport.respond = (_) async => auth.response(_fixture(kind));
        await transport.start();
      });
      tearDown(() => transport.close());
      testWidgets('actual detail consumer dispatches its bound joined read', (
        tester,
      ) async {
        final detail = kind == 'transaction'
            ? 'admin_get_collect_transaction'
            : 'admin_get_hybrid_sms_receipt';
        transport.respond = (request) async => auth.response(
          request.url.path.endsWith('/$detail')
              ? adminDetailFixture(detail, _target(kind))
              : _fixture(kind),
        );
        await _mount(tester, transport, kind, detailConsumer: true);
        await tester.scrollUntilVisible(
          find.text('Payment and receipt investigation'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          transport.requests.map((request) => request.url.path),
          containsAll([
            '/rest/v1/rpc/$detail',
            '/rest/v1/rpc/admin_get_collect_investigation_v1',
          ]),
        );
        final joined = transport.requests.singleWhere(
          (request) =>
              request.url.path.endsWith('/admin_get_collect_investigation_v1'),
        );
        expect(jsonDecode(joined.body), {
          'p_kind': kind,
          'p_id': _target(kind),
        });
        expect(find.text('Masked destination: +250•••123'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _unmount(tester, transport);
      });
      testWidgets(
        'separate snapshot/current values and masked unknown outcome',
        (tester) async {
          await _mount(tester, transport, kind);
          expect(transport.requests, hasLength(1));
          expect(
            find.text('Member balance at this posting: RWF 6,700'),
            findsOneWidget,
          );
          expect(find.textContaining('Member: RWF 7,900'), findsOneWidget);
          expect(find.text('Unknown send outcome'), findsWidgets);
          expect(find.text('Masked destination: +250•••123'), findsOneWidget);
          expect(find.text('+250788123123'), findsNothing);
          expect(find.text('Open transaction'), findsOneWidget);
          expect(find.text('Open SMS receipt'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _unmount(tester, transport);
        },
      );
      testWidgets('missing current permission denies without HTTP', (
        tester,
      ) async {
        await _mount(
          tester,
          transport,
          kind,
          identity: () async => _identity([]),
        );
        expect(find.text('Investigation access denied'), findsOneWidget);
        expect(transport.requests, isEmpty);
        await _unmount(tester, transport);
      });
      testWidgets('optional navigation requires its current capability', (
        tester,
      ) async {
        await _mount(
          tester,
          transport,
          kind,
          identity: () async => _identity([_permission(kind)]),
        );
        expect(find.text('Open group'), findsNothing);
        expect(find.text('Open member'), findsNothing);
        expect(
          find.text(
            kind == 'transaction' ? 'Open SMS receipt' : 'Open transaction',
          ),
          findsNothing,
        );
        expect(
          find.text(
            kind == 'transaction' ? 'Open transaction' : 'Open SMS receipt',
          ),
          findsOneWidget,
        );
        await _unmount(tester, transport);
      });
      testWidgets('loading/error/revocation hides retained private evidence', (
        tester,
      ) async {
        Future<AdminIdentity?> Function() identity = () async =>
            _identity([_permission(kind)]);
        final container = await _mount(
          tester,
          transport,
          kind,
          identity: () => identity(),
        );
        expect(find.text('Masked destination: +250•••123'), findsOneWidget);
        final pending = Completer<AdminIdentity?>();
        identity = () => pending.future;
        container.invalidate(adminIdentityProvider);
        expect(container.read(adminIdentityProvider).isLoading, isTrue);
        await tester.pumpAndSettle();
        expect(find.text('Masked destination: +250•••123'), findsNothing);
        expect(find.text('Loading investigation'), findsOneWidget);
        pending.completeError(StateError('synthetic identity outage'));
        await tester.pumpAndSettle();
        expect(find.text('Investigation access denied'), findsOneWidget);
        expect(find.text('Masked destination: +250•••123'), findsNothing);
        identity = () async => _identity([]);
        container.invalidate(adminIdentityProvider);
        await tester.pumpAndSettle();
        expect(find.text('Investigation access denied'), findsOneWidget);
        expect(transport.requests, hasLength(1));
        await _unmount(tester, transport);
      });
      testWidgets('disposed pending read never publishes linked evidence', (
        tester,
      ) async {
        final started = Completer<void>(), release = Completer<void>();
        transport.respond = (_) async {
          if (!started.isCompleted) started.complete();
          await release.future;
          return auth.response(_fixture(kind));
        };
        await _mount(tester, transport, kind);
        await started.future;
        await auth.session(transport.client, 'session-b');
        await auth.session(transport.client, 'session-a', nonce: 2);
        await _unmount(tester, transport);
        release.complete();
        await tester.pumpAndSettle();
        expect(find.text('Masked destination: +250•••123'), findsNothing);
        expect(tester.takeException(), isNull);
      });
      testWidgets(
        'mounted A-B-A hides departed response and accepts current evidence',
        (tester) async {
          final started = Completer<void>(), release = Completer<void>();
          var dispatch = 0;
          transport.respond = (_) async {
            if (dispatch++ == 0) {
              started.complete();
              await release.future;
              final old = _fixture(kind);
              _receiptSection(old)['masked_snapshot_preview'] =
                  'DEPARTED PRIVATE RECONSTRUCTION';
              return auth.response(old);
            }
            return auth.response(_fixture(kind));
          };
          await _mount(tester, transport, kind);
          await started.future;
          await auth.session(transport.client, 'session-b');
          await auth.session(transport.client, 'session-a', nonce: 2);
          await tester.pumpAndSettle();
          release.complete();
          await _drainSdk(tester);
          expect(find.text('DEPARTED PRIVATE RECONSTRUCTION'), findsNothing);
          expect(find.text('Masked destination: +250•••123'), findsOneWidget);
          expect(transport.requests.length, greaterThan(1));
          expect(tester.takeException(), isNull);
          await _unmount(tester, transport);
        },
      );
      testWidgets(
        'partial history states its bounded count without claiming completeness',
        (tester) async {
          transport.respond = (_) async => auth.response(_partialFixture(kind));
          await _mount(tester, transport, kind);
          expect(
            find.textContaining(
              'Partial history: newest 0 of 0 approvals and 50 of 51 attempts.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Attempt 1 ·'), findsNothing);
          expect(tester.takeException(), isNull);
          await _unmount(tester, transport);
        },
      );
      testWidgets(
        'stale reading hides evidence and explicit refresh restores it',
        (tester) async {
          var now = _now;
          await _mount(tester, transport, kind, clock: () => now);
          now = _now.add(const Duration(seconds: 60));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('Investigation stale'), findsOneWidget);
          expect(find.text('Masked destination: +250•••123'), findsNothing);
          now = _now;
          final refresh = find.widgetWithText(
            OutlinedButton,
            'Refresh investigation',
          );
          await tester.ensureVisible(refresh);
          await tester.tap(refresh);
          await _drainSdk(tester);
          expect(transport.requests, hasLength(2));
          expect(find.text('Masked destination: +250•••123'), findsOneWidget);
          await _unmount(tester, transport);
        },
      );
      for (final state in ['missing', 'denied', 'unavailable']) {
        testWidgets('$state remains an explicit section/service state', (
          tester,
        ) async {
          transport.respond = (_) async {
            if (state == 'unavailable') {
              return auth.response({
                'code': 'PGRST202',
                'message': 'not installed',
              }, 404);
            }
            final raw = _fixture(kind);
            final section = kind == 'transaction' ? 'receipt' : 'payment';
            raw['${section}_state'] = state;
            raw[section] = null;
            return auth.response(raw);
          };
          await _mount(tester, transport, kind);
          final label = state == 'unavailable'
              ? 'Investigation unavailable'
              : kind == 'transaction'
              ? state == 'denied'
                    ? 'Receipt evidence access required'
                    : 'No receipt evidence'
              : state == 'denied'
              ? 'Payment evidence access required'
              : 'Payment evidence missing';
          expect(find.text(label), findsOneWidget);
          expect(find.text('Investigation read failed'), findsNothing);
          expect(transport.requests, hasLength(1));
          await _unmount(tester, transport);
        });
      }
      testWidgets('320px at2x preserves readable scrollable evidence', (
        tester,
      ) async {
        await _mount(
          tester,
          transport,
          kind,
          size: const Size(320, 900),
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        final timeline = find.text('Recorded timeline');
        await tester.ensureVisible(timeline);
        await tester.pumpAndSettle();
        expect(timeline, findsOneWidget);
        expect(tester.takeException(), isNull);
        await _unmount(tester, transport);
      });
    });
  }
}
