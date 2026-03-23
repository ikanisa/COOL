import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/core/services/screen_security_service.dart';
import 'package:cool_app/shared/widgets/secure_screen_mixin.dart';
import 'package:cool_app/shared/widgets/secure_screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeScreenSecurityService extends ScreenSecurityService {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enableSecureMode() async {
    enableCalls += 1;
  }

  @override
  Future<void> disableSecureMode() async {
    disableCalls += 1;
  }
}

void main() {
  testWidgets('toggles secure mode on mount and dispose', (tester) async {
    final service = FakeScreenSecurityService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          screenSecurityServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          home: SecureScreenWrapper(child: Text('Sensitive')),
        ),
      ),
    );
    await tester.pump();

    expect(service.enableCalls, 1);
    expect(service.disableCalls, 0);
    expect(find.text('Sensitive'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(service.enableCalls, 1);
    expect(service.disableCalls, 1);
  });

  testWidgets('SecureScreen delegates to the shared security service', (
    tester,
  ) async {
    final service = FakeScreenSecurityService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          screenSecurityServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(
          // ignore: deprecated_member_use_from_same_package
          home: SecureScreen(child: Text('Legacy sensitive')),
        ),
      ),
    );
    await tester.pump();

    expect(service.enableCalls, 1);
    expect(service.disableCalls, 0);
    expect(find.text('Legacy sensitive'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(service.enableCalls, 1);
    expect(service.disableCalls, 1);
  });
}
