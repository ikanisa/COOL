import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/core/router/app_routes.dart';
import 'package:cool_app/features/admin/providers/admin_workspace_access_provider.dart';
import 'package:cool_app/features/partners/models/partner.dart';

import 'test_harness.dart';

void main() {
  const rayonPartner = Partner(
    id: 'partner-rayon',
    name: 'Rayon Sports',
    slug: 'rayon-sports',
    category: PartnerCategory.football,
    country: 'RW',
  );

  testWidgets('partner admin can open the admin workspace launcher', (
    tester,
  ) async {
    await pumpRouterApp(
      tester,
      initialLocation: AppRoutes.admin,
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'partner_admin_ids': ['partner-rayon'],
        },
      ),
      user: fakeUser(),
      overrides: [
        adminPartnerWorkspacesProvider.overrideWith(
          (ref) async => const <Partner>[rayonPartner],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Admin Workspaces'), findsOneWidget);
    expect(find.text('Rayon Sports'), findsOneWidget);
  });

  testWidgets('partner admin is redirected away from platform admin routes', (
    tester,
  ) async {
    await pumpRouterApp(
      tester,
      initialLocation: AppRoutes.adminPlatform,
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'partner_admin_ids': ['partner-rayon'],
        },
      ),
      user: fakeUser(),
      overrides: [
        adminPartnerWorkspacesProvider.overrideWith(
          (ref) async => const <Partner>[rayonPartner],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Admin Workspaces'), findsOneWidget);
    expect(find.text('Admin Panel'), findsNothing);
  });
}
