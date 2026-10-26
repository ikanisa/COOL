import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/core/cloudflare/collect_turnstile.dart';
import 'package:collect_app/core/cloudflare/collect_turnstile_contract.dart';
import 'package:collect_app/features/privacy/privacy_providers.dart';
import 'package:collect_app/features/privacy/privacy_request_screen.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:collect_app/l10n/collect_localizations.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

const _current = 'get_current_account_deletion_request_status_v1';
const _status = 'get_account_deletion_request_status_v1';
const _submit = 'request_account_deletion_v1';
const _review = 'get_account_deletion_review_status_v1';
const _rawSecret = 'SYNTHETIC_PRIVATE_TOKEN_PHONE_REASON_DO_NOT_RENDER';

http.Response _json(Object? body, [int code = 200]) =>
    http.Response(jsonEncode(body), code);

typedef _Reply = Future<http.Response?> Function(http.Request request);

final _mountedHarnesses = <_RouteHarness>[];

// Cleanup must finish inside the widget body, before Flutter checks fake-clock
// timers. External clients are not owned by an overrideWithValue provider.
void _privacyWidgetTest(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final harness in List<_RouteHarness>.of(
        _mountedHarnesses,
      ).reversed) {
        await harness.close();
      }
      _mountedHarnesses.clear();
    }
  });
}

/// Uses the production router, subject/provider/controller, transport and SDK.
/// Only the financial repository and all HTTP responses are synthetic fixtures.
class _RouteHarness {
  _RouteHarness(this.tester, {this.reply, this.captcha = false});

  final WidgetTester tester;
  final _Reply? reply;
  final bool captcha;
  final _challenge = CollectTurnstileChallenge();
  final requests = <http.Request>[];
  late final CollectCloudflareClient client;
  late final Zone _clientZone;
  late final ProviderContainer container;
  late final GoRouter router;
  bool _closed = false;

  List<http.Request> calls(String tail) =>
      requests.where((request) => request.url.path.endsWith('/$tail')).toList();

