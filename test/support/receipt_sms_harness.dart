import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/models/receipt_sms_consent.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/repositories/receipt_sms_pending_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const smsUser = 'd1000000-0000-4000-8000-000000000001',
    smsOther = 'd1000000-0000-4000-8000-000000000002';
const smsSession = 'd2000000-0000-4000-8000-000000000001',
    smsNextSession = 'd2000000-0000-4000-8000-000000000002';
const smsGroup = 'd3000000-0000-4000-8000-000000000001',
    smsGroupB = 'd3000000-0000-4000-8000-000000000002',
    smsForeign = 'd3000000-0000-4000-8000-000000000003';
Map<String, dynamic> smsRead(
  String group, {
  bool optIn = false,
  int revision = 0,
  int decisionRevision = 0,
  String? status,
  bool binding = true,
  bool proof = true,
  bool available = true,
  String? reason,
}) => {
  'contract_version': 1,
  'scope': 'own_receipt_sms_consent',
  'purpose': receiptSmsPurpose,
  'collection_id': group,
  'opt_in': optIn,
  'revision': revision,
  'decision_revision': decisionRevision,
  'destination_revision': revision == 0 ? null : 1,
  'current_verified_phone_binding': optIn && binding,
  'phone_verification_available': proof,
  'opt_in_available': available,
  'unavailable_reason': reason,
  'delivery_confirmed': false,
  'provider_confirmation': false,
  'authorization_status': status ?? (optIn ? 'active' : 'disabled'),
  'consent_effective': (status ?? (optIn ? 'active' : 'disabled')) == 'active',
};
Map<String, dynamic> smsAuth(String user, String session) => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'role': 'authenticated', 'sub': user, 'session_id': session, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
  'refresh_token': 'synthetic-only-not-a-server-credential',
  'token_type': 'bearer',
  'user': {
    'id': user,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-10-16T00:00:00Z',
  },
};
CollectProfile smsProfile(String user) => CollectProfile(
  id: user,
  publicId: user == smsUser ? '100001' : '100002',
  whatsappPhone: '+250788100001',
  countryCode: 'RW',
  currencyCode: 'RWF',
);
CollectCollection smsCollection(
  String id,
  String title, {
  bool member = true,
}) => CollectCollection(
  id: id,
  slug: 'synthetic-${id.substring(30)}',
  creatorUserId: smsUser,
  title: title,
  description: 'Synthetic member consent fixture',
  isCurrentUserMember: member,
  createdAt: DateTime.utc(2026, 10, 16),
);

