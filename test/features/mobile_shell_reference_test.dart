import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/widgets/collect_shell.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    String path = '/home',
    double scale = 1,
    Brightness brightness = Brightness.dark,
    bool highContrast = false,
    ValueChanged<String>? onNavigate,
  }) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 800),
            textScaler: TextScaler.linear(scale),
            highContrast: highContrast,
            disableAnimations: true,
          ),
          child: CollectShell(
            currentPath: path,
            onNavigate: onNavigate,
            child: const CollectGradientBackground(child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Gradient? backdrop(WidgetTester tester) {
    final box = find
        .descendant(
          of: find.byType(CollectGradientBackground).last,
          matching: find.byType(DecoratedBox),
        )
        .first;
    return (tester.widget<DecoratedBox>(box).decoration as BoxDecoration)
        .gradient;
  }

  testWidgets(
    'Home has reference depth; task and profile screens stay neutral',
    (tester) async {
      await pumpShell(tester);
      final account = backdrop(tester)! as LinearGradient;
      expect(account.colors.first, CollectColors.referenceAccountHighlight);
      await pumpShell(tester, path: '/groups');
      final discovery = backdrop(tester)! as LinearGradient;
      expect(discovery.colors.first, CollectColors.referenceDiscoveryViolet);
      for (final path in [
        '/settings/profile',
        '/groups/fixture/contribute',
        '/auth',
      ]) {
        await pumpShell(tester, path: path);
        expect(backdrop(tester), isNull, reason: path);
      }
    },
  );

  testWidgets('light adapts depth and high contrast removes it', (
    tester,
  ) async {
    await pumpShell(tester, brightness: Brightness.light);
    final light = backdrop(tester)! as LinearGradient;
    expect(light.colors.first.computeLuminance(), greaterThan(0.7));
    await pumpShell(tester, highContrast: true);
    expect(backdrop(tester), isNull);
  });

  for (final scale in [1.0, 1.2, 2.0]) {
    testWidgets(
      'floating navigation fits 320dp at $scale with four real targets',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          String? destination;
          await pumpShell(
            tester,
            scale: scale,
            onNavigate: (path) => destination = path,
          );
          final pill = tester.getRect(
            find.byKey(const ValueKey('collect-floating-navigation')),
          );
          expect(pill.left, 16);
          expect(pill.right, 304);
          expect(pill.bottom, lessThanOrEqualTo(788));
          for (final label in ['home', 'groups', 'activity', 'profile']) {
            final item = find.byKey(ValueKey('collect-nav-$label'));
            expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
            await tester.tap(item);
            await tester.pumpAndSettle();
            expect(destination, label == 'profile' ? '/settings' : '/$label');
            expect(tester.takeException(), isNull);
          }
          final selected = tester.widget<AnimatedContainer>(
            find.byKey(const ValueKey('collect-nav-home')),
          );
          expect(selected.duration, Duration.zero);
          expect(
            (selected.decoration! as BoxDecoration).color!.a,
            greaterThan(0),
          );
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
