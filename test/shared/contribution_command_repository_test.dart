import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/payments/contribution_command_journal.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:collect_app/core/security/contribution_command_storage_contract.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/contribution_command_values.dart';

const _draft = PaymentIntentDraft(
  collectionId: commandGroupId,
  amountRwf: 5000,
);
const _nextSession = '20000000-0000-0000-0000-000000000002';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'actual repository persists exact original body before one creation POST and uses separate review',
    () async {
      final h = await _Harness.create();
      h.onCreate = (request) async {
        final rows = await h.journal.read(commandOwner());
        final record = rows.single;
        expect(record.phase, ContributionCommandPhase.dispatchPossible);
        expect(jsonDecode(request.body), record.body.toJson());
        expect(record.originalSessionId, commandSessionId);
        return commandIntentWire();
      };
      final intent = await h.repo.prepareContributionIntent(_draft);
      expect(h.creates, hasLength(1));
      final originalBody = Map<String, dynamic>.from(
        jsonDecode(h.creates.single.body) as Map,
      );
      expect(originalBody.keys.toSet(), {
        'collection',
        'p_expected_amount_rwf',
        'p_sender_phone_hash',
        'p_request_id',
      });
      final checkpoint = (await h.journal.read(commandOwner())).single;
      expect(checkpoint.phase, ContributionCommandPhase.receiptRetained);
      final review = await h.repo.reviewContributionIntent(intent);
      expect(h.reviews, hasLength(1));
      expect(h.creates, hasLength(1));
      final permit = await h.repo.claimContributionHandoff(intent, review);
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
      expect(permit.consume(), isTrue);
      expect(permit.consume(), isFalse);
      final restarted = h.newRepository();
      expect(
        (await restarted.restoreContributionCommand(
          commandGroupId,
        ))!.body.canonical,
        checkpoint.body.canonical,
      );
      await expectLater(
        restarted.reviewContributionIntent(intent),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      expect(h.creates, hasLength(1));
    },
  );
  for (final failure in [
    'lost creation response',
    'malformed creation receipt',
  ]) {
    test(
      '$failure retains request and repeated preparation never creates another key',
      () async {
        final h = await _Harness.create();
        h.onCreate = (_) {
          if (failure.startsWith('lost')) {
            throw http.ClientException('Synthetic lost response');
          }
          return commandIntentWire()..['amount_minor'] = 5001;
        };
        await expectLater(
          h.repo.prepareContributionIntent(_draft),
          throwsA(isA<ContributionRecoveryRequired>()),
        );
        final retained = (await h.journal.read(commandOwner())).single;
        await expectLater(
          h.repo.prepareContributionIntent(
            const PaymentIntentDraft(
              collectionId: commandGroupId,
              amountRwf: 8000,
            ),
          ),
          throwsA(isA<ContributionRecoveryRequired>()),
        );
        expect(h.creates, hasLength(1));
        expect(
          (await h.journal.read(commandOwner())).single.body.canonical,
          retained.body.canonical,
        );
        final observed = await h.repo.checkContributionCommand(
          retained.body.requestId,
        );
        expect(observed.intentId, isNull);
        expect(h.lookups, hasLength(1));
        expect(
          jsonDecode(h.lookups.single.body)['p_original_body'],
          retained.body.toJson(),
        );
        expect(h.creates, hasLength(1));
        expect(h.repo.state.paymentIntents, isEmpty);
      },
    );
  }
  for (final sender in [
    '',
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  ]) {
    test(
      'creation receipt with invalid sender binding remains unresolved',
      () async {
        final h = await _Harness.create();
        h.onCreate = (_) => commandIntentWire(senderHash: sender);
        await expectLater(
          h.repo.prepareContributionIntent(_draft),
          throwsA(isA<ContributionRecoveryRequired>()),
        );
        final retained = (await h.journal.read(commandOwner())).single;
        expect(retained.phase, ContributionCommandPhase.dispatchPossible);
        expect(retained.providerHandoffPossible, isFalse);
        expect(h.repo.state.paymentIntents, isEmpty);
      },
    );
  }
  for (final failure in [
    'prepare ACK',
    'dispatch ACK',
    'receipt ACK',
    'handoff ACK',
  ]) {
    test(
      'lost local $failure cannot grant creation or provider launch',
      () async {
        final h = await _Harness.create();
        if (failure == 'prepare ACK') h.storage.loseNextAcknowledgement = true;
        if (failure == 'dispatch ACK') h.storage.loseAtCommit = 2;
        if (failure == 'receipt ACK') h.storage.loseAtCommit = 3;
        if (failure != 'handoff ACK') {
          await expectLater(
            h.repo.prepareContributionIntent(_draft),
            failure == 'prepare ACK'
                ? throwsStateError
                : throwsA(isA<ContributionRecoveryRequired>()),
          );
          expect(h.creates, hasLength(failure == 'receipt ACK' ? 1 : 0));
          expect(
            await h.repo.restoreContributionCommand(commandGroupId),
            isNotNull,
          );
          await expectLater(
            h.repo.prepareContributionIntent(_draft),
            throwsA(isA<ContributionRecoveryRequired>()),
          );
          expect(h.creates, hasLength(failure == 'receipt ACK' ? 1 : 0));
        } else {
          final intent = await h.repo.prepareContributionIntent(_draft);
          final review = await h.repo.reviewContributionIntent(intent);
          h.storage.loseNextAcknowledgement = true;
          await expectLater(
            h.repo.claimContributionHandoff(intent, review),
            throwsStateError,
          );
          expect(
            (await h.journal.read(
              commandOwner(),
            )).single.providerHandoffPossible,
            isTrue,
          );
          await expectLater(
            h.repo.reviewContributionIntent(intent),
            throwsA(isA<ContributionRecoveryRequired>()),
          );
        }
      },
    );
  }
  for (final change in [
    'receiver',
    'old create receipt',
    'unavailable',
    'wrong session',
  ]) {
    test(
      'current review $change refuses handoff without new creation',
      () async {
        final h = await _Harness.create();
        final intent = await h.repo.prepareContributionIntent(_draft);
        h.onReview = (_) {
          if (change == 'unavailable') {
            throw http.ClientException('Synthetic current review unavailable');
          }
          if (change == 'old create receipt') return commandIntentWire();
          return commandReviewWire(
            receiver: change == 'receiver' ? '0788999999' : '0788123456',
            session: change == 'wrong session'
                ? _nextSession
                : commandSessionId,
          );
        };
        await expectLater(
          h.repo.reviewContributionIntent(intent),
          throwsA(
            anyOf(
              isA<ContributionReviewChanged>(),
              isA<FormatException>(),
              isA<Exception>(),
            ),
          ),
        );
        expect(h.creates, hasLength(1));
        expect(
          (await h.journal.read(commandOwner())).single.providerHandoffPossible,
          isFalse,
        );
      },
    );
  }
  for (final change in ['receiver', 'status', 'revision', 'sender']) {
    test(
      'change to $change during the durable handoff claim denies launch',
      () async {
        final h = await _Harness.create();
        final intent = await h.repo.prepareContributionIntent(_draft);
        final review = await h.repo.reviewContributionIntent(intent);
        final entered = Completer<void>();
        final release = Completer<void>();
        h.storage.afterCommit = () async {
          entered.complete();
          await release.future;
        };
        final claim = h.repo.claimContributionHandoff(intent, review);
        final denied = expectLater(
          claim,
          throwsA(isA<ContributionReviewChanged>()),
        );
        await entered.future;
        h.onReview = (_) => commandReviewWire(
          receiver: change == 'receiver' ? '0788999999' : '0788123456',
          status: change == 'status' ? 'cancelled' : 'pending',
          senderHash: change == 'sender'
              ? 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
              : null,
        )..['collection_revision'] = change == 'revision' ? 3 : 2;
        release.complete();
        await denied;
        expect(h.reviews, hasLength(2));
        expect(
          (await h.journal.read(commandOwner())).single.providerHandoffPossible,
          isTrue,
        );
        expect(h.creates, hasLength(1));
      },
    );
  }
  test('profile change during the handoff claim denies the permit', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final entered = Completer<void>();
    final release = Completer<void>();
    h.storage.afterCommit = () async {
      entered.complete();
      await release.future;
    };
    final claim = h.repo.claimContributionHandoff(intent, review);
    final denied = expectLater(claim, throwsStateError);
    await entered.future;
    h.repo.updateMomoNumber('0788999999');
    release.complete();
    await denied;
    expect(
      (await h.journal.read(commandOwner())).single.providerHandoffPossible,
      isTrue,
    );
    expect(h.creates, hasLength(1));
  });
  test('profile change invalidates an issued but unused permit', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final permit = await h.repo.claimContributionHandoff(intent, review);
    h.repo.updateMomoNumber('0788999999');
    expect(permit.consume(), isFalse);
  });
  test(
    'unavailable final review retains the handoff claim without a permit',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final review = await h.repo.reviewContributionIntent(intent);
      h.onReview = (_) => throw http.ClientException('Synthetic lost review');
      await expectLater(
        h.repo.claimContributionHandoff(intent, review),
        throwsA(isA<Exception>()),
      );
      expect(
        (await h.journal.read(commandOwner())).single.providerHandoffPossible,
        isTrue,
      );
      expect(h.creates, hasLength(1));
    },
  );
  test('a final review permit expires before a delayed handoff', () async {
    final h = await _Harness.create();
    final intent = await h.repo.prepareContributionIntent(_draft);
    final review = await h.repo.reviewContributionIntent(intent);
    final permit = await h.repo.claimContributionHandoff(intent, review);
    await Future<void>.delayed(const Duration(milliseconds: 5100));
    expect(permit.consume(), isFalse);
    expect(
      (await h.journal.read(commandOwner())).single.providerHandoffPossible,
      isTrue,
    );
  });
  test(
    'replacement session may check original receipt, never review or rebind it',
    () async {
      final h = await _Harness.create();
      final intent = await h.repo.prepareContributionIntent(_draft);
      final original = (await h.journal.read(commandOwner())).single;
      await h.login(commandOwnerId, commandAuthId, _nextSession);
      h.onLookup = (_) => commandObservationWire(
        original,
        intentId: commandIntentId,
        status: 'cancelled',
      );
      final observed = await h.repo.checkContributionCommand(
        original.body.requestId,
      );
      expect(observed.originalSessionId, commandSessionId);
      expect(observed.observedStatus, 'cancelled');
      await expectLater(
        h.repo.reviewContributionIntent(intent),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      await expectLater(
        h.repo.prepareContributionIntent(_draft),
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      expect(h.creates, hasLength(1));
    },
  );
  test(
    'late creation ACK after A B A cannot publish but original owner can inspect custody',
    () async {
      final h = await _Harness.create();
      final entered = Completer<void>(), reply = Completer<Object?>();
      h.onCreate = (_) {
        entered.complete();
        return reply.future;
      };
      final pending = h.repo.prepareContributionIntent(_draft);
      final denied = expectLater(
        pending,
        throwsA(isA<ContributionRecoveryRequired>()),
      );
      await entered.future;
      await h.login(
        '10000000-0000-0000-0000-000000000002',
        '11000000-0000-0000-0000-000000000002',
        _nextSession,
      );
      await h.login(commandOwnerId, commandAuthId, commandSessionId);
      reply.complete(commandIntentWire());
      await denied;
      expect(h.repo.state.paymentIntents, isEmpty);
      expect(
        (await h.repo.restoreContributionCommand(
          commandGroupId,
        ))!.originalSessionId,
        commandSessionId,
      );
      expect(h.creates, hasLength(1));
    },
  );
  test('lost authority and unreadable custody fail before create', () async {
    final h = await _Harness.create();
    h.storage.failRead = true;
    await expectLater(
      h.repo.prepareContributionIntent(_draft),
      throwsStateError,
    );
    expect(h.creates, isEmpty);
    h.storage.failRead = false;
    h.onWitness = (_) =>
        commandWitnessWire()
          ..['issuer'] = 'https://foreign.supabase.co/auth/v1';
    await expectLater(
      h.repo.prepareContributionIntent(_draft),
      throwsFormatException,
    );
    expect(h.creates, isEmpty);
  });

  test(
    'sign-out start fences a pending witness before custody or dispatch',
    () async {
      final h = await _Harness.create();
      final entered = Completer<void>();
      final witness = Completer<Object?>();
      h.onWitness = (_) {
        entered.complete();
        return witness.future;
      };
      final preparing = h.repo.prepareContributionIntent(_draft);
      final denied = expectLater(preparing, throwsStateError);
      await entered.future;
      final logout = h.repo.signOut();
      await h.sms.stopEntered.future;
      witness.complete(commandWitnessWire());
      await denied;
      expect(h.creates, isEmpty);
      expect(await h.journal.read(commandOwner()), isEmpty);
      h.sms.stopReply.complete(true);
      await logout;
    },
  );
}

typedef _Respond = FutureOr<Object?> Function(http.Request);

class _Store extends MemoryContributionStore {
  int? loseAtCommit;
  Future<void> Function()? afterCommit;
  @override
  Future<ContributionStoreCasResult> compareAndSet(
    String partitionId,
    int expectedRevision,
    String payload,
  ) async {
    if (loseAtCommit == commits + 1) loseNextAcknowledgement = true;
    final result = await super.compareAndSet(
      partitionId,
      expectedRevision,
      payload,
    );
    final onCommit = afterCommit;
    afterCommit = null;
    if (result.committed && onCommit != null) await onCommit();
    return result;
  }
}

class _Sms extends SmsAccessChannel {
  final stopEntered = Completer<void>();
  final stopReply = Completer<bool>();

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) {
    if (!stopEntered.isCompleted) stopEntered.complete();
    return stopReply.future;
  }
}

