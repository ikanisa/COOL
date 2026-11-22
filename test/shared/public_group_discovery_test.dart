import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/synthetic_jwt.dart';

const _user = '10000000-0000-4000-8000-000000000001';
const _memberGroup = '20000000-0000-4000-8000-000000000001';
const _publicGroup = '20000000-0000-4000-8000-000000000002';
const _firstSession = '30000000-0000-4000-8000-000000000001';
const _secondSession = '30000000-0000-4000-8000-000000000002';

String _session(String id, {String revision = 'first'}) => jsonEncode({
  'access_token': syntheticJwt(
    {'alg': 'HS256', 'typ': 'JWT'},
    {
      'sub': _user,
      'session_id': id,
      'synthetic_revision': revision,
      'role': 'authenticated',
      'surface': 'member',
      'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
    },
  ),
  'refresh_token': 'synthetic-$id',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': _user,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
  },
});

Map<String, Object?> _group(String id, {required bool member}) => {
  'id': id,
  'slug': 'synthetic-$id',
  if (member) 'creator_user_id': '40000000-0000-4000-8000-000000000001',
  'title': member ? 'Member group' : 'Public group',
  'description': '',
  'collection_type': 'ikimina',
  'is_member': member,
  'is_public': true,
  'visibility_status': 'public_approved',
  if (member) 'status': 'active',
  'moderation_status': 'not_requested',
  'receiver_network': 'mtn_momo',
  if (member) 'receiver_momo_number': '250788123456',
  'payment_rail': 'rwanda_momo',
  'created_at': '2026-01-01T00:00:00Z',
};

class _SmsBarrier extends SmsAccessChannel {
  final disableEntered = Completer<void>();
  final disableReply = Completer<bool>();
  final calls = <String>[];

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) {
    calls.add('$ownerUserId:$enabled');
    if (!disableEntered.isCompleted) disableEntered.complete();
    return disableReply.future;
  }

  @override
  Future<bool> suspendUnlessOwner(String? userId) async => true;
}

class _Harness {
  bool member = true;
  bool publicMember = false;
  int memberListReads = 0;
  int publicStatus = 200;
  bool memberBalanceDenied = false;
  Completer<http.Response>? publicResponse;
  Completer<http.Response>? memberResponse;
  Completer<http.Response>? joinResponse;
  final publicEntered = Completer<void>();
  final memberEntered = Completer<void>();
  final joinEntered = Completer<void>();
  final logoutBearers = <String?>[];
  late final CollectCloudflareClient client;
  late final CollectRepository repo;
  final cache = const CollectOfflineCache();

  Future<void> start({
    SmsAccessChannel smsAccessChannel = const SmsAccessChannel(),
  }) async {
    client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        final path = request.url.path;
        Object? value;
        var status = 200;
        if (path.endsWith('/query/public-collections')) {
          if (publicResponse case final pending?) {
            publicResponse = null;
            publicEntered.complete();
            return pending.future;
          }
          status = publicStatus;
          value = status == 200
              ? [
                  _group(_memberGroup, member: false),
                  _group(_publicGroup, member: false),
                ]
              : {'code': status == 403 ? 'permission_denied' : 'unavailable'};
        } else if (path.endsWith('/get_current_member_profile')) {
          value = {
            'id': _user,
            'public_id': '123456',
            'whatsapp_phone': '+250788123456',
            'country_code': 'RW',
            'currency_code': 'RWF',
          };
        } else if (path.endsWith('/list_current_user_collections')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['p_collection_id'] == _publicGroup) {
            value = publicMember ? [_group(_publicGroup, member: true)] : [];
          } else {
            memberListReads++;
            if (memberResponse case final pending?) {
              memberResponse = null;
              if (!memberEntered.isCompleted) memberEntered.complete();
              return pending.future;
            } else {
              value = [
                if (member) _group(_memberGroup, member: true),
                if (publicMember) _group(_publicGroup, member: true),
              ];
            }
          }
        } else if (path.endsWith('/join_public_group')) {
          if (joinResponse case final pending?) {
            joinResponse = null;
            joinEntered.complete();
            return pending.future;
          }
          publicMember = true;
          value = _publicGroup;
        } else if (path.endsWith('/list_current_member_recent_intents')) {
          value = {'items': [], 'pending_count': 0};
        } else if (path.endsWith('/list_current_member_history_page')) {
          value = {
            'contract_version': 2,
            'contribution_basis': 'reconciled_evidence_entries',
            'items': [],
            'total_count': 0,
            'totals': {'RWF': 0},
            'own_totals': {'RWF': 0},
            'credit_totals': {'RWF': 0},
            'debit_totals': {'RWF': 0},
            'own_credit_totals': {'RWF': 0},
            'own_debit_totals': {'RWF': 0},
            'own_collection_ids': [],
            'revision': '00000000000000000000000000000000',
            'next_cursor': null,
          };
        } else if (path.endsWith('/list_current_member_collection_balances')) {
          status = memberBalanceDenied ? 403 : 200;
          value = memberBalanceDenied ? {'code': 'permission_denied'} : [];
        } else if (path.endsWith('/get_notification_preferences_v2')) {
          value = {
            'contract_version': 2,
            'ok': true,
            'user_id': _user,
            'revision': 0,
            'exists': false,
            'preferences': NotificationPreferences.defaults.toJson(),
          };
        } else if (path.endsWith('/query/notification-events')) {
          value = [];
        } else if (path.endsWith('/record_sms_access_consent')) {
          value = null;
        } else if (path.endsWith('/auth/logout')) {
          logoutBearers.add(request.headers['authorization']);
          value = {};
        } else {
          throw StateError('Unexpected synthetic request: $path');
        }
        return http.Response(
          jsonEncode(value),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(_session(_firstSession));
    repo = CollectRepository(
      backend: client,
      offlineCache: cache,
      smsAccessChannel: smsAccessChannel,
    );
    addTearDown(repo.dispose);
    addTearDown(client.dispose);
  }

