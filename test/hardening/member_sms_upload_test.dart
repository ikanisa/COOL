import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/durable_sms_receipt.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';
import '../support/supabase_sms_fixture.dart';
import '../support/synthetic_jwt.dart';

const _owner = '11111111-1111-4111-8111-111111111111';
const _other = '33333333-3333-4333-8333-333333333333';
const _authOwner = 'a1111111-1111-4111-8111-111111111111';
const _authOther = 'a3333333-3333-4333-8333-333333333333';
const _ownerSession = 'b1111111-1111-4111-8111-111111111111';
const _otherSession = 'b3333333-3333-4333-8333-333333333333';
const _envelope = '22222222-2222-4222-8222-222222222222';
const _secondEnvelope = '55555555-5555-4555-8555-555555555555';
const _raw = '44444444-4444-4444-8444-444444444444';
const _body = '  M-Money receipt: reçu 5,000 RWF. Ref Aé123.\nKeep original.  ';
const _time = '2026-10-19T08:17:31.123456+02:00';
const _sender = '  M-Money  ';

CollectProfile _profile(String id) => CollectProfile(
  id: id,
  publicId: id == _owner ? '038491' : '123456',
  whatsappPhone: '',
  countryCode: 'DE',
  currencyCode: 'EUR',
);

http.Response _response(Object? value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> _ack({
  String owner = _owner,
  String body = _body,
  String envelope = _envelope,
}) => {
  'ok': true,
  'receipt': {
    'contract_version': 2,
    'stored': true,
    'raw_sms_id': _raw,
    'owner_user_id': owner,
    'client_envelope_id': envelope,
    'body_sha256': sha256.convert(utf8.encode(body)).toString(),
  },
};

class _Sms extends SmsAccessChannel {
  _Sms({String completeness = 'complete'}) {
    pending.add(
      SmsAccessEnvelope(
        id: _envelope,
        ownerUserId: _owner,
        rawSender: _sender,
        rawBody: _body,
        receivedAtDevice: _time,
        completeness: completeness,
      ),
    );
  }

  bool nativeEnabled = true;
  bool canDisable = true;
  bool acknowledge = true;
  final pending = <SmsAccessEnvelope>[];
  final readOwners = <String>[];
  final acknowledged = <DurableSmsReceipt>[];
  final enableCalls = <({bool enabled, String? owner})>[];
  final parkCalls = <({String owner, String id})>[];
  final retryOwners = <String>[];
  final suspendedOwners = <String?>[];
  Completer<void>? toggleEntered, toggleRelease;
  Completer<void>? retryEntered;
  Completer<bool>? retryReply;
  Completer<void>? statusEntered;
  Completer<SmsAccessStatus>? statusReply;

  @override
  Future<SmsAccessStatus> status({String? ownerUserId}) async {
    final reply = statusReply;
    if (reply != null) {
      statusReply = null;
      statusEntered!.complete();
      return reply.future;
    }
    return SmsAccessStatus(
      supported: true,
      declared: true,
      enabled: nativeEnabled,
      consentEnabled: nativeEnabled,
      granted: true,
      requestedBefore: true,
      shouldShowRationale: false,
      permanentlyDenied: false,
      queueOverflowed: false,
      queueNeedsReview: pending.any((item) => item.needsReview),
    );
  }

  @override
  Future<List<SmsAccessEnvelope>> readPendingSms({
    required String ownerUserId,
  }) async {
    readOwners.add(ownerUserId);
    return List.unmodifiable(pending);
  }

  @override
  Future<bool> acknowledgeDurableReceipt(DurableSmsReceipt receipt) async {
    acknowledged.add(receipt);
    if (acknowledge) {
      pending.removeWhere(
        (item) =>
            item.id == receipt.envelopeId &&
            item.ownerUserId == receipt.ownerUserId &&
            sha256.convert(utf8.encode(item.rawBody)).toString() ==
                receipt.bodySha256,
      );
    }
    return acknowledge;
  }

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async {
    enableCalls.add((enabled: enabled, owner: ownerUserId));
    if (!enabled && !canDisable) return false;
    nativeEnabled = enabled;
    if (toggleEntered case final entered?) {
      if (!entered.isCompleted) entered.complete();
    }
    if (toggleRelease case final release?) await release.future;
    return true;
  }

  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async {
    suspendedOwners.add(currentUserId);
    if (currentUserId != _owner) nativeEnabled = false;
    return true;
  }

  SmsAccessEnvelope _review(SmsAccessEnvelope item, bool review) =>
      SmsAccessEnvelope(
        id: item.id,
        ownerUserId: item.ownerUserId,
        rawSender: item.rawSender,
        rawBody: item.rawBody,
        receivedAtDevice: item.receivedAtDevice,
        completeness: item.completeness,
        needsReview: review,
      );

  @override
  Future<bool> parkPendingSms({
    required String ownerUserId,
    required String id,
  }) async {
    parkCalls.add((owner: ownerUserId, id: id));
    if (!nativeEnabled || ownerUserId != _owner) return false;
    final index = pending.indexWhere(
      (item) => item.id == id && item.ownerUserId == ownerUserId,
    );
    if (index < 0) return false;
    pending[index] = _review(pending[index], true);
    return true;
  }

  @override
  Future<bool> retryRejectedSms({required String ownerUserId}) async {
    retryOwners.add(ownerUserId);
    retryEntered?.complete();
    if (retryReply != null && !await retryReply!.future) return false;
    if (!nativeEnabled || ownerUserId != _owner) return false;
    for (var i = 0; i < pending.length; i++) {
      pending[i] = _review(pending[i], false);
    }
    return true;
  }
}

class _Repository extends FixtureCollectRepository {
  _Repository(CollectCloudflareClient client, _Sms channel)
    : super(
        backend: client,
        smsAccessChannel: channel,
        profileOverride: _profile(_owner),
      );

  int reloads = 0;
  Completer<void>? reloadSignal;
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    reloads++;
    reloadSignal?.complete();
    reloadSignal = null;
  }

  void replaceOwner(String id) {
    state = state.copyWith(currentProfile: _profile(id));
  }
}