/// Synthetic filesystem fixture, not a substitute for native encryption proof.
/// Atomic claim/CAS is serialized across reconstructed store/repository objects.
class FileReceiptSmsPendingStore implements ReceiptSmsPendingStore {
  FileReceiptSmsPendingStore(this.directory);
  final Directory directory;
  static final Map<String, Future<void>> _queues = {};
  bool failClaims = false, failAfterClaimWrite = false, failCompletions = false;
  Completer<void>? claimGate;
  File path(String user) => File('${directory.path}/$user.json');
  Future<T> _serial<T>(Future<T> Function() action) {
    final prior = _queues[directory.path] ?? Future<void>.value();
    final result = prior.catchError((Object _) {}).then((_) => action());
    _queues[directory.path] = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  ReceiptSmsRecoveryState group(ReceiptSmsRecoveryState all, String id) =>
      ReceiptSmsRecoveryState(
        pending: all.pending.where((r) => r.collectionId == id).toList(),
        superseded: all.superseded
            .where((r) => r.request.collectionId == id)
            .toList(),
      );
  void validate(String owner, ReceiptSmsRecoveryState all) {
    final rows = [...all.pending, ...all.superseded.map((r) => r.request)];
    if (all.pending.length > 32 ||
        all.superseded.length > 32 ||
        rows.any((r) => r.userId != owner) ||
        rows.map((r) => r.requestId).toSet().length != rows.length) {
      throw StateError('Synthetic custody capacity or identity conflict');
    }
    var reserved = 0;
    for (final id in rows.map((r) => r.collectionId).toSet()) {
      final part = group(all, id);
      ReceiptSmsRecoveryState.decode(part.toJson(), owner, id);
      if (part.pending.length > 1) reserved += part.pending.length;
      if (part.pending.where((r) => r.optIn).length > 1) {
        throw StateError('Synthetic custody invalid cohort');
      }
    }
    if (all.superseded.length + reserved > 32) {
      throw StateError('Synthetic reserved history capacity unavailable');
    }
  }

  Future<ReceiptSmsRecoveryState> _read(String owner) async {
    receiptSmsUuid(owner);
    final file = path(owner);
    if (!file.existsSync()) return const ReceiptSmsRecoveryState();
    final raw = await file.readAsString();
    if (raw.length > 65536) {
      throw const FormatException('Synthetic custody corrupt');
    }
    final row = jsonDecode(raw);
    if (row is! Map<String, dynamic> ||
        row.length != 3 ||
        row['schema_version'] != 2 ||
        row['pending'] is! List ||
        row['superseded'] is! List) {
      throw const FormatException('Synthetic custody corrupt');
    }
    final state = ReceiptSmsRecoveryState(
      pending: (row['pending'] as List)
          .map(PendingReceiptSmsRequest.decode)
          .toList(),
      superseded: (row['superseded'] as List)
          .map(ReceiptSmsSuperseded.decode)
          .toList(),
    );
    validate(owner, state);
    return state;
  }

  Future<void> _write(String owner, ReceiptSmsRecoveryState state) async {
    validate(owner, state);
    final temporary = File('${path(owner).path}.new');
    await temporary.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temporary.rename(path(owner).path);
    if (jsonEncode((await _read(owner)).toJson()) !=
        jsonEncode(state.toJson())) {
      throw StateError('Synthetic custody readback failed');
    }
  }

  @override
  Future<ReceiptSmsRecoveryState> read({
    required String userId,
    required String collectionId,
  }) => _serial(() async => group(await _read(userId), collectionId));
  @override
  Future<ReceiptSmsRecoveryState> claim(
    PendingReceiptSmsRequest request, {
    bool withdrawalFence = false,
  }) => _serial(() async {
    if (failClaims) {
      throw const FileSystemException('Synthetic durable write refused');
    }
    if (claimGate != null) await claimGate!.future;
    if (withdrawalFence && request.optIn) {
      throw StateError('Only withdrawal can fence an earlier request');
    }
    final old = await _read(request.userId),
        part = group(old, request.collectionId);
    if (part.pending.any((r) => r.sessionId == request.sessionId) ||
        !withdrawalFence && part.pending.isNotEmpty) {
      return part;
    }
    if (withdrawalFence &&
        (part.pending.isEmpty ||
            part.pending.any(
              (r) =>
                  r.expectedDecisionRevision >
                      request.expectedDecisionRevision ||
                  r.expectedRevision > request.expectedRevision,
            ))) {
      throw StateError('Synthetic fence current state required');
    }
    final next = ReceiptSmsRecoveryState(
      pending: [...old.pending, request],
      superseded: old.superseded,
    );
    await _write(request.userId, next);
    if (failAfterClaimWrite) {
      throw const FileSystemException(
        'Synthetic durable write acknowledgement lost',
      );
    }
    return group(next, request.collectionId);
  });
  @override
  Future<ReceiptSmsRecoveryState> complete(
    PendingReceiptSmsRequest request,
    int head,
  ) => _serial(() async {
    if (failCompletions) {
      throw const FileSystemException(
        'Synthetic completion custody unavailable',
      );
    }
    if (head != request.expectedDecisionRevision + 1) {
      throw StateError('Synthetic acknowledgement order invalid');
    }
    final old = await _read(request.userId);
    final row = [
      ...old.pending,
      ...old.superseded.map((r) => r.request),
    ].where((r) => r.requestId == request.requestId).singleOrNull;
    if (row == null) return group(old, request.collectionId);
    if (!row.sameRequest(request)) {
      throw StateError('Synthetic acknowledgement custody changed');
    }
    final fenced = old.pending
        .where(
          (r) =>
              r.collectionId == request.collectionId &&
              r.requestId != request.requestId &&
              r.expectedDecisionRevision < head,
        )
        .toList();
    final ids = {request.requestId, ...fenced.map((r) => r.requestId)};
    final next = ReceiptSmsRecoveryState(
      pending: old.pending.where((r) => !ids.contains(r.requestId)).toList(),
      superseded: [
        ...old.superseded.where(
          (r) => r.request.requestId != request.requestId,
        ),
        ...fenced.map((r) => ReceiptSmsSuperseded(r, head)),
      ],
    );
    await _write(request.userId, next);
    return group(next, request.collectionId);
  });
  @override
  Future<ReceiptSmsRecoveryState> supersede({
    required String userId,
    required String collectionId,
    required List<PendingReceiptSmsRequest> knownRequests,
    required int observedDecisionRevision,
  }) => _serial(() async {
    receiptSmsDecisionRevision(observedDecisionRevision);
    if (observedDecisionRevision == 0 ||
        knownRequests.isEmpty ||
        knownRequests.length > 32 ||
        knownRequests.map((r) => r.requestId).toSet().length !=
            knownRequests.length ||
        knownRequests.any(
          (r) => r.userId != userId || r.collectionId != collectionId,
        )) {
      throw StateError('Synthetic custody invalid known cohort');
    }
    final old = await _read(userId), part = group(old, collectionId);
    if (!part.pending.every((r) => knownRequests.any(r.sameRequest))) {
      throw StateError('Synthetic custody cohort changed');
    }
    final byId = {
      for (final r in [...old.pending, ...old.superseded.map((r) => r.request)])
        r.requestId: r,
    };
    for (final known in knownRequests) {
      final retained = byId[known.requestId];
      if ((retained != null && !retained.sameRequest(known)) ||
          (retained == null &&
              known.expectedDecisionRevision >= observedDecisionRevision)) {
        throw StateError('Synthetic custody metadata or fence changed');
      }
    }
    final fenced = knownRequests
        .where((r) => r.expectedDecisionRevision < observedDecisionRevision)
        .toList();
    if (fenced.isEmpty) throw StateError('No later decision proof');
    final ids = fenced.map((r) => r.requestId).toSet(),
        history = old.superseded.map((r) => r.request.requestId).toSet();
    final next = ReceiptSmsRecoveryState(
      pending: old.pending.where((r) => !ids.contains(r.requestId)).toList(),
      superseded: [
        ...old.superseded,
        ...fenced
            .where((r) => !history.contains(r.requestId))
            .map((r) => ReceiptSmsSuperseded(r, observedDecisionRevision)),
      ],
    );
    await _write(userId, next);
    return group(next, collectionId);
  });
}

class ReceiptSmsHarness {
  ReceiptSmsHarness._(this.directory);
  final Directory directory;
  late CollectCloudflareClient client;
  late ReceiptSmsRepository repo;
  late FileReceiptSmsPendingStore store;
  final writes = <Map<String, dynamic>>[], reads = <String>[];
  final remote = <String, Map<String, dynamic>>{},
      receipts = <String, Map<String, dynamic>>{};
  final readGates = <String, Completer<http.Response>>{};
  Completer<void>? writeGate;
  final Map<String, Completer<void>> sessionWriteGates = {};
  final Map<String, Map<String, dynamic>> receiptBodies = {};
  bool unsupported = false, loseReply = false;
  Map<String, dynamic> Function(Map<String, dynamic>)? alterAck, alterRead;
  String get _owner => client.auth.currentUser!.id;
  Map<String, dynamic> current(String group, [String? user]) =>
      remote.putIfAbsent('${user ?? _owner}/$group', () => smsRead(group));
  static Future<ReceiptSmsHarness> create() async {
    final h = ReceiptSmsHarness._(
      await Directory.systemTemp.createTemp('collect-receipt-sms-test-'),
    );
    h.client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      timeout: const Duration(seconds: 3),
      httpClient: MockClient(h._respond),
    );
    await h.client.auth.recoverSession(
      jsonEncode(smsAuth(smsUser, smsSession)),
    );
    h.store = FileReceiptSmsPendingStore(h.directory);
    h.repo = ReceiptSmsRepository(h.client, h.store);
    return h;
  }

