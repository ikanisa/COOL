import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RejectedOtpRepository extends AdminEvidenceRepository {
  int sendCount = 0;
  @override
  Future<void> sendOtp({required String phone}) async => sendCount++;
  @override
  Future<AdminIdentity?> verifyOtp({
    required String phone,
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
      await tester.enterText(find.byType(TextField).first, '0788971001');
      await tester.tap(find.text('Send WhatsApp OTP'));
      await tester.pumpAndSettle();
      expect(repository.sendCount, 1);
      await tester.enterText(find.byType(TextField).last, '111111');
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'That code could not be verified. Check the latest WhatsApp code or request a new one.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resend WhatsApp OTP'));
      await tester.pumpAndSettle();
      expect(repository.sendCount, 2);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty,
      );
      expect(
        find.text(
          'That code could not be verified. Check the latest WhatsApp code or request a new one.',
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
