import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_runtime_typography.dart';
import 'package:collect_app/core/widgets/collect_shell.dart';
import 'package:collect_app/features/auth/auth_screen.dart';
import 'package:collect_app/features/collections/collection_create_screen.dart';
import 'package:collect_app/features/collections/collection_detail_screen.dart';
import 'package:collect_app/features/collections/collection_manage_screen.dart';
import 'package:collect_app/features/collections/collections_screen.dart';
import 'package:collect_app/features/collections/group_link_screen.dart';
import 'package:collect_app/features/collections/group_profile_screen.dart';
import 'package:collect_app/features/collections/group_qr_scanner_screen.dart';
import 'package:collect_app/features/collections/share_screen.dart';
import 'package:collect_app/features/home/home_screen.dart';
import 'package:collect_app/features/ledger/ledger_screen.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/features/profile/profile_setup_screen.dart';
import 'package:collect_app/features/settings/settings_screen.dart';
import 'package:collect_app/features/status/production_state_screens.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final evidenceRoot = Platform.environment['COLLECT_VISUAL_EVIDENCE_DIR'];
  final visualThemeMode = _visualThemeModeFromEnv(
    Platform.environment['COLLECT_VISUAL_THEME_MODE'],
  );
  final mobileTextScale = _mobileTextScaleFromEnv();
  final captureAdminEvidence =
      Platform.environment['COLLECT_VISUAL_CAPTURE_ADMIN'] != '0';
  if (evidenceRoot == null || evidenceRoot.isEmpty) {
    test(
      'visual evidence capture is opt-in',
      () => expect(true, isTrue),
      skip: 'Set COLLECT_VISUAL_EVIDENCE_DIR to write PNG evidence.',
    );
    return;
  }

  final root = Directory(evidenceRoot)..createSync(recursive: true);
  final mobileDir = Directory('${root.path}/mobile')
    ..createSync(recursive: true);
  final adminDir = Directory('${root.path}/admin')..createSync(recursive: true);

  setUpAll(_loadCollectRuntimeFontsForEvidence);

  final mobileSpecs = _mobileRouteSpecs();
  final mobileCaptures = <Map<String, Object?>>[];
  group('mobile visual evidence', () {
    for (final spec in mobileSpecs) {
      testWidgets('captures ${spec.name}', (tester) async {
        final viewport = _mobileViewportFromEnv();
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = _visualDevicePixelRatioFromEnv();
        tester.platformDispatcher.platformBrightnessTestValue =
            visualThemeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        final name = spec.name;
        final route = spec.route;
        debugPrint('[visual-evidence] capturing $name $route');
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectRepositoryProvider.overrideWith(
                (ref) => CollectRepository.fixture(),
              ),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                title: 'Collect',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: visualThemeMode,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(mobileTextScale)),
                  child: child!,
                ),
                home: Material(
                  color: Colors.transparent,
                  child: TickerMode(
                    enabled: false,
                    child: CollectShell(
                      currentPath: route,
                      onNavigate: (_) {},
                      child: _mobileRouteScreen(route),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _pumpForEvidence(tester);
        final capture = (await tester.runAsync(
          () => _capturePng(key, pixelRatio: _visualDevicePixelRatioFromEnv()),
        ))!;
        final fileName = '$name-${capture.width}x${capture.height}.png';
        final file = File('${mobileDir.path}/$fileName');
        file.writeAsBytesSync(capture.bytes);
        debugPrint('[visual-evidence] wrote ${file.path}');
        expect(capture.bytes.length, greaterThan(8000));
        expect(capture.nonBackgroundPixels, greaterThan(100));
        expect(capture.distinctRgb, greaterThan(16));
        mobileCaptures.add({
          'status': 'pass',
          'name': name,
          'route': route,
          'route_class': spec.routeClass,
          'product_screen': spec.isProductScreen,
          'path': fileName,
          'width': capture.width,
          'height': capture.height,
          'bytes': capture.bytes.length,
          'sampled_pixels': capture.sampledPixels,
          'distinct_rgb': capture.distinctRgb,
          'non_background_pixels': capture.nonBackgroundPixels,
        });
        debugPrint('[visual-evidence] finished $name');
      }, timeout: const Timeout(Duration(seconds: 35)));
    }

    tearDownAll(() {
      _writeJson(File('${mobileDir.path}/summary.json'), {
        'status': mobileCaptures.length == mobileSpecs.length
            ? 'pass'
            : 'partial',
        'capture_runtime': 'flutter_test_repaint_boundary_member_shell',
        'theme_mode': visualThemeMode.name,
        'text_scale': mobileTextScale,
        'viewport':
            '${_mobileViewportFromEnv().width.toInt()}x${_mobileViewportFromEnv().height.toInt()}',
        'expected_route_count': mobileSpecs.length,
        'route_count': mobileCaptures.length,
        'product_screen_count': mobileSpecs
            .where((spec) => spec.isProductScreen)
            .length,
        'compatibility_route_count': mobileSpecs
            .where((spec) => !spec.isProductScreen)
            .length,
        'routes': [for (final capture in mobileCaptures) capture['route']],
        'route_specs': [
          for (final spec in mobileSpecs)
            {
              'name': spec.name,
              'route': spec.route,
              'route_class': spec.routeClass,
              'product_screen': spec.isProductScreen,
            },
        ],
        'product_screens': [
          for (final spec in mobileSpecs)
            if (spec.isProductScreen) spec.name,
        ],
        'compatibility_routes': [
          for (final spec in mobileSpecs)
            if (!spec.isProductScreen) spec.name,
        ],
        'screenshots': [for (final capture in mobileCaptures) capture['path']],
        'captures': mobileCaptures,
        'privacy':
            'Synthetic test rendering; screenshots must not include raw secrets, OTPs, raw SMS bodies, provider tokens, or production customer data.',
      });
      File(
        '${mobileDir.path}/captures.jsonl',
      ).writeAsStringSync('${mobileCaptures.map(jsonEncode).join('\n')}\n');
    });
  });

  testWidgets(
    'captures admin desktop and mobile screenshots without Chrome',
    (tester) async {
      final captures = <Map<String, Object?>>[];

      Future<void> captureAdmin({
        required String name,
        required Size viewport,
        required Widget child,
      }) async {
        debugPrint('[visual-evidence] capturing $name');
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue =
            visualThemeMode == ThemeMode.dark
            ? Brightness.dark
            : Brightness.light;
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(key: key, child: child));
        await _pumpForEvidence(tester);
        final capture = (await tester.runAsync(
          () => _capturePng(key, pixelRatio: 1),
        ))!;
        final fileName = '$name-${capture.width}x${capture.height}.png';
        File('${adminDir.path}/$fileName').writeAsBytesSync(capture.bytes);
        captures.add({
          'status': 'pass',
          'name': name,
          'path': fileName,
          'width': capture.width,
          'height': capture.height,
          'bytes': capture.bytes.length,
          'sampled_pixels': capture.sampledPixels,
          'distinct_rgb': capture.distinctRgb,
          'non_background_pixels': capture.nonBackgroundPixels,
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      for (final route in _adminEvidenceRoutes) {
        for (final viewport in const [Size(390, 844), Size(1440, 900)]) {
          final viewportName = viewport.width == 390 ? 'mobile' : 'desktop';
          await captureAdmin(
            name: 'admin-${route.name}-$viewportName',
            viewport: viewport,
            child: _adminAppAt(route.path),
          );
        }
      }

      _writeJson(File('${adminDir.path}/summary.json'), {
        'status': 'pass',
        'capture_runtime': 'flutter_test_repaint_boundary',
        'theme_mode': visualThemeMode.name,
        'route_count': _adminEvidenceRoutes.length,
        'viewports': ['390x844', '1440x900'],
        'expected_screenshot_count': _adminEvidenceRoutes.length * 2,
        'screenshots': [for (final capture in captures) capture['path']],
        'captures': captures,
        'privacy':
            'Admin screenshots use test-only masked repository data and no production Supabase session.',
      });

      expect(
        captures.every((capture) => (capture['bytes']! as int) > 8000),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 12)),
    skip: !captureAdminEvidence,
  );
}

Future<void> _loadCollectRuntimeFontsForEvidence() async {
  final collectLoader = FontLoader(CollectRuntimeTypography.fontFamily)
    ..addFont(
      rootBundle.load('assets/fonts/collect/CollectRuntime-Regular.otf'),
    )
    ..addFont(rootBundle.load('assets/fonts/collect/CollectRuntime-Medium.otf'))
    ..addFont(
      rootBundle.load('assets/fonts/collect/CollectRuntime-SemiBold.otf'),
    )
    ..addFont(rootBundle.load('assets/fonts/collect/CollectRuntime-Bold.otf'))
    ..addFont(
      rootBundle.load('assets/fonts/collect/CollectRuntime-ExtraBold.otf'),
    );
  await collectLoader.load();

  final displayLoader = FontLoader(CollectRuntimeTypography.displayFontFamily)
    ..addFont(
      rootBundle.load('assets/fonts/collect/CollectDisplay-Regular.otf'),
    )
    ..addFont(rootBundle.load('assets/fonts/collect/CollectDisplay-Medium.otf'))
    ..addFont(
      rootBundle.load('assets/fonts/collect/CollectDisplay-SemiBold.otf'),
    )
    ..addFont(rootBundle.load('assets/fonts/collect/CollectDisplay-Bold.otf'))
    ..addFont(
      rootBundle.load('assets/fonts/collect/CollectDisplay-ExtraBold.otf'),
    );
  await displayLoader.load();

  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '/Volumes/PRO-G40/flutter_3_44';
  final materialIconsPath =
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  final materialIconsFile = File(materialIconsPath);
  if (materialIconsFile.existsSync()) {
    final materialIconsLoader = FontLoader('MaterialIcons')
      ..addFont(_loadFontFile(materialIconsFile));
    await materialIconsLoader.load();
  }
}

Future<ByteData> _loadFontFile(File file) async {
  final bytes = await file.readAsBytes();
  return ByteData.sublistView(bytes);
}

ThemeMode _visualThemeModeFromEnv(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    _ => ThemeMode.dark,
  };
}

Size _mobileViewportFromEnv() {
  final value = Platform.environment['COLLECT_VISUAL_MOBILE_VIEWPORT']?.trim();
  if (value == null || value.isEmpty) {
    return const Size(390, 844);
  }
  final match = RegExp(r'^(\d+)x(\d+)$').firstMatch(value);
  if (match == null) {
    throw StateError(
      'COLLECT_VISUAL_MOBILE_VIEWPORT must use WIDTHxHEIGHT, got "$value".',
    );
  }
  return Size(double.parse(match.group(1)!), double.parse(match.group(2)!));
}

double _mobileTextScaleFromEnv() {
  final value = Platform.environment['COLLECT_VISUAL_TEXT_SCALE']?.trim();
  if (value == null || value.isEmpty) return 1;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed < 0.8 || parsed > 2.5) {
    throw StateError(
      'COLLECT_VISUAL_TEXT_SCALE must be a number from 0.8 to 2.5, got "$value".',
    );
  }
  return parsed;
}

