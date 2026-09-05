import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/auth/auth_screen.dart';
import 'package:collect_app/features/auth/widgets/auth_screen_widgets.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
}

void main() {
  testWidgets('phone confirmation scrolls to both choices at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 420);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: AuthPhoneConfirmationSheet(phone: '+250***3456'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Edit number'));
    await tester.pumpAndSettle();
    expect(find.text('Edit number').hitTestable(), findsOneWidget);
    expect(find.text('Confirm and send').hitTestable(), findsOneWidget);
  });
  for (final light in [false, true]) {
    testWidgets(
      'auth fields and sheets keep contrast in ${light ? 'light' : 'dark'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = light ? AppTheme.light() : AppTheme.dark();
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(theme: theme, home: const AuthScreen()),
          ),
        );
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(AuthScreen));
        final colors = context.collectColors;
        final phone = tester.widget<TextField>(
          find.byKey(const ValueKey('auth_whatsapp_phone_input')),
        );
        final country = tester.widget<Text>(find.text('+250'));
        expect(
          _contrast(phone.style!.color!, colors.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(country.style!.color!, colors.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
        if (light) {
          expect(
            _contrast(
              phone.decoration!.hintStyle!.color!,
              colors.surfaceRaised,
            ),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            tester
                .widget<Scaffold>(find.byType(Scaffold))
                .backgroundColor!
                .computeLuminance(),
            greaterThan(0.7),
          );
        }
        await tester.tap(
          find.byKey(const ValueKey('auth_country_code_picker')),
        );
        await tester.pumpAndSettle();
        final panel = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(AuthCountryPickerSheet),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(
          _contrast(colors.authForeground, panel.color),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);

        final otp = TextEditingController(text: '123456');
        addTearDown(otp.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: AuthOtpEntry(controller: otp, onChanged: () {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final otpField = tester.widget<TextField>(find.byType(TextField));
        expect(
          _contrast(otpField.style!.color!, colors.surfaceRaised),
          greaterThanOrEqualTo(4.5),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: AuthPhoneConfirmationSheet(phone: '+250***3456'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heading = tester.widget<Text>(find.text('Confirm your number'));
        expect(
          _contrast(heading.style!.color!, colors.authSheetSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
