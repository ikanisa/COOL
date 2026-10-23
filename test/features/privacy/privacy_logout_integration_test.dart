// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/privacy/privacy_contract.dart';
import 'package:collect_app/features/privacy/privacy_providers.dart';
import 'package:collect_app/features/privacy/privacy_request_controller.dart';
import 'package:collect_app/features/privacy/privacy_session.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/features/privacy/privacy_transport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'privacy_test_support.dart';

const _smsChannel = MethodChannel('collect/sms_access');
const _snapshotChannel = MethodChannel('collect/secure_snapshot');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_smsChannel, null);
    messenger.setMockMethodCallHandler(_snapshotChannel, null);
  });

  for (final switchOwner in [false, true]) {
    test(
      'default repository logout fences late OTP before native await${switchOwner ? ' and preserves newer owner' : ''}',
      () async {
        final h = await _Harness.create();
        await h.controller.sendCode();
        final verification = h.controller.verifyCode('123456');
        final rejectedVerification = expectLater(
          verification,
          // UID delivery disposes the old autoDispose controller. That must
          // reject its late result as cancelled rather than reuse its view.
          throwsA(switchOwner ? _cancelled : _sessionChanged),
        );
        await h.verifyStarted.future;

        final logout = h.repository.signOut();
        // Actual default provider callback must have run synchronously, even
        // before the platform handler delivers its pending native result.
        expect(() => h.authority.capture(), throwsA(_sessionChanged));
        await h.disableStarted.future;
        expect(h.client.auth.currentSession?.user.id, privacySubject);
        expect(h.controller.codeSent, isFalse);
        expect(h.controller.busy, isFalse);

        if (switchOwner) {
          await h.client.auth.recoverSession(
            jsonEncode(privacySession(subject: privacyOtherSubject).toJson()),
          );
          await h.container.pump();
          expect(h.authority.capture().subjectId, privacyOtherSubject);
        } else {
          // A refresh event carrying the invalidated SID is not a new login.
          h.client.auth.notifyAllSubscribers(CollectAuthEvent.tokenRefreshed);
          await h.container.pump();
          expect(() => h.authority.capture(), throwsA(_sessionChanged));
        }

        h.verifyReply.complete(
          http.Response(
            jsonEncode(privacySession(sid: privacyNewSid).toJson()),
            200,
          ),
        );
        await rejectedVerification;
        expect(
          h.client.auth.currentSession?.user.id,
          switchOwner ? privacyOtherSubject : privacySubject,
        );
        expect(
          h.client.auth.currentSession?.accessToken,
          isNot(privacySession(sid: privacyNewSid).accessToken),
        );
        h.disableReply.complete(true);
        await logout;
        expect(h.logoutRequests, hasLength(1));
        final sent = h.logoutRequests.single;
        expect(sent.url.path, '/v1/auth/logout');
        expect(sent.method, 'POST');
        expect(
          jsonDecode(sent.body),
          switchOwner
              ? <String, dynamic>{}
              : <String, dynamic>{
                  'refresh_token': privacySession().refreshToken,
                },
        );
        expect(sent.headers['Authorization'], 'Bearer ${h.originalToken}');
        expect(
          h.client.auth.currentUser?.id,
          switchOwner ? privacyOtherSubject : null,
        );
        expect(
          h.privacyRequests.where(
            (r) => r.url.path.contains('request_account'),
          ),
          isEmpty,
        );
      },
    );
  }

  test(
    'confirmed receipt hides immediately at default logout initiation',
    () async {
      final h = await _Harness.create();
      await h.controller.refreshStatus();
      expect(h.controller.receipt?.requestId, privacyCanonical);
      final logout = h.repository.signOut();
      expect(h.controller.receipt, isNull);
      expect(h.controller.pendingIdentity, isNull);
      expect(() => h.authority.capture(), throwsA(_sessionChanged));
      await h.disableStarted.future;
      expect(h.client.auth.currentUser?.id, privacySubject);
      h.disableReply.complete(true);
      await logout;
      expect(h.client.auth.currentUser, isNull);
    },
  );

  test(
    'failed native stop keeps old privacy session blocked until a new login',
    () async {
      final h = await _Harness.create(nativeConsentAfterFailure: true);
      final logout = h.repository.signOut();
      final deniedLogout = expectLater(logout, throwsStateError);
      expect(() => h.authority.capture(), throwsA(_sessionChanged));
      await h.disableStarted.future;
      h.disableReply.complete(false);
      await deniedLogout;
      expect(h.logoutRequests, isEmpty);
      expect(h.client.auth.currentSession?.accessToken, h.originalToken);
      h.client.auth.notifyAllSubscribers(CollectAuthEvent.tokenRefreshed);
      await h.container.pump();
      expect(() => h.authority.capture(), throwsA(_sessionChanged));
      await h.client.auth.recoverSession(
        jsonEncode(privacySession(sid: privacyNewSid).toJson()),
      );
      h.client.auth.notifyAllSubscribers(CollectAuthEvent.signedIn);
      await h.container.pump();
      expect(h.authority.capture().sessionId, privacyNewSid);
      expect(h.controller.receipt, isNull);
    },
  );
}

