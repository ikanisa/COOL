import 'package:flutter_test/flutter_test.dart';

import 'package:cool_app/features/admin/providers/admin_workspace_access_provider.dart';
import 'package:cool_app/features/admin/screens/admin_dashboard_screen.dart';

import '../../integration_smoke/test_harness.dart';

void main() {
  group('AdminDashboardScreen role filtering', () {
    testWidgets('platform admin sees all dashboard cards', (tester) async {
      await pumpScopedApp(
        tester,
        child: const AdminDashboardScreen(),
        session: fakeSession(
          appMetadata: const <String, dynamic>{'is_admin': true},
        ),
        user: fakeUser(isAdmin: true),
      );

      await settleTestApp(tester);

      // Platform admin should see all cards including restricted ones
      expect(find.text('Admin Panel'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
      expect(find.text('Partners'), findsOneWidget);
      expect(find.text('Rayon Sports'), findsOneWidget);
      expect(find.text('Special Products'), findsOneWidget);
      expect(find.text('Admin Roles'), findsOneWidget);
      expect(find.text('System Analytics'), findsOneWidget);
      expect(find.text('Audit Log'), findsOneWidget);

      // Should show Platform Admin badge
      expect(find.text('Platform Admin'), findsOneWidget);
    });

    testWidgets('non-admin user sees no cards', (tester) async {
      await pumpScopedApp(
        tester,
        child: const AdminDashboardScreen(),
        session: fakeSession(),
        user: fakeUser(isAdmin: false),
      );

      await settleTestApp(tester);

      // Non-admin should see dashboard title but no cards
      expect(find.text('Admin Panel'), findsOneWidget);
      expect(find.text('Users'), findsNothing);
      expect(find.text('Partners'), findsNothing);
      expect(find.text('Rayon Sports'), findsNothing);
    });
  });
}