  Future<http.Response> _respond(http.Request request) async {
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    final auth =
        request.headers['Authorization'] ??
        request.headers['authorization'] ??
        '';
    final claims =
        jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(auth.substring(7).split('.')[1]),
                ),
              ),
            )
            as Map<String, dynamic>;
    final user = claims['sub'] as String,
        session = claims['session_id'] as String;
    final group = body['p_collection_id'] as String?;
    http.Response reply(Object? value, [int status = 200]) => http.Response(
      jsonEncode(value),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
    if (request.url.path.endsWith('/get_assisted_sms_consent_v1')) {
      reads.add(group!);
      if (unsupported) return reply({'code': 'operation_unavailable'}, 501);
      if (readGates[group] != null) return readGates[group]!.future;
      final value = {...current(group, user)};
      return reply(alterRead?.call(value) ?? value);
    }
    if (request.url.path.endsWith('/set_assisted_sms_consent_v1')) {
      writes.add({...body, 'captured_session': session});
      final gate = sessionWriteGates[session] ?? writeGate;
      if (gate != null) await gate.future;
      final key = '$user/${body['p_request_id']}';
      var ack = receipts[key];
      if (ack == null) {
        final old = current(group!, user),
            expected = body['p_expected_revision'] as int,
            expectedDecision = body['p_expected_decision_revision'] as int;
        if (old['revision'] != expected ||
            old['decision_revision'] != expectedDecision) {
          return reply({'code': 'sms_consent_changed'}, 409);
        }
        final optIn = body['p_opt_in'] as bool,
            revision = expected + (old['opt_in'] == optIn ? 0 : 1);
        remote['$user/$group'] = smsRead(
          group,
          optIn: optIn,
          revision: revision,
          decisionRevision: expectedDecision + 1,
        );
        ack = {
          'contract_version': 1,
          'scope': 'own_receipt_sms_consent',
          'purpose': receiptSmsPurpose,
          'delivery_confirmed': false,
          'provider_confirmation': false,
          'kind': 'authenticated_member_receipt_sms_consent',
          'request_id': body['p_request_id'],
          'collection_id': group,
          'recipient_user_id': user,
          'originating_session_id': session,
          'opt_in': optIn,
          'consent_revision': revision,
          'decision_revision': expectedDecision + 1,
          'destination_revision': revision == 0 ? null : 1,
          'destination_sha256': revision == 0 ? null : 'a' * 64,
          'phone_verification_challenge_id': optIn
              ? 'd4000000-0000-4000-8000-000000000001'
              : null,
          'recorded_at': '2026-10-16T12:00:00.000Z',
          'decision_sha256': 'b' * 64,
          'authorization_receipt_sha256': revision == 0 ? null : 'b' * 64,
          'recorded_state_only': true,
          'replay': false,
        };
        receipts[key] = ack;
        receiptBodies[key] = {...body};
      } else {
        if (ack['originating_session_id'] != session ||
            jsonEncode(receiptBodies[key]) != jsonEncode(body)) {
          return reply({'code': 'request_conflict'}, 409);
        }
        ack = {...ack, 'replay': true};
      }
      if (loseReply) {
        loseReply = false;
        throw TimeoutException('Synthetic committed reply lost');
      }
      return reply(alterAck?.call({...ack}) ?? ack);
    }
    throw StateError('Unexpected synthetic API request');
  }

  Future<void> login(String user, String session) async {
    await client.auth.recoverSession(jsonEncode(smsAuth(user, session)));
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void reconstruct() {
    repo.dispose();
    store = FileReceiptSmsPendingStore(directory);
    repo = ReceiptSmsRepository(client, store);
  }

  Future<void> close() async {
    repo.dispose();
    await client.dispose();
    await directory.delete(recursive: true);
  }
}