final _sessionChanged = isA<PrivacyRequestException>().having(
  (error) => error.failure,
  'fixed session fence denial',
  PrivacyFailure.sessionChanged,
);
final _cancelled = isA<PrivacyRequestException>().having(
  (error) => error.failure,
  'disposed owner denial',
  PrivacyFailure.cancelled,
);

class _Harness {
  _Harness(this.client, this.container, this.originalToken);
  final CollectCloudflareClient client;
  final ProviderContainer container;
  final String originalToken;
  final disableStarted = Completer<void>();
  final disableReply = Completer<bool>();
  final verifyStarted = Completer<void>();
  final verifyReply = Completer<http.Response>();
  final logoutRequests = <http.Request>[];
  final privacyRequests = <http.Request>[];

  PrivacyRequestController get controller =>
      container.read(privacyRequestControllerProvider)!;
  CollectPrivacySessionAuthority get authority =>
      container.read(privacySessionAuthorityProvider)!;
  CollectRepository get repository =>
      container.read(collectRepositoryProvider.notifier);

  static Future<_Harness> create({
    bool nativeConsentAfterFailure = false,
  }) async {
    late _Harness h;
    final initial = privacySession();
    final client = CollectCloudflareClient(
      'https://synthetic.invalid',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/logout')) {
          h.logoutRequests.add(request);
          return http.Response('{"ok":true}', 200);
        }
        // Initial financial reads are deliberately unavailable. They exercise
        // the production provider without creating fixture financial data or
        // opening realtime/network connections.
        return http.Response(
          '{"message":"Synthetic unavailable read","code":"42501"}',
          403,
        );
      }),
    );
    await client.auth.recoverSession(jsonEncode(initial.toJson()));
    final transport = CollectPrivacyRequestTransport(
      httpClient: MockClient((request) async {
        h.privacyRequests.add(request);
        if (request.url.path.endsWith('/otp')) {
          return http.Response(
            '{"challenge_id":"synthetic-privacy-challenge"}',
            200,
          );
        }
        if (request.url.path.endsWith('/verify')) {
          h.verifyStarted.complete();
          return h.verifyReply.future;
        }
        if (request.url.path.endsWith(
          '/get_current_account_deletion_request_status_v1',
        )) {
          return http.Response(
            jsonEncode(privacyReceiptJson(requestId: privacyCanonical)),
            200,
          );
        }
        throw StateError('Unexpected synthetic privacy request');
      }),
      apiUrl: 'https://synthetic.invalid',
    );
    final container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(client),
        privacyRequestTransportProvider.overrideWithValue(transport),
      ],
    );
    h = _Harness(client, container, initial.accessToken);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_smsChannel, (call) async {
      if (call.method == 'setEnabled') {
        expect(call.arguments['enabled'], isFalse);
        expect(call.arguments['owner_user_id'], privacySubject);
        h.disableStarted.complete();
        return h.disableReply.future;
      }
      if (call.method == 'suspendUnlessOwner') return true;
      if (call.method == 'status') {
        return <String, Object?>{
          'supported': true,
          'consent_enabled': nativeConsentAfterFailure,
        };
      }
      throw StateError('Unexpected synthetic SMS method');
    });
    messenger.setMockMethodCallHandler(_snapshotChannel, (call) async {
      if (call.method == 'clear') return true;
      if (call.method == 'read') return null;
      throw StateError('Privacy integration must not persist a snapshot');
    });
    final subscription = container.listen<PrivacyRequestController?>(
      privacyRequestControllerProvider,
      (_, _) {},
    );
    h.repository;
    await container.pump();
    addTearDown(() async {
      subscription.close();
      container.dispose();
      await client.dispose();
    });
    return h;
  }
}