class _Harness {
  _Harness(this.client, this.storage, this.journal, this.requests, this.sms);
  final CollectCloudflareClient client;
  final _Store storage;
  final ContributionCommandJournal journal;
  final List<http.Request> requests;
  final _Sms sms;
  late _Repository repo;
  late _Respond onCreate, onReview, onLookup, onWitness;
  final repositories = <_Repository>[];
  String currentSession = commandSessionId,
      currentOwner = commandOwnerId,
      currentAuth = commandAuthId;
  List<http.Request> _for(String operation) =>
      requests.where((r) => r.url.path.endsWith('/$operation')).toList();
  List<http.Request> get creates => _for('create_contribution_intent');
  List<http.Request> get reviews =>
      _for('review_current_member_contribution_intent_v1');
  List<http.Request> get lookups =>
      _for('get_current_member_contribution_command_v1');
  static Future<_Harness> create() async {
    final requests = <http.Request>[];
    final config = CollectSupabaseConfiguration.fromEnvironment(
      const AppEnv(
        apiUrl: '',
        publicUrl: '',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: false,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: '',
        authCaptchaSiteKey: '',
        backend: 'supabase',
        supabaseUrl: commandProject,
        supabasePublishableKey: 'sb_publishable_syntheticPublicKey1234',
      ),
    );
    late _Harness h;
    final client = CollectCloudflareClient(
      config.api.origin,
      supabaseConfiguration: config,
      httpClient: MockClient((request) async {
        requests.add(request);
        final Object? value = switch (request.url.path.split('/').last) {
          'create_contribution_intent' => await h.onCreate(request),
          'review_current_member_contribution_intent_v1' => await h.onReview(
            request,
          ),
          'get_current_member_contribution_command_v1' => await h.onLookup(
            request,
          ),
          'get_current_member_contribution_session_v1' => await h.onWitness(
            request,
          ),
          'record_sms_access_consent' => null,
          'logout' => <String, dynamic>{},
          _ => throw StateError('Unexpected synthetic HTTP operation'),
        };
        return http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final storage = _Store(),
        journal = ContributionCommandJournal(storage: storage);
    h = _Harness(client, storage, journal, requests, _Sms());
    h.onCreate = (_) => commandIntentWire();
    h.onReview = (_) => commandReviewWire(session: h.currentSession);
    h.onWitness = (_) => commandWitnessWire(
      session: h.currentSession,
      owner: h.currentOwner,
      auth: h.currentAuth,
    );
    h.onLookup = (request) {
      final body = jsonDecode(request.body) as Map;
      return {
        'contract_version': 1,
        'request_id': body['p_original_request_id'],
        'original_session_id': body['p_original_session_id'],
        'collection_id': body['p_collection_id'],
        'body_sha256': ContributionCommandBody.fromJson(
          body['p_original_body'],
        ).sha256,
        'command_status': 'unknown',
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'external_payment': 'unknown',
        'retry_authorized': false,
        'launch_authorized': false,
        'observed_intent': null,
      };
    };
    await h.login(commandOwnerId, commandAuthId, commandSessionId);
    h.repo = h.newRepository();
    addTearDown(() async {
      for (final r in h.repositories) {
        r.dispose();
      }
      await client.dispose();
    });
    return h;
  }

  _Repository newRepository() {
    final r = _Repository(client, journal, sms);
    repositories.add(r);
    return r;
  }

  Future<void> login(String owner, String auth, String session) async {
    currentOwner = owner;
    currentAuth = auth;
    currentSession = session;
    String part(Object value) =>
        base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${part({'alg': 'ES256'})}.${part({'sub': auth, 'iss': '$commandProject/auth/v1', 'aud': 'authenticated', 'role': 'authenticated', 'session_id': session, 'exp': 4102444800})}.fixture';
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': token,
        'refresh_token': 'synthetic-$session',
        'token_type': 'bearer',
        'user': {'id': owner, 'auth_user_id': auth, 'aud': 'authenticated'},
      }),
    );
    await Future<void>.delayed(Duration.zero);
    // The current auth lifecycle clears financial state immediately and only
    // restores it after the owner/cache fences complete. Await that real
    // transition rather than assuming a single event-loop turn is sufficient.
    for (final repository in repositories) {
      var attempts = 0;
      while (repository.state.currentProfile?.id != owner && attempts++ < 200) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(repository.state.currentProfile?.id, owner);
    }
  }
}

