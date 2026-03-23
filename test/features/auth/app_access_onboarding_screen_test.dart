import 'package:cool_app/core/providers/app_access_provider.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/features/auth/screens/app_access_onboarding_screen.dart';
import 'package:cool_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_app_access_service.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  testWidgets('updates ready count after allowing a permission', (
    tester,
  ) async {
    final service = FakeAppAccessService(
      snapshots: <AppAccessPermission, AppAccessSnapshot>{
        AppAccessPermission.sms: const AppAccessSnapshot(
          permission: AppAccessPermission.sms,
          kind: AppAccessStateKind.ready,
          enabledInApp: true,
          supportedOnDevice: true,
          systemGranted: true,
        ),
        for (final permission in AppAccessPermission.values)
          if (permission != AppAccessPermission.sms)
            permission: AppAccessSnapshot(
              permission: permission,
              kind: AppAccessStateKind.disabledInApp,
              enabledInApp: false,
              supportedOnDevice: true,
            ),
      },
    );

    final container = createTestContainer(
      overrides: [appAccessServiceProvider.overrideWithValue(service)],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: AppAccessOnboardingScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/6 ready'), findsOneWidget);
    expect(find.text('App Access'), findsOneWidget);

    await tester.tap(find.text('Allow').first);
    await tester.pumpAndSettle();

    expect(find.text('2/6 ready'), findsOneWidget);
  });
}
