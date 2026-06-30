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
        '/groups/scan',
        '/groups/create',
        '/groups/:collectionId',
        '/groups/:collectionId/joined',
        '/groups/:collectionId/members',
        '/groups/:collectionId/owner',
        '/groups/:collectionId/owner/sms-health',
        '/groups/:collectionId/owner/receiver',
        '/groups/:collectionId/manage',
        '/groups/:collectionId/profile',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId/handoff',
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

  test('main mobile routes use the shared transition page helper', () {
    final routerSource = File('lib/app/router.dart').readAsStringSync();

    expect(routerSource, contains('CustomTransitionPage<void>'));
    expect(routerSource, contains('pageBuilder:'));
    expect(
      routerSource,
      contains('MediaQuery.maybeOf(context)?.disableAnimations'),
    );
    expect(
      routerSource,
      isNot(contains('builder: (context, state) => const HomeScreen()')),
    );
    expect(
      routerSource,
      isNot(contains('builder: (context, state) => const CollectionsScreen()')),
    );
  });

  test('mobile chrome exposes native refresh and haptic affordances', () {
    final haptics = File(
      'lib/shared/utils/collect_haptics.dart',
    ).readAsStringSync();
    final foundation = File(
      'lib/shared/widgets/collect_foundation.dart',
    ).readAsStringSync();
    final chromeLibrary = File(
      'lib/shared/widgets/collect_chrome.dart',
    ).readAsStringSync();
    final scaffoldChrome = File(
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ).readAsStringSync();
    final topChrome = File(
      'lib/shared/widgets/collect_top_chrome.dart',
    ).readAsStringSync();
    final shell = File(
      'lib/core/widgets/collect_shell.dart',
    ).readAsStringSync();
    final primaryScreens = [
      'lib/features/home/home_screen.dart',
      'lib/features/collections/collections_screen.dart',
      'lib/features/collections/collection_detail_screen.dart',
      'lib/features/ledger/ledger_screen.dart',
      'lib/features/payments/payment_intent_status_screen.dart',
      'lib/features/status/device_notification_center.dart',
      'lib/features/settings/settings_screen.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(haptics, contains('HapticFeedback.selectionClick'));
    expect(haptics, contains('HapticFeedback.lightImpact'));
    expect(haptics, contains('HapticFeedback.mediumImpact'));
    expect(haptics, contains('HapticFeedback.vibrate'));
    expect(chromeLibrary, contains("import '../utils/collect_haptics.dart';"));
    expect(foundation, contains('CollectHaptics.lightImpact();'));
    expect(foundation, contains('CollectHaptics.selection();'));
    expect(scaffoldChrome, contains('RefreshIndicator.adaptive'));
    expect(scaffoldChrome, contains('AlwaysScrollableScrollPhysics'));
    expect(scaffoldChrome, contains('CollectHaptics.lightImpact();'));
    expect(topChrome, contains('CollectHaptics.selection();'));
    expect(shell, contains('CollectHaptics.selection();'));
    expect(primaryScreens, contains('onRefresh:'));
    expect(primaryScreens, contains('collectRepositoryProvider.notifier'));
    expect(primaryScreens, contains('loadInitial()'));
    expect(primaryScreens, contains('_refreshStatus'));
  });

  test('mobile native performance profiling has a device evidence gate', () {
    final profileScript = File(
      'scripts/mobile_native_performance_profile.sh',
    ).readAsStringSync();

    expect(profileScript, contains('flutter'));
    expect(profileScript, contains('drive'));
    expect(profileScript, contains('--profile'));
    expect(profileScript, contains('--trace-startup'));
    expect(profileScript, contains(r'--trace-to-file="$TRACE_FILE"'));
    expect(
      profileScript,
      contains('--dart-define=COLLECT_MOBILE_EVIDENCE_MODE=true'),
    );
    expect(profileScript, contains('timeline.binpb'));
    expect(profileScript, contains('runner_result.json'));
    expect(profileScript, contains('summary.json'));
    expect(profileScript, contains('trace_bytes'));
    expect(
      profileScript,
      contains('Profile-mode runner did not exit cleanly.'),
    );
    expect(profileScript, contains('Perfetto timeline trace was not written.'));
    expect(profileScript, contains('exit 99'));
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
    expect(designAudit, contains('four_primary_color_distinction_contract'));
    expect(designAudit, contains('collect_runtime_alignment_contract'));
    expect(designAudit, contains('collect_font_installed_or_blocked'));
    expect(
      designAudit,
      contains('collect_runtime_assets_installed_or_blocked'),
    );
    expect(designAudit, contains('collect_runtime_asset_switchpoints'));
    expect(
      designAudit,
      contains('collect_runtime_component_token_switchpoints'),
    );
    expect(designAudit, contains('native_mobile_interaction_contract'));
    expect(designAudit, contains('revolut_100_percent_claim_guard'));
    expect(designAudit, contains('gradient_glass_screen_contract'));
    expect(designAudit, contains('theme_mode_visual_parity_gate'));
    expect(designAudit, contains('no_redundant_top_search_chrome_contract'));
    expect(designAudit, contains('mobile_brand_asset_contract'));
    expect(designAudit, contains('no_raw_ui_colors_outside_tokens'));
    expect(designAudit, contains('share_domain_contract'));
    expect(designAudit, contains('all_production_routes_rendered'));
    expect(designAudit, contains('android_device_uat_evidence'));
  });

  test('Collect runtime alignment docs preserve Collect nav contract', () {
    final currentStatus = File(
      'docs/design/FLUTTER_MOBILE_CURRENT_STATUS_AND_GAP_REGISTER_2026-06-27.md',
    ).readAsStringSync();
    final blockerRegister = File(
      'docs/design/REVOLUT_ALIGNMENT_BLOCKER_REGISTER_2026-06-27.md',
    ).readAsStringSync();
    final reviewMatrix = File(
      'docs/design/REVOLUT10_SCREENSHOT_ROUTE_REVIEW_MATRIX_2026-06-27.md',
    ).readAsStringSync();

    expect(currentStatus, contains('`Home`, `Groups`, and `Settings`'));
    expect(reviewMatrix, contains('`Home`, `Groups`, and `Settings`'));
    final rewardsDestinationLabel = ['Rev', 'Points'].join();
    expect(currentStatus, isNot(contains('`Payments`')));
    expect(currentStatus, isNot(contains('`Crypto`')));
    expect(currentStatus, isNot(contains('`$rewardsDestinationLabel`')));
    expect(currentStatus, contains('Use Periwinkle, not Orange'));
    expect(blockerRegister, contains('| collect_route_reference_matrix |'));
    expect(blockerRegister, contains('Source mapped and reviewed'));
    expect(blockerRegister, contains('android_device_uat_current_source'));
    for (final screenshot in <String>[
      'IMG_2739.PNG',
      'IMG_2740.PNG',
      'IMG_2741.PNG',
      'IMG_2742.PNG',
      'IMG_2747.PNG',
      'IMG_2748.PNG',
      'IMG_2749.PNG',
      'IMG_2750.PNG',
      'IMG_2751.PNG',
      'IMG_2752.PNG',
      'IMG_2755.PNG',
    ]) {
      expect(reviewMatrix, contains(screenshot));
    }
  });

  test('orange is reserved away from routine CTA and decorative surfaces', () {
    for (final path in <String>[
      'lib/features/landing/collect_landing_page.dart',
      'lib/features/landing/collect_home_access_trust.dart',
      'lib/features/landing/collect_home_hero.dart',
      'lib/features/landing/public_infographic_content.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('brandOrangeRed')),
        reason: path,
      );
    }

    final groupCardMedia = File(
      'lib/shared/widgets/collect_group_card_media.dart',
    ).readAsStringSync();
    expect(groupCardMedia, isNot(contains('orangePaint')));
    expect(groupCardMedia, isNot(contains('brandAction,')));
    expect(groupCardMedia, contains('colors.rosePaint'));

    final staticSite = File(
      'scripts/public_static_site_build.rb',
    ).readAsStringSync();
    expect(staticSite, isNot(contains('var(--orange)')));
    expect(staticSite, contains('.button.cta-touch { background: var(--rose)'));
    expect(staticSite, contains('.brand-word { color: var(--periwinkle); }'));
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
    final runtimeAssets = File(
      'lib/app/theme/collect_runtime_assets.dart',
    ).readAsStringSync();
    final scaffoldPart = File(
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ).readAsStringSync();

    expect(chromeLibrary, contains("part 'collect_top_chrome.dart';"));
    expect(chromeLibrary, contains("part 'collect_scaffold_chrome.dart';"));
    expect(topChromePart, contains('class CollectBrandMark'));
    expect(topChromePart, contains('CollectRuntimeAssets.wordmarkAssetPath'));
    expect(topChromePart, contains('CollectRuntimeAssets.appIconAssetPath'));
    expect(runtimeAssets, contains('wordmarkAssetPath = sourceWordmarkPath'));
    expect(runtimeAssets, contains('appIconAssetPath = expectedAppIconPath'));
    expect(
      runtimeAssets,
      contains('splashMarkAssetPath = expectedSplashMarkPath'),
    );
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

  test('primary mobile screens delete redundant top search chrome', () {
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
    final settings = File(
      'lib/features/settings/settings_screen.dart',
    ).readAsStringSync();
    final sharedBarrel = File(
      'lib/shared/widgets/collect_components.dart',
    ).readAsStringSync();
    final chromeModule = [
      'lib/shared/widgets/collect_chrome.dart',
      'lib/shared/widgets/collect_top_chrome.dart',
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(home, isNot(contains('CollectTopChrome(')));
    expect(home, isNot(contains("context.go('/groups/search')")));
    expect(home, isNot(contains("label: 'Join'")));
    expect(home, isNot(contains("context.go('/groups/join')")));
    expect(home, contains("label: 'Scan QR'"));
    expect(home, contains("onTap: () => context.go('/groups/scan'),"));
    expect(groups, isNot(contains('CollectTopChrome(')));
    expect(groups, isNot(contains("'Search groups'")));
    expect(settings, isNot(contains('CollectTopChrome(')));
    expect(settings, isNot(contains("'Search settings'")));
    expect(groupDetail, isNot(contains('CollectTopChrome')));
    expect(groupDetail, isNot(contains('persistentPill')));
    expect(sharedBarrel, contains("export 'collect_chrome.dart';"));
    expect(sharedBarrel, isNot(contains('class CollectTopChrome')));
    expect(chromeModule, contains('class CollectTopChrome'));
    expect(chromeModule, isNot(contains('searchLabel')));
    expect(chromeModule, isNot(contains('onSearchTap')));
    expect(chromeModule, isNot(contains('onSearchChanged')));
    expect(chromeModule, isNot(contains('CollectIcons.search')));
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
      expect(createGroup, isNot(contains('_createStepSubtitle')));
      expect(createGroup, isNot(contains('subtitle: _createStepSubtitle')));
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
