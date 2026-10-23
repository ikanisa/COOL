import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_notification_operator_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_notification_operator_page.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/admin_theme.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/legacy_backend_fixture.dart';

const _supabaseOperatorEnvironment = AppEnv(
  apiUrl: '',
  publicUrl: '',
  adminAppUrl: '',
  enableSmsReader: false,
  enableAndroidSmsAccess: true,
  enableAdminPanel: false,
  enableAdminDevTools: false,
  authCaptchaEnabled: false,
  authCaptchaProvider: '',
  authCaptchaSiteKey: '',
  backend: 'supabase',
  supabaseUrl: 'https://operator-fixture.supabase.co',
  supabaseApiUrl: 'https://admin.example.test',
  supabaseAdminApiUrl: 'https://admin.example.test',
  supabasePublishableKey: 'sb_publishable_synthetic_operator_test_only',
);

const _actor = '00000000-0000-4000-8000-000000000001';
const _principal = '00000000-0000-4000-8000-000000000002';
const _publicSession = '00000000-0000-4000-8000-000000000003';
const _canonicalSession = '00000000-0000-4000-8000-000000000004';
const _job = '00000000-0000-4000-8000-000000000005';
const _payment = '00000000-0000-4000-8000-000000000006';
const _claimToken = '00000000-0000-4000-8000-000000000007';
const _attempt = '00000000-0000-4000-8000-000000000008';
const _recipient = '+250781234567';
const _body =
    'Collect record: contribution recorded. Provider confirmation is not asserted.';
const _marker = {
  'contract_version': 1,
  'scope': 'assisted_sms_internal_record',
  'delivery_confirmed': false,
  'provider_confirmation': false,
  'settlement_status': 'not_asserted',
};

http.Response _response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
http.Response _result(Map<String, dynamic> value) =>
    _response({'ok': true, 'result': value});

