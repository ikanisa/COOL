// PRIVATE CANDIDATE: authored, not executed or adopted.
import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';

const requestId = 'a1111111-1111-4111-8111-111111111111';
const principal = '00000000-0000-4000-8000-000000000011';
const authUser = '00000000-0000-4000-8000-000000000012';
const otherPrincipal = '00000000-0000-4000-8000-000000000021';
const otherAuthUser = '00000000-0000-4000-8000-000000000022';
const firstSession = '00000000-0000-4000-8000-000000000013';
const nextSession = '00000000-0000-4000-8000-000000000023';
const groupId = '00000000-0000-4000-8000-000000000031';
const project = 'https://collect-group-fixture.supabase.co';
const publishable = 'sb_publishable_synthetic_group_test_key_only';
const rpcPrefix = '/functions/v1/collect-api/v1/rpc/';
const profile = CollectProfile(
  id: principal,
  publicId: '123456',
  whatsappPhone: '',
  countryCode: 'RW',
  currencyCode: 'RWF',
);

class NoSms extends SmsAccessChannel {
  // Account-switch cleanup may suspend an old owner without granting SMS access.
  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async => true;

  @override
  Future<SmsAccessStatus> status() async =>
      throw StateError('Group metadata must not read SMS');

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async =>
      throw StateError('Group metadata must not request SMS');
}

class MetadataRepository extends FixtureCollectRepository {
  MetadataRepository({
    super.backend,
    CollectProfile memberProfile = profile,
    CollectCollection? selectedGroup,
  }) : super(profileOverride: memberProfile, smsAccessChannel: NoSms()) {
    if (selectedGroup != null) {
      state = state.copyWith(collections: [selectedGroup]);
    }
  }

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {}
}

CollectCloudflareClient backendFor(
  Future<http.Response> Function(http.Request) handler,
) {
  final configuration = CollectSupabaseConfiguration.fromEnvironment(
    const AppEnv(
      apiUrl: '',
      publicUrl: '',
      adminAppUrl: '',
      enableSmsReader: false,
      enableAndroidSmsAccess: false,
      enableAdminPanel: false,
      enableAdminDevTools: false,
      authCaptchaEnabled: false,
      authCaptchaProvider: 'turnstile',
      authCaptchaSiteKey: '',
      backend: 'supabase',
      supabaseUrl: project,
      supabasePublishableKey: publishable,
    ),
  );
  return CollectCloudflareClient(
    configuration.api.origin,
    supabaseConfiguration: configuration,
    httpClient: MockClient(handler),
  );
}

Future<String> recover(
  CollectCloudflareClient backend, {
  String member = principal,
  String subject = authUser,
  String sessionId = firstSession,
  String? email,
}) async {
  String part(Object value) =>
      base64UrlEncode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final accessToken =
      '${part({'alg': 'ES256'})}.${part({'sub': subject, 'iss': '$project/auth/v1', 'aud': 'authenticated', 'role': 'authenticated', 'session_id': sessionId, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.fixture';
  await backend.auth.recoverSession(
    jsonEncode({
      'access_token': accessToken,
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'user': {
        'id': member,
        'auth_user_id': subject,
        'phone': '',
        'email': ?email,
      },
    }),
  );
  expect(backend.auth.currentUser?.id, member);
  expect(backend.auth.currentSession?.claims['sub'], subject);
  return accessToken;
}

