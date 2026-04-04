import 'package:cool_app/features/admin/models/admin_workspace_access.dart';
import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/providers/admin_workspace_access_provider.dart';
import 'package:cool_app/features/admin/screens/admin_workspaces_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: AdminWorkspacesScreen(),
    ),
  );
}

void main() {
  testWidgets('shows only assigned bank workspaces for scoped bank admins', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(<Override>[
        adminWorkspaceAccessProvider.overrideWithValue(
          const AdminWorkspaceAccess(
            hasBankAccess: true,
            bankAdminIds: {'bank-1'},
          ),
        ),
        adminPartnersProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'bank-1',
              'name': 'Equity Bank',
              'category': 'bank',
            },
            <String, dynamic>{
              'id': 'bank-2',
              'name': 'Urwego',
              'category': 'bank',
            },
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bank Workspaces'), findsOneWidget);
    expect(find.text('Equity Bank'), findsOneWidget);
    expect(find.text('Urwego'), findsNothing);
  });

  testWidgets('shows platform and bank sections for platform admins', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(<Override>[
        adminWorkspaceAccessProvider.overrideWithValue(
          const AdminWorkspaceAccess(hasPlatformAccess: true),
        ),
        adminPartnersProvider.overrideWith(
          (ref) async => <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'bank-1',
              'name': 'Equity Bank',
              'category': 'bank',
            },
          ],
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Platform Admin'), findsNWidgets(2));
    expect(find.text('Equity Bank'), findsOneWidget);
  });
}