double _visualDevicePixelRatioFromEnv() {
  final value = Platform.environment['COLLECT_VISUAL_DEVICE_PIXEL_RATIO']
      ?.trim();
  if (value == null || value.isEmpty) return 1;
  final parsed = double.tryParse(value);
  if (parsed == null || parsed <= 0 || parsed > 4) {
    throw StateError(
      'COLLECT_VISUAL_DEVICE_PIXEL_RATIO must be a number from 0.1 to 4, got "$value".',
    );
  }
  return parsed;
}

Widget _adminAppAt(String initialLocation) {
  final router = createAdminRouterForEvidence(initialLocation);
  return ProviderScope(
    overrides: [
      adminAuthGuardProvider.overrideWithValue(
        const AdminAuthGuard(isAuthorized: true),
      ),
      adminIdentityProvider.overrideWith((ref) async => _evidenceAdmin),
      adminRepositoryProvider.overrideWithValue(_EvidenceAdminRepository()),
      adminRouterProvider.overrideWithValue(router),
    ],
    child: const CollectAdminApp(),
  );
}

const _adminEvidenceRoutes = <_AdminEvidenceRoute>[
  _AdminEvidenceRoute('login', '/admin/login'),
  _AdminEvidenceRoute('denied', '/admin/denied'),
  _AdminEvidenceRoute('overview', '/admin'),
  _AdminEvidenceRoute('groups', '/admin/groups'),
  _AdminEvidenceRoute('group-detail', '/admin/groups/group-1'),
  _AdminEvidenceRoute('members', '/admin/members'),
  _AdminEvidenceRoute('member-detail', '/admin/members/member-1'),
  _AdminEvidenceRoute('payment-intents', '/admin/payment-intents'),
  _AdminEvidenceRoute(
    'payment-intent-detail',
    '/admin/payment-intents/intent-1',
  ),
  _AdminEvidenceRoute('payment-events', '/admin/payment-events'),
  _AdminEvidenceRoute('payment-event-detail', '/admin/payment-events/event-1'),
  _AdminEvidenceRoute('allocations', '/admin/allocations'),
  _AdminEvidenceRoute('exceptions', '/admin/exceptions'),
  _AdminEvidenceRoute('ledger', '/admin/ledger'),
  _AdminEvidenceRoute('receivers', '/admin/receivers'),
  _AdminEvidenceRoute('receiver-detail', '/admin/receivers/receiver-1'),
  _AdminEvidenceRoute('sms', '/admin/sms'),
  _AdminEvidenceRoute('sms-detail', '/admin/sms/sms-1'),
  _AdminEvidenceRoute('audit-logs', '/admin/audit-logs'),
  _AdminEvidenceRoute('settings', '/admin/settings'),
  _AdminEvidenceRoute('feature-flags', '/admin/feature-flags'),
  _AdminEvidenceRoute('system-health', '/admin/system-health'),
  _AdminEvidenceRoute('admin-users', '/admin/admin-users'),
];

