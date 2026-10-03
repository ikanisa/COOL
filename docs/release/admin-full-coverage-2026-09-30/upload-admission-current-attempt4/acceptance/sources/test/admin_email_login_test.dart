import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/admin/core/admin_email_otp.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/app/theme/collect_colors.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

class _PkceStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class _Repository extends AdminEvidenceRepository {
  _Repository({this.sendError, this.verifyError, this.identity, this.delayed});
  final Object? sendError, verifyError;
  final AdminIdentity? identity;
  final Completer<void>? delayed;
  final sends = <String>[];
  final verifications = <(String, String)>[];
  int signOuts = 0, phoneCalls = 0;
  @override
  Future<void> sendEmailOtp({required String email}) async {
    sends.add(email);
    if (sendError != null) {
      throw sendError!;
    }
    await delayed?.future;
  }

  @override
  Future<AdminIdentity?> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    verifications.add((email, otp));
    if (verifyError != null) {
      throw verifyError!;
    }
    return identity;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }

  @override
  Future<void> sendOtp({required String phone}) async {
    phoneCalls++;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Repository repository, {
  Size size = const Size(1440, 1000),
  double scale = 1,
  Brightness brightness = Brightness.dark,
  bool router = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = brightness == Brightness.dark
      ? AppTheme.dark()
      : AppTheme.light();
  Widget wrap(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  );
  final app = router
      ? MaterialApp.router(
          theme: theme,
          builder: wrap,
          routerConfig: GoRouter(
            initialLocation: '/login',
            routes: [
              GoRoute(
                path: '/login',
                builder: (_, _) => const AdminLoginPage(),
              ),
              GoRoute(
                path: '/admin',
                builder: (_, _) =>
                    const Scaffold(body: Text('Approved Admin route')),
              ),
            ],
          ),
        )
      : MaterialApp(
          theme: theme,
          builder: wrap,
          home: const RepaintBoundary(
            key: Key('email-login-capture'),
            child: AdminLoginPage(),
          ),
        );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repository),
        supabaseClientProvider.overrideWithValue(null),
      ],
      child: app,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _request(
  WidgetTester tester, {
  String email = ' Operator@Collect.Example ',
}) async {
  await tester.enterText(find.byKey(const Key('admin-operator-email')), email);
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  setUpAll(() async {
    if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
      await (FontLoader('Inter')
            ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  test(
    'operator email normalization accepts canonical address and rejects unsafe malformed inputs',
    () {
      expect(normalizeAdminEmail(' INFO@IKANISA.COM '), 'info@ikanisa.com');
      expect(
        normalizeAdminEmail('operator@collect.example'),
        adminEvidenceEmail,
      );
      for (final value in [
        '',
        '0788123456',
        'a@@b.com',
        'a@localhost',
        '.a@b.com',
        'a..b@c.com',
        'a@-c.com',
        'a@c..com',
        'a\n@b.com',
      ]) {
        expect(() => normalizeAdminEmail(value), throwsFormatException);
      }
      expect(normalizeAdminEmailOtp(' 123456 '), '123456');
      for (final value in ['', '12345', '1234567', '123abc']) {
        expect(() => normalizeAdminEmailOtp(value), throwsFormatException);
      }
    },
  );
  test(
    'synthetic email fixture accepts only its explicit review target and OTP',
    () async {
      const repository = AdminEvidenceRepository();
      await repository.sendEmailOtp(email: 'OPERATOR@collect.example');
      expect(
        await repository.verifyEmailOtp(
          email: adminEvidenceEmail,
          otp: adminEvidenceOtp,
        ),
        isNotNull,
      );
      await expectLater(
        repository.sendEmailOtp(email: 'info@ikanisa.com'),
        throwsFormatException,
      );
      await expectLater(
        repository.verifyEmailOtp(email: adminEvidenceEmail, otp: '000000'),
        throwsFormatException,
      );
      await expectLater(
        repository.sendOtp(phone: '+250788767816'),
        throwsUnsupportedError,
      );
    },
  );
  testWidgets(
    'email form uses keyboard/autofill and sends normalized email without phone',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      final email = tester.widget<TextField>(
        find.byKey(const Key('admin-operator-email')),
      );
      expect(email.keyboardType, TextInputType.emailAddress);
      expect(email.autofillHints, contains(AutofillHints.email));
      await _request(tester);
      expect(repository.sends, ['operator@collect.example']);
      expect(repository.phoneCalls, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('admin-operator-email')))
            .enabled,
        isFalse,
      );
      expect(
        find.text('Email code requested. Check your approved operator inbox.'),
        findsOneWidget,
      );
      final otp = tester.widget<TextField>(find.byType(TextField).last);
      expect(otp.autofillHints, contains(AutofillHints.oneTimeCode));
    },
  );
  testWidgets(
    'invalid email or invalid code never dispatches corresponding request',
    (tester) async {
      final repository = _Repository();
      await _pump(tester, repository);
      await _request(tester, email: '0788123456');
      expect(repository.sends, isEmpty);
      expect(
        find.text('Enter a valid operator email address.'),
        findsOneWidget,
      );
      await _request(tester);
      await tester.enterText(find.byType(TextField).last, '12345');
      await tester.tap(find.text('Verify code'));
      await tester.pumpAndSettle();
      expect(repository.verifications, isEmpty);
      expect(find.text('Enter the six-digit email code.'), findsOneWidget);
    },
  );
  testWidgets('unprovisioned target has clear safe enrollment guidance', (
    tester,
  ) async {
    final repository = _Repository(
      sendError: const AuthException(
        'Signups not allowed for otp: PRIVATE_CANARY',
      ),
    );
    await _pump(tester, repository);
    await _request(tester);
    expect(
      find.textContaining('not provisioned for operator sign-in'),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
  });
  testWidgets('verified unapproved account signs out and remains on login', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository);
    await _request(tester);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(repository.verifications, [('operator@collect.example', '123456')]);
    expect(repository.signOuts, 1);
    expect(
      find.text('This account is not authorized for admin.'),
      findsOneWidget,
    );
  });
  testWidgets('denied verification keeps login and redacts provider details', (
    tester,
  ) async {
    final repository = _Repository(
      verifyError: const AuthException('Invalid token PRIVATE_CANARY'),
    );
    await _pump(tester, repository, router: true);
    await _request(tester);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(repository.verifications, [('operator@collect.example', '123456')]);
    expect(repository.sends, ['operator@collect.example']);
    expect(find.text('Approved Admin route'), findsNothing);
    expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
    expect(
      find.text(
        'That code could not be verified. Use the latest email code or request a new one.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('approved identity navigates only after email verification', (
    tester,
  ) async {
    final repository = _Repository(
      identity: const AdminIdentity(
        userId: 'synthetic',
        displayName: 'Synthetic',
        roles: ['admin'],
        permissions: ['overview.read'],
      ),
    );
    await _pump(tester, repository, router: true);
    await _request(tester);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Approved Admin route'), findsOneWidget);
    expect(repository.signOuts, 0);
  });
  testWidgets('cooldown binds resend and change-email clears previous code', (
    tester,
  ) async {
    final repository = _Repository();
    await _pump(tester, repository);
    await _request(tester);
    final resend = find.widgetWithText(TextButton, 'Resend code in 60s');
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resend email OTP'));
    await tester.pumpAndSettle();
    expect(repository.sends, [
      'operator@collect.example',
      'operator@collect.example',
    ]);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
    await tester.tap(find.text('Use a different email'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('admin-operator-email')))
          .enabled,
      isTrue,
    );
  });
  testWidgets('disposed pending email request cannot update removed login', (
    tester,
  ) async {
    final delayed = Completer<void>();
    final repository = _Repository(delayed: delayed);
    await _pump(tester, repository);
    await tester.enterText(
      find.byKey(const Key('admin-operator-email')),
      'operator@collect.example',
    );
    await tester.tap(find.text('Send code'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      CollectColors.dark.textMuted,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    delayed.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('${brightness.name} email form 320px 2x has no overflow', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repository(),
        size: const Size(320, 900),
        scale: 2,
        brightness: brightness,
      );
      await tester.ensureVisible(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    testWidgets('${brightness.name} synthetic email login capture', (
      tester,
    ) async {
      await _pump(
        tester,
        _Repository(),
        size: const Size(1440, 1000),
        brightness: brightness,
      );
      final primary = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Send code'),
      );
      expect(
        primary.style!.foregroundColor!.resolve({}),
        CollectColors.publicWhite,
      );
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('COLLECT_CAPTURE_OPERATIONS')) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('email-login-capture')),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/release/collect-codex-goal-2026-09-30/email-operator/email-login-${brightness.name}-synthetic.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
  group('pinned SDK email transport', () {
    late SupabaseClient client;
    late AdminRepository repository;
    final requests = <http.Request>[];
    late Future<http.Response> Function(http.Request) respond;
    setUp(() {
      requests.clear();
      respond = (request) async {
        if (request.url.path.endsWith('/verify')) {
          final receipt = auth.authReceipt('email-session', '0');
          receipt['user']['email'] = 'info@ikanisa.com';
          receipt['user']['email_confirmed_at'] = '2026-09-30T00:00:00Z';
          return auth.response(receipt);
        }
        if (request.url.path.endsWith('/admin_current_user')) {
          return auth.response({
            'user_id': auth.actor,
            'display_name': 'Synthetic operator',
            'roles': ['platform_owner'],
            'phone_masked': null,
            'permissions': ['overview.read'],
          });
        }
        return auth.response({});
      };
      client = SupabaseClient(
        'https://synthetic.invalid',
        'synthetic-publishable',
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: _PkceStorage(),
        ),
        httpClient: MockClient((request) async {
          requests.add(request);
          final response = await respond(request);
          return http.Response.bytes(
            response.bodyBytes,
            response.statusCode,
            headers: response.headers,
            request: request,
          );
        }),
      );
      repository = AdminRepository(client);
    });
    tearDown(() => client.dispose());
    test(
      'email request is normalized create_user=false and has no phone or redirect',
      () async {
        await repository.sendEmailOtp(email: ' INFO@IKANISA.COM ');
        final request = requests.single;
        final body = jsonDecode(request.body) as Map;
        expect(request.url.path, '/auth/v1/otp');
        expect(body['email'], 'info@ikanisa.com');
        expect(body['create_user'], false);
        expect(body.containsKey('phone'), isFalse);
        expect(request.url.queryParameters.containsKey('redirect_to'), isFalse);
      },
    );
    test('verification uses email type then current locked identity', () async {
      final identity = await repository.verifyEmailOtp(
        email: 'INFO@IKANISA.COM',
        otp: ' 123456 ',
      );
      expect(identity?.userId, auth.actor);
      expect(jsonDecode(requests.first.body)['type'], 'email');
      expect(jsonDecode(requests.first.body)['email'], 'info@ikanisa.com');
      expect(jsonDecode(requests.first.body)['token'], '123456');
      expect(requests.last.url.path, '/rest/v1/rpc/admin_current_user');
    });
    test('invalid email or token never reaches HTTP', () async {
      await expectLater(
        repository.sendEmailOtp(email: 'phone'),
        throwsFormatException,
      );
      await expectLater(
        repository.verifyEmailOtp(email: 'info@ikanisa.com', otp: 'bad'),
        throwsFormatException,
      );
      expect(requests, isEmpty);
    });
    test(
      'unprovisioned server response remains denied with one request',
      () async {
        respond = (_) async => auth.response({
          'msg': 'Signups not allowed for otp',
          'code': 'signup_disabled',
        }, 400);
        await expectLater(
          repository.sendEmailOtp(email: 'info@ikanisa.com'),
          throwsA(isA<AuthException>()),
        );
        expect(requests, hasLength(1));
      },
    );
  });
}
