// Explicit offline native fixture for unchanged Collect route captures.
// This target is never imported from lib or shipped as a production entrypoint.
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/privacy/privacy_providers.dart';
import 'package:collect_app/features/privacy/privacy_request_controller.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test/features/privacy/privacy_test_support.dart';
import '../test/fixtures/collect_repository_fixture.dart';

class _OfflineFixtureHttpOverrides extends HttpOverrides {
  final attempts = <String>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts.add('HttpClient creation blocked before transport');
    throw const HttpException('Native media fixture has no network access.');
  }
}

void main() {
  if (!kDebugMode ||
      !(Platform.isIOS || Platform.isAndroid) ||
      !const bool.fromEnvironment('COLLECT_MOBILE_EVIDENCE_MODE')) {
    throw StateError('Explicit native debug media fixture required.');
  }
  if (Platform.isAndroid &&
      const String.fromEnvironment('COLLECT_NATIVE_MEDIA_PACKAGE') !=
          'app.cool.mobile.mediafixture') {
    throw StateError('Isolated Android media fixture package required.');
  }
  if (Platform.isAndroid &&
      const bool.fromEnvironment('COLLECT_NATIVE_OS_CAPTURE')) {
    throw StateError('Android fixture captures the real Flutter surface.');
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final offline = _OfflineFixtureHttpOverrides();
  HttpOverrides.global = offline;
  GoRouter? activeRouter;

  testWidgets(
    'seven current native routes provide authentic app media',
    (tester) async {
      await binding.convertFlutterSurfaceToImage();
      final displayCapture =
          const bool.fromEnvironment('COLLECT_NATIVE_OS_CAPTURE')
          ? _NativeDisplayCapture()
          : null;
      await displayCapture?.initialize();
      for (final spec in _routes) {
        _NativeMediaPrivacyFixture? privacy;
        try {
          FocusManager.instance.primaryFocus?.unfocus();
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          activeRouter?.dispose();
          if (spec.id == 'account-deletion') {
            privacy = await _NativeMediaPrivacyFixture.create();
          }
          final repository = FixtureCollectRepository(
            fixtureNow: DateTime.utc(2026, 9, 2, 10),
            profileOverride: privacy?.profile,
          );
          final router = createAppRouter(initialLocation: spec.route);
          activeRouter = router;
          await tester.pumpWidget(
            ProviderScope(
              key: ValueKey('native-public-media-${spec.id}'),
              overrides: [
                // The stock fixture activity deliberately has no SMS host.
                momoReceiptCaptureAvailableProvider.overrideWithValue(false),
                collectBackendClientProvider.overrideWithValue(null),
                collectAuthenticatedUserIdProvider.overrideWithValue(
                  privacy == null ? 'local-user' : privacySubject,
                ),
                if (privacy != null) ...[
                  // A detached, synthetic session exercises the real controller
                  // and transport. The app's backend remains unavailable.
                  privacySessionAuthorityProvider.overrideWithValue(
                    privacy.authority,
                  ),
                  privacyRequestTransportProvider.overrideWithValue(
                    privacy.transport,
                  ),
                  collectAccountDeletionReasonsProvider.overrideWith(
                    (ref) async => collectDefaultAccountDeletionReasons,
                  ),
                ],
                collectRepositoryProvider.overrideWith((ref) => repository),
                appRouterProvider.overrideWithValue(router),
                collectThemeModeProvider.overrideWith(
                  (ref) => CollectThemeModeController(
                    initialMode: ThemeMode.dark,
                    loadPersistedMode: false,
                  ),
                ),
              ],
              child: const CollectApp(),
            ),
          );
          for (var frame = 0; frame < 35; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull, reason: spec.route);
          expect(
            ProviderScope.containerOf(
              tester.element(find.byType(CollectApp)),
            ).read(momoReceiptCaptureAvailableProvider),
            isFalse,
            reason: 'Offline media fixture must not subscribe to native SMS.',
          );
          expect(router.routeInformationProvider.value.uri.path, spec.route);
          expect(find.textContaining(spec.marker), findsWidgets);
          expect(find.text('Screen not found'), findsNothing);
          expect(offline.attempts, isEmpty);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(CollectApp)),
          );
          expect(container.read(collectBackendClientProvider), isNull);
          if (privacy != null) {
            privacy.controller = container.read(
              privacyRequestControllerProvider,
            );
            privacy.assertCurrentUnverifiedForm(tester);
          }
          _assertCurrentRouteLayout(tester, spec);
          FocusManager.instance.primaryFocus?.unfocus();
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final markerBounds = tester.getRect(
            find.textContaining(spec.marker).first,
          );
          await _settleNativeFrame(tester, binding);
          expect(router.routeInformationProvider.value.uri.path, spec.route);
          expect(
            tester.getRect(find.textContaining(spec.marker).first),
            markerBounds,
          );
          _assertCurrentRouteLayout(tester, spec);
          privacy?.assertCurrentUnverifiedForm(tester);
          await binding.takeScreenshot(spec.id);
          if (displayCapture != null) {
            // UIKit hierarchy captures are retained as diagnostics. The host also
            // captures the actual simulator display while this route stays open.
            await tester.runAsync(() => displayCapture.capture(spec));
          }
          // Actual runtime route and marker assertions precede every capture.
          // ignore: avoid_print
          print(
            'collect_native_media:pass:${spec.id}:${spec.route}:${spec.marker}',
          );
        } finally {
          // Complete fixture teardown inside the callback, including the real
          // detached SDK's refresh Timer; no external client is provider-owned.
          try {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            activeRouter?.dispose();
            activeRouter = null;
          } finally {
            await privacy?.close();
          }
        }
      }
      expect(offline.attempts, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      activeRouter?.dispose();
      activeRouter = null;
      // ignore: avoid_print
      print('collect_native_media:complete:7:network-attempts=0');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// The only synthetic privacy response is the supported current-status read.
/// It means this fixture has no existing request; no mutation or health result
/// is supplied. Real identity verification and request handling remain untested.
class _NativeMediaPrivacyFixture {
  CollectCloudflareClient? _client;
  CollectPrivacySessionAuthority? _authority;
  MockClient? _wire;
  CollectPrivacyRequestTransport? _transport;
  PrivacyRequestController? controller;
  int _statusReads = 0;
  int _wireRequests = 0;
  int _pendingReads = 0;
  int _sdkRequests = 0;
  bool _closed = false;

  CollectPrivacySessionAuthority get authority => _authority!;
  CollectPrivacyRequestTransport get transport => _transport!;
  CollectProfile get profile => const CollectProfile(
    id: privacySubject,
    publicId: '123456',
    whatsappPhone: '+250788000001',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788000001',
  );

  static Future<_NativeMediaPrivacyFixture> create() async {
    final fixture = _NativeMediaPrivacyFixture();
    try {
      fixture._client = CollectCloudflareClient(
        'https://synthetic.invalid',
        sessionStorage: CollectMemorySessionStorage(),
        httpClient: MockClient((request) async {
          fixture._sdkRequests++;
          throw StateError('SDK transport is forbidden in the media fixture.');
        }),
      );
      await fixture._client!.auth.recoverSession(
        jsonEncode(privacySession().toJson()),
      );
      fixture._authority = CollectPrivacySessionAuthority(
        fixture._client!.auth,
      );
      fixture._wire = MockClient((request) async {
        fixture._wireRequests++;
        if (fixture._closed ||
            request.method != 'POST' ||
            request.url.toString() !=
                'https://synthetic.invalid/v1/rpc/get_current_account_deletion_request_status_v1' ||
            jsonDecode(request.body) is! Map ||
            (jsonDecode(request.body) as Map).isNotEmpty ||
            fixture._statusReads != 0 ||
            fixture._wireRequests != 1) {
          throw StateError(
            'Only one current-status fixture read is supported.',
          );
        }
        fixture._statusReads++;
        fixture._pendingReads++;
        try {
          return http.Response(
            'null',
            200,
            headers: {'content-type': 'application/json'},
          );
        } finally {
          fixture._pendingReads--;
        }
      });
      fixture._transport = CollectPrivacyRequestTransport(
        httpClient: fixture._wire!,
        apiUrl: 'https://synthetic.invalid',
        isSessionCurrent: (owner) {
          try {
            return fixture.authority.capture().sameFence(owner);
          } catch (_) {
            return false;
          }
        },
      );
      return fixture;
    } catch (_) {
      await fixture.close();
      rethrow;
    }
  }

  void assertCurrentUnverifiedForm(WidgetTester tester) {
    expect(_closed, isFalse);
    expect(authority.capture().subjectId, privacySubject);
    expect(controller, isNotNull);
    expect(identical(controller!.authority, authority), isTrue);
    expect(identical(controller!.transport, transport), isTrue);
    expect(controller!.busy, isFalse);
    expect(controller!.hasFreshVerification, isFalse);
    expect(controller!.codeSent, isFalse);
    expect(controller!.receipt, isNull);
    expect(controller!.pendingIdentity, isNull);
    expect(controller!.outcomeUnknown, isFalse);
    expect(_statusReads, 1);
    expect(_wireRequests, 1);
    expect(_pendingReads, 0);
    expect(_sdkRequests, 0);
    expect(_wireRequests, _statusReads);
    expect(find.text('Reason (optional)'), findsOneWidget);
    expect(find.text('Request account deletion'), findsOneWidget);
    expect(find.text('Request service unavailable'), findsNothing);
    expect(find.text('Request recorded'), findsNothing);
    expect(find.text('Code verified'), findsNothing);
    expect(
      tester
          .widget<CollectButton>(
            find.byKey(const ValueKey('privacy_submit_request')),
          )
          .onPressed,
      isNull,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      controller?.dispose();
    } finally {
      try {
        await _authority?.dispose();
      } finally {
        _wire?.close();
        await _client?.dispose();
      }
    }
    expect(_pendingReads, 0);
    expect(_sdkRequests, 0);
    expect(_wireRequests, _statusReads);
  }
}

Future<void> _settleNativeFrame(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  // A real frame/compositor opportunity supplements the bounded fake-clock
  // pumps. This is diagnostic preparation, not proof of glyph pixel fidelity.
  await tester.pump();
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  // LiveTest's default policy draws explicit pumps. Register completion first,
  // then request that subsequent frame instead of suspending without a pump.
  final subsequentFrame = binding.endOfFrame;
  await Future.wait<void>([
    subsequentFrame,
    tester.pump(),
  ]).timeout(const Duration(seconds: 3));
  expect(tester.takeException(), isNull);
}

void _assertCurrentRouteLayout(WidgetTester tester, _MediaRoute spec) {
  if (const {'home', 'groups', 'group-detail'}.contains(spec.id)) {
    final nav = find.byKey(const ValueKey('collect-floating-navigation'));
    expect(nav, findsOneWidget);
    final navBounds = tester.getRect(nav);
    for (final label in const ['Home', 'Groups', 'Activity', 'Profile']) {
      final item = find.descendant(
        of: nav,
        matching: find.byKey(ValueKey('collect-nav-${label.toLowerCase()}')),
      );
      expect(item, findsOneWidget);
      final icon = find.descendant(of: item, matching: find.byType(Icon));
      final text = find.descendant(of: item, matching: find.text(label));
      expect(icon, findsOneWidget);
      expect(text, findsOneWidget);
      expect(navBounds.contains(tester.getCenter(icon)), isTrue);
      expect(navBounds.contains(tester.getCenter(text)), isTrue);
      expect(tester.getSize(icon).isEmpty, isFalse);
      expect(tester.getSize(text).isEmpty, isFalse);
      expect(tester.widget<Icon>(icon).color!.a, greaterThan(0));
      expect(tester.widget<Text>(text).style!.color!.a, greaterThan(0));
    }
  }
  if (spec.id == 'terms' || spec.id == 'privacy') {
    for (final section in CollectPolicyDocument.defaults(spec.id).sections) {
      final body = find.text(section.body, skipOffstage: false);
      expect(body, findsOneWidget);
      final rich = find.descendant(
        of: body,
        matching: find.byType(RichText, skipOffstage: false),
      );
      expect(rich, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(rich);
      expect(paragraph.text.toPlainText(), section.body);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, greaterThan(0));
      final prefix = section.body.length < 7 ? section.body.length : 7;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: prefix),
      );
      expect(boxes, isNotEmpty);
      for (final box in boxes) {
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(paragraph.size.width));
      }
    }
  }
}