class _AdminEvidenceRoute {
  const _AdminEvidenceRoute(this.name, this.path);

  final String name;
  final String path;
}

GoRouter createAdminRouterForEvidence(String initialLocation) {
  return GoRouter(
    initialLocation: initialLocation,
    redirect: (context, state) {
      if (state.uri.path == '/') return '/admin';
      return null;
    },
    routes: [
      GoRoute(
        path: '/admin/login',
        builder: (context, state) => const AdminLoginPage(),
      ),
      GoRoute(
        path: '/admin/denied',
        builder: (context, state) => const AdminDeniedPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminOverviewContent(),
          ),
          _adminEvidenceListRoute(
            '/admin/groups',
            title: 'Groups',
            rpcName: 'admin_list_collections',
            detailPathPrefix: '/admin/groups',
          ),
          _adminEvidenceDetailRoute(
            '/admin/groups/:id',
            title: 'Group detail',
            rpcName: 'admin_get_collection',
          ),
          _adminEvidenceListRoute(
            '/admin/members',
            title: 'Members',
            rpcName: 'admin_list_users',
            detailPathPrefix: '/admin/members',
          ),
          _adminEvidenceDetailRoute(
            '/admin/members/:id',
            title: 'Member detail',
            rpcName: 'admin_get_user',
          ),
          _adminEvidenceListRoute(
            '/admin/payment-intents',
            title: 'Payment intents',
            rpcName: 'admin_list_payments',
            detailPathPrefix: '/admin/payment-intents',
          ),
          _adminEvidenceDetailRoute(
            '/admin/payment-intents/:id',
            title: 'Payment intent detail',
            rpcName: 'admin_get_payment',
          ),
          GoRoute(
            path: '/admin/payment-events',
            builder: (context, state) => const AdminRpcListPage(
              title: 'SMS parsing',
              rpcName: 'admin_list_payment_events',
              detailPathPrefix: '/admin/payment-events',
              actionKind: 'payment_event_reparse',
            ),
          ),
          _adminEvidenceDetailRoute(
            '/admin/payment-events/:id',
            title: 'Payment event detail',
            rpcName: 'admin_get_payment_event',
          ),
          _adminEvidenceListRoute(
            '/admin/allocations',
            title: 'Allocations',
            rpcName: 'admin_list_allocations',
            detailPathPrefix: '/admin/payment-events',
          ),
          _adminEvidenceListRoute(
            '/admin/exceptions',
            title: 'Exceptions',
            rpcName: 'admin_list_unallocated',
            detailPathPrefix: '/admin/payment-events',
            actionKind: 'payment_event_reparse',
          ),
          _adminEvidenceListRoute(
            '/admin/ledger',
            title: 'Ledger',
            rpcName: 'admin_list_ledger',
          ),
          _adminEvidenceListRoute(
            '/admin/receivers',
            title: 'Receivers',
            rpcName: 'admin_list_receivers',
            detailPathPrefix: '/admin/receivers',
          ),
          _adminEvidenceDetailRoute(
            '/admin/receivers/:id',
            title: 'Receiver detail',
            rpcName: 'admin_get_receiver',
          ),
          _adminEvidenceListRoute(
            '/admin/sms',
            title: 'SMS metadata',
            rpcName: 'admin_list_sms_metadata',
            detailPathPrefix: '/admin/sms',
          ),
          GoRoute(
            path: '/admin/sms/:id',
            builder: (context, state) =>
                AdminSmsDetailPage(id: state.pathParameters['id']!),
          ),
          _adminEvidenceListRoute(
            '/admin/audit-logs',
            title: 'Audit logs',
            rpcName: 'admin_list_audit_logs',
          ),
          _adminEvidenceListRoute(
            '/admin/settings',
            title: 'Settings',
            rpcName: 'admin_list_settings',
          ),
          _adminEvidenceListRoute(
            '/admin/feature-flags',
            title: 'Feature flags',
            rpcName: 'admin_list_feature_flags',
          ),
          GoRoute(
            path: '/admin/system-health',
            builder: (context, state) => const AdminDetailPage(
              title: 'System health',
              rpcName: 'admin_system_health',
              id: 'system',
            ),
          ),
          _adminEvidenceListRoute(
            '/admin/admin-users',
            title: 'Admin users',
            rpcName: 'admin_list_admin_users',
          ),
        ],
      ),
    ],
  );
}

