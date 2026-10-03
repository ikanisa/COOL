import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:collect_app/features/privacy/privacy_providers.dart';
import 'package:collect_app/features/privacy/privacy_request_screen.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:collect_app/l10n/collect_localizations.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'privacy_test_support.dart';

const _route = '/settings/account/delete';
const _sms = MethodChannel('collect/sms_access');
const _snapshot = MethodChannel('collect/secure_snapshot');
const _initialReads = {
  'get_current_member_profile',
  'list_current_user_collections',
  'list_current_member_recent_intents',
  'list_current_member_history_page',
  'list_current_member_collection_balances',
  'get_notification_preferences_v2',
  'notification_events',
};

// Real default repository, protected-cache adapter, provider-owned controller,
// appRouterProvider and global redirect. Only transport replies and platform
// method-channel replies are synthetic. Phoenix joins/replies traverse a real
// loopback WebSocket using the locked SDK; no hosted/RLS/native claim follows.
class _DefaultRouteHarness {
  _DefaultRouteHarness(this.tester);
  final WidgetTester tester;
  late HttpServer server;
  late SupabaseClient client;
  late ProviderContainer container;
  late GoRouter router;
  final sockets = <WebSocket>[];
  final requests = <http.Request>[];
  final events = <Map<String, Object?>>[];
  final nativeEntered = Completer<void>();
  final nativeRelease = Completer<bool>();
  int joins = 0;
  bool holdNextNative = false;
  bool denyProfile = false;
  bool closing = false;
  String verifiedOwner = privacySubject;
  String? protectedValue;
  late ProviderSubscription<CollectState> repositorySubscription;

  CollectState get state => container.read(collectRepositoryProvider);
  CollectRepository get repository =>
      container.read(collectRepositoryProvider.notifier);
  String get path => router.routeInformationProvider.value.uri.path;
  List<http.Request> calls(String tail) =>
      requests.where((r) => r.url.path.endsWith('/$tail')).toList();

