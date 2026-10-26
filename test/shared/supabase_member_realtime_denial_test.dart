import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/core/supabase/collect_supabase_configuration.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = '99770000-0000-4000-8000-000000000001';
const _b = '99770000-0000-4000-8000-000000000002';
const _group = '99770000-0000-4000-8000-000000000011';
const _sidA = '99770000-0000-4000-8000-000000000021';
const _sidB = '99770000-0000-4000-8000-000000000022';
const _project = 'https://synthetic.collect.test';

String _token(String user, String sid, int revision) {
  String part(Object body) =>
      base64Url.encode(utf8.encode(jsonEncode(body))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part({'sub': user, 'session_id': sid, 'iss': '$_project/auth/v1', 'aud': 'authenticated', 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'revision': revision})}.synthetic';
}

class _Sms extends SmsAccessChannel {
  const _Sms();
  @override
  Future<bool> suspendUnlessOwner(String? ownerUserId) async => true;
}

class _Cache extends CollectOfflineCache {
  _Cache() : super(preferencesKey: 'synthetic.supabase.known-denial');
  bool failClear = false;
  Completer<void>? barrier;
  int clears = 0;
  @override
  Future<void> clear() {
    clears++;
    if (failClear) {
      return Future<void>.error(StateError('Synthetic protected store locked'));
    }
    final cleared = super.clear(); // Real synchronous write-epoch advance.
    final held = barrier;
    barrier = null;
    return held == null ? cleared : cleared.then((_) => held.future);
  }
}

