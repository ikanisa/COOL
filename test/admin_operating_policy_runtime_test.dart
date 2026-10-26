import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_operating_policy_models.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as auth;
import 'support/admin_operating_policy_fixture.dart';

const _identity = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic policy reviewer',
  roles: ['platform_owner'],
  permissions: ['notifications.read', 'system_health.read'],
);

class _Probe {
  late CollectCloudflareClient client;
  late AdminRepository repository;
  late ProviderContainer container;
  final raw = operatingPolicyFixture();
  final requests = <http.Request>[];
  final entered = Completer<void>();
  Completer<void>? release;
  Object? error;
  late final authority = StateProvider<Future<AdminIdentity?>>(
    (_) => Future.value(_identity),
  );
  late final clock = StateProvider<DateTime>(
    (_) => DateTime.parse(
      raw['checked_at'] as String,
    ).add(const Duration(seconds: 10)),
  );

  Future<void> start() async {
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final token = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(token[0], token[1]));
        }
        if (request.url.path.endsWith('/logout')) return auth.response({});
        requests.add(request);
        if (!entered.isCompleted) entered.complete();
        if (release != null) await release!.future;
        final response = error is String
            ? auth.response({
                'code': error,
                'message': 'PRIVATE_CANARY',
              }, error == 'operation_unavailable' ? 501 : 403)
            : auth.response(raw);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await auth.session(client, 'policy-session-a');
    repository = AdminRepository(client);
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
        adminClockProvider.overrideWith((ref) {
          final now = ref.watch(clock);
          return () => now;
        }),
      ],
    );
  }

  Future<void> finish() async {
    if (release != null && !release!.isCompleted) release!.complete();
    container.dispose();
    await client.dispose();
  }

  Future<AdminOperatingPolicySnapshot> read() =>
      container.read(adminOperatingPolicyProvider.future);
  AdminIdentity denied(String field) => AdminIdentity(
    userId: auth.actor,
    displayName: 'Synthetic denied policy reviewer',
    roles: field == 'role' ? ['admin'] : _identity.roles,
    permissions: _identity.permissions.where((v) => v != field).toList(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late _Probe probe;
  setUp(() async {
    probe = _Probe();
    await probe.start();
  });
  tearDown(() => probe.finish());

  test(
    'actual SDK binds no-argument policy RPC and current bearer once',
    () async {
      expect(await probe.repository.operatingPolicy(), probe.raw);
      expect(probe.requests, hasLength(1));
      final request = probe.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/v1/rpc/admin_get_unattended_operating_policy_v1',
      );
      expect(jsonDecode(request.body), isEmpty);
      expect(
        request.headers['Authorization'],
        'Bearer ${probe.client.auth.currentSession!.accessToken}',
      );
    },
  );
  test(
    'actual SDK rejects fabricated dispatch in one response without retry',
    () async {
      probe.raw['execution']['unattended_dispatch_available'] = true;
      await expectLater(
        probe.repository.operatingPolicy(),
        throwsFormatException,
      );
      expect(probe.requests, hasLength(1));
    },
  );
  testWidgets('policy read deadline returns uncertainty without a retry', (
    tester,
  ) async {
    probe.release = Completer<void>();
    final outcome = probe.repository.operatingPolicy().then<Object?>(
      (value) => value,
      onError: (Object error) => error,
    );
    await tester.pump();
    expect(probe.requests, hasLength(1));
    await tester.pump(const Duration(seconds: 15));
    expect(await outcome, isA<TimeoutException>());
    expect(probe.requests, hasLength(1));
    probe.release!.complete();
    await tester.pump();
  });
  for (final code in ['55P03', '42501', 'operation_unavailable']) {
    test('actual SDK does not automatically retry policy $code', () async {
      probe.error = code;
      await expectLater(
        probe.repository.operatingPolicy(),
        throwsA(isA<CollectApiException>()),
      );
      expect(probe.requests, hasLength(1));
    });
  }
  for (final switchBack in [false, true]) {
    test(
      'SDK suppresses departed same-owner response A-B-A=$switchBack',
      () async {
        probe.release = Completer<void>();
        final result = probe.repository.operatingPolicy().then<Object?>(
          (v) => v,
          onError: (Object e) => e,
        );
        await probe.entered.future;
        await auth.session(probe.client, 'policy-session-b');
        if (switchBack) {
          await auth.session(probe.client, 'policy-session-a', nonce: 2);
        }
        probe.release!.complete();
        expect(await result, isA<AdminSessionChanged>());
        expect(probe.requests, hasLength(1));
      },
    );
  }
  for (final field in [
    'role',
    'notifications.read',
    'system_health.read',
    'absent',
  ]) {
    test('provider requires current $field proof before dispatch', () async {
      probe.container.read(probe.authority.notifier).state = Future.value(
        field == 'absent' ? null : probe.denied(field),
      );
      await expectLater(
        probe.read(),
        throwsA(isA<AdminOperatingPolicyDenied>()),
      );
      expect(probe.requests, isEmpty);
    });
  }
  test(
    'provider waits for fresh current identity before one SDK dispatch',
    () async {
      final ready = Completer<AdminIdentity?>();
      addTearDown(() {
        if (!ready.isCompleted) ready.complete(null);
      });
      probe.container.read(probe.authority.notifier).state = ready.future;
      final keep = probe.container.listen(
        adminOperatingPolicyProvider,
        (_, _) {},
      );
      addTearDown(keep.close);
      final read = probe.read();
      await probe.container.pump();
      expect(probe.requests, isEmpty);
      ready.complete(_identity);
      expect((await read).revision, 1);
      expect(probe.requests, hasLength(1));
    },
  );
  test('provider suppresses late observation after permission loss', () async {
    probe.release = Completer<void>();
    final emissions = <AsyncValue<AdminOperatingPolicySnapshot>>[];
    final keep = probe.container.listen(
      adminOperatingPolicyProvider,
      (_, next) => emissions.add(next),
    );
    addTearDown(keep.close);
    final pending = probe.read().then<Object?>(
      (v) => v,
      onError: (Object e) => e,
    );
    await probe.entered.future;
    probe.container.read(probe.authority.notifier).state = Future.value(
      probe.denied('notifications.read'),
    );
    await probe.container.pump();
    probe.release!.complete();
    await probe.container.pump();
    expect(await pending, isA<AdminOperatingPolicyDenied>());
    expect(emissions.where((v) => v.asData != null), isEmpty);
    expect(probe.requests, hasLength(1));
  });

  Future<void> drainWidget(WidgetTester tester, bool Function() ready) async {
    for (var attempt = 0; attempt < 40 && !ready(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      ready(),
      isTrue,
      reason: 'Bounded actual SDK/UI event-loop completion',
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 2200),
    double scale = 1,
    bool dark = false,
    GlobalKey? boundary,
  }) async {
    // Prime the real SDK-backed future outside the widget FakeAsync zone.
    // Keep both successful and failed observations mounted for the UI assertion.
    late ProviderSubscription<AsyncValue<AdminOperatingPolicySnapshot>> keep;
    await tester.runAsync(() async {
      keep = probe.container.listen(adminOperatingPolicyProvider, (_, _) {});
      await probe.read().then<Object?>(
        (value) => value,
        onError: (Object error) => error,
      );
    });
    addTearDown(keep.close);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: probe.container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RepaintBoundary(
            key: boundary,
            child: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: AdminOperatingPolicyCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> load(WidgetTester tester, {bool allowError = false}) async {
    late ProviderSubscription<AsyncValue<AdminOperatingPolicySnapshot>> keep;
    // Create and await the SDK-backed provider in the same real event loop.
    // A listener created in FakeAsync cannot finish while runAsync awaits it.
    await tester.runAsync(() async {
      keep = probe.container.listen(adminOperatingPolicyProvider, (_, _) {});
      if (allowError) {
        await probe.read().then<Object?>(
          (value) => value,
          onError: (Object error) => error,
        );
      } else {
        await probe.read();
      }
    });
    addTearDown(keep.close);
  }

  for (final dark in [false, true]) {
    testWidgets(
      'policy preparation renders $dark theme with no execution action',
      (tester) async {
        await load(tester);
        final boundary = GlobalKey();
        await mount(tester, dark: dark, boundary: boundary);
        expect(find.text('Legacy unattended preferences'), findsOneWidget);
        expect(find.textContaining('unavailable in every mode'), findsNothing);
        expect(find.text('Live authority pending'), findsNothing);
        expect(find.text('Action limits'), findsNothing);
        expect(find.text('Refresh policy'), findsOneWidget);
        expect(find.byType(Switch), findsNothing);
        expect(find.text('PRIVATE_CANARY'), findsNothing);
        expect(tester.takeException(), isNull);
        final path = Platform.environment['COLLECT_POLICY_CAPTURE_DIR'];
        if (path != null) {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final target = File(
              '$path/policy-${dark ? 'dark' : 'light'}-synthetic.png',
            );
            await target.parent.create(recursive: true);
            await target.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets('policy facts reflow at 320px doubled text $dark', (
      tester,
    ) async {
      await load(tester);
      await mount(tester, size: const Size(320, 1800), scale: 2, dark: dark);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Refresh policy'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Refresh policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'expired observation hides preference facts and manual refresh performs one read',
    (tester) async {
      await load(tester);
      await mount(tester);
      expect(find.text('Configured preference'), findsOneWidget);
      final checked = DateTime.parse(probe.raw['checked_at'] as String);
      await tester.runAsync(() async {
        probe.container.read(probe.clock.notifier).state = checked.add(
          const Duration(seconds: 60),
        );
      });
      await drainWidget(
        tester,
        () => find.text('Configured preference').evaluate().isEmpty,
      );
      expect(find.text('Configured preference'), findsNothing);
      expect(find.textContaining('observation expired'), findsOneWidget);
      final count = probe.requests.length;
      // Trigger SDK work in the real event loop, then let the mounted
      // Riverpod scope schedule its Flutter frame before observing completion.
      await tester.runAsync(() => tester.tap(find.text('Refresh policy')));
      await tester.pump();
      await drainWidget(
        tester,
        () =>
            probe.requests.length == count + 1 &&
            !probe.container.read(adminOperatingPolicyProvider).isLoading,
      );
      await tester.pump();
      expect(probe.requests, hasLength(count + 1));
      expect(
        probe.requests.every(
          (r) =>
              r.url.path.endsWith('/admin_get_unattended_operating_policy_v1'),
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final field in [
    'role',
    'notifications.read',
    'system_health.read',
    'loading',
  ]) {
    testWidgets('loaded private policy hides when authority becomes $field', (
      tester,
    ) async {
      await load(tester);
      await mount(tester);
      expect(find.text('Configured preference'), findsOneWidget);
      final pending = Completer<AdminIdentity?>();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete(null);
      });
      await tester.runAsync(() async {
        probe.container
            .read(probe.authority.notifier)
            .state = field == 'loading'
            ? pending.future
            : Future.value(probe.denied(field));
      });
      await drainWidget(
        tester,
        () => find.text('Configured preference').evaluate().isEmpty,
      );
      expect(find.text('Configured preference'), findsNothing);
      expect(find.text(probe.raw['policy_id'] as String), findsNothing);
      expect(probe.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final code in [
    '55P03',
    '42501',
    'operation_unavailable',
    'UNEXPECTED_PRIVATE_CANARY',
  ]) {
    testWidgets(
      'policy error $code remains redacted with named manual recovery',
      (tester) async {
        probe.error = code;
        await load(tester, allowError: true);
        await mount(tester);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(find.text('Refresh policy'), findsOneWidget);
        expect(probe.requests, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
