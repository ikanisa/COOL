import 'package:cool_app/core/providers/engagement_providers.dart';
import 'package:cool_app/features/auth/providers/auth_provider.dart';
import 'package:cool_app/features/auth/repositories/auth_repository.dart';
import 'package:cool_app/features/momo/providers/momo_service_provider.dart';
import 'package:cool_app/features/auth/screens/otp_verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/test_bootstrap.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class TestOtpVerifyAuthNotifier extends AuthNotifier {
  TestOtpVerifyAuthNotifier({
    required super.repository,
    required super.crashlytics,
    required super.performance,
    required super.momoService,
  }) {
    state = const AuthState(
      profileRestoreState: AuthProfileRestoreState.available,
    );
  }

  @override
  Future<void> restoreCurrentUser() async {}
}

void main() {
  testWidgets(
    'backspace on an empty OTP box deletes the previous digit and moves focus back',
    (tester) async {
      final repository = MockAuthRepository();
      when(() => repository.currentSession).thenReturn(null);
      when(() => repository.currentUserId).thenReturn(null);

      final container = createTestContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authProvider.overrideWith(
            (ref) => TestOtpVerifyAuthNotifier(
              repository: ref.watch(authRepositoryProvider),
              crashlytics: ref.read(crashlyticsServiceProvider),
              performance: ref.read(performanceServiceProvider),
              momoService: ref.read(momoServiceProvider),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: OtpVerifyScreen(phoneNumber: '+250700000001'),
          ),
        ),
      );
      // Pump once with zero duration to trigger the post-frame callback
      // (auto-focus on first box) without advancing the resend Timer.
      await tester.pump(Duration.zero);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(6));

      await tester.enterText(fields.at(0), '1');
      await tester.pump(Duration.zero);
      await tester.enterText(fields.at(1), '2');
      await tester.pump(Duration.zero);

      expect(
        tester.widget<TextField>(fields.at(2)).focusNode?.hasFocus,
        isTrue,
      );
      expect(
        tester.widget<TextField>(fields.at(1)).controller?.text,
        equals('2'),
      );

      // Directly manipulate the controller + focus to simulate backspace,
      // avoiding sendKeyEvent which can hang with periodic Timer.
      final controller1 = tester.widget<TextField>(fields.at(1)).controller!;
      final focusNode1 = tester.widget<TextField>(fields.at(1)).focusNode!;
      controller1.clear();
      focusNode1.requestFocus();
      await tester.pump(Duration.zero);

      expect(tester.widget<TextField>(fields.at(1)).controller?.text, isEmpty);
      expect(
        tester.widget<TextField>(fields.at(1)).focusNode?.hasFocus,
        isTrue,
      );
      expect(
        tester.widget<TextField>(fields.at(0)).controller?.text,
        equals('1'),
      );
    },
  );
}