class _Harness {
  _Harness(this.client, this.repository, this.sms, this.requests);
  final CollectCloudflareClient client;
  final _Repository repository;
  final _Sms sms;
  final List<http.Request> requests;

  static Future<_Harness> create({
    Future<http.Response> Function(http.Request)? respond,
    String completeness = 'complete',
  }) async {
    final requests = <http.Request>[];
    final config = smsSupabaseConfiguration();
    final client = CollectCloudflareClient(
      config.api.origin,
      supabaseConfiguration: config,
      httpClient: MockClient((request) async {
        expectSupabaseSmsRequest(request);
        requests.add(request);
        if (respond != null) return respond(request);
        if (request.url.path == smsSupabaseUploadPath) {
          return _response(_ack());
        }
        if (request.url.path == smsSupabaseConsentPath) {
          return _response(null);
        }
        throw StateError(
          'Unexpected provider/integrity/registry request: '
          '${request.url.path}',
        );
      }),
    );
    await login(client, _owner);
    final sms = _Sms(completeness: completeness);
    final repository = _Repository(client, sms);
    addTearDown(repository.dispose);
    addTearDown(client.dispose);
    return _Harness(client, repository, sms, requests);
  }

  Future<void> replaceSession(String owner, String sessionId) async {
    final reloaded = Completer<void>();
    repository.reloadSignal = reloaded;
    await login(client, owner, sessionId: sessionId);
    await reloaded.future.timeout(const Duration(seconds: 3));
    repository.replaceOwner(owner);
  }

