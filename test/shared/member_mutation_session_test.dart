import 'dart:async';

import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';

import 'member_data_authority_test.dart' as authority;

const _event = '60000000-0000-0000-0000-000000000001';
const _peer = '654321';
const _nativeStatus = SmsAccessStatus(
  supported: true,
  declared: true,
  enabled: true,
  granted: true,
  requestedBefore: true,
  shouldShowRationale: false,
  permanentlyDenied: false,
  queueOverflowed: false,
);
const _operationRpc = {
  'create': 'create_private_group_with_owner_media_attested',
  'profile': 'update_current_member_profile',
  'group profile': 'update_rwanda_momo_group_profile',
  'join': 'join_group_by_share_code',
  'promote': 'add_group_admin',
  'archive': 'archive_group',
  'transfer': 'transfer_group_ownership',
  'notification': 'mark_notification_event_read',
};
Map<String, dynamic> _profile({String id = authority.actor}) => {
  'id': id,
  'public_id': '123456',
  'whatsapp_phone': '+250788123456',
  'country_code': 'RW',
  'currency_code': 'RWF',
  'momo_provider': 'mtn_momo',
  'momo_number': '0788123456',
};
Map<String, dynamic> _group({String owner = authority.actor}) => {
  'id': authority.group,
  'slug': 'synthetic-group',
  'creator_user_id': owner,
  'title': 'Synthetic group',
  'description': '',
  'is_member': true,
  'created_at': '2026-01-01T00:00:00Z',
};
NotificationEvent _notification({String user = authority.actor}) =>
    NotificationEvent(
      id: _event,
      userId: user,
      type: 'contribution_confirmed',
      title: 'Synthetic notification',
      body: '',
      status: 'unread',
      createdAt: DateTime.utc(2026),
    );

class _Repository extends authority.Repository {
  _Repository(super.client) {
    state = _seed();
  }
  Future<SmsAccessStatus>? nativeStatus;
  @override
  Future<SmsAccessStatus> refreshSmsAccessStatus() async =>
      await (nativeStatus ?? Future.value(_nativeStatus));
  CollectState _seed() => authority
      .stateFor(authority.actor)
      .copyWith(notificationEvents: [_notification()]);
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = _seed();
    nextLoad?.complete();
    nextLoad = null;
  }
}

