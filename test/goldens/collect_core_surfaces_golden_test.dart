import 'dart:io';

import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_runtime_assets.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/main_public.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GoldenFileComparator previousGoldenFileComparator;

  setUpAll(() async {
    previousGoldenFileComparator = goldenFileComparator;
    goldenFileComparator = _CollectGoldenFileComparator(
      Uri.parse('test/goldens/collect_core_surfaces_golden_test.dart'),
      precisionTolerance: 0.0005,
    );
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'));
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([inter.load(), materialIcons.load()]);
  });

  tearDownAll(() {
    goldenFileComparator = previousGoldenFileComparator;
  });

  const memberSurfaces = <String, String>{
    'auth': '/auth',
    'home': '/home',
    'groups': '/groups',
    'contribute_entry': '/contribute',
    'activity': '/activity',
    'profile': '/settings',
    'group_detail': '/groups/col-church',
    'contribution_review': '/groups/col-church/contribute',
    'ledger': '/groups/col-church/ledger',
    'offline': '/offline',
    'appearance': '/settings/appearance',
  };

  test('approved golden manifest covers every baseline exactly', () {
    final files =
        Directory('test/goldens/baselines')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.png'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final manifest = <String, String>{};
    for (final line in File(
      'test/goldens/GOLDEN_MANIFEST.sha256',
    ).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final separator = line.indexOf('  ');
      expect(separator, greaterThan(0), reason: line);
      manifest[line.substring(separator + 2)] = line.substring(0, separator);
    }

    expect(files, hasLength(13));
    expect(manifest, hasLength(files.length));
    for (final file in files) {
      expect(
        manifest[file.path],
        sha256.convert(file.readAsBytesSync()).toString(),
      );
    }
  });

  for (final surface in memberSurfaces.entries) {
    testWidgets(
      'member ${surface.key} matches approved visual baseline',
      (tester) async {
        await _setViewport(tester, const Size(390, 844));
        final goldenKey = ValueKey<String>('golden-member-${surface.key}');
        final router = createAppRouter(initialLocation: surface.value);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appRouterProvider.overrideWithValue(router),
              collectRepositoryProvider.overrideWith(
                (ref) => CollectRepository.fixture(
                  fixtureNow: DateTime.utc(2026, 7, 24, 21),
                ),
              ),
              collectThemeModeProvider.overrideWith(
                (ref) => CollectThemeModeController(
                  initialMode: ThemeMode.dark,
                  loadPersistedMode: false,
                ),
              ),
            ],
            child: RepaintBoundary(
              key: goldenKey,
              child: MediaQuery(
                data: MediaQueryData.fromView(
                  tester.view,
                ).copyWith(accessibleNavigation: true, disableAnimations: true),
                child: const CollectApp(),
              ),
            ),
          ),
        );
        await _precacheOfficialLogo(tester);
        await _pumpStableFrames(tester);
        if (surface.key == 'contribution_review') {
          await tester.enterText(find.byType(TextField).first, '10000');
          await tester.tap(
            find.widgetWithText(FilledButton, 'Continue to MoMo'),
          );
          await _pumpStableFrames(tester);
        }

        expect(tester.takeException(), isNull, reason: surface.value);
        await expectLater(
          find.byKey(goldenKey),
          matchesGoldenFile('baselines/member_${surface.key}_dark.png'),
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'public website matches approved desktop baseline',
    (tester) async {
      await _setViewport(tester, const Size(1440, 900));
      const goldenKey = ValueKey<String>('golden-public-home');

      await tester.pumpWidget(
        const RepaintBoundary(
          key: goldenKey,
          child: ProviderScope(child: CollectPublicWebsiteApp()),
        ),
      );
      await _precacheOfficialLogo(tester);
      await _pumpStableFrames(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('baselines/public_home_desktop.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Admin PWA overview matches approved desktop baseline',
    (tester) async {
      await _setViewport(tester, const Size(1440, 900));
      const goldenKey = ValueKey<String>('golden-admin-overview');
      const identity = AdminIdentity(
        userId: '00000000-0000-0000-0000-00000000e001',
        displayName: 'Collect evidence admin',
        phoneMasked: '+250***6816',
        roles: ['platform_owner'],
        permissions: [
          'overview.read',
          'public_requests.read',
          'collections.read',
          'users.read',
          'bank_details.read',
          'bank_transactions.read',
          'bank_evidence.read',
          'bank_reconciliation.read',
          'audit.read',
          'feature_flags.read',
          'settings.read',
          'system_health.read',
          'admin_users.read',
          'payments.read',
          'payment_events.read',
          'ledger.read',
          'receivers.read',
          'sms.metadata.read',
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAuthGuardProvider.overrideWithValue(
              const AdminAuthGuard(isAuthorized: true),
            ),
            adminIdentityProvider.overrideWith((ref) async => identity),
            adminRepositoryProvider.overrideWithValue(
              const AdminEvidenceRepository(),
            ),
            adminClockProvider.overrideWithValue(
              () => DateTime(2026, 8, 20, 21, 4),
            ),
            collectThemeModeProvider.overrideWith(
              (ref) => CollectThemeModeController(
                initialMode: ThemeMode.dark,
                loadPersistedMode: false,
              ),
            ),
          ],
          child: const RepaintBoundary(
            key: goldenKey,
            child: CollectAdminApp(),
          ),
        ),
      );
      await _precacheOfficialLogo(tester);
      await _pumpStableFrames(tester);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('baselines/admin_overview_desktop.png'),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

/// Allows only sub-pixel rasterization drift while preserving geometry and
/// layout regression detection across the supported Flutter build hosts.
class _CollectGoldenFileComparator extends LocalFileComparator {
  _CollectGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : assert(
         0 <= precisionTolerance && precisionTolerance <= 1,
         'precisionTolerance must be between 0 and 1',
       ),
       _precisionTolerance = precisionTolerance;

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final passed = result.passed || result.diffPercent <= _precisionTolerance;
    if (passed) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(
        accessibleNavigation: true,
        disableAnimations: true,
      );
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Future<void> _pumpStableFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 16; frame += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _precacheOfficialLogo(WidgetTester tester) async {
  final context = tester.element(find.byType(MaterialApp).first);
  await tester.runAsync(
    () => precacheImage(
      const AssetImage(CollectRuntimeAssets.officialLogo),
      context,
    ),
  );
  await tester.pump();
}
