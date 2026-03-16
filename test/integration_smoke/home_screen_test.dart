import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/status/providers/home_status_providers.dart';
import 'package:cool_app/features/home/models/home_dashboard_data.dart';
import 'package:cool_app/features/home/models/quick_action.dart';
import 'package:cool_app/features/home/providers/home_dashboard_provider.dart';
import 'package:cool_app/features/home/providers/quick_action_provider.dart';
import 'package:cool_app/features/home/screens/home_screen.dart';
import 'package:cool_app/shared/widgets/cool_card.dart';

import 'test_harness.dart';

void main() {
  group('Home smoke', () {
    testWidgets(
      'groups quick actions into one quiet list and keeps the route to three primary cards',
      (tester) async {
        final originalErrorWidgetBuilder = ErrorWidget.builder;
        try {
          await pumpScopedApp(
            tester,
            child: const HomeScreen(),
            session: fakeSession(),
            user: fakeUser(),
            overrides: <Override>[
              homeDashboardProvider.overrideWith(
                (ref) async => HomeDashboardData(
                  totalBalance: 120000,
                  monthlyNetChange: 15000,
                  memberCount: 3,
                  recentTransactions: <HomeDashboardTransaction>[
                    HomeDashboardTransaction(
                      title: 'Contribution',
                      type: 'credit',
                      amount: 5000,
                      currency: 'RWF',
                      recordedAt: DateTime(2026, 3, 12, 10),
                    ),
                  ],
                ),
              ),
              currentCountryQuickActionsProvider.overrideWith(
                (ref) async => const <QuickAction>[
                  QuickAction(
                    id: 'groups',
                    title: 'Groups',
                    subtitle: 'Savings and invites',
                    route: '/groups',
                  ),
                  QuickAction(
                    id: 'momo',
                    title: 'MoMo',
                    subtitle: 'Pay and statements',
                    route: '/momo',
                  ),
                  QuickAction(
                    id: 'partners',
                    title: 'Partners',
                    subtitle: 'Tickets and support',
                    route: '/partners',
                  ),
                  QuickAction(
                    id: 'mobility',
                    title: 'Mobility',
                    subtitle: 'Trips and drivers',
                    route: '/mobility',
                  ),
                ],
              ),
              activeSeasonProvider.overrideWith((ref) async => null),
              questsProvider.overrideWith((ref) => const []),
            ],
          );

          await settleTestApp(tester);

          expect(find.text('Home'), findsOneWidget);
          expect(find.text('Quick Actions'), findsOneWidget);
          expect(find.text('Recent Activity'), findsOneWidget);
          expect(find.byType(CoolCard), findsNWidgets(3));
          expect(find.text('Groups'), findsWidgets);
          expect(find.text('MoMo'), findsOneWidget);
          expect(find.text('Partners'), findsOneWidget);
          expect(find.text('Trips'), findsOneWidget);
        } finally {
          ErrorWidget.builder = originalErrorWidgetBuilder;
        }
      },
    );

    testWidgets(
      'shows a group-start recommendation for users without activity',
      (tester) async {
        final originalErrorWidgetBuilder = ErrorWidget.builder;
        try {
          await pumpScopedApp(
            tester,
            child: const HomeScreen(),
            session: fakeSession(),
            user: fakeUser(),
            overrides: <Override>[
              homeDashboardProvider.overrideWith(
                (ref) async => const HomeDashboardData(
                  totalBalance: 0,
                  monthlyNetChange: 0,
                  memberCount: 0,
                  recentTransactions: <HomeDashboardTransaction>[],
                ),
              ),
              currentCountryQuickActionsProvider.overrideWith(
                (ref) async => const <QuickAction>[
                  QuickAction(
                    id: 'groups',
                    title: 'Groups',
                    subtitle: 'Savings and invites',
                    route: '/groups',
                  ),
                ],
              ),
              activeSeasonProvider.overrideWith((ref) async => null),
              questsProvider.overrideWith((ref) => const []),
            ],
          );

          await settleTestApp(tester);

          expect(find.text('Activity will appear here.'), findsOneWidget);
          expect(find.text('Groups'), findsWidgets);
        } finally {
          ErrorWidget.builder = originalErrorWidgetBuilder;
        }
      },
    );
  });
}