class ReceiptSmsRepository extends CollectRepository {
  ReceiptSmsRepository(this.client, ReceiptSmsPendingStore store)
    : super.fixture(
        backend: client,
        receiptSmsPendingStore: store,
        initialState: _state(client.auth.currentUser!.id),
        smsAccessChannel: _Sms(),
        offlineCache: _Cache(),
      );
  final CollectCloudflareClient client;
  bool refuseNextConsentRead = false;
  @override
  Future<void> refreshReceiptSmsConsent(String collectionId) async {
    if (refuseNextConsentRead) {
      refuseNextConsentRead = false;
      throw StateError('Synthetic pre-dispatch sign-in unavailable');
    }
    await super.refreshReceiptSmsConsent(collectionId);
  }

  static CollectState _state(String user) => CollectState(
    currentProfile: smsProfile(user),
    collections: [
      smsCollection(smsGroup, 'Community group'),
      smsCollection(smsGroupB, 'Another group'),
      smsCollection(smsForeign, 'Public group', member: false),
    ],
    paymentIntents: const [],
    contributions: const [],
  );
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    final user = client.auth.currentUser?.id;
    if (user != null) state = _state(user);
  }

  void replaceGroups(List<CollectCollection> groups) =>
      state = state.copyWith(collections: groups);
  void offline() => state = state.copyWith(usingStaleCache: true);
}

class _Sms extends SmsAccessChannel {
  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async => true;
}

class _Cache extends CollectOfflineCache {
  @override
  Future<void> clear() async {}
  @override
  Future<void> save(CollectOfflineSnapshot snapshot) async {}
  @override
  Future<CollectOfflineSnapshot?> read({String? ownerUserId}) async => null;
}
