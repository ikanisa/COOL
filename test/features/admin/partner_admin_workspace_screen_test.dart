import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/admin/providers/admin_workspace_access_provider.dart';
import 'package:cool_app/features/admin/screens/partner_admin_workspace_screen.dart';
import 'package:cool_app/features/partners/models/partner.dart';
import 'package:cool_app/features/partners/providers/partner_provider.dart';

import '../../integration_smoke/test_harness.dart';

void main() {
  const genericPartner = Partner(
    id: 'partner-ops',
    name: 'Apex Services',
    slug: 'apex-services',
    category: PartnerCategory.organization,
    country: 'RW',
    emoji: '🛠️',
    description: 'Operations and field-service partner',
  );

  const rayonPartner = Partner(
    id: 'partner-rayon',
    name: 'Rayon Sports',
    slug: 'rayon-sports',
    category: PartnerCategory.football,
    country: 'RW',
    emoji: '💙',
  );

  testWidgets('generic partner workspace shows launch placeholder', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const PartnerAdminWorkspaceScreen(partnerId: 'partner-ops'),
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'partner_admin_ids': ['partner-ops'],
        },
      ),
      user: fakeUser(fullName: 'Partner Admin'),
      overrides: [
        partnerByIdProvider(
          'partner-ops',
        ).overrideWith((ref) async => genericPartner),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Apex Services'), findsWidgets);
    expect(find.text('Workspace launch sequence'), findsOneWidget);
    expect(find.text('Dedicated partner command center'), findsOneWidget);
    expect(find.bySemanticsLabel('Back to workspaces'), findsOneWidget);
  });

  testWidgets('rayon partner workspace forwards into the dedicated admin hub', (
    tester,
  ) async {
    await pumpScopedApp(
      tester,
      child: const PartnerAdminWorkspaceScreen(partnerId: 'partner-rayon'),
      session: fakeSession(
        appMetadata: const <String, dynamic>{
          'partner_admin_ids': ['partner-rayon'],
        },
      ),
      user: fakeUser(fullName: 'Club Admin'),
      overrides: [
        partnerByIdProvider(
          'partner-rayon',
        ).overrideWith((ref) async => rayonPartner),
        rayonAdminAccessProvider.overrideWith((ref) async => true),
      ],
    );

    await settleTestApp(tester);

    expect(find.text('Rayon Sports Admin'), findsWidgets);
    expect(find.text('Dedicated command routing'), findsOneWidget);
    expect(find.bySemanticsLabel('Open Rayon Sports Admin'), findsOneWidget);
  });
}
