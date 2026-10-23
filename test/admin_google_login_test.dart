import 'dart:async';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_account_pages.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_types.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _googleKey = Key('admin-account-google-sign-in');
const _cancelKey = Key('admin-account-cancel-google');
const _emailKey = Key('admin-account-email');
const _noAccessKey = Key('admin-access-not-approved');
const _checkSessionKey = Key('admin-account-check-session');
const _unknownMessage =
    'Google sign-in could not be confirmed. Check your session before starting a fresh sign-in.';
const _popupBlockedMessage =
    'Allow the sign-in window in your browser, then try Google again.';
const _genericMessage =
    'Google sign-in could not finish. Try again or use your email.';
const _signedOutMessage = 'No active session was found. Sign in again.';
const _checkFailureMessage =
    'Your session could not be checked. Try Check session again.';

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
    'disabled Google build flag keeps blank and invalid email validation local',
    (tester) async {
      var apiResolutions = 0;
      var routeChecks = 0;
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminAccountApiProvider.overrideWith((ref) {
              apiResolutions++;
              throw StateError(
                'Local validation must not resolve account API.',
              );
            }),
          ],
          child: MaterialApp(
            theme: CollectTheme.dark(),
            home: AdminAccountLoginPage(
              googleSignInEnabled: false,
              onSignedIn: () => routeChecks++,
              onForgotPassword: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(apiResolutions, 0);
      expect(find.byKey(_googleKey), findsNothing);
      await _tap(tester, _emailSendButton());
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(apiResolutions, 0);
      await tester.enterText(find.byKey(_emailKey), 'not-an-email');
      await _tap(tester, _emailSendButton());
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(apiResolutions, 0);
      expect(routeChecks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final hasGoogleInterface in [false, true]) {
    testWidgets(
      'Google stays hidden when its ${hasGoogleInterface ? 'capability is disabled' : 'optional interface is absent'}',
      (tester) async {
        final _EmailApi api = hasGoogleInterface
            ? _GoogleApi(available: false)
            : _EmailApi();
        await _mount(tester, api);
        expect(find.byKey(_googleKey), findsNothing);
        expect(find.text('Continue with Google'), findsNothing);
        expect(find.byKey(_cancelKey), findsNothing);
        expect(find.byKey(_emailKey), findsOneWidget);
        expect(_emailSendButton(), findsOneWidget);
        expect(api.emailRequests, isEmpty);
        expect(api.passwordRequests, 0);
        if (api is _GoogleApi) expect(api.attempts, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Google starts without email validation and blocks competing email submission until success',
    (tester) async {
      final api = _GoogleApi();
      var signedIn = 0;
      await _mount(tester, api, onSignedIn: () => signedIn++);
      expect(
        tester.widget<TextFormField>(find.byKey(_emailKey)).controller!.text,
        isEmpty,
      );
      await _startGoogle(tester);
      expect(api.attempts, hasLength(1));
      expect(api.authorizers, hasLength(1));
      expect(find.text('Enter a valid email address.'), findsNothing);
      _expectPending(tester);
      expect(api.emailRequests, isEmpty);
      expect(api.emailVerifications, 0);
      expect(api.passwordRequests, 0);
      expect(signedIn, 0);

      await _tap(tester, find.byKey(_googleKey), settle: false);
      expect(api.attempts, hasLength(1));
      api.attempts.single.complete();
      await tester.pumpAndSettle();
      expect(signedIn, 1);
      expect(find.byKey(_cancelKey), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(signedIn, 1);
      expect(api.attempts, hasLength(1));
      expect(api.emailRequests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Google account without Admin access opens the existing guidance',
    (tester) async {
      final api = _GoogleApi();
      var signedIn = 0;
      await _mount(tester, api, onSignedIn: () => signedIn++);
      await _startGoogle(tester);
      api.attempts.single.completeError(const AdminAccountAccessNotApproved());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(_noAccessKey), findsOneWidget);
      expect(find.text('Contact your super admin'), findsOneWidget);
      expect(signedIn, 0);
      await _tap(tester, find.text('Got it'));
      expect(find.byKey(_noAccessKey), findsNothing);
      expect(find.byKey(_emailKey), findsOneWidget);
      expect(api.attempts, hasLength(1));
      expect(api.emailRequests, isEmpty);
      expect(signedIn, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown Google outcome locks fresh sign-in and exposes session recovery without replaying',
    (tester) async {
      final api = _GoogleApi();
      var routeChecks = 0;
      await _mountUnknown(tester, api, onSignedIn: () => routeChecks++);
      expect(find.text(_unknownMessage), findsOneWidget);
      expect(find.textContaining('PRIVATE_'), findsNothing);
      _expectUnknownLocked(tester);
      final email = tester.widget<TextFormField>(find.byKey(_emailKey));
      expect(email.controller!.text, 'operator@collect.example');
      expect(find.byKey(_cancelKey), findsNothing);
      expect(find.text('Check session'), findsOneWidget);
      expect(routeChecks, 0);

      await _tap(tester, find.byKey(_googleKey));
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(api.attempts, hasLength(1));
      expect(api.sessionChecks, isEmpty);
      expect(api.emailRequests, isEmpty);
      expect(api.emailVerifications, 0);
      expect(api.passwordRequests, 0);
      expect(routeChecks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmed signed-out recheck clears an unknown email verification receipt before a fresh send',
    (tester) async {
      final api = _GoogleApi()
        ..emailVerificationFailure = const AdminAccountSecurityOutcomeUnknown(
          'Email verification could not be confirmed.',
        );
      var routeChecks = 0;
      await _mount(tester, api, onSignedIn: () => routeChecks++);
      await tester.enterText(find.byKey(_emailKey), 'Operator@Collect.Example');
      await _tap(tester, _emailSendButton());
      expect(api.emailRequests, ['operator@collect.example']);
      final code = find.byKey(const Key('admin-account-email-code'));
      await tester.enterText(code, '123456');
      final oldCode = tester.widget<TextFormField>(code).controller!;
      await _tap(
        tester,
        find.widgetWithText(FilledButton, 'Verify and sign in'),
      );
      expect(api.emailVerifications, 1);
      expect(find.byKey(_checkSessionKey), findsOneWidget);
      expect(find.text('Check session'), findsOneWidget);
      expect(tester.widget<TextFormField>(code).enabled, isFalse);
      expect(oldCode.text, '123456');
      expect(find.text('Verify and sign in'), findsNothing);
      expect(find.byKey(_googleKey), findsNothing);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('admin-account-resend-code')),
            )
            .onPressed,
        isNull,
      );
      expect(api.attempts, isEmpty);
      expect(api.sessionChecks, isEmpty);

      await _tap(tester, find.byKey(_checkSessionKey), settle: false);
      expect(api.sessionChecks, hasLength(1));
      api.sessionChecks.single.complete(false);
      await tester.pumpAndSettle();
      expect(find.text(_signedOutMessage), findsOneWidget);
      expect(find.byKey(_checkSessionKey), findsNothing);
      expect(code, findsNothing);
      expect(find.text('Verify and sign in'), findsNothing);
      expect(find.byKey(const Key('admin-account-resend-code')), findsNothing);
      expect(oldCode.text, isEmpty);
      final email = tester.widget<TextFormField>(find.byKey(_emailKey));
      expect(email.enabled, isTrue);
      expect(email.controller!.text, 'Operator@Collect.Example');
      expect(_emailSendButton(), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_emailSendButton()).onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(find.byKey(_emailKey), findsOneWidget);
      expect(code, findsNothing);
      expect(find.text('Verify and sign in'), findsNothing);
      expect(api.emailRequests, ['operator@collect.example']);
      expect(api.emailVerifications, 1);
      expect(api.sessionChecks, hasLength(1));
      expect(api.attempts, isEmpty);
      expect(api.authorizers, isEmpty);
      expect(api.passwordRequests, 0);
      expect(routeChecks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final outcome in ['authenticated', 'signed out', 'uncertain']) {
    testWidgets(
      'explicit Google session check handles $outcome without replaying authentication',
      (tester) async {
        final api = _GoogleApi();
        var routeChecks = 0;
        await _mountUnknown(tester, api, onSignedIn: () => routeChecks++);
        expect(api.sessionChecks, isEmpty);
        await _tap(tester, find.byKey(_checkSessionKey), settle: false);
        expect(api.sessionChecks, hasLength(1));
        _expectUnknownLocked(tester);
        expect(
          tester.widget<FilledButton>(find.byKey(_checkSessionKey)).onPressed,
          isNull,
        );
        await _tap(tester, find.byKey(_checkSessionKey), settle: false);
        await _tap(tester, find.byKey(_googleKey), settle: false);
        expect(api.sessionChecks, hasLength(1));
        expect(api.attempts, hasLength(1));
        expect(api.emailRequests, isEmpty);
        expect(api.passwordRequests, 0);
        expect(routeChecks, 0);

        if (outcome == 'uncertain') {
          api.sessionChecks.single.completeError(
            StateError('PRIVATE_SESSION_CHECK_DETAIL'),
          );
        } else {
          api.sessionChecks.single.complete(outcome == 'authenticated');
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('PRIVATE_'), findsNothing);
        expect(api.attempts, hasLength(1));
        expect(api.emailRequests, isEmpty);
        expect(api.emailVerifications, 0);
        expect(api.passwordRequests, 0);

        if (outcome == 'authenticated') {
          expect(routeChecks, 1);
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(routeChecks, 1);
          expect(api.sessionChecks, hasLength(1));
        } else if (outcome == 'signed out') {
          expect(routeChecks, 0);
          expect(find.text(_signedOutMessage), findsOneWidget);
          expect(find.text(_unknownMessage), findsNothing);
          expect(find.byKey(_checkSessionKey), findsNothing);
          expect(
            tester.widget<TextFormField>(find.byKey(_emailKey)).enabled,
            isTrue,
          );
          expect(
            tester.widget<FilledButton>(_emailSendButton()).onPressed,
            isNotNull,
          );
          expect(_googleActionButton(tester).onPressed, isNotNull);
          await _startGoogle(tester);
          expect(api.attempts, hasLength(2));
          api.attempts.last.completeError(
            const CollectAuthException('Cancelled', code: 'google_cancelled'),
          );
          await tester.pumpAndSettle();
          expect(routeChecks, 0);
          expect(api.sessionChecks, hasLength(1));
        } else {
          expect(routeChecks, 0);
          expect(find.text(_checkFailureMessage), findsOneWidget);
          _expectUnknownLocked(tester);
          await _tap(tester, find.byKey(_googleKey));
          await tester.pump(const Duration(seconds: 61));
          await tester.pumpAndSettle();
          expect(api.attempts, hasLength(1));
          expect(api.sessionChecks, hasLength(1));
          expect(api.emailRequests, isEmpty);

          await _tap(tester, find.byKey(_checkSessionKey), settle: false);
          expect(api.sessionChecks, hasLength(2));
          api.sessionChecks.last.complete(false);
          await tester.pumpAndSettle();
          expect(routeChecks, 0);
          expect(find.text(_signedOutMessage), findsOneWidget);
          expect(find.byKey(_checkSessionKey), findsNothing);
          expect(_googleActionButton(tester).onPressed, isNotNull);
          expect(api.attempts, hasLength(1));
          expect(api.emailRequests, isEmpty);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final lateSuccess in [true, false]) {
    testWidgets(
      'cancel without replacement ignores late Google ${lateSuccess ? 'success' : 'access denial'} and keeps email editable',
      (tester) async {
        final api = _GoogleApi();
        var signedIn = 0;
        await _mount(tester, api, onSignedIn: () => signedIn++);
        await tester.enterText(
          find.byKey(_emailKey),
          'Draft.Operator@Collect.Example',
        );
        await _startGoogle(tester);
        expect(api.attempts, hasLength(1));
        await _tap(tester, find.byKey(_cancelKey));
        expect(api.cancellations, 1);
        final restoredEmail = tester.widget<TextFormField>(
          find.byKey(_emailKey),
        );
        expect(restoredEmail.enabled, isTrue);
        expect(
          restoredEmail.controller!.text,
          'Draft.Operator@Collect.Example',
        );
        await tester.enterText(
          find.byKey(_emailKey),
          'Edited.Operator@Collect.Example',
        );
        await tester.pump();

        if (lateSuccess) {
          api.attempts.single.complete();
        } else {
          api.attempts.single.completeError(
            const AdminAccountAccessNotApproved(),
          );
        }
        await tester.pumpAndSettle();
        expect(signedIn, 0);
        expect(find.byKey(_noAccessKey), findsNothing);
        expect(find.text('Contact your super admin'), findsNothing);
        expect(find.byKey(_cancelKey), findsNothing);
        expect(find.byKey(_checkSessionKey), findsNothing);
        expect(find.text('Connecting to Google'), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.liveRegion == true &&
                widget.child is Text,
          ),
          findsNothing,
          reason: 'A cancelled attempt must not announce late error or status.',
        );
        final email = tester.widget<TextFormField>(find.byKey(_emailKey));
        expect(email.enabled, isTrue);
        expect(email.controller!.text, 'Edited.Operator@Collect.Example');
        expect(
          tester.widget<FilledButton>(_emailSendButton()).onPressed,
          isNotNull,
        );
        expect(_googleActionButton(tester).onPressed, isNotNull);
        await tester.enterText(
          find.byKey(_emailKey),
          'After.Late@Collect.Example',
        );
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        expect(email.controller!.text, 'After.Late@Collect.Example');
        expect(signedIn, 0);
        expect(api.attempts, hasLength(1));
        expect(api.cancellations, 1);
        expect(api.sessionChecks, isEmpty);
        expect(api.emailRequests, isEmpty);
        expect(api.emailVerifications, 0);
        expect(api.passwordRequests, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'removed Google session recovery ignores late ${lateSuccess ? 'authenticated result' : 'read failure'}',
      (tester) async {
        final api = _GoogleApi();
        var routeChecks = 0;
        await _mountUnknown(tester, api, onSignedIn: () => routeChecks++);
        await _tap(tester, find.byKey(_checkSessionKey), settle: false);
        expect(api.sessionChecks, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (lateSuccess) {
          api.sessionChecks.single.complete(true);
        } else {
          api.sessionChecks.single.completeError(
            StateError('PRIVATE_LATE_SESSION_DETAIL'),
          );
        }
        await tester.pumpAndSettle();
        expect(routeChecks, 0);
        expect(api.sessionChecks, hasLength(1));
        expect(api.attempts, hasLength(1));
        expect(api.emailRequests, isEmpty);
        expect(api.passwordRequests, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scenario in [
    (
      name: 'blocked popup',
      error: const CollectAuthException(
        'PRIVATE_POPUP_DETAIL',
        code: 'google_popup_blocked',
      ),
      message: _popupBlockedMessage,
    ),
    (
      name: 'untrusted account error',
      error: const AdminAccountException('PRIVATE_ACCOUNT_DETAIL'),
      message: _genericMessage,
    ),
    (
      name: 'unexpected failure',
      error: StateError('PRIVATE_FAILURE_DETAIL'),
      message: _genericMessage,
    ),
  ]) {
    testWidgets('Google ${scenario.name} restores email with safe feedback', (
      tester,
    ) async {
      final api = _GoogleApi();
      var signedIn = 0;
      await _mount(tester, api, onSignedIn: () => signedIn++);
      await _startGoogle(tester);
      api.attempts.single.completeError(scenario.error);
      await tester.pumpAndSettle();
      expect(find.text(scenario.message), findsOneWidget);
      expect(find.textContaining('PRIVATE_'), findsNothing);
      expect(find.byKey(_emailKey), findsOneWidget);
      expect(_emailSendButton(), findsOneWidget);
      expect(find.byKey(_cancelKey), findsNothing);
      expect(api.attempts, hasLength(1));
      expect(api.emailRequests, isEmpty);
      expect(api.passwordRequests, 0);
      expect(signedIn, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final lateSuccess in [true, false]) {
    testWidgets(
      'cancel restores the email draft and fences late ${lateSuccess ? 'success' : 'access denial'} from a fresh Google attempt',
      (tester) async {
        final api = _GoogleApi();
        var signedIn = 0;
        await _mount(tester, api, onSignedIn: () => signedIn++);
        await tester.enterText(
          find.byKey(_emailKey),
          'Draft.Operator@Collect.Example',
        );
        await _startGoogle(tester);
        _expectPending(tester);
        await _tap(tester, find.byKey(_cancelKey));
        expect(api.cancellations, 1);
        expect(find.byKey(_emailKey), findsOneWidget);
        expect(
          tester.widget<TextFormField>(find.byKey(_emailKey)).controller!.text,
          'Draft.Operator@Collect.Example',
        );
        expect(_emailSendButton(), findsOneWidget);
        expect(signedIn, 0);

        await _startGoogle(tester);
        expect(api.attempts, hasLength(2));
        if (lateSuccess) {
          api.attempts.first.complete();
        } else {
          api.attempts.first.completeError(
            const AdminAccountAccessNotApproved(),
          );
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        _expectPending(tester);
        expect(find.byKey(_noAccessKey), findsNothing);
        expect(find.text(_genericMessage), findsNothing);
        expect(signedIn, 0);
        expect(api.cancellations, 1);

        api.attempts.last.complete();
        await tester.pumpAndSettle();
        expect(signedIn, 1);
        expect(api.attempts, hasLength(2));
        expect(api.emailRequests, isEmpty);
        expect(api.passwordRequests, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'removed Google login cancels and ignores late ${lateSuccess ? 'success' : 'failure'}',
      (tester) async {
        final api = _GoogleApi();
        var signedIn = 0;
        await _mount(tester, api, onSignedIn: () => signedIn++);
        await _startGoogle(tester);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(api.cancellations, 1);
        if (lateSuccess) {
          api.attempts.single.complete();
        } else {
          api.attempts.single.completeError(StateError('PRIVATE_LATE_DETAIL'));
        }
        await tester.pumpAndSettle();
        expect(signedIn, 0);
        expect(api.attempts, hasLength(1));
        expect(api.emailRequests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _EmailApi implements AdminAccountApi, AdminEmailOtpAccountApi {
  final emailRequests = <String>[];
  Object? emailVerificationFailure;
  int emailVerifications = 0;
  int passwordRequests = 0;

  @override
  Future<AdminEmailOtpReceipt> requestEmailOtp(String email) async {
    emailRequests.add(email);
    return const AdminEmailOtpReceipt(
      challengeId: 'google-test-unused-email-challenge',
      retryAfterSeconds: 60,
      expiresInSeconds: 300,
    );
  }

  @override
  Future<void> verifyEmailOtp({
    required String email,
    required String challengeId,
    required String code,
  }) async {
    emailVerifications++;
    if (emailVerificationFailure case final failure?) throw failure;
  }

  @override
  Future<void> signIn(String email, String password) async {
    passwordRequests++;
    throw StateError('Google login must not invoke password sign-in.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GoogleApi extends _EmailApi implements AdminGoogleAccountApi {
  _GoogleApi({this.available = true});

  final bool available;
  final attempts = <Completer<void>>[];
  final authorizers = <AdminGoogleAuthorize>[];
  final sessionChecks = <Completer<bool>>[];
  int cancellations = 0;

  @override
  bool get googleSignInAvailable => available;

  @override
  Future<void> signInWithGoogle({required AdminGoogleAuthorize authorize}) {
    // Keep the lifecycle seam observable without opening any browser/provider.
    // This fake deliberately never invokes the authorize callback.
    authorizers.add(authorize);
    final attempt = Completer<void>();
    attempts.add(attempt);
    return attempt.future;
  }

  @override
  void cancelGoogleSignIn() {
    cancellations++;
  }

  @override
  Future<bool> recheckSession() {
    final check = Completer<bool>();
    sessionChecks.add(check);
    return check.future;
  }
}

Future<void> _mount(
  WidgetTester tester,
  AdminAccountApi api, {
  VoidCallback? onSignedIn,
}) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminAccountApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: CollectTheme.dark(),
        home: AdminAccountLoginPage(
          googleSignInEnabled: true,
          onSignedIn: onSignedIn ?? () {},
          onForgotPassword: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _mountUnknown(
  WidgetTester tester,
  _GoogleApi api, {
  VoidCallback? onSignedIn,
}) async {
  await _mount(tester, api, onSignedIn: onSignedIn);
  await tester.enterText(find.byKey(_emailKey), 'operator@collect.example');
  await _startGoogle(tester);
  api.attempts.single.completeError(
    const AdminAccountSecurityOutcomeUnknown('PRIVATE_UNKNOWN_DETAIL'),
  );
  await tester.pumpAndSettle();
}

Future<void> _startGoogle(WidgetTester tester) =>
    _tap(tester, find.byKey(_googleKey), settle: false);

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  bool settle = true,
}) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A pending Google button animates; never wait for that spinner to settle.
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _emailSendButton() =>
    find.widgetWithText(FilledButton, 'Send sign-in code');

OutlinedButton _googleActionButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(_googleKey),
        matching: find.byType(OutlinedButton),
      ),
    );

void _expectUnknownLocked(WidgetTester tester) {
  expect(tester.widget<TextFormField>(find.byKey(_emailKey)).enabled, isFalse);
  expect(_emailSendButton(), findsNothing);
  expect(_googleActionButton(tester).onPressed, isNull);
  expect(find.byKey(_checkSessionKey), findsOneWidget);
}

void _expectPending(WidgetTester tester) {
  expect(find.text('Connecting to Google'), findsOneWidget);
  expect(find.byKey(_cancelKey), findsOneWidget);
  expect(find.byKey(_emailKey), findsNothing);
  expect(_emailSendButton(), findsNothing);
  final button = find.descendant(
    of: find.byKey(_googleKey),
    matching: find.byType(OutlinedButton),
  );
  expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
}
