import 'dart:io';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_motion.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app opens with Collect launch splash', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const ProviderScope(child: CollectApp()));
      await tester.pump();

      expect(find.text('Collect'), findsOneWidget);
      expect(find.text('Groups. MoMo. Done.'), findsOneWidget);
      expect(find.byTooltip('Open profile'), findsNothing);
      expect(find.text('TOTAL COLLECTED'), findsNothing);
      expect(find.text('Home'), findsNothing);
      expect(find.text('Settings'), findsNothing);
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

  testWidgets('app boots with persisted dark-first theme mode', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CollectApp()));
    await tester.pump();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
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
      expect(find.byTooltip('Back'), findsOneWidget);
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
        '/',
        '/auth',
        '/auth/success',
        '/auth/failure',
        '/onboarding',
        '/onboarding/legal',
        '/home',
        '/offline',
        '/sync',
        '/notifications',
        '/permissions/sms',
        '/permissions/sms-denied',
        '/permissions/device',
        '/permissions/notifications-denied',
        '/permissions/camera-denied',
        '/platform/iphone-create-unavailable',
        '/groups',
        '/groups/join',
        '/groups/scan',
        '/groups/create',
        '/groups/:collectionId',
        '/groups/:collectionId/created',
        '/groups/:collectionId/joined',
        '/groups/:collectionId/members',
        '/groups/:collectionId/owner',
        '/groups/:collectionId/owner/sms-health',
        '/groups/:collectionId/owner/receiver',
        '/groups/:collectionId/manage',
        '/groups/:collectionId/profile',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId/handoff',
        '/groups/:collectionId/pay/:intentId/waiting',
        '/groups/:collectionId/pay/:intentId/state/:state',
        '/groups/:collectionId/pay/:intentId',
        '/groups/:collectionId/support/payment/:intentId',
        '/groups/:collectionId/share',
        '/groups/:collectionId/invite',
        '/groups/:collectionId/ledger',
        '/c/:slug',
        '/share/invalid',
        '/share/expired',
        '/share/expired/request',
        '/app',
        '/invite/:publicId',
        '/settings',
        '/settings/profile',
        '/settings/readiness',
        '/settings/account',
        '/settings/account/delete',
        '/settings/privacy',
        '/settings/help',
        '/settings/legal/terms',
        '/settings/legal/privacy',
        '/share/confirmed',
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

  test(
    'physical-device route matrix covers mobile screenshot smoke routes',
    () {
      final smokeScript = File(
        'scripts/mobile_route_render_smoke.sh',
      ).readAsStringSync();
      final deviceTest = File(
        'integration_test/mobile_route_matrix_device_uat_test.dart',
      ).readAsStringSync();
      final smokeRouteBlock = smokeScript.substring(
        smokeScript.indexOf('route_specs=('),
        smokeScript.indexOf('\n)\n\ncaptures_json='),
      );
      final smokeRoutes = RegExp(
        r'^\s*"[^"|]+\|([^"]+)"',
        multiLine: true,
      ).allMatches(smokeRouteBlock).map((match) => match.group(1)!).toSet();
      final deviceRoutes = RegExp(
        r"_RouteSpec\(\s*'[^']+',\s*'([^']+)'\s*,?\s*\)",
        multiLine: true,
      ).allMatches(deviceTest).map((match) => match.group(1)!).toSet();

      expect(deviceRoutes, containsAll(smokeRoutes));
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
    expect(designAudit, contains('theme_mode_visual_parity_gate'));
    expect(designAudit, contains('revolut_top_chrome_search_contract'));
    expect(designAudit, contains('mobile_brand_asset_contract'));
    expect(designAudit, contains('no_raw_ui_colors_outside_tokens'));
    expect(designAudit, contains('share_domain_contract'));
    expect(designAudit, contains('all_production_routes_rendered'));
    expect(designAudit, contains('android_device_uat_evidence'));
  });

  test('design compliance audit reads refactored chrome part files', () {
    final designAudit = File(
      'scripts/collect_mobile_design_compliance_audit.sh',
    ).readAsStringSync();
    final chromeLibrary = File(
      'lib/shared/widgets/collect_chrome.dart',
    ).readAsStringSync();
    final topChromePart = File(
      'lib/shared/widgets/collect_top_chrome.dart',
    ).readAsStringSync();
    final scaffoldPart = File(
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ).readAsStringSync();

    expect(chromeLibrary, contains("part 'collect_top_chrome.dart';"));
    expect(chromeLibrary, contains("part 'collect_scaffold_chrome.dart';"));
    expect(topChromePart, contains('class CollectBrandMark'));
    expect(topChromePart, contains('collect_wordmark_transparent.png'));
    expect(scaffoldPart, contains('class PremiumScaffold'));
    expect(scaffoldPart, contains('CollectGradientBackground'));
    expect(designAudit, contains('def read_dart_library'));
    expect(
      designAudit,
      contains(
        'chrome = read_dart_library(root, "lib/shared/widgets/collect_chrome.dart")',
      ),
    );
  });

  test('design system catalog route is debug-only', () {
    expect(kDebugMode, isTrue);
    expect(collectRoutePaths, contains('/dev/design-system'));
  });

  test('theme loads', () {
    expect(AppTheme.light(), isA<ThemeData>());
    expect(AppTheme.dark(), isA<ThemeData>());
    expect(AppTheme.dark().brightness, Brightness.dark);
  });

  test('member and admin apps use persisted Collect theme mode', () {
    final memberApp = File('lib/app/app.dart').readAsStringSync();
    final adminApp = File('lib/admin/admin_app.dart').readAsStringSync();

    expect(memberApp, contains('collectThemeModeProvider'));
    expect(adminApp, contains('collectThemeModeProvider'));
    expect(memberApp, isNot(contains('themeMode: ThemeMode.system')));
    expect(adminApp, isNot(contains('themeMode: ThemeMode.system')));
  });

  test(
    'mobile route smoke uses sanitized fixture evidence mode only by flag',
    () {
      final main = File('lib/main.dart').readAsStringSync();
      final smokeScript = File(
        'scripts/mobile_route_render_smoke.sh',
      ).readAsStringSync();

      expect(main, contains('COLLECT_MOBILE_EVIDENCE_MODE'));
      expect(main, contains('CollectRepository.fixture()'));
      expect(
        smokeScript,
        contains('--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true'),
      );
    },
  );

  test('home and groups keep Revolut-style searchable top chrome', () {
    final home = [
      'lib/features/home/home_screen.dart',
      'lib/features/home/home_action_strip.dart',
      'lib/features/home/home_public_groups_section.dart',
      'lib/features/home/home_total_collected_card.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    final groups = File(
      'lib/features/collections/collections_screen.dart',
    ).readAsStringSync();
    final groupDetail = File(
      'lib/features/collections/collection_detail_screen.dart',
    ).readAsStringSync();
    final sharedBarrel = File(
      'lib/shared/widgets/collect_components.dart',
    ).readAsStringSync();
    final chromeModule = [
      'lib/shared/widgets/collect_chrome.dart',
      'lib/shared/widgets/collect_top_chrome.dart',
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(home, contains('CollectTopChrome('));
    expect(home, contains("searchLabel: 'Search'"));
    expect(home, contains("onSearchTap: () => context.go('/groups/search')"));
    expect(home, contains("tooltip: 'Notifications'"));
    expect(home, contains("tooltip: 'Scan QR code'"));
    expect(home, contains("label: 'Join'"));
    expect(home, contains("onTap: () => context.go('/groups/join'),"));
    expect(home, contains("label: 'Scan QR'"));
    expect(home, contains("onTap: () => context.go('/groups/scan'),"));
    expect(groups, contains('CollectTopChrome('));
    expect(groups, contains('persistentPill: groupsTopChrome'));
    expect(groups, contains("'Search groups'"));
    expect(groups, contains("tooltip: 'Scan QR code'"));
    expect(groups, contains("tooltip: 'Create group'"));
    expect(groupDetail, isNot(contains('CollectTopChrome')));
    expect(groupDetail, isNot(contains('persistentPill')));
    expect(sharedBarrel, contains("export 'collect_chrome.dart';"));
    expect(sharedBarrel, isNot(contains('class CollectTopChrome')));
    expect(chromeModule, contains('class CollectTopChrome'));
    expect(chromeModule, contains('class ScreenHeader'));
  });

  test('group card media primitives stay out of the base component barrel', () {
    final sharedBarrel = File(
      'lib/shared/widgets/collect_components.dart',
    ).readAsStringSync();
    final groupCards = [
      'lib/shared/widgets/collect_group_cards.dart',
      'lib/shared/widgets/collect_group_card_media.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');
    final home = File('lib/features/home/home_screen.dart').readAsStringSync();
    final groups = File(
      'lib/features/collections/collections_screen.dart',
    ).readAsStringSync();

    expect(sharedBarrel, isNot(contains('class GroupCard')));
    expect(sharedBarrel, isNot(contains('_GroupCoverMedia')));
    expect(groupCards, contains('class GroupCard'));
    expect(groupCards, contains('_GroupCoverMedia'));
    expect(home, contains('widgets/collect_group_cards.dart'));
    expect(groups, contains('widgets/collect_group_cards.dart'));
  });

  test(
    'review-note cleanup removes verbose permission and group filter UI',
    () {
      final groups = File(
        'lib/features/collections/collections_screen.dart',
      ).readAsStringSync();
      final profile = File(
        'lib/features/profile/profile_setup_screen.dart',
      ).readAsStringSync();
      final statusScreens = File(
        'lib/features/status/production_state_screens.dart',
      ).readAsStringSync();
      final devicePrivacyScreens = [
        'lib/features/status/device_privacy_screens.dart',
        'lib/features/status/device_permission_screens.dart',
        'lib/features/status/device_privacy_data_screen.dart',
        'lib/features/status/device_notification_center.dart',
        'lib/features/status/device_support_screen.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      final settings = File(
        'lib/features/settings/settings_screen.dart',
      ).readAsStringSync();
      final scanner = File(
        'lib/features/collections/group_qr_scanner_screen.dart',
      ).readAsStringSync();
      final groupCards = [
        'lib/shared/widgets/collect_group_cards.dart',
        'lib/shared/widgets/collect_group_card_media.dart',
      ].map((path) => File(path).readAsStringSync()).join('\n');
      final createGroup = File(
        'lib/features/collections/collection_create_screen.dart',
      ).readAsStringSync();
      final collectComponents = File(
        'lib/shared/widgets/collect_components.dart',
      ).readAsStringSync();

      expect(groups, isNot(contains('_GroupControlDock')));
      expect(groups, isNot(contains('Visibility')));
      expect(groups, isNot(contains('Sort groups')));
      expect(profile, isNot(contains("label: 'Device permissions'")));
      expect(
        profile,
        contains("CollectPlainPageHeader(title: 'Profile setup')"),
      );
      expect(settings, isNot(contains('Ready for group activity')));
      expect(statusScreens, contains("export 'device_privacy_screens.dart';"));
      expect(devicePrivacyScreens, contains('Action-triggered'));
      expect(
        devicePrivacyScreens,
        contains("CollectPlainPageHeader(title: 'App access')"),
      );
      expect(
        createGroup,
        contains("CollectPlainPageHeader(title: 'Create group')"),
      );
      expect(scanner, contains("CollectPlainPageHeader(title: 'Scan QR')"));
      expect(scanner, isNot(contains('analyzeImage')));
      expect(scanner, isNot(contains("'Gallery'")));
      expect(scanner, isNot(contains("label: 'Enter link'")));
      expect(groupCards, contains('_GroupCoverTitleOverlay'));
      expect(collectComponents, isNot(contains('plateFill')));
      expect(collectComponents, isNot(contains('plateBorder')));
    },
  );

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
    final app = File('lib/app/app.dart').readAsStringSync();

    expect(env.enableSmsReader, isFalse);
    expect(env.enableAndroidSmsAccess, isFalse);
    expect(env.enableAdminPanel, isFalse);
    expect(env.enableAdminDevTools, isFalse);
    expect(
      app,
      contains(
        'if (!env.enableAndroidSmsAccess && !env.enableSmsReader) return;',
      ),
    );
  });
}

String _materializeRouteForSmoke(String route) {
  return route
      .replaceAll(':collectionId', 'col-church')
      .replaceAll(':intentId', 'intent-render')
      .replaceAll(':state', 'pending')
      .replaceAll(':publicId', '038491')
      .replaceAll(':slug', 'st-michel-building-fund');
}