class _Fixture {
  _Fixture({
    this.permissions = const ['assisted_sms.read', 'assisted_sms.manage'],
    this.aal = 2,
    this.handler,
    this.useSupabase = false,
    this.emailProofAge = Duration.zero,
    this.claimLifetime = const Duration(seconds: 110),
  }) {
    session = CloudflareAdminSession(
      MockClient((request) async {
        if (request.url.path == '${prefix}auth/session') {
          return _response({
            'user': {
              'id': _actor,
              'email': 'operator@example.test',
              'role': 'owner',
              'sessionId': publicSession,
              'permissions': permissions,
              'assuranceLevel': aal,
              'principalId': _principal,
              if (aal == 2) 'mfaAt': now.toIso8601String(),
              if (useSupabase && aal == 1) 'mfaAt': null,
            },
            'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
            if (useSupabase) 'csrfToken': 'a' * 64,
          });
        }
        if (useSupabase &&
            request.url.path == '${prefix}auth/email-verification') {
          expect(request.method, 'GET');
          return _response({
            'contractVersion': 1,
            'sessionId': sidecarSessionId ?? publicSession,
            'emailVerifiedAt': emailProofAge == null
                ? null
                : now.subtract(emailProofAge!).toUtc().toIso8601String(),
          });
        }
        expect(request.url.path, '${prefix}notification-operator');
        if (useSupabase) {
          expect(request.headers['X-Collect-CSRF'], 'a' * 64);
          expect(request.headers.containsKey('Authorization'), isFalse);
        }
        final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        requests.add(body);
        final custom = await handler?.call(body);
        if (custom != null) return custom;
        return _defaultResponse(body);
      }),
      origin: Uri.parse('https://admin.example.test'),
      environment: useSupabase
          ? _supabaseOperatorEnvironment
          : legacyBackendFixtureEnvironment,
    );
  }
  _Fixture.supabase({
    List<String> permissions = const [
      'assisted_sms.read',
      'assisted_sms.manage',
    ],
    Duration? proofAge = Duration.zero,
    Duration claimLifetime = const Duration(seconds: 110),
    Future<http.Response?> Function(Map<String, dynamic>)? handler,
  }) : this(
         permissions: permissions,
         aal: 1,
         handler: handler,
         useSupabase: true,
         emailProofAge: proofAge,
         claimLifetime: claimLifetime,
       );
  final List<String> permissions;
  final int aal;
  final bool useSupabase;
  Duration? emailProofAge;
  final Duration claimLifetime;
  String? sidecarSessionId;
  String get prefix =>
      useSupabase ? '/functions/v1/admin-api/api/admin/' : '/api/admin/';
  final Future<http.Response?> Function(Map<String, dynamic>)? handler;
  String publicSession = _publicSession;
  final requests = <Map<String, dynamic>>[];
  // The actual operator contract uses the database's millisecond UTC wire
  // format. A raw DateTime.now() can serialize six fractional digits and is
  // correctly rejected by the strict client, including during readback.
  final now = DateTime.fromMillisecondsSinceEpoch(
    (DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000,
    isUtc: true,
  );
  String get expiry => now.add(claimLifetime).toIso8601String();
  late final CloudflareAdminSession session;
  String? workerId;
  Map<String, dynamic> claimReceipt() => {
    ..._marker,
    'job_id': _job,
    'claim_token': _claimToken,
    'fence_version': 1,
    'worker_id': workerId!,
    'claim_expires_at': expiry,
    'originating_session_id': _canonicalSession,
    'public_session_id': _publicSession,
  };
  http.Response _defaultResponse(Map<String, dynamic> request) {
    switch (request['action']) {
      case 'list_pending':
        return _result({
          ..._marker,
          'items': [
            {
              'id': _job,
              'payment_id': _payment,
              'state': 'queued',
              'created_at': '2026-10-01T00:00:00.000Z',
              'fence': 0,
              'attempt_id': null,
            },
          ],
          'next_cursor': null,
        });
      case 'claim':
        workerId = request['worker_id'] as String;
        return _result(claimReceipt());
      case 'get_claimed':
        return _result({
          ..._marker,
          'job_id': _job,
          'claim_token': _claimToken,
          'fence_version': 1,
          'destination_e164': _recipient,
          'destination_sha256': sha256
              .convert(utf8.encode(_recipient))
              .toString(),
          'destination_revision': 1,
          'message_body': _body,
          'body_sha256': sha256.convert(utf8.encode(_body)).toString(),
          'payment_id': _payment,
          'template_key': 'collect.recorded_contribution.v1',
          'claim_expires_at': expiry,
        });
      case 'confirm':
        return _result({
          ..._marker,
          'job_id': _job,
          'claim_token': _claimToken,
          'fence_version': 1,
          'confirmation_id': request['confirmation_id'],
          'body_sha256': request['body_sha256'],
          'destination_sha256': request['destination_sha256'],
          'destination_revision': 1,
          'expires_at': expiry,
          'originating_session_id': _canonicalSession,
          'public_session_id': _publicSession,
        });
      case 'release_claim':
        return _result({
          ..._marker,
          'job_id': _job,
          'state': 'queued',
          'fence_version': 2,
        });
      case 'get_operation':
        return _result({
          ..._marker,
          'request_id': request['request_id'],
          'observed': false,
          'receipt': null,
          'may_send': false,
        });
      default:
        throw StateError('Unexpected request ${request['action']}');
    }
  }
}

class _RejectedStorage implements AdminPendingAttemptStorage {
  @override
  String? read(String key) => null;
  @override
  void remove(String key) {}
  @override
  void write(String key, String value) => throw StateError('Storage denied');
}

class _CountingAdapter implements NotificationOperatorAssistedSmsAdapter {
  int calls = 0;
  @override
  Future<NotificationOperatorAdapterObservation> sendOnce(
    NotificationOperatorNativeSendContext context,
  ) async {
    calls++;
    throw StateError('This fixture must never dispatch');
  }
}

class _DelayedAdapter implements NotificationOperatorAssistedSmsAdapter {
  NotificationOperatorNativeSendContext? context;
  final reply = Completer<NotificationOperatorAdapterObservation>();
  @override
  Future<NotificationOperatorAdapterObservation> sendOnce(
    NotificationOperatorNativeSendContext context,
  ) {
    this.context = context;
    return reply.future;
  }
}

Future<ProviderContainer> _mount(
  WidgetTester tester,
  _Fixture fixture,
  AdminPendingAttemptStorage storage, {
  NotificationOperatorAssistedSmsAdapter? adapter,
  Size viewport = const Size(1500, 1400),
  ThemeData? theme,
  TextScaler? textScaler,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
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
        theme: theme,
        builder: textScaler == null
            ? null
            : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
        home: Scaffold(
          body: CloudflareAdminNotificationOperatorPage(
            assistedSmsAdapter: adapter,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
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

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // ensureVisible changes scroll positions before the next layout frame.
  // Settle that layout before deriving a tap point, including both the table's
  // horizontal viewport and AdminPage's outer vertical viewport.
  await tester.pumpAndSettle();
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'The actual control must be visible and hittable after scrolling.',
  );
}

Future<void> _background(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  await tester.pump();
}

Future<void> _foreground(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

Future<void> _unmount(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  container.dispose();
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  testWidgets(
    'Supabase AAL1 email proof retains read-only permission boundaries',
    (tester) async {
      final fixture = _Fixture.supabase(
        permissions: const ['assisted_sms.read'],
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      expect(fixture.session.user!.assuranceLevel, 1);
      expect(fixture.session.user!.mfaAt, isNull);
      expect(fixture.requests.map((r) => r['action']), ['list_pending']);
      expect(find.byType(AdminDataTable), findsOneWidget);
      expect(find.textContaining('Read-only access.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Claim for review'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'Supabase missing or stale proof offers Verify email without transport',
    (tester) async {
      for (final age in <Duration?>[null, const Duration(minutes: 6)]) {
        final fixture = _Fixture.supabase(proofAge: age);
        final container = await _mount(
          tester,
          fixture,
          MemoryAdminPendingAttemptStorage(),
        );
        expect(fixture.requests, isEmpty);
        expect(
          find.textContaining('recent email verification'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Verify email'),
          findsOneWidget,
        );
        expect(find.byType(AdminDataTable), findsNothing);
        await _unmount(tester, container);
      }
    },
  );

  testWidgets(
    'same-session email renewal preserves confirmation and earlier expiry',
    (tester) async {
      final fixture = _Fixture.supabase(
        proofAge: const Duration(minutes: 4, seconds: 45),
        claimLifetime: const Duration(seconds: 20),
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _tap(tester, 'Claim for review');
      await _reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Confirm exact content');
      final original = fixture.requests.singleWhere(
        (r) => r['action'] == 'confirm',
      );
      final requestId = original['request_id'];
      final confirmationId = original['confirmation_id'];
      final authority = fixture.session.authorityFence;
      fixture.emailProofAge = Duration.zero;
      await fixture.session.refresh();
      await tester.pumpAndSettle();
      expect(fixture.session.authorityFence, authority);
      expect(fixture.session.user!.sessionId, _publicSession);
      expect(fixture.session.user!.assuranceLevel, 1);
      expect(fixture.session.user!.mfaAt, isNull);
      expect(find.text(_body), findsOneWidget);
      expect(find.textContaining('left its original session'), findsNothing);
      // Renewal removes the former 15-second proof deadline, while the original
      // 20-second claim/confirmation still expires without another command.
      await tester.pump(const Duration(seconds: 16));
      expect(find.text(_body), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(_body), findsNothing);
      expect(find.text(_recipient), findsNothing);
      expect(
        find.textContaining('claim or confirmation expired'),
        findsOneWidget,
      );
      expect(fixture.requests.where((r) => r['action'] == 'confirm'), [
        original,
      ]);
      expect(original['request_id'], requestId);
      expect(original['confirmation_id'], confirmationId);
      expect(
        fixture.requests.where((r) => r['action'] == 'record_send_start'),
        isEmpty,
      );
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'Supabase proof loss clears exact content without a new command',
    (tester) async {
      final fixture = _Fixture.supabase();
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _tap(tester, 'Claim for review');
      expect(find.text(_body), findsOneWidget);
      final commands = fixture.requests.length;
      fixture.emailProofAge = const Duration(minutes: 6);
      await tester.runAsync(fixture.session.refresh);
      await tester.pumpAndSettle();
      expect(find.text(_body), findsNothing);
      expect(find.text(_recipient), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, 'Verify email'),
        findsOneWidget,
      );
      expect(fixture.requests, hasLength(commands));
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'Supabase renewal retains unknown UUID and readback never retries claim',
    (tester) async {
      final fixture = _Fixture.supabase(
        proofAge: const Duration(minutes: 4),
        handler: (request) async => request['action'] == 'claim'
            ? _response({'code': 'sms_operation_unknown'}, 503)
            : null,
      );
      final storage = MemoryAdminPendingAttemptStorage();
      final container = await _mount(tester, fixture, storage);
      await _tap(tester, 'Claim for review');
      final original = fixture.requests.singleWhere(
        (r) => r['action'] == 'claim',
      );
      final requestId = original['request_id'] as String;
      expect(storage.values.values.join(), contains(requestId));
      final authority = fixture.session.authorityFence;
      fixture.emailProofAge = Duration.zero;
      await tester.runAsync(fixture.session.refresh);
      await tester.pumpAndSettle();
      expect(fixture.session.authorityFence, authority);
      expect(storage.values.values.join(), contains(requestId));
      await _tap(tester, 'Check operation');
      expect(
        fixture.requests.where((r) => r['action'] == 'claim'),
        hasLength(1),
      );
      expect(
        fixture.requests.singleWhere(
          (r) => r['action'] == 'get_operation',
        )['request_id'],
        requestId,
      );
      expect(storage.values.values.join(), contains(requestId));
      expect(storage.values.values.join(), isNot(contains(_claimToken)));
      expect(find.byType(CheckboxListTile), findsNothing);
      await _unmount(tester, container);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'compact 320x800 ${scale}x shared-theme review retains reachable named controls',
      (tester) async {
        final fixture = _Fixture();
        final semantics = tester.ensureSemantics();
        ProviderContainer? container;
        try {
          container = await _mount(
            tester,
            fixture,
            MemoryAdminPendingAttemptStorage(),
            viewport: const Size(320, 800),
            theme: AdminTheme.adapt(AppTheme.dark()),
            textScaler: TextScaler.linear(scale),
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(AdminDataTable), findsOneWidget);
          final tableViewport = tester.widget<SingleChildScrollView>(
            find.ancestor(
              of: find.descendant(
                of: find.byType(AdminDataTable),
                matching: find.byType(DataTable),
              ),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is SingleChildScrollView &&
                    widget.scrollDirection == Axis.horizontal,
              ),
            ),
          );
          expect(
            tableViewport.controller!.position.maxScrollExtent,
            greaterThan(0),
            reason:
                'The full-field table has contained horizontal scrolling at phone width.',
          );
          await _tap(tester, 'Claim for review');
          expect(fixture.requests.map((request) => request['action']), [
            'list_pending',
            'claim',
            'get_claimed',
          ]);
          expect(tester.takeException(), isNull);
          for (final value in [_recipient, _body]) {
            final text = find.text(value);
            expect(text, findsOneWidget);
            await _reveal(tester, text);
            final bounds = tester.getRect(text);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(320));
            expect(bounds.top, greaterThanOrEqualTo(0));
            expect(bounds.bottom, lessThanOrEqualTo(800));
          }
          await _reveal(tester, find.byType(CheckboxListTile));
          expect(
            find.bySemanticsLabel('I checked this exact recipient and message'),
            findsOneWidget,
          );
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isTrue,
          );
          final confirm = find.widgetWithText(
            FilledButton,
            'Confirm exact content',
          );
          await _reveal(tester, confirm);
          expect(
            find.bySemanticsLabel('Confirm exact content'),
            findsOneWidget,
          );
          await _tap(tester, 'Confirm exact content');
          expect(fixture.requests.last['user_confirmation'], isTrue);
          expect(find.text('Record start and send once'), findsOneWidget);
          expect(
            find.textContaining('Native SMS adapter is unavailable'),
            findsOneWidget,
          );
          final release = find.widgetWithText(OutlinedButton, 'Release claim');
          await _reveal(tester, release);
          expect(find.bySemanticsLabel('Release claim'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _tap(tester, 'Release claim');
          expect(
            fixture.requests.where(
              (request) => request['action'] == 'release_claim',
            ),
            hasLength(1),
          );
          expect(
            fixture.requests.where(
              (request) => request['action'] == 'record_send_start',
            ),
            isEmpty,
          );
          expect(find.text(_body), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          if (container != null) await _unmount(tester, container);
        }
      },
    );
  }

  testWidgets(
    'fresh AAL2 and explicit permission are required before list transport',
    (tester) async {
      final fixture = _Fixture(aal: 1);
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      expect(fixture.requests, isEmpty);
      expect(
        find.textContaining('fresh authenticator verification'),
        findsOneWidget,
      );
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'generic notification grants do not admit the assisted SMS page',
    (tester) async {
      final fixture = _Fixture(
        permissions: const ['notifications.read', 'notifications.manage'],
      );
      final adapter = _CountingAdapter();
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
        adapter: adapter,
      );
      expect(fixture.requests, isEmpty);
      expect(find.textContaining('assisted_sms.read access'), findsOneWidget);
      expect(find.byType(AdminDataTable), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Claim for review'), findsNothing);
      expect(find.text('Original operation UUID'), findsNothing);
      expect(adapter.calls, 0);
      expect(tester.takeException(), isNull);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'fresh read-only access lists metadata and disables management actions',
    (tester) async {
      final fixture = _Fixture(permissions: const ['assisted_sms.read']);
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      expect(fixture.requests.map((request) => request['action']), [
        'list_pending',
      ]);
      expect(find.byType(AdminDataTable), findsOneWidget);
      expect(find.textContaining('Read-only access.'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Claim for review'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Original operation UUID'), findsNothing);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'exact review uses tables; missing native adapter disables send-start and allows release',
    (tester) async {
      final fixture = _Fixture(), storage = MemoryAdminPendingAttemptStorage();
      final container = await _mount(tester, fixture, storage);
      expect(find.byType(AdminDataTable), findsOneWidget);
      await _tap(tester, 'Claim for review');
      expect(find.text(_recipient), findsOneWidget);
      expect(find.text(_body), findsOneWidget);
      final confirm = find.widgetWithText(
        FilledButton,
        'Confirm exact content',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await _reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Confirm exact content');
      expect(fixture.requests.last['user_confirmation'], true);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Record start and send once'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Native SMS adapter is unavailable'),
        findsOneWidget,
      );
      expect(
        fixture.requests.where((r) => r['action'] == 'record_send_start'),
        isEmpty,
      );
      expect(storage.values.values.join(), isNot(contains(_recipient)));
      expect(storage.values.values.join(), isNot(contains(_body)));
      expect(storage.values.values.join(), isNot(contains(_claimToken)));
      await _tap(tester, 'Release claim');
      expect(
        fixture.requests.where((r) => r['action'] == 'release_claim'),
        hasLength(1),
      );
      expect(find.text(_body), findsNothing);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'unknown original key survives reload; checking never repeats claim or adopts recovered authority',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final first = _Fixture(
        handler: (request) async {
          if (request['action'] == 'claim') {
            throw http.ClientException('Lost reply');
          }
          return null;
        },
      );
      var container = await _mount(tester, first, storage);
      await _tap(tester, 'Claim for review');
      final original = first.requests.singleWhere(
        (r) => r['action'] == 'claim',
      );
      final originalId = original['request_id'] as String;
      expect(storage.values.values.join(), contains(originalId));
      expect(storage.values.values.join(), isNot(contains('claim_token')));
      expect(storage.values.values.join(), isNot(contains('message_body')));
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Claim for review'),
            )
            .onPressed,
        isNull,
      );
      await _tap(tester, 'Check operation');
      expect(first.requests.where((r) => r['action'] == 'claim'), hasLength(1));
      expect(first.requests.last['request_id'], originalId);
      await _unmount(tester, container);
      late _Fixture next;
      next = _Fixture(
        handler: (request) async {
          if (request['action'] == 'get_operation') {
            next.workerId = original['worker_id'] as String;
            return _result({
              ..._marker,
              'request_id': originalId,
              'observed': true,
              'receipt': next.claimReceipt(),
              'may_send': false,
            });
          }
          return null;
        },
      );
      container = await _mount(tester, next, storage);
      expect(next.requests.map((r) => r['action']), ['list_pending']);
      expect(find.text(originalId), findsOneWidget);
      await _tap(tester, 'Check operation');
      expect(next.requests.map((r) => r['action']), [
        'list_pending',
        'get_operation',
      ]);
      expect(find.text(_recipient), findsNothing);
      expect(find.text(_body), findsNothing);
      expect(storage.values, isEmpty);
      await _unmount(tester, container);
    },
  );

  testWidgets('rejected durable checkpoint prevents any claim dispatch', (
    tester,
  ) async {
    final fixture = _Fixture();
    final container = await _mount(tester, fixture, _RejectedStorage());
    await _tap(tester, 'Claim for review');
    expect(fixture.requests.map((r) => r['action']), ['list_pending']);
    expect(find.textContaining('No request was submitted'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Claim for review'),
          )
          .onPressed,
      isNull,
    );
    await _unmount(tester, container);
  });

  testWidgets(
    'a competing original checkpoint is preserved when retain refuses a new key',
    (tester) async {
      const original = '00000000-0000-4000-8000-000000000099';
      final fixture = _Fixture(), storage = MemoryAdminPendingAttemptStorage();
      final container = await _mount(tester, fixture, storage);
      container
          .read(adminPendingAttemptStoreProvider)
          .retain(
            family: 'notification-operator',
            resourceId: _job,
            requestKey: original,
            permission: 'assisted_sms.manage',
            intent: const {'action': 'claim', 'resource_id': _job},
            schema: const AdminPendingAttemptSchema(
              fields: {'action', 'resource_id'},
            ),
          );
      await tester.pumpAndSettle();
      await _tap(tester, 'Claim for review');
      expect(fixture.requests.map((r) => r['action']), ['list_pending']);
      expect(storage.values.values.join(), contains(original));
      expect(find.text(original), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Claim for review'),
            )
            .onPressed,
        isNull,
      );
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'hidden app drops exact content and confirmation; foreground does not restore them',
    (tester) async {
      final fixture = _Fixture();
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _tap(tester, 'Claim for review');
      expect(find.text(_body), findsOneWidget);
      await _background(tester);
      await _foreground(tester);
      await tester.pumpAndSettle();
      expect(find.text(_body), findsNothing);
      expect(find.text(_recipient), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(fixture.requests.where((r) => r['action'] == 'confirm'), isEmpty);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'a late claim response after logout cannot release plaintext into the departed page',
    (tester) async {
      final reply = Completer<http.Response>();
      late _Fixture fixture;
      fixture = _Fixture(
        handler: (request) async {
          if (request['action'] == 'claim') {
            fixture.workerId = request['worker_id'] as String;
            return reply.future;
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      final claim = find.widgetWithText(TextButton, 'Claim for review');
      await _reveal(tester, claim);
      await tester.tap(claim);
      await tester.pump();
      fixture.session.clear();
      reply.complete(_result(fixture.claimReceipt()));
      await tester.pumpAndSettle();
      expect(
        fixture.requests.where((r) => r['action'] == 'get_claimed'),
        isEmpty,
      );
      expect(find.text(_recipient), findsNothing);
      expect(find.text(_body), findsNothing);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'navigation away and back clears the original exact-content authority',
    (tester) async {
      final fixture = _Fixture();
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _tap(tester, 'Claim for review');
      final navigator = Navigator.of(
        tester.element(find.byType(CloudflareAdminNotificationOperatorPage)),
      );
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Another task')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text(_recipient), findsNothing);
      expect(find.text(_body), findsNothing);
      expect(find.textContaining('original current session'), findsOneWidget);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'a lost send-start acknowledgement never invokes the injected adapter or creates another start key',
    (tester) async {
      final adapter = _CountingAdapter();
      final fixture = _Fixture(
        handler: (request) async {
          if (request['action'] == 'record_send_start') {
            throw http.ClientException('Lost start reply');
          }
          return null;
        },
      );
      final storage = MemoryAdminPendingAttemptStorage();
      final container = await _mount(
        tester,
        fixture,
        storage,
        adapter: adapter,
      );
      await _tap(tester, 'Claim for review');
      await _reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Confirm exact content');
      await _tap(tester, 'Record start and send once');
      expect(adapter.calls, 0);
      expect(
        fixture.requests.where((r) => r['action'] == 'record_send_start'),
        hasLength(1),
      );
      expect(find.text(_body), findsNothing);
      expect(storage.values.values.join(), isNot(contains(_recipient)));
      expect(storage.values.values.join(), isNot(contains(_claimToken)));
      final reference = fixture.requests.singleWhere(
        (r) => r['action'] == 'record_send_start',
      )['request_id'];
      final checks = find.widgetWithText(OutlinedButton, 'Check operation');
      await _reveal(tester, checks.last);
      await tester.tap(checks.last);
      await tester.pumpAndSettle();
      expect(fixture.requests.last['request_id'], reference);
      expect(adapter.calls, 0);
      expect(
        fixture.requests.where((r) => r['action'] == 'record_send_start'),
        hasLength(1),
      );
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'post-commit authority refusal retains the original start UUID and prevents another start',
    (tester) async {
      final adapter = _CountingAdapter(),
          storage = MemoryAdminPendingAttemptStorage();
      final fixture = _Fixture(
        handler: (request) async {
          if (request['action'] == 'record_send_start') {
            // The actual handler may commit the start and then refuse its final
            // authority read. A 403 here cannot establish that no start exists.
            return _response({'error': 'sms_authority_changed'}, 403);
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        storage,
        adapter: adapter,
      );
      await _tap(tester, 'Claim for review');
      await _reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Confirm exact content');
      await _tap(tester, 'Record start and send once');
      final original = fixture.requests.singleWhere(
        (request) => request['action'] == 'record_send_start',
      );
      expect(storage.values.values.join(), contains(original['request_id']));
      expect(storage.values.values.join(), isNot(contains(_claimToken)));
      expect(storage.values.values.join(), isNot(contains(_recipient)));
      expect(adapter.calls, 0);
      expect(find.text(_body), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Claim for review'),
            )
            .onPressed,
        isNull,
      );
      final checks = find.widgetWithText(OutlinedButton, 'Check operation');
      await _reveal(tester, checks.last);
      await tester.tap(checks.last);
      await tester.pumpAndSettle();
      expect(fixture.requests.last['action'], 'get_operation');
      expect(fixture.requests.last['request_id'], original['request_id']);
      expect(storage.values.values.join(), contains(original['request_id']));
      expect(
        fixture.requests.where(
          (request) => request['action'] == 'record_send_start',
        ),
        hasLength(1),
      );
      expect(adapter.calls, 0);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'recorded send-start readback exposes only observation history and never a new permit',
    (tester) async {
      final adapter = _CountingAdapter();
      final storage = MemoryAdminPendingAttemptStorage();
      late _Fixture fixture;
      fixture = _Fixture(
        handler: (request) async {
          if (request['action'] == 'record_send_start') {
            throw http.ClientException('Lost start reply');
          }
          if (request['action'] == 'get_operation') {
            final original = fixture.requests.singleWhere(
              (r) => r['action'] == 'record_send_start',
            );
            return _result({
              ..._marker,
              'request_id': original['request_id'],
              'observed': true,
              'may_send': false,
              'receipt': {
                ..._marker,
                'attempt_id': _attempt,
                'job_id': _job,
                'confirmation_id': original['confirmation_id'],
                'claim_token': _claimToken,
                'fence_version': 1,
                'state': 'send_started',
                'originating_session_id': _canonicalSession,
                'public_session_id': _publicSession,
              },
            });
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        storage,
        adapter: adapter,
      );
      await _tap(tester, 'Claim for review');
      await _reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Confirm exact content');
      await _tap(tester, 'Record start and send once');
      // The first two references are known successful. Check the unresolved
      // original start row explicitly; no claim/confirmation is adopted.
      final checks = find.widgetWithText(OutlinedButton, 'Check operation');
      await _reveal(tester, checks.last);
      await tester.tap(checks.last);
      await tester.pumpAndSettle();
      expect(adapter.calls, 0);
      expect(
        find.text('Recorded result recovered: no sending authority'),
        findsOneWidget,
      );
      expect(find.text('Record observed outcome'), findsOneWidget);
      expect(find.text(_recipient), findsNothing);
      expect(find.text(_body), findsNothing);
      expect(
        fixture.requests.where((r) => r['action'] == 'record_send_start'),
        hasLength(1),
      );
      expect(storage.values, isEmpty);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'switching observation attempts clears the previous evidence and outcome',
    (tester) async {
      const otherJob = '00000000-0000-4000-8000-000000000015';
      const otherAttempt = '00000000-0000-4000-8000-000000000018';
      final fixture = _Fixture(
        handler: (request) async {
          if (request['action'] == 'list_pending') {
            return _result({
              ..._marker,
              'items': [
                for (final entry in [
                  (_job, _attempt),
                  (otherJob, otherAttempt),
                ])
                  {
                    'id': entry.$1,
                    'payment_id': _payment,
                    'state': 'send_started',
                    'created_at': '2026-10-01T00:00:00.000Z',
                    'fence': 1,
                    'attempt_id': entry.$2,
                  },
              ],
              'next_cursor': null,
            });
          }
          if (request['action'] == 'record_outcome') {
            return _result({
              ..._marker,
              'attempt_id': request['attempt_id'],
              'observation': request['observation'],
              'evidence_reference_sha256': request['evidence_reference_sha256'],
              'may_send': false,
            });
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      final selections = find.widgetWithText(TextButton, 'Record observation');
      await _reveal(tester, selections.first);
      await tester.tap(selections.first);
      await tester.pumpAndSettle();
      final outcome = find.byType(
        DropdownButtonFormField<NotificationOperatorObservation>,
      );
      await _reveal(tester, outcome);
      await tester.tap(outcome);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Observed sent').last);
      await tester.pumpAndSettle();
      final evidence = find.widgetWithText(
        TextField,
        'Evidence reference SHA-256',
      );
      await _reveal(tester, evidence);
      await tester.enterText(evidence, 'a' * 64);
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Record observation');
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await _reveal(tester, selections.last);
      await tester.tap(selections.last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(evidence).controller!.text, isEmpty);
      expect(
        tester
            .widget<DropdownButtonFormField<NotificationOperatorObservation>>(
              outcome,
            )
            .initialValue,
        NotificationOperatorObservation.uncertain,
      );
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(
        fixture.requests.where((r) => r['action'] == 'record_outcome'),
        isEmpty,
      );
      await _reveal(tester, evidence);
      await tester.enterText(evidence, 'b' * 64);
      await tester.pumpAndSettle();
      await _reveal(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      final recorded = fixture.requests.singleWhere(
        (r) => r['action'] == 'record_outcome',
      );
      expect(recorded['attempt_id'], otherAttempt);
      expect(recorded['observation'], 'uncertain');
      expect(recorded['evidence_reference_sha256'], 'b' * 64);
      await _unmount(tester, container);
    },
  );

  testWidgets(
    'backgrounding invalidates an acknowledged but delayed native handoff',
    (tester) async {
      final adapter = _DelayedAdapter();
      final fixture = _Fixture(
        handler: (request) async {
          if (request['action'] == 'record_send_start') {
            return _result({
              ..._marker,
              'attempt_id': _attempt,
              'job_id': _job,
              'confirmation_id': request['confirmation_id'],
              'claim_token': _claimToken,
              'fence_version': 1,
              'state': 'send_started',
              'originating_session_id': _canonicalSession,
              'public_session_id': _publicSession,
              'may_send': true,
              'replay': false,
              'acknowledgement': 'first_committed_response_only',
            });
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
        adapter: adapter,
      );
      await _tap(tester, 'Claim for review');
      await _reveal(tester, find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Confirm exact content');
      final start = find.widgetWithText(
        FilledButton,
        'Record start and send once',
      );
      await _reveal(tester, start);
      await tester.tap(start);
      await tester.pump();
      await tester.pump();
      expect(adapter.context, isNotNull);
      await _background(tester);
      expect(adapter.context!.takeForImmediateDispatch(), isNull);
      expect(adapter.context!.takeForImmediateDispatch(), isNull);
      await _foreground(tester);
      adapter.reply.complete(
        NotificationOperatorAdapterObservation(
          observation: NotificationOperatorObservation.uncertain,
          evidenceReferenceSha256: 'a' * 64,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        fixture.requests.where((r) => r['action'] == 'record_outcome'),
        isEmpty,
      );
      expect(find.text(_recipient), findsNothing);
      expect(find.text(_body), findsNothing);
      await _unmount(tester, container);
    },
  );
}