// A debug-fixture-only file handshake keeps the asserted route on screen until
// the host's simctl screenshot finishes. It uses no transport or app service.
class _NativeDisplayCapture {
  final directory = Directory(
    '${Directory.systemTemp.path}/collect-native-media-display',
  );
  final runId = DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> initialize() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  Future<void> capture(_MediaRoute spec) async {
    // Allow the raster thread and OS compositor to complete in real time.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final ready = File('${directory.path}/${spec.id}.ready.json');
    final temporary = File('${ready.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'run_id': runId,
        'id': spec.id,
        'route': spec.route,
        'marker': spec.marker,
        'capture_kind': 'native_ios_simulator_display',
      }),
      flush: true,
    );
    await temporary.rename(ready.path);
    final acknowledgment = File('${directory.path}/${spec.id}.ack.json');
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (DateTime.now().isBefore(deadline)) {
      if (acknowledgment.existsSync()) {
        final data = jsonDecode(await acknowledgment.readAsString());
        if (data is Map &&
            data['run_id'] == runId &&
            data['id'] == spec.id &&
            data['status'] == 'captured') {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Native display capture timed out for ${spec.id}.');
  }
}

class _MediaRoute {
  const _MediaRoute(this.id, this.route, this.marker);
  final String id;
  final String route;
  final String marker;
}

const _routes = [
  _MediaRoute('home', '/home', 'RWF 35,000'),
  _MediaRoute('groups', '/groups', 'Groups'),
  _MediaRoute('group-detail', '/groups/qa-private-group', 'QA private group'),
  _MediaRoute('security', '/settings/security', 'Approve payments in MoMo'),
  _MediaRoute('privacy', '/settings/legal/privacy', 'Data we collect'),
  _MediaRoute('terms', '/settings/legal/terms', 'Using Collect'),
  _MediaRoute(
    'account-deletion',
    '/settings/account/delete',
    'Reason (optional)',
  ),
];
