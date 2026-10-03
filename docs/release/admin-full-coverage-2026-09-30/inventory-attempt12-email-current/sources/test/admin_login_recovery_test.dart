import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RejectedOtpRepository extends AdminEvidenceRepository {
  int sendCount = 0;
  @override
  Future<void> sendEmailOtp({required String email}) async => sendCount++;
  @override
  Future<AdminIdentity?> verifyEmailOtp({
    required String email,
    required String otp,
  }) => Future.error(StateError('Token has expired or is invalid'));
}

void main() {
  testWidgets(
    'invalid OTP is not misreported as definitely used; resend clears it',
    (tester) async {
      final repository = _RejectedOtpRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adminRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AdminLoginPage(),
          ),
        ),
      );
      await tester.enterText(
        find.byType(TextField).first,
        'operator@collect.example',
      );
      await tester.tap(find.text('Send email OTP'));
      await tester.pumpAndSettle();
      expect(repository.sendCount, 1);
      await tester.enterText(find.byType(TextField).last, '111111');
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'That code could not be verified. Use the latest email code or request a new one.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Resend email OTP'));
      await tester.tap(find.text('Resend email OTP'));
      await tester.pumpAndSettle();
      expect(repository.sendCount, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      expect(
        find.text(
          'That code could not be verified. Use the latest email code or request a new one.',
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
