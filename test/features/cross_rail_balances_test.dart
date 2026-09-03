import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme_controller.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MixedRailRepository extends CollectRepository {
  _MixedRailRepository() : super.fixture(fixtureNow: DateTime.utc(2026, 9, 2)) {
    state = state.copyWith(
      contributions: [
        Contribution(
          id: 'momo:one',
          collectionId: 'col-church',
          amountRwf: 3000,
          currency: 'RWF',
          supporterLabel: 'You',
          isCurrentUserContribution: true,
          createdAt: DateTime.utc(2026, 9, 2),
        ),
        Contribution(
          id: 'bank:two',
          collectionId: 'col-church',
          amountRwf: 12345,
          currency: 'EUR',
          supporterLabel: 'You',
          isCurrentUserContribution: true,
          createdAt: DateTime.utc(2026, 9, 2),
        ),
      ],
      collectionSummaries: {
        'col-church': CollectionSummary.multiCurrency(
          totals: const {'RWF': 3000, 'EUR': 12845},
          ownBalances: const {'RWF': 3000, 'EUR': 12345},
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
    '/groups/col-church',
    '/groups/col-church/ledger',
    '/groups/col-church/manage',
    '/groups/col-church/share',
  ]) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$route shows separate currency amounts at $width dp, ${scale}x text',
          (tester) async {
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final repo = _MixedRailRepository();
            final router = createAppRouter(initialLocation: route);
            final captureKey = GlobalKey();
            final semantics = tester.ensureSemantics();
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
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
            expect(find.textContaining('RWF 3,000'), findsWidgets);
            expect(find.textContaining('EUR 12'), findsWidgets);
            expect(find.textContaining('RWF 15,345'), findsNothing);
            expect(find.textContaining('RWF 12,345'), findsNothing);
            if (![
              '/groups',
              '/groups/col-church/manage',
              '/groups/col-church/share',
            ].contains(route)) {
              if (route == '/groups/col-church' && scale == 2) {
                await tester.scrollUntilVisible(
                  find.text('EUR 123.45'),
                  250,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.pumpAndSettle();
              }
              expect(find.text('EUR 123.45'), findsWidgets);
              expect(find.textContaining('RWF 12,345'), findsNothing);
              expect(tester.takeException(), isNull);
            }
            final captureDir = Platform.environment['COLLECT_UAT_CAPTURE_DIR'];
            if (captureDir != null &&
                width == 390 &&
                scale == 1 &&
                route == '/groups/col-church') {
              await tester.runAsync(() async {
                final boundary =
                    captureKey.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '$captureDir/31-mixed-currency-group-390.png',
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