  Future<void> mount({
    CollectAuthSession? session,
    bool signedIn = true,
    bool dark = false,
    bool highContrast = false,
    double scale = 1,
    double keyboard = 0,
  }) async {
    await tester.runAsync(() async {
      _clientZone = Zone.current;
      client = CollectCloudflareClient(
        'https://synthetic.invalid',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/logout')) {
            return http.Response('{"ok":true}', 200);
          }
          throw StateError('Unexpected SDK HTTP in isolated route fixture');
        }),
      );
      if (signedIn) {
        await client.auth.recoverSession(
          jsonEncode((session ?? privacySession()).toJson()),
        );
      }
    });
    final transport = CollectPrivacyRequestTransport(
      httpClient: MockClient((request) async {
        requests.add(request);
        final result = await reply?.call(request);
        if (result != null) return result;
        if (request.url.path.endsWith('/otp')) {
          return _json({'challenge_id': 'synthetic-privacy-challenge'});
        }
        if (request.url.path.endsWith('/verify')) {
          return _json(privacySession(sid: privacyNewSid).toJson());
        }
        if (request.url.path.endsWith('/$_current')) return _json(null);
        if (request.url.path.endsWith('/$_review')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(
            privacyReviewJson(requestId: body['p_request_id'] as String),
          );
        }
        if (request.url.path.endsWith('/$_submit')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(
            privacyReceiptJson(
              submission: true,
              requestId: body['p_request_id'] as String,
              submissionId: body['p_request_id'] as String,
              reasonSupplied: body['p_reason'] != null,
            ),
          );
        }
        throw StateError('Unexpected privacy RPC in isolated route fixture');
      }),
      apiUrl: 'https://synthetic.invalid',

      captchaRequired: captcha,
      captchaProvider: captcha ? _challenge.acquire : null,
      cancelCaptcha: _challenge.cancel,
      isSessionCurrent: (owner) {
        try {
          return container
              .read(privacySessionAuthorityProvider)!
              .capture()
              .sameFence(owner);
        } catch (_) {
          return false;
        }
      },
    );
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        privacyRequestTransportProvider.overrideWithValue(transport),
        appEnvProvider.overrideWithValue(
          AppEnv(
            apiUrl: 'https://synthetic.invalid',
            publicUrl: '',
            adminAppUrl: '',
            enableSmsReader: false,
            enableAndroidSmsAccess: false,
            enableAdminPanel: false,
            enableAdminDevTools: false,
            authCaptchaEnabled: captcha,
            authCaptchaProvider: '',
            authCaptchaSiteKey: '',
            backend: 'cloudflare',
          ),
        ),
        collectAccountDeletionReasonsProvider.overrideWith(
          (ref) async => collectDefaultAccountDeletionReasons,
        ),
        collectRepositoryProvider.overrideWith(
          (ref) => CollectRepository.fixture(
            initialState: const CollectState(
              currentProfile: CollectProfile(
                id: privacySubject,
                publicId: '123456',
                whatsappPhone: '+250788999999',
                countryCode: 'RW',
                currencyCode: 'RWF',
                momoProvider: 'mtn_momo',
                momoNumber: '0788999999',
              ),
              collections: [],
              paymentIntents: [],
              contributions: [],
            ),
          ),
        ),
      ],
    );
    router = createAppRouter(initialLocation: '/settings/account/delete');
    _mountedHarnesses.add(this);
    addTearDown(close);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: highContrast
              ? (dark
                    ? AppTheme.highContrastDark()
                    : AppTheme.highContrastLight())
              : (dark ? AppTheme.dark() : AppTheme.light()),
          supportedLocales: CollectLocalizations.supportedLocales,
          localizationsDelegates: const [
            CollectLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          locale: const Locale('en'),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              highContrast: highContrast,
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: child!,
          ),
        ),
      ),
    );
    await flush();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _challenge.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    // Flush any widget-zone work, then shut down the client in the real zone
    // that created its storage tail and broadcast stream. Fake pumps cannot
    // drive that original zone's asynchronous stream-close completion.
    await tester.pump();
    final closing = _clientZone.run(client.dispose);
    await tester.runAsync(() async {
      await closing.timeout(const Duration(seconds: 3));
    });
  }

  Future<void> replaceSession(CollectAuthSession session) async {
    // Credential persistence belongs to the client's real execution zone.
    // Awaiting that tail directly inside a widget's fake clock stalls adoption.
    await tester.runAsync(
      () => _clientZone.run(
        () => client.auth.recoverSession(jsonEncode(session.toJson())),
      ),
    );
  }

  Future<void> flush() async {
    for (var i = 0; i < 8; ++i) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> reveal(Finder finder) async {
    if (finder.evaluate().isEmpty) {
      final scrollable = find
          .descendant(
            of: find.byType(DeleteAccountRequestScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      // The target may be above the current lazy viewport after the form
      // replaces an OTP field. Use a real scroll gesture back to the start.
      for (var i = 0; i < 80; ++i) {
        final position = tester.state<ScrollableState>(scrollable).position;
        if (position.pixels <= position.minScrollExtent + 1) break;
        await tester.drag(scrollable, const Offset(0, 180));
        await flush();
      }
      await tester.scrollUntilVisible(
        finder,
        180,
        maxScrolls: 80,
        scrollable: scrollable,
      );
    }
    await tester.ensureVisible(finder);
    await flush();
  }

  Future<void> press(Finder finder) async {
    await reveal(finder);
    await tester.tap(finder);
    await flush();
  }

  Future<void> sendCode() =>
      press(find.byKey(const ValueKey('privacy_send_code')));

  Future<void> enterCode([String value = '123456']) async {
    final input = find.byKey(const ValueKey('auth_otp_digit_0'));
    await reveal(input);
    await tester.enterText(input, value);
    await flush();
  }

  Future<void> verify() async {
    await sendCode();
    await enterCode();
    await press(find.byKey(const ValueKey('privacy_verify_code')));
  }

  Future<void> confirm({bool retry = false}) async {
    await press(
      find.byKey(
        ValueKey(retry ? 'privacy_retry_request' : 'privacy_submit_request'),
      ),
    );
    await press(find.text(retry ? 'Retry request' : 'Submit request').last);
  }

  String get renderedText => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const challengeChannel = MethodChannel('collect/turnstile');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(challengeChannel, null));
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'));
    await font.load();
  });

  _privacyWidgetTest(
    'actual delete route recovers only server pending-review receipt',
    (tester) async {
      final harness = _RouteHarness(
        tester,
        reply: (request) async => request.url.path.endsWith('/$_current')
            ? _json(privacyReceiptJson(requestId: privacyCanonical))
            : null,
      );
      await harness.mount();
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        '/settings/account/delete',
      );
      expect(find.text('Pending review'), findsOneWidget);
      expect(find.text('Request recorded'), findsOneWidget);
      expect(
        find.text(
          'Your account has not been deleted. Your request is awaiting review.',
        ),
        findsOneWidget,
      );
      expect(find.text(privacyCanonical), findsOneWidget);
      expect(harness.calls(_current), hasLength(1));
      expect(harness.calls(_submit), isEmpty);
      expect(find.byKey(const ValueKey('privacy_send_code')), findsNothing);
    },
  );

  _privacyWidgetTest(
    'pending initial read is loading and cannot invent success',
    (tester) async {
      final gate = Completer<http.Response>();
      final harness = _RouteHarness(
        tester,
        reply: (r) async =>
            r.url.path.endsWith('/$_current') ? gate.future : null,
      );
      await harness.mount();
      expect(find.text('Checking your request'), findsOneWidget);
      expect(find.text('Request recorded'), findsNothing);
      expect(
        find.byKey(const ValueKey('privacy_submit_request')),
        findsNothing,
      );
      gate.complete(_json(null));
      await harness.flush();
      expect(find.text('Request account deletion'), findsOneWidget);
      expect(find.text('Request recorded'), findsNothing);
      expect(harness.calls(_submit), isEmpty);
    },
  );

  _privacyWidgetTest(
    'status failure exposes fixed safe error and no local receipt',
    (tester) async {
      final harness = _RouteHarness(
        tester,
        reply: (r) async => r.url.path.endsWith('/$_current')
            ? _json({'message': _rawSecret}, 503)
            : null,
      );
      await harness.mount();
      await harness.reveal(
        find.text(
          'Your request status is unavailable. Check your connection and try again.',
        ),
      );
      expect(
        find.text(
          'Your request status is unavailable. Check your connection and try again.',
        ),
        findsOneWidget,
      );
      expect(harness.renderedText, isNot(contains(_rawSecret)));
      expect(find.text('Request recorded'), findsNothing);
      expect(harness.calls(_submit), isEmpty);
    },
  );

  _privacyWidgetTest('signed-out route cannot issue a status or mutation', (
    tester,
  ) async {
    final harness = _RouteHarness(tester);
    await harness.mount(signedIn: false);
    expect(find.text('Request service unavailable'), findsOneWidget);
    expect(harness.requests, isEmpty);
    expect(find.text('Request recorded'), findsNothing);
  });

  _privacyWidgetTest(
    'OTP is bound to Auth phone, masked and obscured; no profile fallback',
    (tester) async {
      final harness = _RouteHarness(tester);
      await harness.mount();
      expect(harness.renderedText, contains('•••• 0001'));
      expect(harness.renderedText, isNot(contains('+250788000001')));
      expect(harness.renderedText, isNot(contains('+250788999999')));
      await harness.sendCode();
      final body = jsonDecode(harness.calls('otp').single.body) as Map;
      expect(body['phone'], '+250788000001');
      expect(body['surface'], 'member');
      expect(body.containsKey('create_user'), isFalse);
      expect(body.containsKey('channel'), isFalse);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('auth_otp_digit_0')),
      );
      expect(field.obscureText, isTrue);
      await harness.enterCode('123');
      await harness.press(find.byKey(const ValueKey('privacy_verify_code')));
      expect(harness.calls('verify'), isEmpty);
      expect(harness.calls(_submit), isEmpty);
      await harness.enterCode();
      await harness.press(find.byKey(const ValueKey('privacy_verify_code')));
      expect(clientSid(harness.client), privacyNewSid);
      expect(find.text('Code verified'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth_otp_digit_0')), findsNothing);
      expect(harness.calls(_submit), isEmpty);
    },
  );

  _privacyWidgetTest(
    'unavailable Auth phone does not use profile or MoMo phone',
    (tester) async {
      final harness = _RouteHarness(tester);
      await harness.mount(session: privacySession(phone: ''));
      await harness.sendCode();
      expect(harness.calls('otp'), isEmpty);
      expect(
        harness.renderedText,
        contains('signed-in phone number is unavailable'),
      );
      expect(find.byKey(const ValueKey('auth_otp_digit_0')), findsNothing);
      expect(harness.calls(_submit), isEmpty);
      await harness.press(find.byKey(const ValueKey('privacy_get_help')));
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        '/settings/help',
      );
    },
  );

  _privacyWidgetTest('confirmation cancellation and dismissal never submit', (
    tester,
  ) async {
    final harness = _RouteHarness(tester);
    await harness.mount();
    await harness.verify();
    await harness.press(find.byKey(const ValueKey('privacy_submit_request')));
    expect(find.text('Submit delete request?'), findsOneWidget);
    await harness.press(find.text('Cancel'));
    expect(harness.calls(_submit), isEmpty);
    await harness.press(find.byKey(const ValueKey('privacy_submit_request')));
    harness.router.pop();
    await harness.flush();
    expect(harness.calls(_submit), isEmpty);
    expect(find.text('Code verified'), findsOneWidget);
  });

  _privacyWidgetTest(
    'explicit confirmation records receipt only after server response',
    (tester) async {
      final gate = Completer<http.Response>();
      final harness = _RouteHarness(
        tester,
        reply: (r) async =>
            r.url.path.endsWith('/$_submit') ? gate.future : null,
      );
      await harness.mount();
      await harness.press(find.text('I joined by mistake'));
      await harness.verify();
      await harness.confirm();
      expect(harness.calls(_submit), hasLength(1));
      expect(find.text('Request recorded'), findsNothing);
      final body = jsonDecode(harness.calls(_submit).single.body) as Map;
      expect(body['p_reason'], 'I joined by mistake');
      gate.complete(
        _json(
          privacyReceiptJson(
            submission: true,
            requestId: body['p_request_id'] as String,
            submissionId: body['p_request_id'] as String,
          ),
        ),
      );
      await harness.flush();
      expect(find.text('Request recorded'), findsOneWidget);
      expect(find.text(body['p_request_id'] as String), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);
    },
  );

  _privacyWidgetTest(
    'malformed success remains unconfirmed instead of fake erasure',
    (tester) async {
      final harness = _RouteHarness(
        tester,
        reply: (r) async => r.url.path.endsWith('/$_submit')
            ? _json({
                'success': true,
                'erasure_completed': true,
                'message': _rawSecret,
              })
            : null,
      );
      await harness.mount();
      await harness.verify();
      await harness.confirm();
      expect(find.text('Request result unconfirmed'), findsOneWidget);
      expect(find.text('Request recorded'), findsNothing);
      expect(harness.renderedText, isNot(contains(_rawSecret)));
      expect(harness.calls(_submit), hasLength(1));
    },
  );

  _privacyWidgetTest(
    'ambiguous result requires status read then explicit SAME UUID retry',
    (tester) async {
      var submissions = 0;
      final harness = _RouteHarness(
        tester,
        reply: (request) async {
          if (request.url.path.endsWith('/$_submit') && ++submissions == 1) {
            return _json({'message': _rawSecret}, 502);
          }
          if (request.url.path.endsWith('/$_status')) {
            return _json({'message': _rawSecret}, 503);
          }
          return null;
        },
      );
      await harness.mount();
      await harness.press(find.text('I joined by mistake'));
      await harness.verify();
      await harness.confirm();
      final first = harness.calls(_submit).single.body;
      await harness.press(find.byKey(const ValueKey('privacy_retry_request')));
      expect(find.text('Retry your request?'), findsNothing);
      expect(harness.calls(_submit), hasLength(1));
      await harness.press(find.byKey(const ValueKey('privacy_check_status')));
      expect(harness.calls(_status), hasLength(1));
      expect(harness.calls(_submit), hasLength(1));
      await harness.confirm(retry: true);
      expect(harness.calls(_submit), hasLength(2));
      expect(harness.calls(_submit).last.body, first);
      expect(find.text('Request recorded'), findsOneWidget);
      expect(harness.renderedText, isNot(contains(_rawSecret)));
    },
  );

  _privacyWidgetTest(
    'ambiguous status recovery returns canonical receipt without replay',
    (tester) async {
      final harness = _RouteHarness(
        tester,
        reply: (request) async {
          if (request.url.path.endsWith('/$_submit')) return _json({}, 502);
          if (request.url.path.endsWith('/$_status')) {
            return _json(privacyReceiptJson(requestId: privacyCanonical));
          }
          return null;
        },
      );
      await harness.mount();
      await harness.verify();
      await harness.confirm();
      await harness.press(find.byKey(const ValueKey('privacy_check_status')));
      expect(find.text(privacyCanonical), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);
      expect(harness.calls(_submit), hasLength(1));
      expect(find.byKey(const ValueKey('privacy_retry_request')), findsNothing);
    },
  );

  for (final (status, code, copy) in [
    (429, 'rate_limit', 'Wait before requesting another verification code.'),
    (400, 'otp_expired', 'Check the six-digit code or request a new one.'),
    (
      500,
      'unknown',
      'The code could not be verified. Check it or try again later.',
    ),
  ]) {
    _privacyWidgetTest(
      'verification $status uses fixed copy without raw credentials',
      (tester) async {
        final harness = _RouteHarness(
          tester,
          reply: (r) async => r.url.path.endsWith('/verify')
              ? _json({'code': code, 'message': _rawSecret}, status)
              : null,
        );
        await harness.mount();
        await harness.verify();
        expect(find.text(copy), findsOneWidget);
        expect(harness.renderedText, isNot(contains(_rawSecret)));
        expect(harness.renderedText, isNot(contains('123456')));
        expect(clientSid(harness.client), privacyOldSid);
        expect(harness.calls(_submit), isEmpty);
      },
    );
  }

  _privacyWidgetTest(
    'configured CAPTCHA uses a fresh native challenge for send and verify',
    (tester) async {
      final attempts = <String>[];
      messenger.setMockMethodCallHandler(challengeChannel, (call) async {
        if (call.method == 'cancel') return null;
        expect(call.method, 'acquire');
        final attempt = (call.arguments as Map)['attempt_id'] as String;
        attempts.add(attempt);
        return jsonEncode({
          'type': collectChallengeEnvelope,
          'attempt_id': attempt,
          'token': 'SYNTHETIC_PRIVACY_CHALLENGE_${attempts.length}',
        });
      });
      final harness = _RouteHarness(tester, captcha: true);
      await harness.mount();
      expect(find.text('Verification unavailable'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await harness.sendCode();
      expect(attempts, hasLength(1));
      expect(
        jsonDecode(harness.calls('otp').single.body)['captcha_token'],
        'SYNTHETIC_PRIVACY_CHALLENGE_1',
      );
      await harness.enterCode();
      await harness.press(find.byKey(const ValueKey('privacy_verify_code')));
      expect(attempts, hasLength(2));
      expect(attempts.toSet(), hasLength(2));
      expect(
        jsonDecode(harness.calls('verify').single.body)['captcha_token'],
        'SYNTHETIC_PRIVACY_CHALLENGE_2',
      );
      expect(find.text('Code verified'), findsOneWidget);
      expect(
        harness.renderedText,
        isNot(contains('SYNTHETIC_PRIVACY_CHALLENGE')),
      );
      expect(harness.calls(_submit), isEmpty);
      await harness.confirm();
      expect(harness.calls(_submit), hasLength(1));
    },
  );

  for (final failure in ['captcha_cancelled', 'captcha_unavailable']) {
    _privacyWidgetTest(
      'challenge $failure exposes recovery without sending an OTP',
      (tester) async {
        messenger.setMockMethodCallHandler(challengeChannel, (call) async {
          if (call.method == 'cancel') return null;
          throw PlatformException(code: failure);
        });
        final harness = _RouteHarness(tester, captcha: true);
        await harness.mount();
        await harness.sendCode();
        expect(harness.calls('otp'), isEmpty);
        expect(harness.calls(_submit), isEmpty);
        expect(
          find.text(
            'Security verification could not finish. Try again or get help.',
          ),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);
        await harness.press(find.byKey(const ValueKey('privacy_get_help')));
        expect(
          harness.router.routeInformationProvider.value.uri.path,
          '/settings/help',
        );
      },
    );
  }

  _privacyWidgetTest(
    'leaving privacy cancels the owned challenge and cannot send late OTP',
    (tester) async {
      final candidate = Completer<String>();
      String? attempt;
      final cancelled = <String>[];
      messenger.setMockMethodCallHandler(challengeChannel, (call) async {
        final id = (call.arguments as Map)['attempt_id'] as String;
        if (call.method == 'cancel') {
          cancelled.add(id);
          return null;
        }
        attempt = id;
        return candidate.future;
      });
      final harness = _RouteHarness(tester, captcha: true);
      await harness.mount();
      await harness.sendCode();
      expect(attempt, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      candidate.complete(
        jsonEncode({
          'type': collectChallengeEnvelope,
          'attempt_id': attempt,
          'token': 'SYNTHETIC_LATE_CANDIDATE',
        }),
      );
      await harness.flush();
      expect(cancelled, contains(attempt));
      expect(harness.calls('otp'), isEmpty);
      expect(harness.calls(_submit), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  _privacyWidgetTest(
    'configured CAPTCHA still recovers an existing server receipt',
    (tester) async {
      final harness = _RouteHarness(
        tester,
        captcha: true,
        reply: (r) async => r.url.path.endsWith('/$_current')
            ? _json(privacyReceiptJson(requestId: privacyCanonical))
            : null,
      );
      await harness.mount();
      expect(find.text(privacyCanonical), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(harness.calls('otp'), isEmpty);
      expect(harness.calls(_submit), isEmpty);
    },
  );

  _privacyWidgetTest(
    'late verify after account switch cannot adopt or expose old draft',
    (tester) async {
      final gate = Completer<http.Response>();
      final harness = _RouteHarness(
        tester,
        reply: (r) async => r.url.path.endsWith('/verify') ? gate.future : null,
      );
      await harness.mount();
      await harness.press(find.text('I joined by mistake'));
      await harness.sendCode();
      await harness.enterCode();
      await harness.press(find.byKey(const ValueKey('privacy_verify_code')));
      await harness.replaceSession(
        privacySession(subject: privacyOtherSubject, phone: '+250788000002'),
      );
      await harness.flush();
      gate.complete(_json(privacySession(sid: privacyNewSid).toJson()));
      await harness.flush();
      expect(harness.client.auth.currentUser?.id, privacyOtherSubject);
      expect(clientSid(harness.client), privacyOldSid);
      expect(harness.renderedText, contains('•••• 0002'));
      expect(harness.renderedText, isNot(contains('•••• 0001')));
      expect(find.text('Code verified'), findsNothing);
      expect(find.byKey(const ValueKey('auth_otp_digit_0')), findsNothing);
      expect(
        tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
            .every((tile) => tile.value == false),
        isTrue,
      );
      expect(harness.calls(_submit), isEmpty);
    },
  );

  _privacyWidgetTest(
    'disposing route during verification refuses late session adoption',
    (tester) async {
      final gate = Completer<http.Response>();
      final harness = _RouteHarness(
        tester,
        reply: (r) async => r.url.path.endsWith('/verify') ? gate.future : null,
      );
      await harness.mount();
      await harness.sendCode();
      await harness.enterCode();
      await harness.press(find.byKey(const ValueKey('privacy_verify_code')));
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete(_json(privacySession(sid: privacyNewSid).toJson()));
      await harness.flush();
      expect(clientSid(harness.client), privacyOldSid);
      expect(harness.calls(_submit), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  _privacyWidgetTest(
    'accepted receipt disappears on account switch before new recovery',
    (tester) async {
      final gate = Completer<http.Response>();
      final harness = _RouteHarness(
        tester,
        reply: (r) async {
          if (!r.url.path.endsWith('/$_current')) return null;
          final token = r.headers['Authorization']!.substring(7);
          final subject = jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1])),
            ),
          )['sub'];
          return subject == privacySubject
              ? _json(privacyReceiptJson(requestId: privacyCanonical))
              : gate.future;
        },
      );
      await harness.mount();
      expect(find.text(privacyCanonical), findsOneWidget);
      await harness.replaceSession(
        privacySession(subject: privacyOtherSubject),
      );
      await harness.flush();
      expect(find.text(privacyCanonical), findsNothing);
      expect(find.text('Request recorded'), findsNothing);
      gate.complete(_json(null));
      await harness.flush();
      expect(find.text('Request account deletion'), findsOneWidget);
      expect(harness.calls(_submit), isEmpty);
    },
  );

  _privacyWidgetTest(
    'switch while confirmation is open cannot submit for either owner',
    (tester) async {
      final harness = _RouteHarness(tester);
      await harness.mount();
      await harness.verify();
      await harness.press(find.byKey(const ValueKey('privacy_submit_request')));
      await harness.replaceSession(
        privacySession(subject: privacyOtherSubject),
      );
      await harness.flush();
      await harness.press(find.text('Submit request').last);
      expect(harness.calls(_submit), isEmpty);
      expect(harness.client.auth.currentUser?.id, privacyOtherSubject);
      expect(find.text('Request recorded'), findsNothing);
    },
  );

  _privacyWidgetTest(
    'server fresh-session refusal requires another OTP before submission',
    (tester) async {
      final harness = _RouteHarness(
        tester,
        reply: (r) async => r.url.path.endsWith('/$_submit')
            ? _json({
                'code': '42501',
                'message': 'privacy_request_fresh_session_required',
              }, 403)
            : null,
      );
      await harness.mount();
      await harness.verify();
      await harness.confirm();
      expect(
        find.text('Verify your identity again before submitting the request.'),
        findsOneWidget,
      );
      expect(find.text('Code verified'), findsNothing);
      expect(find.byKey(const ValueKey('privacy_send_code')), findsOneWidget);
      await harness.press(find.byKey(const ValueKey('privacy_submit_request')));
      expect(harness.calls(_submit), hasLength(1));
    },
  );

  for (final state in const {
    'awaiting_review': 'Pending review',
    'claim_active': 'Review in progress',
    'claim_expired': 'Waiting to resume review',
    'blocked': 'Waiting for policy approval',
  }.entries) {
    _privacyWidgetTest(
      'production route presents observed ${state.key} without erasure claims',
      (tester) async {
        final harness = _RouteHarness(
          tester,
          reply: (r) async {
            if (r.url.path.endsWith('/$_current')) {
              return _json(privacyReceiptJson(requestId: privacyCanonical));
            }
            if (r.url.path.endsWith('/$_review')) {
              return _json(privacyReviewJson(state: state.key));
            }
            return null;
          },
        );
        await harness.mount();
        expect(find.text('Request recorded'), findsOneWidget);
        expect(find.text(state.value), findsOneWidget);
        expect(
          find.textContaining('Your account has not been deleted.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('privacy_submit_request')),
          findsNothing,
        );
        expect(harness.calls(_submit), isEmpty);
        expect(harness.calls(_review), hasLength(1));
        expect(jsonDecode(harness.calls(_review).single.body), {
          'p_request_id': privacyCanonical,
        });
      },
    );
  }

  for (final failure in ['denied', 'contradiction', 'foreign request']) {
    _privacyWidgetTest(
      'confirmed intake stays visible when review is $failure',
      (tester) async {
        final harness = _RouteHarness(
          tester,
          reply: (r) async {
            if (r.url.path.endsWith('/$_current')) {
              return _json(privacyReceiptJson(requestId: privacyCanonical));
            }
            if (r.url.path.endsWith('/$_review')) {
              return switch (failure) {
                'denied' => _json({'message': _rawSecret}, 403),
                'contradiction' => _json(
                  privacyReviewJson()..['erasure_completed'] = true,
                ),
                _ => _json(privacyReviewJson(requestId: privacySubmission)),
              };
            }
            return null;
          },
        );
        await harness.mount();
        expect(find.text('Request recorded'), findsOneWidget);
        expect(find.text('Review status unavailable'), findsOneWidget);
        expect(find.text('Pending review'), findsNothing);
        expect(find.textContaining(_rawSecret), findsNothing);
        expect(harness.calls(_submit), isEmpty);
        expect(
          find.byKey(const ValueKey('privacy_submit_request')),
          findsNothing,
        );
      },
    );
  }

  _privacyWidgetTest(
    'refresh reads actual new review state without resubmitting intake',
    (tester) async {
      var state = 'claim_active';
      final harness = _RouteHarness(
        tester,
        reply: (r) async {
          if (r.url.path.endsWith('/$_current')) {
            return _json(privacyReceiptJson(requestId: privacyCanonical));
          }
          if (r.url.path.endsWith('/$_review')) {
            return _json(privacyReviewJson(state: state));
          }
          return null;
        },
      );
      await harness.mount();
      expect(find.text('Review in progress'), findsOneWidget);
      state = 'blocked';
      await harness.press(find.text('Refresh request status'));
      expect(find.text('Waiting for policy approval'), findsOneWidget);
      expect(find.text('Review in progress'), findsNothing);
      expect(harness.calls(_current), hasLength(2));
      expect(harness.calls(_review), hasLength(2));
      expect(harness.calls(_submit), isEmpty);
    },
  );

  _privacyWidgetTest(
    'same-user replacement Auth event hides the old review observation',
    (tester) async {
      final harness = _RouteHarness(
        tester,
        reply: (r) async {
          if (r.url.path.endsWith('/$_current')) {
            return _json(privacyReceiptJson(requestId: privacyCanonical));
          }
          if (r.url.path.endsWith('/$_review')) {
            return _json(privacyReviewJson(state: 'claim_active'));
          }
          return null;
        },
      );
      await harness.mount();
      expect(find.text('Review in progress'), findsOneWidget);
      final authority = harness.container.read(
        privacySessionAuthorityProvider,
      )!;
      // The shipping renewal path installs the same-user session and emits
      // signedIn. Silent SDK recoverSession alone emits no renewal event.
      authority.adopt(authority.capture(), privacySession(sid: privacyNewSid));
      await harness.flush();
      expect(find.text('Review in progress'), findsNothing);
      expect(find.text('Review status unavailable'), findsOneWidget);
      expect(find.text('Request recorded'), findsOneWidget);
    },
  );

  _privacyWidgetTest(
    'blocked review remains readable at 320px and 3x text with keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = _RouteHarness(
        tester,
        reply: (r) async {
          if (r.url.path.endsWith('/$_current')) {
            return _json(privacyReceiptJson(requestId: privacyCanonical));
          }
          if (r.url.path.endsWith('/$_review')) {
            return _json(privacyReviewJson(state: 'blocked'));
          }
          return null;
        },
      );
      await harness.mount(scale: 3, keyboard: 260);
      await harness.reveal(find.text('Waiting for policy approval'));
      await harness.press(find.text('Refresh request status'));
      expect(harness.calls(_review), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final dark in [false, true]) {
    for (final highContrast in [false, true]) {
      _privacyWidgetTest(
        '320px 3x keyboard route and confirmation reachable dark=$dark contrast=$highContrast',
        (tester) async {
          tester.view.physicalSize = const Size(320, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          try {
            final harness = _RouteHarness(tester);
            await harness.mount(
              dark: dark,
              highContrast: highContrast,
              scale: 3,
              keyboard: 260,
            );
            await harness.press(find.text('I joined by mistake'));
            await harness.verify();
            await harness.reveal(find.text('Code verified'));
            expect(find.text('Code verified'), findsOneWidget);
            await harness.press(
              find.byKey(const ValueKey('privacy_submit_request')),
            );
            await harness.press(find.text('Cancel'));
            expect(harness.calls(_submit), isEmpty);
            await harness.confirm();
            await harness.reveal(find.text('Request recorded'));
            expect(find.text('Pending review'), findsOneWidget);
            expect(harness.calls(_submit), hasLength(1));
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }
}

String? clientSid(CollectCloudflareClient client) {
  final token = client.auth.currentSession?.accessToken;
  if (token == null) return null;
  return (jsonDecode(
            utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1])),
            ),
          )
          as Map)['session_id']
      as String?;
}
