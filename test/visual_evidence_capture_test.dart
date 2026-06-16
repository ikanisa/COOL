import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
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
import 'package:collect_app/features/payments/payment_intent_status_screen.dart';
import 'package:collect_app/features/profile/profile_setup_screen.dart';
import 'package:collect_app/features/settings/settings_screen.dart';
import 'package:collect_app/features/status/production_state_screens.dart';
import 'package:collect_app/shared/providers/collect_app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  final evidenceRoot = Platform.environment['COLLECT_VISUAL_EVIDENCE_DIR'];
  final visualThemeMode = _visualThemeModeFromEnv(
    Platform.environment['COLLECT_VISUAL_THEME_MODE'],
  );
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

  final mobileSpecs = _mobileRouteSpecs();
  final mobileCaptures = <Map<String, Object?>>[];
  group('mobile visual evidence', () {
    for (final spec in mobileSpecs) {
      testWidgets('captures ${spec.name}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
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
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                title: 'Collect',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: visualThemeMode,
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
        final fileName = '$name-390x844.png';
        final bytes = (await tester.runAsync(() => _capturePng(key)))!;
        final file = File('${mobileDir.path}/$fileName');
        file.writeAsBytesSync(bytes);
        debugPrint('[visual-evidence] wrote ${file.path}');
        expect(bytes.length, greaterThan(8000));
        mobileCaptures.add({
          'status': 'pass',
          'name': name,
          'route': route,
          'path': fileName,
          'width': 390,
          'height': 844,
          'bytes': bytes.length,
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
        'viewport': '390x844',
        'expected_route_count': mobileSpecs.length,
        'route_count': mobileCaptures.length,
        'routes': [for (final capture in mobileCaptures) capture['route']],
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
        final fileName =
            '$name-${viewport.width.toInt()}x${viewport.height.toInt()}.png';
        final bytes = (await tester.runAsync(() => _capturePng(key)))!;
        File('${adminDir.path}/$fileName').writeAsBytesSync(bytes);
        captures.add({
          'status': 'pass',
          'name': name,
          'path': fileName,
          'width': viewport.width.toInt(),
          'height': viewport.height.toInt(),
          'bytes': bytes.length,
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await captureAdmin(
        name: 'admin-login-mobile',
        viewport: const Size(390, 844),
        child: const ProviderScope(child: CollectAdminApp()),
      );
      await captureAdmin(
        name: 'admin-login-desktop',
        viewport: const Size(1440, 900),
        child: const ProviderScope(child: CollectAdminApp()),
      );
      await captureAdmin(
        name: 'admin-overview-desktop',
        viewport: const Size(1440, 900),
        child: _adminAppAt('/admin'),
      );
      await captureAdmin(
        name: 'admin-payment-events-mobile',
        viewport: const Size(390, 844),
        child: _adminAppAt('/admin/payment-events'),
      );
      await captureAdmin(
        name: 'admin-sms-detail-desktop',
        viewport: const Size(1440, 900),
        child: _adminAppAt('/admin/sms/sms-1'),
      );

      _writeJson(File('${adminDir.path}/summary.json'), {
        'status': 'pass',
        'capture_runtime': 'flutter_test_repaint_boundary',
        'theme_mode': visualThemeMode.name,
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
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

ThemeMode _visualThemeModeFromEnv(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    _ => ThemeMode.dark,
  };
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
          GoRoute(
            path: '/admin/payment-events',
            builder: (context, state) => const AdminRpcListPage(
              title: 'SMS parsing',
              rpcName: 'admin_list_payment_events',
              detailPathPrefix: '/admin/payment-events',
              actionKind: 'payment_event_reparse',
            ),
          ),
          GoRoute(
            path: '/admin/sms/:id',
            builder: (context, state) =>
                AdminSmsDetailPage(id: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
}

Widget _mobileRouteScreen(String route) {
  const collectionId = 'col-church';
  const intentId = 'intent-render';
  return switch (route) {
    '/onboarding' => const OnboardingScreen(),
    '/onboarding/legal' => const LegalConsentScreen(),
    '/auth' => const AuthScreen(),
    '/auth/success' => const AuthResultScreen(success: true),
    '/auth/failure' => const AuthResultScreen(success: false),
    '/home' => const HomeScreen(),
    '/offline' => const OfflineStateScreen(),
    '/sync' => const SyncStatusScreen(),
    '/notifications' => const NotificationCenterScreen(),
    '/permissions/sms-denied' => const SmsPermissionDeniedScreen(),
    '/permissions/device' => const NotificationPermissionScreen(),
    '/permissions/notifications-denied' => const PermissionRecoveryScreen(
      kind: 'notifications',
    ),
    '/permissions/camera-denied' => const PermissionRecoveryScreen(
      kind: 'camera',
    ),
    '/platform/iphone-create-unavailable' =>
      const IphoneCreateUnavailableScreen(),
    '/groups' => const CollectionsScreen(),
    '/groups/join' => const JoinGroupPortalScreen(),
    '/groups/scan' => const GroupQrScannerScreen(),
    '/groups/create' => const CollectionCreateScreen(),
    '/groups/$collectionId' => const CollectionDetailScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/created' => const GroupCreatedSuccessScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/joined' => const JoinGroupConfirmationScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/members' => const GroupMembersScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/owner' => const CollectionManageScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/owner/sms-health' =>
      const NotificationPermissionScreen(),
    '/groups/$collectionId/owner/receiver' => const GroupProfileScreen(
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
    '/groups/$collectionId/pay/$intentId/handoff' =>
      const ReturnFromMomoWaitingScreen(
        collectionId: collectionId,
        intentId: intentId,
      ),
    '/groups/$collectionId/pay/$intentId/waiting' =>
      const ReturnFromMomoWaitingScreen(
        collectionId: collectionId,
        intentId: intentId,
      ),
    '/groups/$collectionId/pay/$intentId/state/pending' =>
      const PaymentStateDetailScreen(
        collectionId: collectionId,
        intentId: intentId,
        state: PaymentUiStatus.pending,
      ),
    '/groups/$collectionId/pay/$intentId/state/confirmed' =>
      const PaymentStateDetailScreen(
        collectionId: collectionId,
        intentId: intentId,
        state: PaymentUiStatus.confirmed,
      ),
    '/groups/$collectionId/pay/$intentId/state/expired' =>
      const PaymentStateDetailScreen(
        collectionId: collectionId,
        intentId: intentId,
        state: PaymentUiStatus.expired,
      ),
    '/groups/$collectionId/pay/$intentId/state/needs-review' =>
      const PaymentStateDetailScreen(
        collectionId: collectionId,
        intentId: intentId,
        state: PaymentUiStatus.needsReview,
      ),
    '/groups/$collectionId/pay/$intentId' => const PaymentIntentStatusScreen(
      collectionId: collectionId,
      intentId: intentId,
    ),
    '/groups/$collectionId/support/payment/$intentId' =>
      const PaymentSupportReviewScreen(
        collectionId: collectionId,
        intentId: intentId,
      ),
    '/groups/$collectionId/share' => const ShareScreen(
      collectionId: collectionId,
    ),
    '/groups/$collectionId/invite' => const CollectionDetailScreen(
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
    '/settings/readiness' => const ProfileReadinessScreen(),
    '/settings/account' => const AccountSessionScreen(),
    '/settings/account/delete' => const DeleteAccountRequestScreen(),
    '/settings/privacy' => const PrivacyDataScreen(),
    '/settings/help' => const HelpSupportScreen(),
    '/settings/legal/terms' => const LegalScreen(kind: 'terms'),
    '/settings/legal/privacy' => const LegalScreen(kind: 'privacy'),
    '/share/confirmed' => const HomeScreen(),
    _ => throw StateError('No visual evidence widget for $route'),
  };
}

Future<void> _pumpForEvidence(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 750));
}

Future<List<int>> _capturePng(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return byteData!.buffer.asUint8List();
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
  final specs = RegExp(r'^\s*"([^"|]+)\|(/[^"]+)"', multiLine: true)
      .allMatches(routeSpecs)
      .map((match) => _RouteSpec(match.group(1)!, match.group(2)!))
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
  return specs;
}

class _RouteSpec {
  const _RouteSpec(this.name, this.route);

  final String name;
  final String route;
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