  Future<void> settleDiscovery() async {
    for (
      var i = 0;
      i < 200 && (repo.state.isLoading || repo.state.publicDiscoveryLoading);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(repo.state.isLoading, isFalse);
    expect(repo.state.publicDiscoveryLoading, isFalse);
  }

  Future<void> refresh() async {
    await repo.loadInitial();
    await settleDiscovery();
  }

  Future<void> waitForMemberReads(int expected) async {
    for (var i = 0; i < 200 && memberListReads < expected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(memberListReads, greaterThanOrEqualTo(expected));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'member record wins over public duplicate and public data is not cached',
    () async {
      final h = _Harness();
      await h.start();
      await h.refresh();
      expect(h.repo.state.lastError, isNull);
      expect(h.repo.state.publicDiscoveryUnavailable, isFalse);
      expect(h.repo.state.collections, hasLength(2));
      final member = h.repo.state.collections.singleWhere(
        (g) => g.id == _memberGroup,
      );
      expect(member.isCurrentUserMember, isTrue);
      expect(member.receiverMomoNumber, '250788123456');
      final discovered = h.repo.state.collections.singleWhere(
        (g) => g.id == _publicGroup,
      );
      expect(discovered.isCurrentUserMember, isFalse);
      expect(discovered.receiverMomoNumber, isNull);
      final cached = await h.cache.read(ownerUserId: _user);
      expect(cached?.collections.map((g) => g.id), [_memberGroup]);
    },
  );

  test(
    'loss of membership clears member cache even while group remains public',
    () async {
      final h = _Harness();
      await h.start();
      await h.refresh();
      expect(
        (await h.cache.read(ownerUserId: _user))?.collections,
        hasLength(1),
      );
      h.member = false;
      await h.refresh();
      final displayed = h.repo.state.collections.singleWhere(
        (g) => g.id == _memberGroup,
      );
      expect(displayed.isCurrentUserMember, isFalse);
      expect(displayed.receiverMomoNumber, isNull);
      expect((await h.cache.read(ownerUserId: _user))?.collections, isEmpty);
    },
  );

  for (final status in [403, 503]) {
    test(
      'public failure $status preserves member data and recovers on retry',
      () async {
        final h = _Harness();
        await h.start();
        h.publicStatus = status;
        await h.refresh();
        expect(h.repo.state.currentProfile?.id, _user);
        expect(h.repo.state.collections.map((g) => g.id), [_memberGroup]);
        expect(h.repo.state.publicDiscoveryUnavailable, isTrue);
        h.publicStatus = 200;
        await h.refresh();
        expect(h.repo.state.publicDiscoveryUnavailable, isFalse);
        expect(
          h.repo.state.collections.map((g) => g.id),
          contains(_publicGroup),
        );
      },
    );
  }

  test(
    'member authority failure still clears member and public data',
    () async {
      final h = _Harness();
      await h.start();
      await h.refresh();
      h.memberBalanceDenied = true;
      await h.repo.loadInitial();
      expect(h.repo.state.currentProfile, isNull);
      expect(h.repo.state.collections, isEmpty);
      expect(await h.cache.read(ownerUserId: _user), isNull);
    },
  );

  test('a stalled public request does not delay member data', () async {
    final h = _Harness();
    await h.start();
    h.publicResponse = Completer<http.Response>();
    final pending = h.publicResponse!;
    await h.repo.loadInitial().timeout(const Duration(seconds: 2));
    await h.publicEntered.future;
    expect(h.repo.state.isLoading, isFalse);
    expect(h.repo.state.currentProfile?.id, _user);
    expect(h.repo.state.collections.map((g) => g.id), [_memberGroup]);
    expect(h.repo.state.publicDiscoveryLoading, isTrue);
    pending.complete(
      http.Response(
        jsonEncode([_group(_publicGroup, member: false)]),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await h.settleDiscovery();
    expect(h.repo.state.collections.map((g) => g.id), contains(_publicGroup));
  });

  test(
    'a public join survives a concurrent redacted discovery response',
    () async {
      final h = _Harness();
      await h.start();
      await h.refresh();
      h.memberResponse = Completer<http.Response>();
      h.joinResponse = Completer<http.Response>();
      h.publicResponse = Completer<http.Response>();
      final memberReply = h.memberResponse!;
      final joinReply = h.joinResponse!;
      final publicReply = h.publicResponse!;

      final refresh = h.repo.loadInitial();
      await h.memberEntered.future;
      final join = h.repo.joinPublicGroup(_publicGroup);
      await h.joinEntered.future;
      memberReply.complete(
        http.Response(
          jsonEncode([_group(_memberGroup, member: true)]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await h.publicEntered.future;
      h.publicMember = true;
      joinReply.complete(
        http.Response(
          jsonEncode(_publicGroup),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect((await join).isCurrentUserMember, isTrue);

      publicReply.complete(
        http.Response(
          jsonEncode([_group(_publicGroup, member: false)]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await refresh;
      await h.waitForMemberReads(3);
      await h.settleDiscovery();
      final joined = h.repo.state.collections
          .where((group) => group.id == _publicGroup)
          .toList();
      expect(joined, hasLength(1));
      expect(joined.single.isCurrentUserMember, isTrue);
      expect(joined.single.receiverMomoNumber, '250788123456');
    },
  );

  test(
    'join invalidates a stalled older member read and refreshes authority',
    () async {
      final h = _Harness();
      await h.start();
      await h.refresh();
      h.memberResponse = Completer<http.Response>();
      final staleMemberReply = h.memberResponse!;
      final oldRead = h.repo.loadInitial();
      await h.memberEntered.future;

      final joined = await h.repo.joinPublicGroup(_publicGroup);
      expect(joined.isCurrentUserMember, isTrue);
      // The fresh authoritative read must finish while the old one is still
      // stalled; this also prevents a missing refresh from passing the test.
      await h.waitForMemberReads(3);
      await h.settleDiscovery();
      expect(
        h.repo.state.collections
            .singleWhere((g) => g.id == _publicGroup)
            .isCurrentUserMember,
        isTrue,
      );
      expect(
        (await h.cache.read(ownerUserId: _user))?.collections.map((g) => g.id),
        contains(_publicGroup),
      );
      // The old member response predates the join. It must never overwrite the
      // post-join authoritative reread when it arrives last.
      staleMemberReply.complete(
        http.Response(
          jsonEncode([_group(_memberGroup, member: true)]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await oldRead;
      final current = h.repo.state.collections.singleWhere(
        (g) => g.id == _publicGroup,
      );
      expect(current.isCurrentUserMember, isTrue);
      expect(current.receiverMomoNumber, '250788123456');
      expect(
        (await h.cache.read(ownerUserId: _user))?.collections.map((g) => g.id),
        contains(_publicGroup),
      );

      // A later authoritative removal must not be masked by discovery.
      h.publicMember = false;
      await h.refresh();
      expect(
        h.repo.state.collections
            .singleWhere((g) => g.id == _publicGroup)
            .isCurrentUserMember,
        isFalse,
      );
      expect(
        (await h.cache.read(ownerUserId: _user))?.collections.map((g) => g.id),
        isNot(contains(_publicGroup)),
      );
    },
  );

  test('post-join refresh still clears authority on a member denial', () async {
    final h = _Harness();
    await h.start();
    await h.refresh();
    h.joinResponse = Completer<http.Response>();
    final reply = h.joinResponse!;
    final joining = h.repo.joinPublicGroup(_publicGroup);
    await h.joinEntered.future;
    h.publicMember = true;
    h.memberBalanceDenied = true;
    reply.complete(
      http.Response(
        jsonEncode(_publicGroup),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await joining;
    await h.waitForMemberReads(2);
    await h.settleDiscovery();
    expect(h.repo.state.currentProfile, isNull);
    expect(h.repo.state.collections, isEmpty);
    expect(await h.cache.read(ownerUserId: _user), isNull);
  });

  test(
    'stale same-bearer denial clears authority while join refresh stalls',
    () async {
      final h = _Harness();
      await h.start();
      await h.refresh();

      h.memberResponse = Completer<http.Response>();
      final oldReply = h.memberResponse!;
      final oldRead = h.repo.loadInitial();
      await h.memberEntered.future.timeout(const Duration(seconds: 2));

      h.memberResponse = Completer<http.Response>();
      final joinRefreshReply = h.memberResponse!;
      expect(
        (await h.repo.joinPublicGroup(_publicGroup)).isCurrentUserMember,
        isTrue,
      );
      await h.waitForMemberReads(3);

      // Hold the denial-triggered reread too, so the denial's immediate effect
      // can be distinguished from any later successful authority refresh.
      h.memberResponse = Completer<http.Response>();
      final denialRefreshReply = h.memberResponse!;
      oldReply.complete(
        http.Response(
          jsonEncode({'code': 'permission_denied'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );
      await h.waitForMemberReads(4);
      expect(h.repo.state.currentProfile, isNull);
      expect(h.repo.state.collections, isEmpty);
      expect(await h.cache.read(ownerUserId: _user), isNull);

      final currentMembers = jsonEncode([
        _group(_memberGroup, member: true),
        _group(_publicGroup, member: true),
      ]);
      denialRefreshReply.complete(
        http.Response(
          currentMembers,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await oldRead.timeout(const Duration(seconds: 2));
      await h.settleDiscovery();
      joinRefreshReply.complete(
        http.Response(
          jsonEncode([_group(_memberGroup, member: true)]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await pumpEventQueue();
      expect(
        h.repo.state.collections
            .singleWhere((g) => g.id == _publicGroup)
            .isCurrentUserMember,
        isTrue,
      );
    },
  );

  test(
    'stale denial for a replaced bearer does not clear the newer session',
    () async {
      final h = _Harness();
      await h.start();
      await h.refresh();
      final oldBearer = h.client.auth.currentSession!.accessToken;
      h.memberResponse = Completer<http.Response>();
      final oldReply = h.memberResponse!;
      final oldRead = h.repo.loadInitial();
      await h.memberEntered.future.timeout(const Duration(seconds: 2));

      await h.client.auth.recoverSession(
        _session(_firstSession, revision: 'second'),
      );
      expect(h.client.auth.currentSession!.accessToken, isNot(oldBearer));
      await h.refresh();
      oldReply.complete(
        http.Response(
          jsonEncode({'code': 'permission_denied'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );
      await oldRead.timeout(const Duration(seconds: 2));
      expect(h.repo.state.currentProfile?.id, _user);
      expect(
        h.repo.state.collections
            .singleWhere((g) => g.id == _memberGroup)
            .isCurrentUserMember,
        isTrue,
      );
      expect(
        (await h.cache.read(ownerUserId: _user))?.collections.map((g) => g.id),
        contains(_memberGroup),
      );
      expect(h.memberListReads, 3);
    },
  );

  test(
    'stale denial cannot interrupt sign-out native and cache cleanup',
    () async {
      final h = _Harness();
      final sms = _SmsBarrier();
      await h.start(smsAccessChannel: sms);
      await h.refresh();
      final bearer = h.client.auth.currentSession!.accessToken;
      h.memberResponse = Completer<http.Response>();
      final oldReply = h.memberResponse!;
      final oldRead = h.repo.loadInitial();
      await h.memberEntered.future.timeout(const Duration(seconds: 2));

      final logout = h.repo.signOut();
      await sms.disableEntered.future.timeout(const Duration(seconds: 2));
      oldReply.complete(
        http.Response(
          jsonEncode({'code': 'permission_denied'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      );
      await oldRead.timeout(const Duration(seconds: 2));
      expect(h.client.auth.currentSession, isNotNull);
      expect(h.repo.state.currentProfile?.id, _user);
      expect(h.memberListReads, 2);
      expect(sms.calls, ['$_user:false']);

      sms.disableReply.complete(true);
      await logout.timeout(const Duration(seconds: 2));
      expect(h.client.auth.currentSession, isNull);
      expect(h.repo.state.currentProfile, isNull);
      expect(await h.cache.read(ownerUserId: _user), isNull);
      expect(h.logoutBearers, ['Bearer $bearer']);
    },
  );

  test(
    'old public read cannot publish after same-user session replacement',
    () async {
      final h = _Harness();
      await h.start();
      h.publicResponse = Completer<http.Response>();
      final pending = h.publicResponse!;
      final oldRead = h.repo.loadInitial();
      await h.publicEntered.future;
      h.publicStatus = 503;
      await h.client.auth.recoverSession(_session(_secondSession));
      pending.complete(
        http.Response(
          jsonEncode([_group(_publicGroup, member: false)]),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await oldRead;
      await pumpEventQueue();
      expect(
        h.repo.state.collections.any((g) => g.id == _publicGroup),
        isFalse,
      );
    },
  );
}