  static Future<void> login(
    CollectCloudflareClient client,
    String owner, {
    String? sessionId,
  }) => client.auth
      .recoverSession(
        jsonEncode(
          smsSupabaseSession(
            principal: owner,
            authUserId: owner == _owner ? _authOwner : _authOther,
            sessionId:
                sessionId ?? (owner == _owner ? _ownerSession : _otherSession),
          ),
        ),
      )
      .then((_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const replacementSession = 'baaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  test(
    'a refreshed bearer for the same authority keeps the original upload and receipt',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      final h = await _Harness.create(
        respond: (_) {
          entered.complete();
          return reply.future;
        },
      );
      final auth = h.client.auth;
      final original = auth.currentSession!;
      final generation = h.repository.sessionGeneration;
      final run = h.repository.syncPendingSmsAccess();
      await entered.future;
      final replacement = smsSupabaseSession(
        principal: _owner,
        authUserId: _authOwner,
        sessionId: _ownerSession,
      );
      replacement['access_token'] = syntheticJwt(
        {'alg': 'ES256', 'typ': 'JWT'},
        {...original.claims, 'iat': 1},
      );
      await auth.recoverSession(jsonEncode(replacement));
      expect(auth.currentSession!.accessToken, isNot(original.accessToken));
      expect(h.repository.sessionGeneration, generation);
      reply.complete(_response(_ack()));
      expect(await run, 1);
      expect(
        h.requests.single.headers['authorization'],
        'Bearer ${original.accessToken}',
      );
      expect(h.sms.acknowledged.single.envelopeId, _envelope);
      expect(h.sms.pending, isEmpty);
    },
  );
  test(
    'an event during opt-in waits for the original consent acknowledgement before uploading',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      final h = await _Harness.create(
        respond: (request) async {
          if (request.url.path == smsSupabaseConsentPath) {
            entered.complete();
            return reply.future;
          }
          return _response(_ack());
        },
      );
      final allowed = h.repository.setSmsAccess(true);
      await entered.future;
      final wake = h.repository.syncPendingSmsAccess();
      await Future<void>.delayed(Duration.zero);
      expect(h.requests.map((r) => r.url.path), [smsSupabaseConsentPath]);
      expect(h.sms.readOwners, isEmpty);
      expect(h.sms.pending.single.rawBody, _body);
      reply.complete(_response(null));
      expect(await allowed, isTrue);
      expect(await wake, 1);
      expect(h.requests.map((r) => r.url.path), [
        smsSupabaseConsentPath,
        smsSupabaseUploadPath,
      ]);
      expect(h.sms.acknowledged.single.envelopeId, _envelope);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'failed rollback keeps the observed native capture state and original for review',
    () async {
      final h = await _Harness.create(
        respond: (_) async => _response({'error': 'unavailable'}, status: 503),
      );
      h.sms.canDisable = false;
      await expectLater(h.repository.setSmsAccess(true), throwsA(anything));
      expect(h.sms.nativeEnabled, isTrue);
      expect(h.repository.state.smsAccessEnabled, isTrue);
      expect(h.repository.state.smsSyncNeedsAttention, isTrue);
      expect(h.sms.pending.single.id, _envelope);
      expect(h.sms.acknowledged, isEmpty);
    },
  );

