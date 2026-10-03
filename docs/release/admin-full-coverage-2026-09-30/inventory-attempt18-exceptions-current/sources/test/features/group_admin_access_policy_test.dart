import '../fixtures/collect_repository_fixture.dart';

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

  for (final width in [320.0, 390.0, 1184.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('group owner can add an active admin at $width dp ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = createAppRouter(
          initialLocation: '/groups/qa-private-group/manage',
        );
        final key = GlobalKey();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appRouterProvider.overrideWithValue(router),
              collectRepositoryProvider.overrideWith(
                (ref) => FixtureCollectRepository(
                  fixtureNow: DateTime.utc(2026, 9, 2),
                  fixtureAdditionalMembers: {
                    'qa-private-group': [
                      CollectMember(
                        publicId: '123456',
                        role: 'member',
                        status: 'active',
                        joinedAt: DateTime.utc(2026, 8, 1),
                      ),
                    ],
                  },
                ),
              ),
              collectThemeModeProvider.overrideWith(
                (ref) =>
                    CollectThemeModeController(initialMode: ThemeMode.dark),
              ),
            ],
            child: RepaintBoundary(
              key: key,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: const CollectApp(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          router.dispose();
        });

        for (final action in [
          'Members',
          'Add admin',
          'Ledger',
          'Transfer ownership',
          'Archive group',
        ]) {
          await tester.scrollUntilVisible(
            find.text(action),
            160,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text(action), findsOneWidget);
          expect(find.textContaining('Invite another member'), findsNothing);
          expect(find.textContaining('pre-approved'), findsNothing);
          expect(find.byType(TextField), findsNothing);
          expect(tester.takeException(), isNull);
        }

        final capture = Platform.environment['COLLECT_UAT_CAPTURE_DIR'];
        if (capture != null && scale == 1 && width != 320) {
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '$capture/55-group-admin-settings-${width.toInt()}.png',
            ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }

        // Return to the restored action; a group owner is not a platform Admin.
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Add admin'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await Scrollable.ensureVisible(
          tester.element(find.text('Add admin')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        expect(find.text('Add admin').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Add admin'));
        await tester.pumpAndSettle();
        expect(find.text('Collect ID'), findsOneWidget);
        expect(find.textContaining('pre-approved'), findsNothing);
        expect(find.textContaining('WhatsApp'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byType(TextField).last, '123456');
        await tester.tap(find.widgetWithText(FilledButton, 'Add admin'));
        await tester.pumpAndSettle();
        expect(find.text('Group admin added.'), findsOneWidget);
        router.go('/groups/qa-private-group/members');
        await tester.pumpAndSettle();
        expect(find.text('123456'), findsOneWidget);
        expect(find.text('Admin · Active'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (capture != null && scale == 1 && width != 320) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            await File(
              '$capture/56-group-admin-roster-${width.toInt()}.png',
            ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
