import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/shared/widgets/contact_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_app_access_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the in-app contacts access gate before any OS prompt', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 2560);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appAccessService = FakeAppAccessService(
      snapshots: {
        for (final permission in AppAccessPermission.values)
          permission: AppAccessSnapshot(
            permission: permission,
            kind: permission == AppAccessPermission.contacts
                ? AppAccessStateKind.disabledInApp
                : AppAccessStateKind.ready,
            enabledInApp: permission != AppAccessPermission.contacts,
            supportedOnDevice: true,
            systemGranted: permission != AppAccessPermission.contacts,
          ),
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  ContactPickerSheet.show(
                    context,
                    appAccessService: appAccessService,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Contacts are off'), findsOneWidget);
    expect(find.text('Enable Contacts'), findsOneWidget);
    expect(find.textContaining('Contacts access is currently'), findsOneWidget);
  });
}