GoRoute _adminEvidenceListRoute(
  String path, {
  required String title,
  required String rpcName,
  String? detailPathPrefix,
  String? actionKind,
}) {
  return GoRoute(
    path: path,
    builder: (context, state) => AdminRpcListPage(
      title: title,
      rpcName: rpcName,
      detailPathPrefix: detailPathPrefix,
      actionKind: actionKind,
    ),
  );
}

GoRoute _adminEvidenceDetailRoute(
  String path, {
  required String title,
  required String rpcName,
}) {
  return GoRoute(
    path: path,
    builder: (context, state) => AdminDetailPage(
      title: title,
      rpcName: rpcName,
      id: state.pathParameters['id']!,
    ),
  );
}

Widget _mobileRouteScreen(String route) {
  const collectionId = 'col-church';
  return switch (route) {
    '/' => const HomeScreen(),
    '/auth' => const AuthScreen(),
    '/home' => const HomeScreen(),
    '/offline' => const OfflineStateScreen(),
    '/sync' => const SyncStatusScreen(),
    '/groups' => const CollectionsScreen(),
    '/groups/scan' => const GroupQrScannerScreen(),
    '/groups/create' => const CollectionCreateScreen(),
    '/groups/$collectionId' => const CollectionDetailScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/members' => const GroupMembersScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/manage' => const CollectionManageScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/profile' => const GroupProfileScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/contribute' => const ContributionFlowScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/share' => const ShareScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/invite' => const ShareScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/ledger' => const LedgerScreen(
      collectionId: collectionId,
    ),
    '/c/st-michel-building-fund' => const GroupLinkScreen(
      slug: 'st-michel-building-fund',
    ),
    '/share/invalid' => const SharedLinkProblemScreen(expired: false),
    '/share/expired' => const SharedLinkProblemScreen(expired: true),
    '/share/expired/request' => const FreshLinkRequestScreen(slug: ''),
    '/settings' => const SettingsScreen(),
    '/settings/profile' => const ProfileSetupScreen(),
    '/settings/account' => const AccountSessionScreen(),
    '/settings/account/delete' => const DeleteAccountRequestScreen(),
    '/settings/privacy' => const PrivacyDataScreen(),
    '/settings/help' => const HelpSupportScreen(),
    '/settings/legal/terms' => const LegalScreen(kind: 'terms'),
    '/settings/legal/privacy' => const LegalScreen(kind: 'privacy'),
    '/app' => const HomeScreen(),
    '/invite/038491' => const HomeScreen(),
    _ => throw StateError('No visual evidence widget for $route'),
  };
}