class _Repository extends CollectRepository {
  _Repository(
    this.client,
    ContributionCommandJournal journal,
    SmsAccessChannel sms,
  ) : super.fixture(
        backend: client,
        smsAccessChannel: sms,
        contributionCommandJournal: journal,
        initialState: _state(client.auth.currentUser!.id),
      );
  final CollectCloudflareClient client;
  void updateMomoNumber(String number) {
    state = state.copyWith(
      currentProfile: state.currentProfile!.copyWith(momoNumber: number),
    );
  }

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = _state(client.auth.currentUser!.id);
  }
}

CollectState _state(String actor) => CollectState(
  currentProfile: CollectProfile(
    id: actor,
    publicId: '123456',
    whatsappPhone: '+250788123456',
    countryCode: 'RW',
    currencyCode: 'RWF',
    momoProvider: 'mtn_momo',
    momoNumber: '0788123456',
  ),
  collections: [
    CollectCollection(
      id: commandGroupId,
      slug: 'synthetic-group',
      creatorUserId: actor,
      title: 'Synthetic group',
      description: '',
      createdAt: DateTime.utc(2026),
      receiverMomoNumber: '0788123456',
      receiverNetwork: 'mtn_momo',
      isPublic: true,
    ),
  ],
  paymentIntents: const [],
  contributions: const [],
);
