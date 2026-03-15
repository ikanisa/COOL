import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/admin/providers/admin_workspace_access_provider.dart';
import 'package:cool_app/features/admin/screens/admin_workspaces_screen.dart';
import 'package:cool_app/features/partners/models/partner.dart';

import '../../integration_smoke/test_harness.dart';

void main() {
  const rayonPartner = Partner(
    id: 'partner-rayon',
    name: 'Rayon Sports',
    slug: 'rayon-sports',
    category: PartnerCategory.football,
    country: 'RW',
  );
  const bankPartner = Partner(
    id: 'bank-1',
    name: 'Custody Bank',
    slug: 'custody-bank',
    category: PartnerCategory.bank,
    country: 'RW',
  );

  testWidgets('shows partner and bank workspaces for scoped admin accounts', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const AdminWorkspacesScreen(),
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'partner_admin_ids': ['partner-rayon'],
          'bank_admin_ids': ['bank-1'],
        },
      ),
      user: fakeUser(),
      overrides: [
        adminPartnerWorkspacesProvider.overrideWith(
          (ref) async => const <Partner>[rayonPartner],
        ),
        adminBankWorkspacesProvider.overrideWith(
          (ref) async => const <Partner>[bankPartner],
        ),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Admin Workspaces'), findsOneWidget);
    expect(find.text('Partner Workspaces'), findsOneWidget);
    expect(find.text('Bank Custodian Workspaces'), findsOneWidget);
    expect(find.text('Rayon Sports'), findsOneWidget);
    expect(find.text('Custody Bank'), findsOneWidget);
    expect(find.text('Platform Admin'), findsNothing);
  });
}