class _Poll {
  _Poll(this.request);
  final http.Request request;
  final response = Completer<http.Response>();
  void finish(int status) {
    if (response.isCompleted) return;
    response.complete(
      http.Response(
        status == 200
            ? '{"events":[],"cursor":"0"}'
            : '{"code":"custom_unlisted_denial"}',
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
  }
}

class _Probe {
  final cache = _Cache();
  final polls = <_Poll>[];
  final histories = <Completer<http.Response>>[];
  final rosters = <Completer<http.Response>>[];
  late CollectCloudflareClient client;
  late CollectRepository repo;
  bool offline = false, missingProfile = false, holdHistory = false;
  int profileReads = 0, historyReads = 0;
  http.Response reply(http.Request request, Object? body) => http.Response(
    jsonEncode(body),
    200,
    request: request,
    headers: {'content-type': 'application/json'},
  );
  Map<String, Object?> history() => {
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
    'revision': '0123456789abcdef0123456789abcdef',
    'next_cursor': null,
  };
  Future<void> start() async {
    final config = CollectSupabaseConfiguration.fromEnvironment(
      const AppEnv(
        apiUrl: '',
        publicUrl: 'https://collect.ikanisa.com',
        adminAppUrl: '',
        enableSmsReader: false,
        enableAndroidSmsAccess: false,
        enableAdminPanel: false,
        enableAdminDevTools: false,
        authCaptchaEnabled: false,
        authCaptchaProvider: '',
        authCaptchaSiteKey: '',
        backend: 'supabase',
        supabaseUrl: _project,
        supabaseApiUrl: 'https://api.synthetic.collect.test',
        supabasePublishableKey: 'sb_publishable_syntheticPublicKey1234',
      ),
    );
    client = CollectCloudflareClient(
      config.api.origin,
      supabaseConfiguration: config,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/v1/sync')) {
          final poll = _Poll(request);
          polls.add(poll);
          return poll.response.future;
        }
        if (offline) throw const SocketException('Synthetic offline transport');
        final body =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(
                      base64Url.normalize(
                        request.headers['Authorization']!
                            .substring(7)
                            .split('.')[1],
                      ),
                    ),
                  ),
                )
                as Map;
        final owner = body['sub'] as String;
        switch (request.url.path.split('/').last) {
          case 'get_current_member_profile':
            profileReads++;
            return reply(
              request,
              missingProfile
                  ? null
                  : {
                      'id': owner,
                      'public_id': '123456',
                      'whatsapp_phone': '250788123456',
                      'country_code': 'RW',
                      'currency_code': 'RWF',
                    },
            );
          case 'list_current_user_collections':
            return reply(request, [
              {
                'id': _group,
                'slug': 'synthetic-member',
                'creator_user_id': owner,
                'title': 'Synthetic private',
                'description': '',
                'payment_rail': 'rwanda_momo',
                'settlement_currency': 'RWF',
                'receiver_network': 'mtn_momo',
                'is_member': true,
                'created_at': '2026-09-01T00:00:00Z',
              },
            ]);
          case 'list_current_member_recent_intents':
            return reply(request, {'items': [], 'pending_count': 0});
          case 'list_current_member_history_page':
            historyReads++;
            if (holdHistory) {
              final held = Completer<http.Response>();
              histories.add(held);
              return held.future;
            }
            return reply(request, history());
          case 'list_current_member_group_roster':
            final held = Completer<http.Response>();
            rosters.add(held);
            return held.future;
          case 'list_current_member_collection_balances':
            return reply(request, []);
          case 'get_notification_preferences_v2':
            return reply(request, {
              'contract_version': 2,
              'ok': true,
              'user_id': owner,
              'revision': 0,
              'exists': false,
              'preferences': NotificationPreferences.defaults.toJson(),
            });
          case 'notification-events':
            return reply(request, []);
          default:
            throw StateError('Unexpected synthetic endpoint');
        }
      }),
    );
    await login(_a, _sidA);
    repo = CollectRepository(
      backend: client,
      smsAccessChannel: const _Sms(),
      offlineCache: cache,
    );
    await repo.loadInitial();
    await until(() => polls.isNotEmpty && !repo.state.isLoading);
    // This synthetic project cannot open the nominated native WS. Actual
    // Supabase HTTP denial/subscription/repository logic executes unchanged.
    expect(repo.state.currentProfile?.id, _a);
    expect((await cache.read())?.collections.single.id, _group);
  }

  Future<void> login(String owner, String sid, {int revision = 0}) async {
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': _token(owner, sid, revision),
        'refresh_token': 'synthetic-refresh',
        'token_type': 'bearer',
        'user': {'id': owner, 'auth_user_id': owner},
      }),
    );
  }

  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(
      condition(),
      true,
      reason: 'Bounded synthetic consumer condition not reached',
    );
  }

  Future<void> close() async {
    repo.dispose();
    for (final poll in polls) {
      poll.finish(200);
    }
    for (final held in histories) {
      if (!held.isCompleted) {
        held.complete(
          http.Response(
            jsonEncode(history()),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
      }
    }
    for (final held in rosters) {
      if (!held.isCompleted) {
        held.complete(
          http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
      }
    }
    await client.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Probe h;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    h = _Probe();
    await h.start();
  });
  tearDown(() async => h.close());
  test(
    'unlisted403 immediately empties scope; offline and failed cache clear cannot restore it',
    () async {
      final revision = h.repo.sessionGeneration;
      h.cache.failClear = true;
      h.offline = true;
      h.polls.single.finish(403);
      await h.until(() => h.repo.sessionGeneration != revision);
      expect(h.repo.state.currentProfile, isNull);
      expect(h.repo.state.collections, isEmpty);
      expect(h.repo.state.contributions, isEmpty);
      expect(
        await h.repo.restoreOfflineSnapshot(reason: 'Synthetic outage'),
        false,
      );
      expect(
        (await h.cache.read())?.collections.single.id,
        _group,
      ); // Stale-cache positive control.
      expect(h.cache.clears, 1);
      await expectLater(
        h.repo.fetchHistoryPage(const MemberHistoryQuery()),
        throwsStateError,
      );
    },
  );
  test('denial fences already in-flight same-session history reply', () async {
    h.holdHistory = true;
    final rejected = expectLater(
      h.repo.fetchHistoryPage(const MemberHistoryQuery()),
      throwsStateError,
    );
    await h.until(() => h.histories.length == 1);
    h.offline = true;
    h.polls.single.finish(401);
    await h.until(() => h.repo.state.currentProfile == null);
    h.histories.single.complete(
      http.Response(
        jsonEncode(h.history()),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    await rejected;
  });
  test(
    'complete accepted current read restores live history after denial',
    () async {
      final before = h.repo.sessionGeneration;
      h.polls.single.finish(403);
      await h.until(
        () =>
            h.repo.sessionGeneration > before &&
            h.repo.state.currentProfile != null &&
            !h.repo.state.isLoading &&
            h.polls.length == 2,
      );
      expect(
        (await h.repo.fetchHistoryPage(const MemberHistoryQuery())).totalCount,
        0,
      );
      expect(h.repo.state.usingStaleCache, false);
    },
  );
  test('null live profile cannot start private history reads', () async {
    h.missingProfile = true;
    final revision = h.repo.sessionGeneration;
    h.polls.single.finish(403);
    await h.until(
      () => h.repo.sessionGeneration > revision && !h.repo.state.isLoading,
    );
    final reads = h.historyReads;
    expect(
      await h.repo.restoreOfflineSnapshot(reason: 'Synthetic outage'),
      false,
    );
    expect(h.repo.state.currentProfile, isNull);
    await expectLater(
      h.repo.fetchHistoryPage(const MemberHistoryQuery()),
      throwsStateError,
    );
    expect(h.historyReads, reads);
  });
  test('departed bearer403 cannot deny same SID refreshed token', () async {
    final revision = h.repo.sessionGeneration;
    final poll = h.polls.single;
    await h.login(_a, _sidA, revision: 1);
    poll.finish(403);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(h.repo.sessionGeneration, revision);
    expect(h.repo.state.currentProfile?.id, _a);
    expect(h.cache.clears, 0);
  });
  test(
    'departed account403 cannot clear replacement scope including A-B-A',
    () async {
      final poll = h.polls.single;
      await h.login(_b, _sidB);
      await h.until(() => h.repo.state.currentProfile?.id == _b);
      await h.login(_a, _sidA);
      await h.until(() => h.repo.state.currentProfile?.id == _a);
      final clears = h.cache.clears;
      final revision = h.repo.sessionGeneration;
      poll.finish(403);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(h.repo.sessionGeneration, revision);
      expect(h.cache.clears, clears);
      expect(h.repo.state.currentProfile?.id, _a);
    },
  );
  test('old denied clear completion cannot reload replacement scope', () async {
    final barrier = Completer<void>();
    h.cache.barrier = barrier;
    final revision = h.repo.sessionGeneration;
    h.polls.single.finish(403);
    await h.until(() => h.repo.sessionGeneration > revision);
    expect(h.repo.state.currentProfile, isNull);
    await h.login(_b, _sidB);
    await h.until(() => h.repo.state.currentProfile?.id == _b);
    final reads = h.profileReads;
    barrier.complete();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(h.profileReads, reads);
    expect(h.repo.state.currentProfile?.id, _b);
    expect((await h.cache.read())?.currentProfile?.id, _b);
  });
  test(
    'retained history controller cannot publish after same-session denial',
    () async {
      h.holdHistory = true;
      final controller = MemberHistoryController(
        h.repo,
        const MemberHistoryQuery(sort: 'highest'),
      );
      addTearDown(controller.dispose);
      await h.until(() => h.histories.length == 1);
      h.offline = true;
      h.polls.single.finish(403);
      await h.until(() => h.repo.state.currentProfile == null);
      h.histories.single.complete(
        http.Response(
          jsonEncode(h.history()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.page, isNull);
      expect(controller.state.error, 'Account changed. Reload history.');
    },
  );
  test(
    'roster old reply stays fenced after denied scope is authoritatively reaccepted',
    () async {
      final pending = expectLater(
        h.repo.membersForCollection(_group),
        throwsStateError,
      );
      await h.until(() => h.rosters.length == 1);
      final revision = h.repo.sessionGeneration;
      h.polls.single.finish(403);
      await h.until(
        () =>
            h.repo.sessionGeneration > revision &&
            h.repo.state.currentProfile != null &&
            !h.repo.state.isLoading,
      );
      h.rosters.single.complete(
        http.Response('[]', 200, headers: {'content-type': 'application/json'}),
      );
      await pending;
    },
  );
  test(
    'synchronous empty-state listener account switch prevents stale global clear',
    () async {
      final revision = h.repo.sessionGeneration;
      var switched = false;
      final remove = h.repo.addListener((state) {
        if (!switched &&
            state.currentProfile == null &&
            h.repo.sessionGeneration > revision) {
          switched = true;
          unawaited(h.login(_b, _sidB));
        }
      }, fireImmediately: false);
      final clears = h.cache.clears;
      h.polls.single.finish(403);
      await h.until(() => h.repo.state.currentProfile?.id == _b);
      // Only the ordinary account-change clear is authorized, never the departed A denial.
      expect(h.cache.clears, clears + 1);
      expect(switched, true);
      remove();
    },
  );
}
