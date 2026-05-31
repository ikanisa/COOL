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
  testWidgets('app boots with Collect home shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CollectApp()));
    await tester.pump();

    expect(find.text('Collect'), findsWidgets);
    expect(find.text('Platform admin'), findsNothing);
    expect(find.textContaining('BioPay'), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
  });

  test('main Collect routes are registered', () {
    expect(
      collectRoutePaths,
      containsAll(<String>[
        '/auth',
        '/home',
        '/groups',
        '/groups/create',
        '/groups/:collectionId',
        '/groups/:collectionId/manage',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId',
        '/groups/:collectionId/share',
        '/groups/:collectionId/invite',
        '/groups/:collectionId/ledger',
        '/c/:slug',
        '/settings',
        '/settings/profile',
        if (kDebugMode) '/dev/design-system',
      ]),
    );

    final router = createAppRouter();
    addTearDown(router.dispose);
    expect(router.configuration.routes, isNotEmpty);
  });

  test('design system catalog route is debug-only', () {
    expect(kDebugMode, isTrue);
    expect(collectRoutePaths, contains('/dev/design-system'));
  });

  test('theme loads', () {
    expect(AppTheme.light(), isA<ThemeData>());
    expect(AppTheme.dark(), isA<ThemeData>());
  });

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

    expect(env.enableSmsReader, isFalse);
    expect(env.enableAndroidSmsAccess, isFalse);
    expect(env.enableAdminPanel, isFalse);
    expect(env.enableAdminDevTools, isFalse);
  });
}