  Map<String, dynamic> claims(String? bearer) {
    if (bearer == null) return {};
    return Map<String, dynamic>.from(
      jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(bearer.split('.')[1])),
            ),
          )
          as Map,
    );
  }

  http.Response json(http.Request request, Object? body, [int status = 200]) =>
      http.Response(
        jsonEncode(body),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );

  Future<http.Response> sdkReply(http.Request request) async {
    requests.add(request);
    final tail = request.url.path.split('/').last;
    final identity = claims(request.headers['Authorization']);
    final owner = identity['sub'];
    events.add({
      'kind': 'http',
      'tail': tail,
      'owner': owner,
      'sid': identity['session_id'],
    });
    if (tail == 'logout') return json(request, {});
    if (tail == 'get_current_member_profile' && denyProfile) {
      return json(request, {
        'code': '42501',
        'message': 'Synthetic member profile denial',
      }, 403);
    }
    final body = switch (tail) {
      'get_current_member_profile' => {
        'id': owner,
        'public_id': '123456',
        'whatsapp_phone': '+250788000001',
        'country_code': 'RW',
        'currency_code': 'RWF',
        'momo_provider': 'mtn_momo',
        'momo_number': '0788000001',
      },
      'list_current_user_collections' => [],
      'list_current_member_recent_intents' => {'items': [], 'pending_count': 0},
      'list_current_member_history_page' => {
        'items': [],
        'total_count': 0,
        'totals': {},
        'own_totals': {},
        'own_collection_ids': [],
        'revision': '0123456789abcdef0123456789abcdef',
        'next_cursor': null,
      },
      'list_current_member_collection_balances' => [],
      'get_notification_preferences_v2' => {
        'contract_version': 2,
        'ok': true,
        'user_id': owner,
        'revision': 0,
        'exists': false,
        'preferences': NotificationPreferences.defaults.toJson(),
      },
      'notification_events' || 'public_collections_view' => [],
      'list_account_request_reasons' => [
        {'key': 'mistake', 'label': 'I joined by mistake'},
      ],
      'get_public_runtime_config' => {},
      _ => throw StateError('Unexpected SDK HTTP fixture: $tail'),
    };
    return json(request, body);
  }

  Future<http.Response> privacyReply(http.Request request) async {
    requests.add(request);
    final tail = request.url.path.split('/').last;
    events.add({'kind': 'privacy', 'tail': tail});
    if (tail == 'otp') return json(request, {});
    if (tail == 'verify') {
      return json(
        request,
        privacySession(subject: verifiedOwner, sid: privacyNewSid).toJson(),
      );
    }
    if (tail == 'get_current_account_deletion_request_status_v1') {
      return json(request, null);
    }
    if (tail == 'request_account_deletion_v1') {
      final body = jsonDecode(request.body) as Map;
      return json(
        request,
        privacyReceiptJson(
          submission: true,
          requestId: body['p_request_id'] as String,
          submissionId: body['p_request_id'] as String,
          reasonSupplied: body['p_reason'] != null,
        ),
      );
    }
    throw StateError('Unexpected privacy HTTP fixture: $tail');
  }

  Future<void> mount() async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_sms, (call) async {
      events.add({'kind': 'native', 'method': call.method});
      if (call.method == 'suspendUnlessOwner') {
        if (holdNextNative) {
          holdNextNative = false;
          nativeEntered.complete();
          return nativeRelease.future;
        }
        return true;
      }
      if (call.method == 'setEnabled') return true;
      if (call.method == 'status') {
        return {
          'supported': true,
          'declared': true,
          'enabled': false,
          'consent_enabled': false,
          'granted': false,
        };
      }
      throw StateError('Unexpected native fixture method ${call.method}');
    });
    messenger.setMockMethodCallHandler(_snapshot, (call) async {
      events.add({'kind': 'protected_cache', 'method': call.method});
      if (call.method == 'clear') {
        protectedValue = null;
        return true;
      }
      if (call.method == 'read') return protectedValue;
      if (call.method == 'write') {
        protectedValue = (call.arguments as Map)['value'] as String;
        return true;
      }
      throw StateError('Unexpected protected-cache fixture ${call.method}');
    });
    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) {
          final frame = jsonDecode(raw as String) as List;
          final event = frame[3];
          Map<String, Object?> response = {};
          if (event == 'phx_join') {
            joins++;
            final filters =
                ((frame[4] as Map)['config'] as Map)['postgres_changes']
                    as List;
            response = {
              'postgres_changes': [
                for (final filter in filters) {...filter as Map, 'id': 1},
              ],
            };
            events.add({'kind': 'real_websocket_join', 'count': joins});
          }
          if (!closing &&
              socket.readyState == WebSocket.open &&
              ['phx_join', 'phx_leave', 'heartbeat'].contains(event)) {
            socket.add(
              jsonEncode([
                frame[0],
                frame[1],
                frame[2],
                'phx_reply',
                {'status': 'ok', 'response': response},
              ]),
            );
          }
        });
      });
      final url = 'http://127.0.0.1:${server.port}';
      client = SupabaseClient(
        url,
        'SYNTHETIC_PUBLIC_KEY',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(sdkReply),
      );
      await client.auth.recoverSession(jsonEncode(privacySession().toJson()));
      container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appEnvProvider.overrideWithValue(
            AppEnv(
              supabaseUrl: url,
              supabaseAnonKey: 'SYNTHETIC_PUBLIC_KEY',
              publicUrl: '',
              adminAppUrl: '',
              enableSmsReader: false,
              enableAndroidSmsAccess: false,
              enableAdminPanel: false,
              enableAdminDevTools: false,
              authCaptchaEnabled: false,
              authCaptchaProvider: '',
              authCaptchaSiteKey: '',
            ),
          ),
          privacyRequestTransportProvider.overrideWithValue(
            SupabasePrivacyRequestTransport(
              httpClient: MockClient(privacyReply),
              supabaseUrl: url,
              publishableKey: 'SYNTHETIC_PUBLIC_KEY',
              captchaRequired: false,
            ),
          ),
        ],
      );
      repositorySubscription = container.listen(
        collectRepositoryProvider,
        (_, state) => events.add({
          'kind': 'repository',
          'owner': state.currentProfile?.id,
          'is_loading': state.isLoading,
          'has_error': state.lastError != null,
        }),
      );
      await until(
        () =>
            state.currentProfile?.id == privacySubject &&
            !state.isLoading &&
            joins > 0 &&
            protectedValue != null,
      );
      expect(state.lastError, isNull);
      expect(
        requests.map((r) => r.url.path.split('/').last).toSet(),
        containsAll(_initialReads),
      );
      router = container.read(appRouterProvider);
      router.routeInformationProvider.addListener(
        () => events.add({
          'kind': 'route',
          'uri': router.routeInformationProvider.value.uri.toString(),
        }),
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: const [
            CollectLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          locale: const Locale('en'),
          routerConfig: router,
        ),
      ),
    );
    router.go(_route);
    await flush();
    expect(path, _route);
    expect(find.byType(DeleteAccountRequestScreen), findsOneWidget);
    await press(find.text('I joined by mistake'));
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .value,
      isTrue,
    );
  }

  Future<void> until(bool Function() predicate) async {
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (!predicate() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(predicate(), isTrue, reason: 'Initial/default reads did not settle');
  }

  Future<void> flush() async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> reveal(Finder finder) async {
    final scrollable = find
        .descendant(
          of: find.byType(DeleteAccountRequestScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scrollable, const Offset(0, 3000));
    await flush();
    await tester.scrollUntilVisible(
      finder,
      220,
      scrollable: scrollable,
      maxScrolls: 80,
    );
    await tester.ensureVisible(finder);
    await flush();
  }

  Future<void> press(Finder finder) async {
    await reveal(finder);
    await tester.tap(finder);
    await flush();
  }

  Future<void> verifyWithNativeHeld() async {
    await press(find.byKey(const ValueKey('privacy_send_code')));
    final digit = find.byKey(const ValueKey('auth_otp_digit_0'));
    await reveal(digit);
    await tester.enterText(digit, '123456');
    await flush();
    holdNextNative = true;
    await press(find.byKey(const ValueKey('privacy_verify_code')));
    expect(nativeEntered.isCompleted, isTrue);
    expect(nativeRelease.isCompleted, isFalse);
  }

  void observe(String label) => debugPrintSynchronously(
    'PRIVACY_DEFAULT_ROUTE_PROBE ${jsonEncode({'label': label, 'route': path, 'owner': state.currentProfile?.id, 'is_loading': state.isLoading, 'deletion_form_count': find.byType(DeleteAccountRequestScreen).evaluate().length, 'code_verified_count': find.text('Code verified').evaluate().length, 'submit_calls': calls('request_account_deletion_v1').length, 'native_held': nativeEntered.isCompleted && !nativeRelease.isCompleted, 'real_websocket_joins': joins, 'events': events})}',
  );

  Future<void> resume() async {
    if (!nativeRelease.isCompleted) nativeRelease.complete(true);
    await tester.runAsync(() async {
      await until(
        () =>
            !state.isLoading &&
            (state.currentProfile != null || state.lastError != null),
      );
    });
    await flush();
  }

  Future<void> close() async {
    if (!nativeRelease.isCompleted) nativeRelease.complete(true);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
    repositorySubscription.close();
    container.dispose();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      closing = true;
      await client.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_sms, null);
    messenger.setMockMethodCallHandler(_snapshot, null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'default guarded route retains same-owner verified deletion form through native reread',
    (tester) async {
      final h = _DefaultRouteHarness(tester);
      await h.mount();
      try {
        await h.verifyWithNativeHeld();
        h.observe('same_owner_native_held');
        final heldRoute = h.path;
        final heldFormCount = find
            .byType(DeleteAccountRequestScreen)
            .evaluate()
            .length;
        await h.resume();
        h.observe('same_owner_resumed');
        expect(
          heldRoute,
          _route,
          reason:
              'Same-owner OTP renewal must not dispose the privacy form while native synchronization is held',
        );
        expect(heldFormCount, 1);
        expect(h.path, _route);
        expect(find.text('Code verified'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
              .value,
          isTrue,
        );
        await h.press(find.byKey(const ValueKey('privacy_submit_request')));
        expect(find.text('Submit delete request?'), findsOneWidget);
        await tester.tap(find.text('Submit request').last);
        await h.flush();
        expect(find.text('Request recorded'), findsOneWidget);
        expect(h.calls('request_account_deletion_v1'), hasLength(1));
        expect(
          (jsonDecode(h.calls('request_account_deletion_v1').single.body)
              as Map)['p_reason'],
          'I joined by mistake',
        );
        h.observe('same_owner_submitted');
      } finally {
        await h.close();
      }
    },
  );

  testWidgets(
    'default guarded route removes privacy form on logout while renewal native stop is held',
    (tester) async {
      final h = _DefaultRouteHarness(tester);
      await h.mount();
      try {
        await h.verifyWithNativeHeld();
        await tester.runAsync(() => h.repository.signOut());
        await h.flush();
        h.observe('logout_native_held');
        expect(h.client.auth.currentUser, isNull);
        expect(h.path, '/auth');
        expect(find.byType(DeleteAccountRequestScreen), findsNothing);
        expect(h.calls('request_account_deletion_v1'), isEmpty);
      } finally {
        await h.close();
      }
    },
  );

  testWidgets(
    'default guarded route never transfers old reasons or receipt to another owner',
    (tester) async {
      final h = _DefaultRouteHarness(tester);
      await h.mount();
      try {
        await h.verifyWithNativeHeld();
        await tester.runAsync(
          () => h.client.auth.recoverSession(
            jsonEncode(
              privacySession(
                subject: privacyOtherSubject,
                sid: privacyNewSid,
              ).toJson(),
            ),
          ),
        );
        await tester.runAsync(
          () => h.until(
            () =>
                h.state.currentProfile?.id == privacyOtherSubject &&
                !h.state.isLoading,
          ),
        );
        await h.flush();
        h.observe('owner_switch_native_held');
        expect(find.byType(DeleteAccountRequestScreen), findsNothing);
        expect(h.calls('request_account_deletion_v1'), isEmpty);
        h.router.go(_route);
        await h.flush();
        expect(find.text('Code verified'), findsNothing);
        expect(
          tester
              .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
              .value,
          isFalse,
        );
        expect(find.text('Request recorded'), findsNothing);
      } finally {
        await h.close();
      }
    },
  );

  testWidgets(
    'default guarded route denies privacy submission when refreshed member profile is denied',
    (tester) async {
      final h = _DefaultRouteHarness(tester);
      await h.mount();
      try {
        h.denyProfile = true;
        await h.verifyWithNativeHeld();
        await h.resume();
        h.observe('profile_denied_after_native_resume');
        expect(h.state.currentProfile, isNull);
        expect(h.state.lastError, isNotNull);
        expect(h.path, '/auth');
        expect(find.byType(DeleteAccountRequestScreen), findsNothing);
        expect(h.calls('request_account_deletion_v1'), isEmpty);
        expect(h.protectedValue, isNull);
      } finally {
        await h.close();
      }
    },
  );
}
