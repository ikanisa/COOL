import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/screens/system_analytics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('renders analytics sections and audit metric', (tester) async {
    _configureTallViewport(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          platformAnalyticsProvider.overrideWith(
            (ref) async => <String, dynamic>{
              'total_users': 48,
              'real_users': 42,
              'mock_users': 6,
              'total_admins': 3,
              'total_partners': 5,
              'total_groups': 7,
              'active_groups': 6,
              'total_contributions': 29,
              'signups_7d': 11,
              'signups_30d': 37,
              'contributions_7d': 14,
              'active_partners': 4,
              'audit_actions_7d': 18,
              'role_distribution': <String, int>{
                'platform_admin': 2,
                'bank_admin': 1,
              },
              'event_distribution': <String, int>{
                'create': 9,
                'update': 6,
                'delete': 3,
              },
            },
          ),
        ],
        child: const MaterialApp(home: SystemAnalyticsScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('System Analytics'), findsOneWidget);
    expect(find.text('Core Counts'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Growth'), findsOneWidget);
    expect(find.text('platform_admin'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Event Distribution (30d)'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('create'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Admin Actions (7d)'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Audit'), findsOneWidget);
    expect(find.text('Admin Actions (7d)'), findsOneWidget);
    expect(find.text('18'), findsWidgets);
  });
}
