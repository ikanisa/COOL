// Explicit offline native fixture for unchanged Collect route captures.
// This target is never imported from lib or shipped as a production entrypoint.
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

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
      !Platform.isIOS ||
      !const bool.fromEnvironment('COLLECT_MOBILE_EVIDENCE_MODE')) {
    throw StateError('Explicit iOS debug media fixture required.');
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
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        activeRouter?.dispose();
        final repository = FixtureCollectRepository(
          fixtureNow: DateTime.utc(2026, 9, 2, 10),
        );
        final router = createAppRouter(initialLocation: spec.route);
        activeRouter = router;
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey('native-public-media-${spec.id}'),
            overrides: [
              supabaseClientProvider.overrideWithValue(null),
              collectAuthenticatedUserIdProvider.overrideWithValue(
                'local-user',
              ),
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
        expect(router.routeInformationProvider.value.uri.path, spec.route);
        expect(find.textContaining(spec.marker), findsWidgets);
        expect(find.text('Screen not found'), findsNothing);
        expect(offline.attempts, isEmpty);
        FocusManager.instance.primaryFocus?.unfocus();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        for (var frame = 0; frame < 6; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
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
    'Select a reason to submit.',
  ),
];