http.Response reply(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> group({String owner = principal}) => {
  'id': groupId,
  'slug': 'synthetic-private',
  'title': 'Private draft',
  'description': '',
  'creator_user_id': owner,
  'collection_type': 'ikimina',
  'is_member': true,
  'is_public': false,
  'is_platform_sponsored': false,
  'receiver_momo_number': null,
  'receiver_network': null,
  'receiver_display_label': null,
  'payment_rail': 'unavailable',
  'settlement_currency': 'RWF',
  'visibility_status': 'private',
  'created_at': '2026-10-20T09:00:00Z',
};

void expectSupabaseCalls(List<http.Request> calls, String capturedToken) {
  expect(calls, isNotEmpty);
  for (final call in calls) {
    expect(call.url.origin, project);
    expect(call.url.path, startsWith(rpcPrefix));
    expect(call.headers['apikey'], publishable);
    expect(call.headers['authorization'], 'Bearer $capturedToken');
  }
  final claims =
      jsonDecode(
            utf8.decode(
              base64Url.decode(
                base64Url.normalize(capturedToken.split('.')[1]),
              ),
            ),
          )
          as Map;
  expect(claims['iss'], '$project/auth/v1');
  expect(claims['sub'], authUser);
  expect(claims['sub'], isNot(principal));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'metadata draft without a phone or wallet has no payment route',
    () async {
      final repo = MetadataRepository();
      addTearDown(repo.dispose);
      final value = await repo.createCollection(
        title: 'Private draft',
        description: '',
        requestId: requestId,
        imageUrl: 'collect-cover:rw-01-neighbourhood-ikimina:v1',
        accentColorHex: '#123456',
      );
      expect(value.creatorUserId, principal);
      expect(value.receiverMomoNumber, isNull);
      expect(value.primaryPaymentRail, 'unavailable');
      expect(value.supportsRwandaMomo, isFalse);
      expect(value.isPublic, isFalse);
      expect(value.isCurrentUserMember, isTrue);
      final same = await repo.createCollection(
        title: 'Private draft',
        description: '',
        requestId: requestId,
        imageUrl: 'collect-cover:rw-01-neighbourhood-ikimina:v1',
        accentColorHex: '#123456',
      );
      expect(same.id, value.id);
      expect(
        repo.state.collections.where((g) => g.id == value.id),
        hasLength(1),
      );
    },
  );

  test(
    'Supabase email-only foreign walletless creator binds mapped principal',
    () async {
      final calls = <http.Request>[];
      final backend = backendFor((request) async {
        calls.add(request);
        if (request.url.path ==
            '${rpcPrefix}create_private_group_metadata_v1') {
          return reply(groupId);
        }
        if (request.url.path == '${rpcPrefix}list_current_user_collections') {
          return reply([group()]);
        }
        throw StateError('Unexpected request ${request.url.path}');
      });
      final token = await recover(backend, email: 'creator@example.invalid');
      final creator = profile.copyWith(countryCode: 'DE', currencyCode: 'EUR');
      final repo = MetadataRepository(backend: backend, memberProfile: creator);
      addTearDown(() async {
        repo.dispose();
        await backend.dispose();
      });
      final created = await repo.createCollection(
        title: ' Private draft ',
        description: '',
        requestId: requestId,
      );
      expect(backend.auth.currentUser?.email, 'creator@example.invalid');
      expect(backend.auth.currentUser?.phone, isEmpty);
      expect(creator.countryCode, 'DE');
      expect(creator.currencyCode, 'EUR');
      expect(creator.whatsappPhone, isEmpty);
      expect(creator.momoNumber, isEmpty);
      expect(creator.momoProvider, isEmpty);
      expect(creator.isComplete, isFalse);
      expect(created.creatorUserId, principal);
      expect(created.creatorUserId, isNot(authUser));
      final sent = calls.singleWhere(
        (request) =>
            request.url.path.endsWith('create_private_group_metadata_v1'),
      );
      final body = jsonDecode(sent.body) as Map;
      expect(
        body.keys,
        unorderedEquals([
          'p_request_id',
          'build_channel',
          'group_name',
          'group_description',
          'group_collection_type',
          'group_category_subtype',
          'group_purpose_label',
          'group_image_url',
          'group_accent_color_hex',
          'group_is_public',
        ]),
      );
      expect(body['p_request_id'], requestId);
      expect(body['group_name'], 'Private draft');
      expect(body['group_is_public'], isFalse);
      expect(body['build_channel'], 'android_group_metadata');
      for (final key in [
        'receiver_momo_number',
        'receiver_label',
        'receiver_provider',
        'native_capability',
        'momo_number_hash',
        'creator_user_id',
      ]) {
        expect(body.containsKey(key), isFalse);
      }
      final read = calls.singleWhere(
        (request) => request.url.path.endsWith('list_current_user_collections'),
      );
      expect(jsonDecode(read.body), {'p_collection_id': groupId});
      expect(calls, hasLength(2));
      expectSupabaseCalls(calls, token);
    },
  );

  test(
    'late Supabase create cannot publish after account replacement',
    () async {
      final entered = Completer<void>();
      final release = Completer<http.Response>();
      final calls = <http.Request>[];
      final backend = backendFor((request) async {
        calls.add(request);
        if (request.url.path.endsWith('create_private_group_metadata_v1')) {
          entered.complete();
          return release.future;
        }
        return reply([group()]);
      });
      final token = await recover(backend);
      final repo = MetadataRepository(backend: backend);
      addTearDown(() async {
        repo.dispose();
        await backend.dispose();
      });
      final pending = expectLater(
        repo.createCollection(
          title: 'Private draft',
          description: '',
          requestId: requestId,
        ),
        throwsStateError,
      );
      await entered.future;
      await recover(
        backend,
        member: otherPrincipal,
        subject: otherAuthUser,
        sessionId: nextSession,
      );
      release.complete(reply(groupId));
      await pending;
      expect(
        repo.state.collections.any(
          (item) => item.id == groupId && item.creatorUserId == principal,
        ),
        isFalse,
      );
      expect(calls, hasLength(1));
      expectSupabaseCalls(calls, token);
    },
  );

  test(
    'explicit unavailable DTO overrides a stale network and retains currency',
    () {
      final unavailable = CollectCollection.fromJson({
        ...group(),
        'receiver_network': 'mtn_momo',
      });
      expect(unavailable.supportsRwandaMomo, isFalse);
      expect(unavailable.contributionRailFor(profile), 'unavailable');
      expect(unavailable.settlementCurrency, 'RWF');
      final legacy = CollectCollection.fromJson({
        ...group(),
        'payment_rail': null,
        'receiver_network': 'mtn_momo',
      });
      expect(legacy.primaryPaymentRail, 'unavailable');
      final public = CollectCollection.fromJson({
        ...group(),
        'is_public': true,
        'payment_rail': 'rwanda_momo',
        'receiver_network': 'mtn_momo',
      });
      expect(public.receiverMomoNumber, isNull);
      expect(public.supportsRwandaMomo, isTrue);
    },
  );

  test(
    'foreign walletless Supabase invite keeps original session and body',
    () async {
      final calls = <http.Request>[];
      final backend = backendFor((request) async {
        calls.add(request);
        if (request.url.path == '${rpcPrefix}join_group_by_share_code') {
          return reply(groupId);
        }
        if (request.url.path == '${rpcPrefix}list_current_user_collections') {
          return reply([group(owner: otherPrincipal)]);
        }
        throw StateError('Unexpected request ${request.url.path}');
      });
      final token = await recover(backend);
      final repo = MetadataRepository(
        backend: backend,
        memberProfile: profile.copyWith(countryCode: 'DE', currencyCode: 'EUR'),
      );
      addTearDown(() async {
        repo.dispose();
        await backend.dispose();
      });
      final joined = await repo.joinGroupBySlug(
        '44444444-4444-4444-8444-444444444444',
      );
      expect(joined.id, groupId);
      expect(joined.isCurrentUserMember, isTrue);
      expect(repo.state.currentProfile!.countryCode, 'DE');
      expect(repo.state.currentProfile!.momoNumber, isEmpty);
      final request = calls.singleWhere(
        (request) => request.url.path.endsWith('join_group_by_share_code'),
      );
      expect(jsonDecode(request.body), {
        'p_group_code': '44444444-4444-4444-8444-444444444444',
      });
      expect(calls, hasLength(2));
      expectSupabaseCalls(calls, token);
    },
  );

  test(
    'metadata create does not require a country or payment profile',
    () async {
      for (final member in [
        profile.copyWith(countryCode: 'DE', currencyCode: 'EUR'),
        profile.copyWith(countryCode: '', currencyCode: ''),
        profile.copyWith(currencyCode: 'EUR'),
      ]) {
        final repo = MetadataRepository(memberProfile: member);
        addTearDown(repo.dispose);
        final created = await repo.createCollection(
          title: 'Private draft',
          description: '',
          requestId: requestId,
        );
        expect(created.creatorUserId, member.id);
        expect(created.primaryPaymentRail, 'unavailable');
        expect(created.receiverMomoNumber, isNull);
      }
    },
  );

  test('metadata create remains private without financial authority', () async {
    final repo = MetadataRepository();
    addTearDown(repo.dispose);
    await expectLater(
      repo.createCollection(
        title: 'Private draft',
        description: '',
        requestId: requestId,
        isPublic: true,
      ),
      throwsFormatException,
    );
  });

  test(
    'uncertain Supabase create retries retain one explicit draft identity',
    () async {
      final calls = <http.Request>[];
      var creates = 0;
      final backend = backendFor((request) async {
        calls.add(request);
        if (request.url.path.endsWith('create_private_group_metadata_v1')) {
          creates++;
          if (creates == 1) {
            return http.Response(
              jsonEncode({'error': 'temporarily_unavailable'}),
              503,
            );
          }
          return reply(groupId);
        }
        if (request.url.path.endsWith('list_current_user_collections')) {
          return reply([group()]);
        }
        throw StateError('Unexpected request ${request.url.path}');
      });
      final token = await recover(backend);
      final repo = MetadataRepository(backend: backend);
      addTearDown(() async {
        repo.dispose();
        await backend.dispose();
      });
      await expectLater(
        repo.createCollection(
          title: 'Private draft',
          description: '',
          requestId: requestId,
        ),
        throwsA(isA<CollectApiException>()),
      );
      expect(creates, 1, reason: 'No automatic retry of an uncertain command');
      final created = await repo.createCollection(
        title: 'Private draft',
        description: '',
        requestId: requestId,
      );
      expect(created.id, groupId);
      final attempts = calls
          .where(
            (request) =>
                request.url.path.endsWith('create_private_group_metadata_v1'),
          )
          .toList();
      expect(attempts, hasLength(2));
      expect(jsonDecode(attempts.first.body), jsonDecode(attempts.last.body));
      expect(
        (jsonDecode(attempts.last.body) as Map)['p_request_id'],
        requestId,
      );
      expect(calls, hasLength(3));
      expectSupabaseCalls(calls, token);
    },
  );

  for (final imageCommand in <String?>[null, '']) {
    test(
      'Supabase profile image ${imageCommand == null ? 'preserve' : 'clear'} keeps the exact edit contract',
      () async {
        const cover = 'collect-cover:rw-01-neighbourhood-ikimina:v1';
        String? storedImage = cover;
        var storedTitle = 'Private draft';
        final calls = <http.Request>[];
        final backend = backendFor((request) async {
          calls.add(request);
          if (request.url.path ==
              '${rpcPrefix}update_rwanda_momo_group_profile') {
            final body = jsonDecode(request.body) as Map;
            storedTitle = body['p_group_name'] as String;
            final command = body['p_group_image_url'];
            if (command != null) {
              storedImage = command == '' ? null : command as String;
            }
            return reply(null);
          }
          if (request.url.path == '${rpcPrefix}list_current_user_collections') {
            return reply([
              {...group(), 'title': storedTitle, 'image_url': storedImage},
            ]);
          }
          throw StateError('Unexpected request ${request.url.path}');
        });
        final token = await recover(backend, email: 'owner@example.invalid');
        final repo = MetadataRepository(
          backend: backend,
          selectedGroup: CollectCollection.fromJson({
            ...group(),
            'image_url': cover,
          }),
        );
        addTearDown(() async {
          repo.dispose();
          await backend.dispose();
        });
        final updated = await repo.updateCollectionProfile(
          collectionId: groupId,
          title: ' Updated title ',
          description: ' Updated description ',
          recurringCadence: 'monthly',
          imageUrl: imageCommand,
          isPublic: false,
        );
        final sent = calls.singleWhere(
          (request) =>
              request.url.path.endsWith('update_rwanda_momo_group_profile'),
        );
        expect(jsonDecode(sent.body), {
          'p_collection_id': groupId,
          'p_group_name': 'Updated title',
          'p_group_description': 'Updated description',
          'p_group_image_url': imageCommand,
          'p_group_accent_color_hex': null,
          'p_group_is_public': false,
          'p_group_recurring_cadence': 'monthly',
          'p_group_collection_type': null,
          'p_group_category_subtype': null,
          'p_group_purpose_label': null,
          'p_group_is_recurring': true,
        });
        final read = calls.singleWhere(
          (request) =>
              request.url.path.endsWith('list_current_user_collections'),
        );
        expect(jsonDecode(read.body), {'p_collection_id': groupId});
        expect(calls, hasLength(2));
        expectSupabaseCalls(calls, token);
        expect(updated.title, 'Updated title');
        expect(updated.imageUrl, imageCommand == null ? cover : null);
        expect(updated.creatorUserId, principal);
        expect(updated.receiverMomoNumber, isNull);
        expect(updated.primaryPaymentRail, 'unavailable');
      },
    );
  }
}