Future<void> _pumpForEvidence(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 750));
}

Future<_PngCapture> _capturePng(
  GlobalKey key, {
  required double pixelRatio,
}) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final rawData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final metrics = _imageMetrics(rawData!, image.width, image.height);
  image.dispose();
  return _PngCapture(
    bytes: byteData!.buffer.asUint8List(),
    width: metrics.width,
    height: metrics.height,
    sampledPixels: metrics.sampledPixels,
    distinctRgb: metrics.distinctRgb,
    nonBackgroundPixels: metrics.nonBackgroundPixels,
  );
}

_ImageMetrics _imageMetrics(ByteData data, int width, int height) {
  final colors = <int>{};
  var sampled = 0;
  var nonBackground = 0;
  final stride = (width * height / 24000).ceil().clamp(1, 32).toInt();
  final firstR = data.getUint8(0);
  final firstG = data.getUint8(1);
  final firstB = data.getUint8(2);
  for (var pixel = 0; pixel < width * height; pixel += stride) {
    final offset = pixel * 4;
    final r = data.getUint8(offset);
    final g = data.getUint8(offset + 1);
    final b = data.getUint8(offset + 2);
    final a = data.getUint8(offset + 3);
    sampled += 1;
    colors.add((r << 16) | (g << 8) | b);
    if (a != 0 && (r != firstR || g != firstG || b != firstB)) {
      nonBackground += 1;
    }
  }
  return _ImageMetrics(
    width: width,
    height: height,
    sampledPixels: sampled,
    distinctRgb: colors.length,
    nonBackgroundPixels: nonBackground,
  );
}

