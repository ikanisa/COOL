import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/admin_shell.dart';
import 'package:collect_app/admin/core/admin_automations_page.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_sms_queue_health.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:collect_app/app/theme/collect_runtime_assets.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 30, 10);
const _identity = AdminIdentity(
  userId: '00000000-0000-4000-8000-000000000001',
  displayName: 'Synthetic operations reviewer',
  roles: ['admin'],
  permissions: ['system_health.read', 'notifications.read'],
);

Map<String, dynamic> _sms({bool enabled = false}) => {
  'enabled': enabled,
  'queued': 2,
  'awaiting_confirmation': 1,
  'send_started': 0,
  'uncertain': 1,
  'suppressed': 0,
  'active_workers': 0,
  'oldest_queued_at': _now
      .subtract(const Duration(minutes: 3))
      .toIso8601String(),
  'observed_at': _now.toIso8601String(),
};

Map<String, dynamic> _push() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/admin_operational_health148.json',
            ).readAsStringSync(),
          )
          as Map;
  return Map<String, dynamic>.from(fixture['receipt'] as Map)
    ..['checked_at'] = _now.toIso8601String()
    ..['sample_valid_until'] = _now
        .add(const Duration(seconds: 60))
        .toIso8601String();
}

class _Repository extends AdminEvidenceRepository {
  _Repository({this.smsFailure, this.pendingSms});
  final Object? smsFailure;
  final Completer<Map<String, dynamic>>? pendingSms;
  int reads = 0, healthReads = 0, writes = 0;
  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;
  @override
  Future<Map<String, dynamic>> smsQueueHealth() async {
    reads++;
    if (smsFailure != null) throw smsFailure!;
    return pendingSms?.future ?? _sms();
  }

  @override
  Future<Map<String, dynamic>> detail(String rpcName, String id) async {
    healthReads++;
    return _push();
  }

