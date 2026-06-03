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

    expect(find.text('Good morning'), findsWidgets);
    expect(find.text('TOTAL COLLECTED'), findsOneWidget);
    expect(find.text('Platform admin'), findsNothing);
    expect(find.textContaining('BioPay'), findsNothing);
    expect(find.textContaining('wallet'), findsNothing);
  });

  testWidgets('unknown routes render branded recovery actions', (tester) async {
    final router = createAppRouter(initialLocation: '/missing-route');
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
    await tester.pump();

    expect(find.text('Screen not found'), findsOneWidget);
    expect(find.textContaining('verified groups'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
  });

  test('main Collect routes are registered', () {
    expect(
      collectRoutePaths,
      containsAll(<String>[
        '/auth',
        '/auth/success',
        '/auth/failure',
        '/onboarding',
        '/home',
        '/offline',
        '/sync',
        '/permissions/sms',
        '/permissions/sms-denied',
        '/permissions/device',
        '/platform/iphone-create-unavailable',
        '/groups',
        '/groups/create',
        '/groups/:collectionId',
        '/groups/:collectionId/created',
        '/groups/:collectionId/joined',
        '/groups/:collectionId/members',
        '/groups/:collectionId/owner',
        '/groups/:collectionId/owner/sms-health',
        '/groups/:collectionId/owner/receiver',
        '/groups/:collectionId/manage',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId/waiting',
        '/groups/:collectionId/pay/:intentId/state/:state',
        '/groups/:collectionId/pay/:intentId',
        '/groups/:collectionId/share',
        '/groups/:collectionId/invite',
        '/groups/:collectionId/ledger',
        '/c/:slug',
        '/share/invalid',
        '/share/expired',
        '/settings',
        '/settings/profile',
        '/settings/readiness',
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
