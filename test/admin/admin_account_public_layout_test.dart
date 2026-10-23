import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_account_pages.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _narrowSize = Size(320, 568);
const _invitationGuidance =
    'New to the team? Ask your super admin for an invitation, then sign in with your email.';

// Widget-unit stress only: these MediaQuery settings simulate enlarged text,
// high contrast and an IME inset. They do not prove browser zoom, a physical
// keyboard, browser accessibility output or hosted authentication.
Future<void> _mount(
  WidgetTester tester,
  Widget page, {
  required VoidCallback onApiResolution,
  double textScale = 1,
  bool highContrast = false,
  double keyboardInset = 0,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _narrowSize;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAccountApiProvider.overrideWith((ref) {
          onApiResolution();
          throw StateError('Blank layout cases must not resolve account API.');
        }),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: highContrast
            ? CollectTheme.highContrastDark()
            : CollectTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            highContrast: highContrast,
            viewInsets: EdgeInsets.only(bottom: keyboardInset),
          ),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  double keyboardInset = 0,
}) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(-0.5));
  expect(rect.right, lessThanOrEqualTo(_narrowSize.width + 0.5));
  expect(rect.top, greaterThanOrEqualTo(-0.5));
  expect(
    rect.bottom,
    lessThanOrEqualTo(_narrowSize.height - keyboardInset + 0.5),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    '320px enlarged login validates locally and scrolls to actions and full invitation guidance',
    (tester) async {
      var apiResolutions = 0;
      var signIns = 0;
      await _mount(
        tester,
        AdminAccountLoginPage(
          onSignedIn: () => signIns++,
          onForgotPassword: () {},
        ),
        textScale: 2,
        onApiResolution: () => apiResolutions++,
      );
      final submit = find.widgetWithText(FilledButton, 'Send sign-in code');
      await _reveal(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('admin-account-Password')),
        findsNothing,
      );
      final email = find.byKey(const Key('admin-account-email'));
      await _reveal(tester, email);
      expect(find.bySemanticsLabel(RegExp('Email address')), findsWidgets);
      final guidance = find.text(_invitationGuidance);
      await _reveal(tester, guidance);
      final scroll = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first;
      expect(
        tester.state<ScrollableState>(scroll).position.pixels,
        greaterThan(0),
      );
      expect(signIns, 0);
      expect(apiResolutions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px high-contrast enlarged recovery keeps invalid email and back action reachable',
    (tester) async {
      var apiResolutions = 0;
      var back = 0;
      await _mount(
        tester,
        AdminAccountForgotPasswordPage(onBackToLogin: () => back++),
        textScale: 2,
        highContrast: true,
        onApiResolution: () => apiResolutions++,
      );
      final submit = find.widgetWithText(FilledButton, 'Send reset email');
      await _reveal(tester, submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await _reveal(tester, find.byKey(const Key('admin-account-email')));
      expect(find.bySemanticsLabel(RegExp('Email address')), findsWidgets);
      await _reveal(tester, find.text('Enter a valid email address.'));
      final returnToLogin = find.widgetWithText(TextButton, 'Back to sign in');
      await _reveal(tester, returnToLogin);
      await tester.tap(returnToLogin);
      await tester.pumpAndSettle();
      expect(back, 1);
      expect(apiResolutions, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px simulated keyboard inset preserves email validation and footer reachability',
    (tester) async {
      const inset = 284.0;
      var apiResolutions = 0;
      await _mount(
        tester,
        AdminAccountLoginPage(onSignedIn: () {}, onForgotPassword: () {}),
        keyboardInset: inset,
        onApiResolution: () => apiResolutions++,
      );
      final email = find.byKey(const Key('admin-account-email'));
      await _reveal(tester, email, keyboardInset: inset);
      await tester.showKeyboard(email);
      await tester.enterText(email, 'invalid-email');
      await tester.pumpAndSettle();
      final editable = tester.widget<EditableText>(
        find.descendant(of: email, matching: find.byType(EditableText)),
      );
      expect(editable.keyboardType, TextInputType.emailAddress);
      expect(editable.controller.text, 'invalid-email');
      final submit = find.widgetWithText(FilledButton, 'Send sign-in code');
      await _reveal(tester, submit, keyboardInset: inset);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      await _reveal(
        tester,
        find.text('Enter a valid email address.'),
        keyboardInset: inset,
      );
      await _reveal(
        tester,
        find.text(_invitationGuidance),
        keyboardInset: inset,
      );
      expect(apiResolutions, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