  test(
    'scoped channel status refuses old unscoped bridge replies and retains ordinary device queries',
    () async {
      const method = MethodChannel('collect/sms_access');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      var scopedResponse = false;
      messenger.setMockMethodCallHandler(method, (call) async {
        calls.add(call);
        return <String, Object?>{
          'supported': true,
          'declared': true,
          'granted': true,
          'enabled': true,
          'consent_enabled': true,
          if (scopedResponse) 'owner_scoped': true,
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(method, null));
      const channel = SmsAccessChannel();
      expect(
        (await channel.status(ownerUserId: _owner)).bridgeAvailable,
        isFalse,
      );
      expect((await channel.status()).enabled, isTrue);
      scopedResponse = true;
      expect((await channel.status(ownerUserId: _owner)).enabled, isTrue);
      expect(calls.map((c) => c.arguments), [
        {'owner_user_id': _owner},
        null,
        {'owner_user_id': _owner},
      ]);
    },
  );

  test(
    'a newer status read wins when an earlier device callback arrives late',
    () async {
      final h = await _Harness.create();
      final reply = Completer<SmsAccessStatus>();
      h.sms.statusEntered = Completer<void>();
      h.sms.statusReply = reply;
      final old = h.repository.refreshSmsAccessStatus();
      await h.sms.statusEntered!.future;
      h.sms.nativeEnabled = false;
      expect((await h.repository.refreshSmsAccessStatus()).enabled, isFalse);
      reply.complete(
        const SmsAccessStatus(
          supported: true,
          declared: true,
          enabled: true,
          consentEnabled: true,
          granted: true,
          requestedBefore: true,
          shouldShowRationale: false,
          permanentlyDenied: false,
          queueOverflowed: true,
        ),
      );
      expect((await old).enabled, isFalse);
      expect(h.repository.state.smsAccessEnabled, isFalse);
      expect(h.repository.state.smsQueueOverflowed, isFalse);
    },
  );
  for (final enabled in [true, false]) {
    test(
      'native toggle $enabled cannot send consent through a replacement session for the same member',
      () async {
        final h = await _Harness.create();
        h.sms.toggleEntered = Completer<void>();
        h.sms.toggleRelease = Completer<void>();
        final result = h.repository.setSmsAccess(
          enabled,
          expectedOwnerUserId: _owner,
        );
        final stale = expectLater(result, throwsStateError);
        await h.sms.toggleEntered!.future;
        await h.replaceSession(_owner, replacementSession);
        h.sms.toggleRelease!.complete();
        await stale;
        expect(h.requests, isEmpty);
        expect(h.sms.acknowledged, isEmpty);
        expect(h.sms.pending.single.id, _envelope);
        expect(h.sms.pending.single.rawBody, _body);
      },
    );
  }

  test(
    'old revoked permission status cannot withdraw consent for the new member',
    () async {
      final h = await _Harness.create();
      final reply = Completer<SmsAccessStatus>();
      h.sms.statusEntered = Completer<void>();
      h.sms.statusReply = reply;
      final read = h.repository.refreshSmsAccessStatus();
      await h.sms.statusEntered!.future;
      await h.replaceSession(_other, _otherSession);
      reply.complete(
        const SmsAccessStatus(
          supported: true,
          declared: true,
          enabled: false,
          consentEnabled: true,
          granted: false,
          requestedBefore: true,
          shouldShowRationale: false,
          permanentlyDenied: true,
          queueOverflowed: false,
        ),
      );
      final readback = await read;
      expect(readback.enabled, isFalse);
      expect(h.sms.enableCalls, isEmpty);
      expect(h.requests, isEmpty);
      expect(h.repository.state.currentProfile?.id, _other);
      expect(h.sms.pending.single.ownerUserId, _owner);
    },
  );

  test(
    'previous session status cannot publish its permission or pending review',
    () async {
      final h = await _Harness.create();
      final reply = Completer<SmsAccessStatus>();
      h.sms.statusEntered = Completer<void>();
      h.sms.statusReply = reply;
      final read = h.repository.refreshSmsAccessStatus();
      await h.sms.statusEntered!.future;
      await h.replaceSession(_owner, replacementSession);
      reply.complete(
        const SmsAccessStatus(
          supported: true,
          declared: true,
          enabled: true,
          consentEnabled: true,
          granted: true,
          requestedBefore: true,
          shouldShowRationale: false,
          permanentlyDenied: false,
          queueOverflowed: true,
          queueNeedsReview: true,
        ),
      );
      expect((await read).enabled, isFalse);
      expect(h.repository.state.smsAccessEnabled, isFalse);
      expect(h.repository.state.smsSyncNeedsAttention, isFalse);
      expect(h.repository.state.smsQueueOverflowed, isFalse);
      expect(h.requests, isEmpty);
    },
  );

  test(
    'a rejected old enable cannot turn off a newer explicit opt-in on the same account',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      var consentCalls = 0;
      final h = await _Harness.create(
        respond: (request) async {
          if (request.url.path == smsSupabaseUploadPath) {
            return _response(_ack());
          }
          if (consentCalls++ == 0) {
            entered.complete();
            return reply.future;
          }
          return _response(null);
        },
      );
      final original = h.repository.setSmsAccess(true);
      final failed = expectLater(original, throwsA(anything));
      await entered.future;
      await h.replaceSession(_owner, replacementSession);
      final replacement = h.repository.setSmsAccess(true);
      await Future<void>.delayed(Duration.zero);
      reply.complete(_response({'error': 'unavailable'}, status: 503));
      await failed;
      expect(await replacement, isTrue);
      expect(h.sms.enableCalls.where((action) => !action.enabled), isEmpty);
      expect(h.sms.nativeEnabled, isTrue);
      expect(h.repository.state.smsAccessEnabled, isTrue);
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'new session drains the original envelope after the old response without inheriting its acknowledgement',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      var uploads = 0;
      final h = await _Harness.create(
        respond: (request) async {
          if (uploads++ == 0) {
            entered.complete();
            return reply.future;
          }
          return _response(_ack());
        },
      );
      final firstBearer = h.client.auth.currentSession!.accessToken;
      final original = h.repository.syncPendingSmsAccess();
      final stale = expectLater(original, throwsStateError);
      await entered.future;
      await h.replaceSession(_owner, replacementSession);
      final secondBearer = h.client.auth.currentSession!.accessToken;
      expect(secondBearer, isNot(firstBearer));
      final fresh = h.repository.syncPendingSmsAccess();
      reply.complete(_response(_ack()));
      await stale;
      expect(await fresh, 1);
      expect(h.requests.map((r) => r.headers['authorization']), [
        'Bearer $firstBearer',
        'Bearer $secondBearer',
      ]);
      expect(h.requests.map((r) => r.body).toSet(), hasLength(1));
      expect(h.sms.acknowledged.map((r) => r.envelopeId), [_envelope]);
      expect(h.sms.pending, isEmpty);
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'Supabase email-only DE member uploads originals without a phone or MoMo wallet',
    () async {
      final h = await _Harness.create();
      expect(h.repository.state.currentProfile!.momoNumber, isEmpty);
      expect(h.repository.state.currentProfile!.whatsappPhone, isEmpty);
      expect(h.client.auth.currentUser?.id, _owner);
      expect(h.client.auth.currentUser?.phone, isNull);
      expect(h.client.auth.currentSession?.claims['sub'], _authOwner);
      expect(
        h.client.auth.currentSession?.claims['iss'],
        '$smsSupabaseProject/auth/v1',
      );
      final initialContributions = h.repository.state.contributions;
      expect(await h.repository.syncPendingSmsAccess(), 1);
      expect(h.requests.map((r) => r.url.path), [smsSupabaseUploadPath]);
      expect(jsonDecode(h.requests.single.body), {
        'client_envelope_id': _envelope,
        'raw_sender': _sender,
        'raw_body': _body,
        'received_at_device': _time,
        'completeness': 'complete',
      });
      expect(
        h.requests.single.headers['Authorization'],
        'Bearer ${h.client.auth.currentSession!.accessToken}',
      );
      expect(h.sms.readOwners, [_owner]);
      expect(h.sms.acknowledged, hasLength(1));
      final receipt = h.sms.acknowledged.single;
      expect(receipt.ownerUserId, _owner);
      expect(receipt.envelopeId, _envelope);
      expect(receipt.rawSmsId, _raw);
      expect(receipt.bodySha256, sha256.convert(utf8.encode(_body)).toString());
      expect(h.sms.pending, isEmpty);
      expect(h.repository.reloads, 1);
      expect(
        h.repository.state.contributions,
        initialContributions,
        reason: 'Uploading evidence does not post a contribution.',
      );
    },
  );

  test(
    'queue completeness is passed intact instead of silently becoming complete',
    () async {
      final h = await _Harness.create(completeness: 'incomplete');
      expect(await h.repository.syncPendingSmsAccess(), 1);
      expect(jsonDecode(h.requests.single.body)['completeness'], 'incomplete');
    },
  );

  test(
    'native ACK failure retains exact pending message and can safely retry',
    () async {
      final h = await _Harness.create();
      h.sms.acknowledge = false;
      await expectLater(h.repository.syncPendingSmsAccess(), throwsStateError);
      expect(h.sms.pending.single.rawBody, _body);
      expect(h.repository.state.smsSyncNeedsAttention, isTrue);
      expect(h.repository.reloads, 0);
      final firstBody = h.requests.single.body;
      h.sms.acknowledge = true;
      expect(await h.repository.syncPendingSmsAccess(), 1);
      expect(h.requests.last.body, firstBody);
      expect(h.sms.pending, isEmpty);
      expect(h.repository.state.smsSyncNeedsAttention, isFalse);
    },
  );

  test('contradictory server ACK never reaches native deletion', () async {
    final h = await _Harness.create(
      respond: (_) async => _response(_ack(owner: _other)),
    );
    await expectLater(
      h.repository.syncPendingSmsAccess(),
      throwsFormatException,
    );
    expect(h.sms.acknowledged, isEmpty);
    expect(h.sms.pending.single.rawBody, _body);
  });

  test(
    'Supabase auth subject in an ACK cannot replace the Collect queue owner',
    () async {
      final h = await _Harness.create(
        respond: (_) async => _response(_ack(owner: _authOwner)),
      );
      expect(h.client.auth.currentSession?.claims['sub'], _authOwner);
      await expectLater(
        h.repository.syncPendingSmsAccess(),
        throwsFormatException,
      );
      expect(h.sms.readOwners, [_owner]);
      expect(h.sms.acknowledged, isEmpty);
      expect(h.sms.pending.single.ownerUserId, _owner);
      expect(h.sms.pending.single.rawBody, _body);
    },
  );

  test(
    'native row owned by the Supabase subject is retained without uploading',
    () async {
      final h = await _Harness.create();
      h.sms.pending[0] = const SmsAccessEnvelope(
        id: _envelope,
        ownerUserId: _authOwner,
        rawSender: _sender,
        rawBody: _body,
        receivedAtDevice: _time,
      );
      await expectLater(h.repository.syncPendingSmsAccess(), throwsStateError);
      expect(h.sms.readOwners, [_owner]);
      expect(h.requests, isEmpty);
      expect(h.sms.acknowledged, isEmpty);
      expect(h.sms.pending.single.rawBody, _body);
      expect(h.repository.state.smsSyncNeedsAttention, isTrue);
    },
  );

  test(
    'late upload response after an owner switch cannot acknowledge old evidence',
    () async {
      final entered = Completer<void>(), reply = Completer<http.Response>();
      final h = await _Harness.create(
        respond: (_) {
          entered.complete();
          return reply.future;
        },
      );
      final capturedBearer = h.client.auth.currentSession!.accessToken;
      final pending = h.repository.syncPendingSmsAccess();
      final failed = expectLater(pending, throwsStateError);
      await entered.future;
      await _Harness.login(h.client, _other);
      h.repository.replaceOwner(_other);
      reply.complete(_response(_ack()));
      await failed;
      expect(
        h.requests.single.headers['authorization'],
        'Bearer $capturedBearer',
      );
      expect(h.client.auth.currentSession?.claims['sub'], _authOther);
      expect(h.sms.acknowledged, isEmpty);
      expect(h.sms.pending.single.ownerUserId, _owner);
      expect(h.sms.pending.single.rawBody, _body);
    },
  );

  test(
    'offline transport leaves immutable originals queued and marks attention',
    () async {
      final h = await _Harness.create(
        respond: (_) async => throw http.ClientException('offline'),
      );
      await expectLater(
        h.repository.syncPendingSmsAccess(),
        throwsA(isA<Exception>()),
      );
      expect(h.sms.acknowledged, isEmpty);
      expect(h.sms.pending.single.rawBody, _body);
      expect(h.repository.state.smsSyncNeedsAttention, isTrue);
    },
  );

  test(
    'DE consent needs no registry or wallet hash and withdrawal turns capture off',
    () async {
      final h = await _Harness.create();
      expect(
        await h.repository.setSmsAccess(true, expectedOwnerUserId: _owner),
        isTrue,
      );
      expect(jsonDecode(h.requests.single.body), {
        'enabled': true,
        'build_channel': 'android_sms_access',
        'device_label': 'flutter_app',
      });
      expect(
        await h.repository.setSmsAccess(false, expectedOwnerUserId: _owner),
        isFalse,
      );
      expect(h.sms.enableCalls, [
        (enabled: true, owner: _owner),
        (enabled: false, owner: _owner),
      ]);
      expect(h.sms.nativeEnabled, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(h.repository.state.smsAccessEnabled, isFalse);
      expect(jsonDecode(h.requests.last.body)['enabled'], isFalse);
      expect(
        h.requests.every((r) => r.url.path == smsSupabaseConsentPath),
        isTrue,
      );
      expect(
        h.sms.pending.single.rawBody,
        _body,
        reason: 'Withdrawal stops capture without clearing retained originals.',
      );
    },
  );

  test('explicit SMS disable cannot follow an account switch', () async {
    final h = await _Harness.create();
    h.sms.toggleEntered = Completer<void>();
    h.sms.toggleRelease = Completer<void>();
    addTearDown(() {
      if (!h.sms.toggleRelease!.isCompleted) h.sms.toggleRelease!.complete();
    });
    final pending = h.repository.setSmsAccess(false);
    final failed = expectLater(pending, throwsStateError);
    await h.sms.toggleEntered!.future.timeout(const Duration(seconds: 3));
    final authReloaded = Completer<void>();
    h.repository.reloadSignal = authReloaded;
    await _Harness.login(h.client, _other);
    await authReloaded.future.timeout(const Duration(seconds: 3));
    h.repository.replaceOwner(_other);
    h.sms.suspendedOwners.clear();
    h.sms.toggleRelease!.complete();
    await failed;
    expect(h.sms.suspendedOwners, [_other]);
    expect(h.sms.enableCalls, [(enabled: false, owner: _owner)]);
    expect(h.sms.acknowledged, isEmpty);
    expect(h.requests, isEmpty);
    expect(h.sms.pending.single.ownerUserId, _owner);
    expect(h.sms.pending.single.rawBody, _body);
  });

  test(
    'successful server consent ACK starts foreground recovery asynchronously',
    () async {
      final consentEntered = Completer<void>(),
          consentReply = Completer<http.Response>();
      final h = await _Harness.create(
        respond: (request) {
          if (request.url.path == smsSupabaseConsentPath) {
            consentEntered.complete();
            return consentReply.future;
          }
          return Future.value(_response(_ack()));
        },
      );
      final reloaded = Completer<void>();
      h.repository.reloadSignal = reloaded;
      final optedIn = h.repository.setSmsAccess(
        true,
        expectedOwnerUserId: _owner,
      );
      await consentEntered.future;
      expect(h.requests, hasLength(1));
      expect(h.sms.acknowledged, isEmpty);
      consentReply.complete(_response(null));
      expect(await optedIn, isTrue);
      await reloaded.future;
      expect(h.requests.map((r) => r.url.path), [
        smsSupabaseConsentPath,
        smsSupabaseUploadPath,
      ]);
      expect(h.sms.pending, isEmpty);
    },
  );

  for (final status in [400, 409, 413, 422]) {
    test(
      'permanent$status parks only that original and continues later uploads',
      () async {
        final h = await _Harness.create(
          respond: (request) async {
            final body = jsonDecode(request.body) as Map;
            return body['client_envelope_id'] == _envelope
                ? _response({'error': 'source_rejected'}, status: status)
                : _response(
                    _ack(envelope: _secondEnvelope, body: 'second original'),
                  );
          },
        );
        h.sms.pending.add(
          const SmsAccessEnvelope(
            id: _secondEnvelope,
            ownerUserId: _owner,
            rawSender: _sender,
            rawBody: 'second original',
            receivedAtDevice: _time,
          ),
        );
        expect(await h.repository.syncPendingSmsAccess(), 1);
        expect(h.requests, hasLength(2));
        expect(h.sms.parkCalls, [(owner: _owner, id: _envelope)]);
        expect(h.sms.pending.single.rawBody, _body);
        expect(h.sms.pending.single.rawSender, _sender);
        expect(h.sms.pending.single.needsReview, isTrue);
        expect(h.sms.acknowledged.single.envelopeId, _secondEnvelope);
        expect(h.repository.state.smsSyncNeedsAttention, isTrue);
      },
    );
  }

  for (final status in [401, 403, 408, 429, 500]) {
    test(
      'authorization or transient$status stops without parking or deleting',
      () async {
        final h = await _Harness.create(
          respond: (_) async =>
              _response({'error': 'not_ready'}, status: status),
        );
        h.sms.pending.add(
          const SmsAccessEnvelope(
            id: _secondEnvelope,
            ownerUserId: _owner,
            rawSender: _sender,
            rawBody: 'second original',
            receivedAtDevice: _time,
          ),
        );
        await expectLater(
          h.repository.syncPendingSmsAccess(),
          throwsA(isA<CollectFunctionException>()),
        );
        expect(h.requests, hasLength(1));
        expect(h.sms.pending, hasLength(2));
        expect(h.sms.parkCalls, isEmpty);
        expect(h.sms.acknowledged, isEmpty);
        expect(h.repository.state.smsSyncNeedsAttention, isTrue);
      },
    );
  }

  test(
    'foreground skips parked originals and retains review attention',
    () async {
      final h = await _Harness.create(
        respond: (_) async =>
            _response(_ack(envelope: _secondEnvelope, body: 'second original')),
      );
      await h.sms.parkPendingSms(ownerUserId: _owner, id: _envelope);
      h.sms.pending.add(
        const SmsAccessEnvelope(
          id: _secondEnvelope,
          ownerUserId: _owner,
          rawSender: _sender,
          rawBody: 'second original',
          receivedAtDevice: _time,
        ),
      );
      expect(await h.repository.syncPendingSmsAccess(), 1);
      expect(
        jsonDecode(h.requests.single.body)['client_envelope_id'],
        _secondEnvelope,
      );
      expect(h.sms.pending.single.needsReview, isTrue);
      expect(h.repository.state.smsSyncNeedsAttention, isTrue);
    },
  );

  test(
    'explicit owner retry preserves original identity and clears only review metadata',
    () async {
      final h = await _Harness.create();
      await h.sms.parkPendingSms(ownerUserId: _owner, id: _envelope);
      expect(await h.repository.syncPendingSmsAccess(), 0);
      expect(h.requests, isEmpty);
      expect(h.repository.state.smsSyncNeedsAttention, isTrue);
      expect(
        await h.repository.retryRejectedSmsAccess(expectedOwnerUserId: _owner),
        1,
      );
      expect(h.sms.retryOwners, [_owner]);
      expect(h.sms.enableCalls, isEmpty);
      expect(jsonDecode(h.requests.single.body), {
        'client_envelope_id': _envelope,
        'raw_sender': _sender,
        'raw_body': _body,
        'received_at_device': _time,
        'completeness': 'complete',
      });
      expect(h.sms.pending, isEmpty);
      expect(h.repository.state.smsSyncNeedsAttention, isFalse);
    },
  );

  test(
    'retry cannot enable withdrawn capture or act for a different owner',
    () async {
      final h = await _Harness.create();
      await h.sms.parkPendingSms(ownerUserId: _owner, id: _envelope);
      await expectLater(
        h.repository.retryRejectedSmsAccess(expectedOwnerUserId: _other),
        throwsStateError,
      );
      h.sms.nativeEnabled = false;
      await expectLater(
        h.repository.retryRejectedSmsAccess(expectedOwnerUserId: _owner),
        throwsStateError,
      );
      expect(h.sms.retryOwners, isEmpty);
      expect(h.sms.enableCalls, isEmpty);
      expect(h.requests, isEmpty);
      expect(h.sms.pending.single.needsReview, isTrue);
    },
  );

  test(
    'owner change while retry metadata awaits cannot upload or acknowledge',
    () async {
      final h = await _Harness.create();
      await h.sms.parkPendingSms(ownerUserId: _owner, id: _envelope);
      h.sms.retryEntered = Completer<void>();
      h.sms.retryReply = Completer<bool>();
      final retry = h.repository.retryRejectedSmsAccess(
        expectedOwnerUserId: _owner,
      );
      final failed = expectLater(retry, throwsStateError);
      await h.sms.retryEntered!.future;
      h.repository.replaceOwner(_other);
      h.sms.retryReply!.complete(true);
      await failed;
      expect(h.requests, isEmpty);
      expect(h.sms.acknowledged, isEmpty);
      expect(h.sms.pending.single.rawBody, _body);
    },
  );

  test(
    'failed backend opt-in turns native capture off without clearing originals',
    () async {
      final h = await _Harness.create(
        respond: (_) async => _response({'error': 'unavailable'}, status: 503),
      );
      await expectLater(
        h.repository.setSmsAccess(true, expectedOwnerUserId: _owner),
        throwsA(anything),
      );
      expect(h.sms.enableCalls, [
        (enabled: true, owner: _owner),
        (enabled: false, owner: _owner),
      ]);
      expect(h.sms.nativeEnabled, isFalse);
      expect(h.repository.state.smsAccessEnabled, isFalse);
      expect(h.sms.pending.single.rawBody, _body);
    },
  );

  test(
    'legacy native envelope defaults completeness and preserves explicit flags',
    () {
      final base = <String, Object?>{
        'id': _envelope,
        'owner_user_id': _owner,
        'raw_sender': _sender,
        'raw_body': _body,
        'received_at_device': _time,
      };
      expect(SmsAccessEnvelope.fromMap(base).completeness, 'complete');
      expect(SmsAccessEnvelope.fromMap(base).needsReview, isFalse);
      for (final flag in [true, 'true']) {
        expect(
          SmsAccessEnvelope.fromMap({
            ...base,
            'needs_review': flag,
          }).needsReview,
          isTrue,
        );
      }
      expect(
        SmsAccessEnvelope.fromMap({
          ...base,
          'completeness': 'incomplete',
        }).completeness,
        'incomplete',
      );
    },
  );

  test(
    'native review helpers carry only the current owner and immutable capture ID',
    () async {
      const method = MethodChannel('collect/sms_access');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(method, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(method, null),
      );
      expect(
        await const SmsAccessChannel().parkPendingSms(
          ownerUserId: _owner,
          id: _envelope,
        ),
        isTrue,
      );
      expect(
        await const SmsAccessChannel().retryRejectedSms(ownerUserId: _owner),
        isTrue,
      );
      expect(calls.map((c) => c.method), [
        'parkPendingSms',
        'retryRejectedSms',
      ]);
      expect(calls.first.arguments, {'owner_user_id': _owner, 'id': _envelope});
      expect(calls.last.arguments, {'owner_user_id': _owner});
    },
  );

  test(
    'review flags default safely and malformed row metadata is not silently uploaded',
    () {
      expect(const SmsAccessStatus.unavailable().queueNeedsReview, isFalse);
      expect(
        SmsAccessStatus.fromMap({'queue_needs_review': true}).queueNeedsReview,
        isTrue,
      );
      expect(
        () => SmsAccessEnvelope.fromMap({'needs_review': 'unknown'}),
        throwsFormatException,
      );
    },
  );
}
