import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/shared/widgets/cool_otp_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('calls onComplete when all digits are entered', (tester) async {
    String? completedCode;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CoolOtpField(
            autofocus: false,
            onComplete: (code) => completedCode = code,
          ),
        ),
      ),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(6));

    for (var index = 0; index < 6; index++) {
      await tester.enterText(fields.at(index), '${index + 1}');
      await tester.pump();
    }

    expect(completedCode, '123456');
  });

  testWidgets('controller clear empties all entered digits', (tester) async {
    final controller = CoolOtpController();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: CoolOtpField(
            controller: controller,
            autofocus: false,
            onComplete: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1');
    await tester.pump();
    await tester.enterText(fields.at(1), '2');
    await tester.pump();

    controller.clear(focusFirst: false);
    await tester.pump();

    for (var index = 0; index < 6; index++) {
      final textField = tester.widget<TextField>(fields.at(index));
      expect(textField.controller?.text ?? '', isEmpty);
    }
    expect(controller.value, isEmpty);
  });
}
