import 'dart:io';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_motion.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots with Collect home shell', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const ProviderScope(child: CollectApp()));
      await tester.pump();

      expect(find.byType(CollectBrandMark), findsOneWidget);
      expect(find.text('038491'), findsOneWidget);
      expect(find.text('TOTAL COLLECTED'), findsOneWidget);
      expect(find.text('Public groups'), findsOneWidget);
      expect(find.text('CONFIRMED'), findsNothing);
      expect(find.text('PENDING'), findsNothing);
      expect(find.text('FAILED'), findsNothing);
      expect(find.text('Platform admin'), findsNothing);
      expect(find.textContaining('BioPay'), findsNothing);
      expect(find.textContaining('wallet'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('unknown routes render branded recovery actions', (tester) async {
    final semantics = tester.ensureSemantics();
    final router = createAppRouter(initialLocation: '/missing-route');
    addTearDown(router.dispose);

    try {
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      );
      await tester.pump();

      expect(find.text('Screen not found'), findsOneWidget);
      expect(find.byType(CollectBrandMark), findsOneWidget);
      expect(find.text('This screen is unavailable.'), findsOneWidget);
      expect(find.textContaining('verified groups'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  test('main Collect routes are registered', () {
    expect(
      collectRoutePaths,
      containsAll(<String>[
        '/auth',
        '/auth/success',
        '/auth/failure',
        '/onboarding',
        '/onboarding/legal',
        '/home',
        '/offline',
        '/sync',
        '/permissions/sms',
        '/permissions/sms-denied',
        '/permissions/device',
        '/permissions/notifications-denied',
        '/permissions/camera-denied',
        '/platform/iphone-create-unavailable',
        '/groups',
        '/groups/join',
        '/groups/create',
        '/groups/:collectionId',
        '/groups/:collectionId/created',
        '/groups/:collectionId/joined',
        '/groups/:collectionId/members',
        '/groups/:collectionId/manage',
        '/groups/:collectionId/profile',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId/waiting',
        '/groups/:collectionId/pay/:intentId/state/:state',
        '/groups/:collectionId/pay/:intentId',
        '/groups/:collectionId/support/payment/:intentId',
        '/groups/:collectionId/share',
        '/groups/:collectionId/ledger',
        '/c/:slug',
        '/share/invalid',
        '/share/expired',
        '/share/expired/request',
        '/settings',
        '/settings/profile',
        '/settings/readiness',
        '/settings/account',
        '/settings/account/delete',
        '/settings/privacy',
        '/settings/help',
        '/settings/legal/terms',
        '/settings/legal/privacy',
        if (kDebugMode) '/dev/design-system',
      ]),
    );

    final router = createAppRouter();
    addTearDown(router.dispose);
    expect(router.configuration.routes, isNotEmpty);
  });

  test(
    'mobile route screenshot smoke covers every production screen route',
    () {
      final script = File(
        'scripts/mobile_route_render_smoke.sh',
      ).readAsStringSync();
      final smokeRoutes = RegExp(
        r'"[^"|]+\|([^"]+)"',
      ).allMatches(script).map((match) => match.group(1)!).toSet();
      final productionScreenRoutes = collectRoutePaths
          .where((route) => route != '/dev/design-system')
          .map(_materializeRouteForSmoke)
          .toSet();

      expect(smokeRoutes, containsAll(productionScreenRoutes));
    },
  );

  test('repo-wide QA includes the mobile design compliance gate', () {
    final qaRunner = File('scripts/repo_wide_qa_uat.sh').readAsStringSync();
    final designAudit = File(
      'scripts/collect_mobile_design_compliance_audit.sh',
    ).readAsStringSync();

    expect(qaRunner, contains('collect_mobile_design_compliance_audit'));
    expect(qaRunner, contains('mobile_design_compliance'));
    expect(designAudit, contains('four_primary_color_contract'));
    expect(designAudit, contains('revolut_reference_collect_owned_contract'));
    expect(designAudit, contains('gradient_glass_screen_contract'));
    expect(designAudit, contains('mobile_brand_asset_contract'));
    expect(designAudit, contains('no_raw_ui_colors_outside_tokens'));
    expect(designAudit, contains('share_domain_contract'));
    expect(designAudit, contains('all_production_routes_rendered'));
    expect(designAudit, contains('android_device_uat_evidence'));
  });

  test('design system catalog route is debug-only', () {
    expect(kDebugMode, isTrue);
    expect(collectRoutePaths, contains('/dev/design-system'));
  });

  test('theme loads', () {
    expect(AppTheme.light(), isA<ThemeData>());
  });

  testWidgets('reduced motion returns zero animation duration', (tester) async {
    late Duration duration;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = CollectMotion.duration(context, CollectMotion.medium);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(duration, Duration.zero);
  });

  test('environment defaults keep Android SMS access disabled', () {
    final env = AppEnv.fromEnvironment();

    expect(env.enableSmsReader, isFalse);
    expect(env.enableAndroidSmsAccess, isFalse);
    expect(env.enableAdminPanel, isFalse);
    expect(env.enableAdminDevTools, isFalse);
  });
}

String _materializeRouteForSmoke(String route) {
  return route
      .replaceAll(':collectionId', 'col-church')
      .replaceAll(':intentId', 'intent-render')
      .replaceAll(':state', 'pending')
      .replaceAll(':slug', 'st-michel-building-fund');
}