class _PngCapture {
  const _PngCapture({
    required this.bytes,
    required this.width,
    required this.height,
    required this.sampledPixels,
    required this.distinctRgb,
    required this.nonBackgroundPixels,
  });

  final List<int> bytes;
  final int width;
  final int height;
  final int sampledPixels;
  final int distinctRgb;
  final int nonBackgroundPixels;
}

class _ImageMetrics {
  const _ImageMetrics({
    required this.width,
    required this.height,
    required this.sampledPixels,
    required this.distinctRgb,
    required this.nonBackgroundPixels,
  });

  final int width;
  final int height;
  final int sampledPixels;
  final int distinctRgb;
  final int nonBackgroundPixels;
}

void _writeJson(File file, Map<String, Object?> data) {
  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  file.writeAsStringSync('\n', mode: FileMode.append);
}

List<_RouteSpec> _mobileRouteSpecs() {
  final script = File(
    'scripts/mobile_route_render_smoke.sh',
  ).readAsStringSync();
  final start = script.indexOf('route_specs=(');
  final end = script.indexOf('\n)\n\ncaptures_json=', start);
  if (start < 0 || end < 0) {
    throw StateError(
      'Unable to find route_specs in mobile route smoke script.',
    );
  }
  final routeSpecs = script.substring(start, end);
  final specs =
      RegExp(r'^\s*"([^"|]+)\|([^"|]+)(?:\|([^"]+))?"', multiLine: true)
          .allMatches(routeSpecs)
          .map(
            (match) => _RouteSpec(
              match.group(1)!,
              match.group(2)!,
              match.group(3) ?? 'workflow',
            ),
          )
          .toList(growable: false);
  if (specs.isEmpty) {
    throw StateError('No route specs found in mobile route smoke script.');
  }
  final limit = int.tryParse(
    Platform.environment['COLLECT_VISUAL_EVIDENCE_ROUTE_LIMIT'] ?? '',
  );
  if (limit != null && limit > 0 && limit < specs.length) {
    return specs.take(limit).toList(growable: false);
  }
  final selected = Platform.environment['COLLECT_VISUAL_EVIDENCE_ROUTES']
      ?.split(',')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toSet();
  if (selected != null && selected.isNotEmpty) {
    final selectedSpecs = specs
        .where((spec) => selected.contains(spec.name))
        .toList(growable: false);
    if (selectedSpecs.length != selected.length) {
      final found = selectedSpecs.map((spec) => spec.name).toSet();
      final missing = selected.difference(found).join(', ');
      throw StateError('Unknown visual evidence route name(s): $missing');
    }
    return selectedSpecs;
  }
  return specs;
}

