import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/features/rayon/models/rs_contribution_models.dart';
import 'package:cool_app/features/rayon/providers/rs_contribution_provider.dart';
import 'package:cool_app/features/rayon/screens/contribution_circles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_smoke/test_harness.dart';

void main() {
  List<Override> contributionOverrides() {
    return <Override>[
      myContributionGroupsProvider.overrideWith(
        (ref) async => const <RsContributionGroup>[],
      ),
      publicContributionGroupsProvider.overrideWith(
        (ref) async => const <RsContributionGroup>[],
      ),
    ];
  }

  group('ContributionCirclesScreen', () {
    testWidgets(
      'routes to wallet settings before create-group when profile MoMo is missing',
      (tester) async {
        await pumpRouterApp(
          tester,
          initialLocation: AppRoutes.contributionCircles,
          session: fakeSession(),
          user: fakeUser(momoNumber: '', momoCode: null),
          overrides: contributionOverrides(),
        );

        await settleTestApp(tester);

        await tester.tap(find.text('CREATE GROUP'));
        await settleTestApp(tester);

        expect(find.text('Wallet'), findsOneWidget);
      },
    );

    testWidgets('prefills group MoMo fields from the profile wallet', (
      tester,
    ) async {
      await pumpScopedApp(
        tester,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: false,
            splashFactory: NoSplash.splashFactory,
          ),
          home: const ContributionCirclesScreen(),
        ),
        session: fakeSession(),
        user: fakeUser(momoNumber: '0788123456', momoCode: '445566'),
        overrides: contributionOverrides(),
      );

      await settleTestApp(tester);

      await tester.tap(find.text('CREATE GROUP'));
      await settleTestApp(tester);

      expect(find.text('GROUP COLLECTION MOMO'), findsOneWidget);

      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields.length, greaterThanOrEqualTo(5));
      expect(fields[3].controller?.text, '0788123456');
      expect(fields[4].controller?.text, '445566');
    });
  });
}
