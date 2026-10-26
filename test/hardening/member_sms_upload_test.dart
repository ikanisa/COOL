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
  bool acknowledge = true;
  final pending = <SmsAccessEnvelope>[];
  final readOwners = <String>[];
  final acknowledged = <DurableSmsReceipt>[];
  final enableCalls = <({bool enabled, String? owner})>[];
  final parkCalls = <({String owner, String id})>[];
  final retryOwners = <String>[];
  Completer<void>? retryEntered;
  Completer<bool>? retryReply;

  @override
  Future<SmsAccessStatus> status() async => SmsAccessStatus(
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
    nativeEnabled = enabled;
    return true;
  }

  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async {
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

  static Future<void> login(CollectCloudflareClient client, String owner) =>
      client.auth
          .recoverSession(
            jsonEncode(
              smsSupabaseSession(
                principal: owner,
                authUserId: owner == _owner ? _authOwner : _authOther,
                sessionId: owner == _owner ? _ownerSession : _otherSession,
              ),
            ),
          )
          .then((_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