class _RouteSpec {
  const _RouteSpec(this.name, this.route, this.routeClass);

  final String name;
  final String route;
  final String routeClass;

  bool get isProductScreen => routeClass != 'compatibility';
}

const _evidenceAdmin = AdminIdentity(
  userId: '00000000-0000-0000-0000-00000000e001',
  displayName: 'Collect evidence admin',
  roles: ['platform_owner'],
  permissions: [
    'overview.read',
    'public_requests.read',
    'collections.read',
    'users.read',
    'receivers.read',
    'sms.metadata.read',
    'sms.raw.reveal',
    'payment_events.read',
    'payment_events.reparse',
    'payments.read',
    'payments.allocate',
    'ledger.read',
    'audit.read',
    'feature_flags.read',
    'settings.read',
    'system_health.read',
    'admin_users.read',
  ],
);

class _EvidenceAdminRepository extends AdminRepositoryBase {
  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    if (rpcName == 'admin_reveal_raw_sms') {
      return {'message': 'Raw message hidden in visual evidence.'};
    }
    return {'status': 'queued'};
  }

  @override
  Future<AdminIdentity?> currentIdentity() async => _evidenceAdmin;

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    return {
      'id': id,
      'transaction_id': 'MOMO-EVIDENCE-001',
      'amount': 'RWF 24,500',
      'sender_masked': '+250***4321',
      'receiver_masked': '+250***1222',
      'payment_intent_id': 'intent-evidence',
      'status': 'needs_review',
      'created_at': '2026-06-15T12:00:00Z',
    };
  }

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
  }) async {
    return AdminListResult(
      total: 6,
      rows: [
        for (var index = 1; index <= 6; index += 1)
          AdminTableRowData(
            id: 'event-$index',
            title: 'Parsed MoMo event $index',
            subtitle: 'Masked sender and allocation review',
            status: index.isEven ? 'allocated' : 'needs_review',
            amount: 'RWF ${index * 2500}',
          ),
      ],
    );
  }

  @override
  Future<List<AdminMetric>> overviewMetrics() async => const [
    AdminMetric(label: 'Review queue', value: '6', status: 'needs_review'),
    AdminMetric(label: 'Allocated today', value: '42', status: 'allocated'),
    AdminMetric(label: 'Parser health', value: '99%', status: 'active'),
  ];

  @override
  Future<void> sendOtp({required String phone}) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<AdminIdentity?> verifyOtp({
    required String phone,
    required String otp,
  }) async => _evidenceAdmin;
}
