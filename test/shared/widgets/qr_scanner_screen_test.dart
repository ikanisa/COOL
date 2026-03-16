import 'package:cool_app/core/providers/app_access_provider.dart';
import 'package:cool_app/core/services/app_access_service.dart';
import 'package:cool_app/shared/widgets/qr_scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_app_access_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows the in-app camera gate before scanner startup', (
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
            kind: permission == AppAccessPermission.camera
                ? AppAccessStateKind.disabledInApp
                : AppAccessStateKind.ready,
            enabledInApp: permission != AppAccessPermission.camera,
            supportedOnDevice: true,
            systemGranted: permission != AppAccessPermission.camera,
          ),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAccessServiceProvider.overrideWithValue(appAccessService),
        ],
        child: const MaterialApp(home: QrScannerScreen(mode: QrScanMode.momo)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Camera is off in COOL'), findsOneWidget);
    expect(find.text('Enable Camera'), findsOneWidget);
    expect(
      find.text(
        'Turn camera access back on to scan MoMo QR codes or signed tickets.',
      ),
      findsOneWidget,
    );
  });
}