  @override
  Future<Map<String, dynamic>> action(
    String rpcName,
    Map<String, dynamic> params,
  ) async {
    writes++;
    throw StateError('This page must not write.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
      await (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  test('SMS sample validates counts, UTC dates, consistency and expiry', () {
    final health = AdminSmsQueueHealth.parse(_sms());
    expect(health.enabled, isFalse);
    expect(health.counts['uncertain'], 1);
    expect(health.isFresh(_now), isTrue);
    expect(health.isFresh(_now.add(const Duration(seconds: 60))), isFalse);
    expect(health.isFresh(_now.subtract(const Duration(seconds: 6))), isFalse);
    expect(() => health.counts['queued'] = 0, throwsUnsupportedError);
    for (final bad in [
      {..._sms(), 'queued': '2'},
      {..._sms(), 'uncertain': -1},
      {..._sms(), 'enabled': 'false'},
      {..._sms(), 'oldest_queued_at': null},
      {..._sms(), 'observed_at': '2026-02-30T10:00:00Z'},
      {..._sms(), 'private_data': 'PRIVATE_CANARY'},
    ]) {
      expect(() => AdminSmsQueueHealth.parse(bad), throwsFormatException);
    }
  });

  test('Automations route retains canonical system-health permission', () {
    expect(adminRoutePaths, contains('/admin/automations'));
    expect(
      adminRequiredPermissionForPath('/admin/automations'),
      'system_health.read',
    );
    expect(adminCanOpenPath(_identity, '/admin/automations'), isTrue);
    expect(
      adminCanOpenPath(
        const AdminIdentity(
          userId: 'none',
          displayName: 'Denied',
          roles: [],
          permissions: ['notifications.read'],
        ),
        '/admin/automations',
      ),
      isFalse,
    );
  });

  Future<void> mount(
    WidgetTester tester,
    _Repository repository, {
    AdminIdentity identity = _identity,
    double width = 1440,
    double scale = 1,
    DateTime Function()? clock,
    bool banner = false,
    bool dark = false,
    bool shell = false,
    GlobalKey? capture,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(null),
          adminIdentityProvider.overrideWith((ref) async => identity),
          adminRepositoryProvider.overrideWithValue(repository),
          adminClockProvider.overrideWithValue(clock ?? () => _now),
        ],
        child: MaterialApp(
          theme: dark ? CollectTheme.dark() : CollectTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: capture,
              child: shell
                  ? const AdminShell(
                      location: '/admin/automations',
                      child: AdminAutomationsPage(),
                    )
                  : banner
                  ? const AdminSmsDispatchBanner()
                  : const AdminAutomationsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'real service samples remain distinct; unavailable telemetry is explicit',
    (tester) async {
      final repository = _Repository();
      await mount(tester, repository);
      expect(find.text('Dispatch disabled'), findsOneWidget);
      expect(find.text('Send outcome unknown'), findsOneWidget);
      expect(find.text('Schedule disabled'), findsOneWidget);
      expect(find.text('Unmeasured'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Run telemetry unavailable'),
        300,
      );
      expect(find.text('Run telemetry unavailable'), findsOneWidget);
      expect(find.text('Run now'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(repository.writes, 0);
      await finish(tester);
    },
  );

  testWidgets('resolved status can refresh both services without writes', (
    tester,
  ) async {
    final repository = _Repository();
    await mount(tester, repository);
    expect(find.text('Send outcome unknown'), findsOneWidget);
    expect(find.text('Schedule disabled'), findsOneWidget);
    expect(repository.reads, 1);
    expect(repository.healthReads, 1);
    final refresh = find.ancestor(
      of: find.text('Refresh status'),
      matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
    );
    expect(refresh, findsOneWidget);
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(repository.reads, 2);
    expect(repository.healthReads, 2);
    expect(repository.writes, 0);
    expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
    await finish(tester);
  });

  testWidgets(
    'expiry hides old numbers and automatic tick never refetches or writes',
    (tester) async {
      var now = _now;
      final repository = _Repository();
      await mount(tester, repository, clock: () => now);
      expect(find.text('Queued receipts'), findsOneWidget);
      now = _now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Sample expired'), findsNWidgets(2));
      expect(find.text('Queued receipts'), findsNothing);
      expect(repository.reads, 1);
      expect(repository.writes, 0);
      await finish(tester);
    },
  );

  testWidgets('partial SMS failure retains scheduler and hides raw errors', (
    tester,
  ) async {
    final repository = _Repository(smsFailure: StateError('PRIVATE_CANARY'));
    await mount(tester, repository);
    expect(find.text('Schedule disabled'), findsOneWidget);
    expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
    expect(
      find.text('The admin request could not be completed.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('permission denial does not read SMS or health services', (
    tester,
  ) async {
    final repository = _Repository();
    await mount(
      tester,
      repository,
      identity: const AdminIdentity(
        userId: 'none',
        displayName: 'Denied',
        roles: [],
        permissions: [],
      ),
    );
    expect(repository.reads, 0);
    expect(find.text('Automations'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'global gate banner loads, closes and expires without implying a pause of ingestion',
    (tester) async {
      var now = _now;
      final pending = Completer<Map<String, dynamic>>();
      await mount(
        tester,
        _Repository(pendingSms: pending),
        clock: () => now,
        banner: true,
      );
      expect(find.text('Checking SMS dispatch gate'), findsOneWidget);
      pending.complete(_sms());
      await tester.pump();
      await tester.pump();
      expect(find.text('New SMS receipt dispatch disabled'), findsOneWidget);
      now = _now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('SMS dispatch gate unverified'), findsOneWidget);
      expect(find.text('Refresh gate'), findsOneWidget);
      await finish(tester);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'desktop ${dark ? 'dark' : 'light'} rendering uses synthetic service samples',
      (tester) async {
        final capture = GlobalKey();
        await mount(
          tester,
          _Repository(),
          capture: capture,
          dark: dark,
          shell: true,
        );
        final selectedNavigation = find.byWidgetPredicate(
          (widget) => widget is ListTile && widget.selected,
        );
        expect(selectedNavigation, findsOneWidget);
        final railForeground = tester
            .element(selectedNavigation)
            .collectColors
            .onImagePrimary;
        expect(
          tester.widget<ListTile>(selectedNavigation).selectedColor,
          railForeground,
        );
        final selectedIcon = find.descendant(
          of: selectedNavigation,
          matching: find.byIcon(Icons.manage_search_outlined),
        );
        expect(selectedIcon, findsOneWidget);
        expect(
          IconTheme.of(tester.element(selectedIcon)).color,
          railForeground,
        );
        if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
          await tester.runAsync(
            () => precacheImage(
              const AssetImage(CollectRuntimeAssets.officialLogo),
              capture.currentContext!,
              onError: (error, stack) =>
                  Error.throwWithStackTrace(error, stack!),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          final logo = find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is Image &&
                  widget.image is AssetImage &&
                  (widget.image as AssetImage).assetName ==
                      CollectRuntimeAssets.officialLogo,
            ),
            matching: find.byType(RawImage),
          );
          expect(tester.widget<RawImage>(logo).image, isNotNull);
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'docs/release/collect-codex-2026-09-30/automations-${dark ? 'dark' : 'light'}-synthetic.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );
  }

  testWidgets('320px doubled text remains scrollable through every section', (
    tester,
  ) async {
    await mount(tester, _Repository(), width: 320, scale: 2);
    await tester.scrollUntilVisible(
      find.text('Run telemetry unavailable'),
      250,
    );
    expect(find.text('Run telemetry unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('persistent shell and SMS gate reflow at 320px doubled text', (
    tester,
  ) async {
    await mount(tester, _Repository(), width: 320, scale: 2, shell: true);
    expect(find.text('New SMS receipt dispatch disabled'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
