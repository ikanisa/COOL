import 'package:cool_app/core/providers/production_redesign_provider.dart';
import 'package:cool_app/shared/widgets/admin_dense_row_tile.dart';
import 'package:cool_app/shared/widgets/admin_detail_scaffold.dart';
import 'package:cool_app/shared/widgets/admin_filter_rail.dart';
import 'package:cool_app/shared/widgets/admin_section_header.dart';
import 'package:cool_app/shared/widgets/admin_summary_metric_grid.dart';
import 'package:cool_app/shared/widgets/cool_admin_inline_field.dart';
import 'package:cool_app/shared/widgets/cool_otp_field.dart';
import 'package:cool_app/shared/widgets/cool_search_field.dart';
import 'package:cool_app/shared/widgets/core_detail_scaffold.dart';
import 'package:cool_app/shared/widgets/core_tab_root_scaffold.dart';
import 'package:cool_app/shared/widgets/dense_admin_workspace_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Golden tests for the shared scaffold archetypes, form kit, and admin kits.
///
/// These test the **UI governance deliverables** in isolation (not full screens),
/// validating layout, padding, title/subtitle slots, background ownership,
/// back/home button behaviour, and dense admin component rendering.
void main() {
  const captureKey = Key('golden-capture');
  const phoneSize = Size(390, 844);

  Future<void> settleGoldenApp(WidgetTester tester, {int frames = 8}) async {
    for (var i = 0; i < frames * 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (!tester.binding.hasScheduledFrame) break;
    }
  }

  Future<void> pumpGolden(
    WidgetTester tester, {
    required Widget child,
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phoneSize;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productionRedesignConfigProvider.overrideWith(
            (ref) => ProductionRedesignConfig.defaults(),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: MediaQuery(
            data: const MediaQueryData(
              size: phoneSize,
              devicePixelRatio: 1,
              disableAnimations: true,
            ),
            child: TickerMode(
              enabled: false,
              child: RepaintBoundary(key: captureKey, child: child),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await settleGoldenApp(tester, frames: 8);
  }

  Future<void> expectGolden(WidgetTester tester, String name) {
    return expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('goldens/archetypes/$name.png'),
    );
  }

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ═══════════════════════════════════════════════════════════════
  // Phase 1: Scaffold archetypes
  // ═══════════════════════════════════════════════════════════════

  group('CoreTabRootScaffold', () {
    testWidgets('default — child only', (tester) async {
      await pumpGolden(
        tester,
        child: const CoreTabRootScaffold(
          child: Center(child: Text('Tab Root Body')),
        ),
      );
      await expectGolden(tester, 'core_tab_root_default');
    });

    testWidgets('with title + subtitle', (tester) async {
      await pumpGolden(
        tester,
        child: const CoreTabRootScaffold(
          title: Text(
            'Home',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            'Welcome back',
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          child: Center(child: Text('Scrollable content')),
        ),
      );
      await expectGolden(tester, 'core_tab_root_with_header');
    });
  });

  group('CoreDetailScaffold', () {
    testWidgets('default — back button + child', (tester) async {
      await pumpGolden(
        tester,
        child: const CoreDetailScaffold(
          child: Center(child: Text('Detail Body')),
        ),
      );
      await expectGolden(tester, 'core_detail_default');
    });

    testWidgets('with title + subtitle + home button', (tester) async {
      await pumpGolden(
        tester,
        child: const CoreDetailScaffold(
          showHomeButton: true,
          title: Text(
            'Partners',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            'Explore partner services',
            style: TextStyle(fontSize: 14, color: Colors.white70),
          ),
          child: Center(child: Text('Partner content')),
        ),
      );
      await expectGolden(tester, 'core_detail_with_header_home');
    });
  });

  group('AdminDetailScaffold', () {
    testWidgets('default', (tester) async {
      await pumpGolden(
        tester,
        child: const AdminDetailScaffold(
          title: Text(
            'Admin Dashboard',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          actions: [
            IconButton(onPressed: null, icon: Icon(Icons.refresh_rounded)),
          ],
          child: Center(child: Text('Dashboard content')),
        ),
      );
      await expectGolden(tester, 'admin_detail_default');
    });
  });

  group('DenseAdminWorkspaceScaffold', () {
    testWidgets('with search bar + filter actions', (tester) async {
      await pumpGolden(
        tester,
        child: DenseAdminWorkspaceScaffold(
          searchBar: const CoolSearchField(hint: 'Search users...'),
          filterActions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.filter_list_rounded),
            ),
          ],
          child: const Center(child: Text('Dense workspace content')),
        ),
      );
      await expectGolden(tester, 'dense_admin_workspace_with_search');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Phase 3: Form kit
  // ═══════════════════════════════════════════════════════════════

  group('CoolSearchField', () {
    testWidgets('empty state', (tester) async {
      await pumpGolden(
        tester,
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: CoolSearchField(hint: 'Search transactions...'),
          ),
        ),
      );
      await expectGolden(tester, 'cool_search_field_empty');
    });
  });

  group('CoolOtpField', () {
    testWidgets('empty 6-digit', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: CoolOtpField(
              onComplete: (_) {},
              length: 6,
              autofocus: false,
            ),
          ),
        ),
      );
      await expectGolden(tester, 'cool_otp_field_empty');
    });

    testWidgets('with error', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: CoolOtpField(
              onComplete: (_) {},
              length: 6,
              autofocus: false,
              error: 'Invalid verification code',
            ),
          ),
        ),
      );
      await expectGolden(tester, 'cool_otp_field_error');
    });
  });

  group('CoolAdminInlineField', () {
    testWidgets('with label and actions', (tester) async {
      await pumpGolden(
        tester,
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: CoolAdminInlineField(
              label: 'Display Name',
              hint: 'Enter name...',
              showActions: true,
            ),
          ),
        ),
      );
      await expectGolden(tester, 'cool_admin_inline_field_with_actions');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Phase 4: Admin kits
  // ═══════════════════════════════════════════════════════════════

  group('AdminSectionHeader', () {
    testWidgets('with message and trailing', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: AdminSectionHeader(
              title: 'Triage Queue',
              message: 'Focused on failed payments',
              trailing: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ),
          ),
        ),
      );
      await expectGolden(tester, 'admin_section_header_full');
    });
  });

  group('AdminSummaryMetricGrid', () {
    testWidgets('4 metrics', (tester) async {
      await pumpGolden(
        tester,
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: AdminSummaryMetricGrid(
              metrics: [
                AdminMetric(
                  label: 'Active Users',
                  value: '1,234',
                  icon: Icons.people_rounded,
                  trend: '+12%',
                  trendIsPositive: true,
                ),
                AdminMetric(
                  label: 'Revenue',
                  value: '45.2K',
                  icon: Icons.attach_money_rounded,
                  trend: '-3%',
                  trendIsPositive: false,
                ),
                AdminMetric(
                  label: 'Orders',
                  value: '892',
                  icon: Icons.receipt_long_rounded,
                ),
                AdminMetric(
                  label: 'Uptime',
                  value: '99.9%',
                  icon: Icons.monitor_heart_rounded,
                  trend: '→',
                  trendIsPositive: null,
                ),
              ],
            ),
          ),
        ),
      );
      await expectGolden(tester, 'admin_summary_metric_grid_4');
    });
  });

  group('AdminFilterRail', () {
    testWidgets('with selection', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: AdminFilterRail(
              filters: const ['All', 'Active', 'Pending', 'Failed', 'Archived'],
              selectedIndices: const {1},
              onSelected: (index, isSelected) {},
            ),
          ),
        ),
      );
      await expectGolden(tester, 'admin_filter_rail_selected');
    });
  });

  group('AdminDenseRowTile', () {
    testWidgets('with icon, title, subtitle, trailing', (tester) async {
      await pumpGolden(
        tester,
        child: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 24),
              AdminDenseRowTile(
                title: 'John Doe',
                subtitle: '+250 788 123 456',
                leading: const CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.person_rounded, size: 18),
                ),
                trailing: IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ),
              const Divider(height: 1),
              const AdminDenseRowTile(
                title: 'Jane Smith',
                subtitle: '+250 788 654 321',
                leading: CircleAvatar(
                  radius: 18,
                  child: Icon(Icons.person_rounded, size: 18),
                ),
              ),
            ],
          ),
        ),
      );
      await expectGolden(tester, 'admin_dense_row_tile_list');
    });
  });
}