class _Harness {
  _Harness(this.client, this.repo, this.requests);
  final CollectCloudflareClient client;
  final _Repository repo;
  final List<http.Request> requests;
  static Future<_Harness> create({
    String? block,
    Completer<void>? entered,
    Completer<http.Response>? release,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? group,
    String? capabilityExpiry,
  }) async {
    final requests = <http.Request>[];
    final client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        requests.add(request);
        final name = request.url.path.split('/').last;
        http.Response response;
        if (name == block) {
          entered!.complete();
          response = await release!.future;
        } else {
          response = authority.jsonResponse(switch (name) {
            'verify-play-integrity' => {
              'status': 'pass',
              'native_capability': 'synthetic-native-capability',
              'capability_expires_at':
                  capabilityExpiry ?? '2030-01-01T00:00:00Z',
            },
            'create_private_group_with_owner_media_attested' ||
            'join_group_by_share_code' => authority.group,
            'list_current_user_collections' => [group ?? _group()],
            'update_current_member_profile' => profile ?? _profile(),
            'add_group_admin' => {
              'collection_id': authority.group,
              'public_id': _peer,
              'role': 'admin',
              'status': 'active',
            },
            _ => null,
          });
        }
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          request: request,
          headers: response.headers,
        );
      }),
    );
    await client.auth.recoverSession(
      authority.session(authority.actor, authority.firstSession),
    );
    final repository = _Repository(client);
    final h = _Harness(client, repository, requests);
    addTearDown(() async {
      repository.dispose();
      await client.dispose();
    });
    return h;
  }

  Future<void> login(String user, String sid) async {
    final loaded = Completer<void>();
    repo.nextLoad = loaded;
    await client.auth.recoverSession(authority.session(user, sid));
    await loaded.future.timeout(const Duration(seconds: 3));
  }

  Future<dynamic> invoke(String operation) async => switch (operation) {
    'create' => repo.createCollectionWithVerifiedReceiver(
      title: 'Synthetic group',
      description: '',
    ),
    'profile' => repo.updateCurrentProfile(
      countryCode: 'RW',
      momoProvider: 'mtn_momo',
      momoNumber: '0788123456',
    ),
    'group profile' => repo.updateCollectionProfile(
      collectionId: authority.group,
      title: 'Synthetic group',
      description: '',
      recurringCadence: 'monthly',
      isPublic: false,
    ),
    'join' => repo.joinGroupBySlug('synthetic-share-code'),
    'promote' => repo.inviteCollectionAdmin(
      collectionId: authority.group,
      publicId: _peer,
    ),
    'archive' => repo.archiveCollection(authority.group),
    'transfer' => repo.transferCollectionOwnership(
      collectionId: authority.group,
      publicId: _peer,
    ),
    'notification' => repo.markNotificationRead(_event),
    _ => throw StateError('Unknown synthetic operation'),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('collect/play_integrity'),
          (call) async => 'synthetic-native-token',
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('collect/play_integrity'),
          null,
        );
  });
  for (final operation in _operationRpc.keys) {
    test(
      '$operation current production SDK workflow remains valid and pinned',
      () async {
        final h = await _Harness.create();
        await h.invoke(operation);
        expect(
          h.requests.where(
            (r) => r.url.path.endsWith(_operationRpc[operation]!),
          ),
          hasLength(1),
        );
        for (final request in h.requests) {
          expect(
            request.headers['Authorization'],
            'Bearer ${authority.jwt(authority.actor, authority.firstSession)}',
          );
        }
        if (operation == 'notification') {
          expect(h.repo.state.notificationEvents.single.status, 'read');
        }
      },
    );
    for (final transition in ['replacement session', 'A to B to A']) {
      test(
        '$operation rejects late ACK after $transition with original Bearer',
        () async {
          final entered = Completer<void>(),
              release = Completer<http.Response>();
          final h = await _Harness.create(
            block: _operationRpc[operation],
            entered: entered,
            release: release,
          );
          final pending = h.invoke(operation);
          final rejected = expectLater(pending, throwsStateError);
          await entered.future;
          if (transition == 'A to B to A') {
            await h.login(authority.other, authority.nextSession);
            await h.login(authority.actor, authority.firstSession);
          } else {
            await h.login(authority.actor, authority.nextSession);
          }
          release.complete(
            authority.jsonResponse(switch (operation) {
              'create' || 'join' => authority.group,
              'profile' => _profile(),
              'promote' => {
                'collection_id': authority.group,
                'public_id': _peer,
                'role': 'admin',
                'status': 'active',
              },
              _ => null,
            }),
          );
          await rejected;
          final mutation = h.requests.singleWhere(
            (r) => r.url.path.endsWith(_operationRpc[operation]!),
          );
          expect(
            mutation.headers['Authorization'],
            'Bearer ${authority.jwt(authority.actor, authority.firstSession)}',
          );
          expect(h.repo.state.notificationEvents.single.status, 'unread');
          expect(
            h.requests.any(
              (r) => r.url.path.endsWith('list_current_user_collections'),
            ),
            isFalse,
          );
        },
      );
    }
  }
  for (final field in ['id', 'public_id', 'whatsapp_phone']) {
    test('profile ACK cannot forge immutable $field', () async {
      final profile = _profile()
        ..[field] = field == 'id' ? authority.other : 'forged';
      final h = await _Harness.create(profile: profile);
      await expectLater(h.invoke('profile'), throwsFormatException);
      expect(h.repo.state.currentProfile!.id, authority.actor);
      expect(h.repo.state.currentProfile!.publicId, '123456');
    });
  }
  for (final operation in ['create', 'group profile']) {
    test(
      '$operation scoped fetch cannot return a forged group owner',
      () async {
        final h = await _Harness.create(group: _group(owner: authority.other));
        await expectLater(h.invoke(operation), throwsFormatException);
        expect(h.repo.state.collections.single.creatorUserId, authority.actor);
      },
    );
  }
  test('join scoped fetch must confirm current membership', () async {
    final h = await _Harness.create(
      group: _group(owner: authority.other)..['is_member'] = false,
    );
    await expectLater(h.invoke('join'), throwsFormatException);
  });
  test(
    'creation stops after native permission await changes session',
    () async {
      final native = Completer<SmsAccessStatus>();
      final h = await _Harness.create();
      h.repo.nativeStatus = native.future;
      final rejected = expectLater(h.invoke('create'), throwsStateError);
      await h.login(authority.actor, authority.nextSession);
      native.complete(_nativeStatus);
      await rejected;
      expect(h.requests, isEmpty);
    },
  );
  for (final operation in ['create', 'group profile', 'join']) {
    test(
      '$operation late scoped group reply cannot publish after session replacement',
      () async {
        final entered = Completer<void>(), release = Completer<http.Response>();
        final h = await _Harness.create(
          block: 'list_current_user_collections',
          entered: entered,
          release: release,
        );
        final rejected = expectLater(h.invoke(operation), throwsStateError);
        await entered.future;
        await h.login(authority.actor, authority.nextSession);
        release.complete(authority.jsonResponse([_group()]));
        await rejected;
        final fetch = h.requests.singleWhere(
          (r) => r.url.path.endsWith('list_current_user_collections'),
        );
        expect(
          fetch.headers['Authorization'],
          'Bearer ${authority.jwt(authority.actor, authority.firstSession)}',
        );
      },
    );
  }
  test(
    'creation late integrity verdict cannot dispatch create under a new session',
    () async {
      final entered = Completer<void>(), release = Completer<http.Response>();
      final h = await _Harness.create(
        block: 'verify-play-integrity',
        entered: entered,
        release: release,
      );
      final rejected = expectLater(h.invoke('create'), throwsStateError);
      await entered.future;
      await h.login(authority.actor, authority.nextSession);
      release.complete(
        authority.jsonResponse({
          'status': 'pass',
          'native_capability': 'synthetic-native-capability',
          'capability_expires_at': '2030-01-01T00:00:00Z',
        }),
      );
      await rejected;
      expect(
        h.requests.any(
          (r) => r.url.path.endsWith(
            'create_private_group_with_owner_media_attested',
          ),
        ),
        isFalse,
      );
    },
  );
  for (final expiry in [
    '2030-02-30T12:00:00Z',
    '2030-01-01T00:00:00',
    '0000-01-01T00:00:00Z',
  ]) {
    test(
      'creation capability calendar $expiry fails before create RPC',
      () async {
        final h = await _Harness.create(capabilityExpiry: expiry);
        await expectLater(h.invoke('create'), throwsFormatException);
        expect(
          h.requests.any(
            (r) => r.url.path.endsWith(
              'create_private_group_with_owner_media_attested',
            ),
          ),
          isFalse,
        );
      },
    );
  }
  test(
    'notification optimistic state cannot relabel a foreign event',
    () async {
      final h = await _Harness.create();
      h.repo.state = h.repo.state.copyWith(
        notificationEvents: [_notification(user: authority.other)],
      );
      await h.invoke('notification');
      expect(h.repo.state.notificationEvents.single.status, 'unread');
    },
  );
}
