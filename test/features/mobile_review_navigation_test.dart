import '../fixtures/collect_repository_fixture.dart';

import 'package:collect_app/app/app.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('review routes render after form edits, scrolling and resizing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FixtureCollectRepository();
    final router = createAppRouter(initialLocation: '/home');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appRouterProvider.overrideWithValue(router),
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: const CollectApp(),
      ),
    );
    await tester.pumpAndSettle();

    for (final entry in const {
      '/offline': 'You are offline',
      '/sync': 'Sync needs attention',
      '/groups/qa-private-group/profile': 'Group profile',
      '/groups/qa-private-group/ledger': 'Ledger',
      '/activity': 'Activity',
      '/settings/legal/privacy': 'Privacy Policy',
    }.entries) {
      router.go(entry.key);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(find.text(entry.value), findsWidgets, reason: entry.key);
      if (entry.key.endsWith('/profile')) {
        await tester.enterText(find.byType(TextField).first, 'Review draft');
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(780, 844);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'wide profile');
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'narrow profile');
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Review draft',
        );
      }
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.last, const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: '${entry.key} scrolled');
    }
  });
}
