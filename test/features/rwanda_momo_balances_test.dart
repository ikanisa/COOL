import '../fixtures/collect_repository_fixture.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RwandaMomoRepository extends FixtureCollectRepository {
  _RwandaMomoRepository() : super(fixtureNow: DateTime.utc(2026, 9, 2)) {
    state = state.copyWith(
      contributions: [
        Contribution(
          id: 'momo:one',
          collectionId: 'qa-private-group',
          amountRwf: 3000,
          currency: 'RWF',
          supporterLabel: 'You',
          isCurrentUserContribution: true,
          createdAt: DateTime.utc(2026, 9, 2),
        ),
        Contribution(
          id: 'momo:two',
          collectionId: 'qa-private-group',
          amountRwf: 12345,
          currency: 'RWF',
          supporterLabel: 'You',
          isCurrentUserContribution: true,
          createdAt: DateTime.utc(2026, 9, 2),
        ),
      ],
      collectionSummaries: {
        'qa-private-group': CollectionSummary.multiCurrency(
          totals: const {'RWF': 15345},
          ownBalances: const {'RWF': 15345},
          supporterCount: 2,
        ),
      },
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final route in [
    '/home',
    '/activity',
    '/groups',
    '/groups/qa-private-group',
    '/groups/qa-private-group/ledger',
    '/groups/qa-private-group/manage',
    '/groups/qa-private-group/share',
  ]) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$route shows RWF MoMo balances at $width dp, ${scale}x text',
          (tester) async {
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final repo = _RwandaMomoRepository();
            final router = createAppRouter(initialLocation: route);
            final captureKey = GlobalKey();
            final semantics = tester.ensureSemantics();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  collectBackendClientProvider.overrideWithValue(null),
                  appRouterProvider.overrideWithValue(router),
                  collectRepositoryProvider.overrideWith((ref) => repo),
                  collectThemeModeProvider.overrideWith(
                    (ref) =>
                        CollectThemeModeController(initialMode: ThemeMode.dark),
                  ),
                ],
                child: RepaintBoundary(
                  key: captureKey,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: Size(width, 844),
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true,
                    ),
                    child: const CollectApp(),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.textContaining('EUR'), findsNothing);
            expect(find.textContaining('RWF'), findsWidgets);
            expect(tester.takeException(), isNull);
            final captureDir = Platform.environment['COLLECT_UAT_CAPTURE_DIR'];
            if (captureDir != null &&
                width == 390 &&
                scale == 1 &&
                route == '/groups/qa-private-group') {
              await tester.runAsync(() async {
                final boundary =
                    captureKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$captureDir/31-rwanda-momo-group-390.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            semantics.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
            router.dispose();
          },
        );
      }
    }
  }
}
