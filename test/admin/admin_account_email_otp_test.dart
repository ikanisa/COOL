import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_account_pages.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _receipt = AdminEmailOtpReceipt(
  challengeId: 'email-challenge-one',
  retryAfterSeconds: 60,
  expiresInSeconds: 300,
);
const _captureKey = ValueKey('admin-auth-capture');

Future<void> _capture(WidgetTester tester, String name) async {
  final output = Platform.environment['COLLECT_ADMIN_AUTH_SCREENSHOTS'];
  if (output == null || output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _EmailApi implements AdminAccountApi, AdminEmailOtpAccountApi {
  final sent = <String>[];
  final verified = <({String email, String challenge, String code})>[];
  Object? sendFailure;
  Object? verifyFailure;
  Completer<void>? verifying;

  @override
  Future<AdminEmailOtpReceipt> requestEmailOtp(String email) async {
    sent.add(email);
    if (sendFailure case final failure?) throw failure;
    return _receipt;
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    verified.add((email: email, challenge: challengeId, code: code));
    if (verifyFailure case final failure?) throw failure;
    await verifying?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester,
  _EmailApi api, {
  VoidCallback? signedIn,
  bool enlarged = false,
  bool desktop = false,
}) async {
  if (enlarged || desktop) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = desktop
        ? const Size(1280, 900)
        : const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminAccountApiProvider.overrideWithValue(api)],
      child: RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: CollectTheme.dark(),
          builder: enlarged
              ? (_, child) => MediaQuery(
                  data: const MediaQueryData(
                    size: Size(320, 568),
                    textScaler: TextScaler.linear(2),
                  ),
                  child: child!,
                )
              : null,
          home: AdminAccountLoginPage(
            onSignedIn: signedIn ?? () {},
            onForgotPassword: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
}

Future<void> _send(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('admin-account-email')),
    ' Teammate@Collect.Example ',
  );
  final button = find.widgetWithText(FilledButton, 'Send sign-in code');
  await tester.ensureVisible(button);
  await tester.tap(button);
  // Unknown-email dialog keeps the request pending until dismissed.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
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
    'email-only entry sends normalized email then verifies bound code',
    (tester) async {
      final api = _EmailApi();
      var signIns = 0;
      await _mount(tester, api, signedIn: () => signIns++);
      expect(
        find.byKey(const ValueKey('admin-account-Password')),
        findsNothing,
      );
      expect(find.text('Forgot password?'), findsNothing);
      await _send(tester);
      expect(api.sent, ['teammate@collect.example']);
      expect(signIns, 0);
      final code = find.byKey(const Key('admin-account-email-code'));
      expect(code, findsOneWidget);
      final field = tester.widget<TextField>(
        find.descendant(of: code, matching: find.byType(TextField)),
      );
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
      await tester.enterText(code, '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify and sign in'));
      await tester.pumpAndSettle();
      expect(api.verified.single, (
        email: 'teammate@collect.example',
        challenge: 'email-challenge-one',
        code: '123456',
      ));
      expect(signIns, 1);
    },
  );

  testWidgets('unlisted email opens contact-super-admin exception popup', (
    tester,
  ) async {
    final api = _EmailApi()
      ..sendFailure = const AdminAccountAccessNotApproved();
    await _mount(tester, api);
    await _send(tester);
    expect(find.byKey(const Key('admin-access-not-approved')), findsOneWidget);
    expect(find.text('Contact your super admin'), findsOneWidget);
    expect(find.byKey(const Key('admin-account-email-code')), findsNothing);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(api.verified, isEmpty);
    expect(
      find.widgetWithText(FilledButton, 'Send sign-in code'),
      findsOneWidget,
    );
  });

  testWidgets(
    'malformed email and short OTP never reach corresponding service',
    (tester) async {
      final api = _EmailApi();
      await _mount(tester, api);
      await tester.enterText(
        find.byKey(const Key('admin-account-email')),
        'a..b@test.example',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Send sign-in code'));
      await tester.pumpAndSettle();
      expect(api.sent, isEmpty);
      await _send(tester);
      await tester.enterText(
        find.byKey(const Key('admin-account-email-code')),
        '123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Verify and sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the 6-digit email code.'), findsOneWidget);
      expect(api.verified, isEmpty);
    },
  );

  testWidgets('uncertain email retains challenge without an automatic resend', (
    tester,
  ) async {
    final api = _EmailApi()
      ..sendFailure = const AdminEmailOtpDeliveryUnknown(_receipt);
    var signIns = 0;
    await _mount(tester, api, signedIn: () => signIns++);
    await _send(tester);
    expect(
      find.textContaining('Email delivery could not be confirmed.'),
      findsOneWidget,
    );
    expect(api.sent, hasLength(1));
    await tester.enterText(
      find.byKey(const Key('admin-account-email-code')),
      '123456',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Verify and sign in'));
    await tester.pumpAndSettle();
    expect(api.sent, hasLength(1));
    expect(signIns, 1);
  });

  testWidgets('resend clears old code and change-email returns to email task', (
    tester,
  ) async {
    final api = _EmailApi();
    await _mount(tester, api);
    await _send(tester);
    final resend = find.byKey(const Key('admin-account-resend-code'));
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('admin-account-email-code')),
      '123456',
    );
    await tester.pump(const Duration(seconds: 61));
    await tester.tap(resend);
    await tester.pumpAndSettle();
    expect(api.sent, hasLength(2));
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('admin-account-email-code')),
          )
          .controller!
          .text,
      isEmpty,
    );
    final changeEmail = find.text('Use a different email');
    await tester.ensureVisible(changeEmail);
    await tester.tap(changeEmail);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-account-email')), findsOneWidget);
    expect(find.byKey(const Key('admin-account-email-code')), findsNothing);
    expect(api.verified, isEmpty);
  });

  testWidgets(
    'desktop email, OTP and denied access states can be captured with real fonts',
    (tester) async {
      final api = _EmailApi();
      await _mount(tester, api, desktop: true);
      await _capture(tester, 'admin-email-entry');
      await _send(tester);
      await _capture(tester, 'admin-email-code');
      final change = find.text('Use a different email');
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      api.sendFailure = const AdminAccountAccessNotApproved();
      await _send(tester);
      expect(
        find.byKey(const Key('admin-access-not-approved')),
        findsOneWidget,
      );
      final dialogSurface = find.descendant(
        of: find.byKey(const Key('admin-access-not-approved')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.type == MaterialType.card,
        ),
      );
      expect(dialogSurface, findsOneWidget);
      expect(tester.getSize(dialogSurface).width, lessThanOrEqualTo(480));
      await _capture(tester, 'admin-email-access-denied');
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(api.verified, isEmpty);
    },
  );

  for (final failure in [
    const AdminAccountException(
      'Too many attempts. Please wait before trying again.',
    ),
    StateError('Network response lost'),
    const AdminAccountAccessNotApproved(),
  ]) {
    testWidgets(
      'receiptless resend ${failure.runtimeType} returns to email with no stale code',
      (tester) async {
        final api = _EmailApi();
        await _mount(tester, api);
        await _send(tester);
        await tester.enterText(
          find.byKey(const Key('admin-account-email-code')),
          '123456',
        );
        await tester.pump(const Duration(seconds: 61));
        api.sendFailure = failure;
        final resend = find.byKey(const Key('admin-account-resend-code'));
        await tester.ensureVisible(resend);
        await tester.tap(resend);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        if (failure is AdminAccountAccessNotApproved) {
          expect(
            find.byKey(const Key('admin-access-not-approved')),
            findsOneWidget,
          );
          await tester.tap(find.text('Got it'));
        }
        await tester.pumpAndSettle();
        expect(api.sent, hasLength(2));
        expect(find.byKey(const Key('admin-account-email-code')), findsNothing);
        expect(find.byKey(const Key('admin-account-email')), findsOneWidget);
        expect(api.verified, isEmpty);
        if (failure is! AdminAccountAccessNotApproved) {
          expect(
            find.textContaining(
              failure is AdminAccountException
                  ? 'Too many attempts.'
                  : 'Check your connection and try again.',
            ),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets('uncertain resend with a new receipt keeps usable code entry', (
    tester,
  ) async {
    final api = _EmailApi();
    await _mount(tester, api);
    await _send(tester);
    await tester.pump(const Duration(seconds: 61));
    api.sendFailure = const AdminEmailOtpDeliveryUnknown(_receipt);
    final resend = find.byKey(const Key('admin-account-resend-code'));
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-account-email-code')), findsOneWidget);
    expect(
      find.textContaining('Email delivery could not be confirmed.'),
      findsOneWidget,
    );
    expect(api.sent, hasLength(2));
    expect(api.verified, isEmpty);
  });

  testWidgets(
    'pending verification disables account switch and cannot navigate after disposal',
    (tester) async {
      final pending = Completer<void>();
      final api = _EmailApi()..verifying = pending;
      var signIns = 0;
      await _mount(tester, api, signedIn: () => signIns++);
      await _send(tester);
      await tester.enterText(
        find.byKey(const Key('admin-account-email-code')),
        '123456',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Verify and sign in'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Use a different email'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pump();
      expect(signIns, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px enlarged OTP keeps errors and change-email action reachable',
    (tester) async {
      final api = _EmailApi();
      await _mount(tester, api, enlarged: true);
      await _send(tester);
      final submit = find.widgetWithText(FilledButton, 'Verify and sign in');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.text('Enter the 6-digit email code.'), findsOneWidget);
      final change = find.text('Use a different email');
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-account-email')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
