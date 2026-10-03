import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _a = '99720000-0000-4000-8000-000000000001';
const _b = '99720000-0000-4000-8000-000000000002';
const _s1 = '99720000-0000-4000-8000-000000000011';
const _s2 = '99720000-0000-4000-8000-000000000012';
const _edit = NotificationPreferences(paymentReminders: false);
const _newer = NotificationPreferences(groupUpdates: false);

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
Map<String, dynamic> _read({
  int revision = 1,
  bool exists = true,
  String user = _a,
}) => {
  'contract_version': 2,
  'ok': true,
  'user_id': user,
  'revision': revision,
  'exists': exists,
  'preferences': NotificationPreferences.defaults.toJson(),
};
Map<String, dynamic> _ack({
  int previous = 1,
  bool changed = true,
  String user = _a,
}) => {
  'contract_version': 2,
  'ok': true,
  'user_id': user,
  'previous_revision': previous,
  'revision': previous + (changed ? 1 : 0),
  'changed': changed,
  'updated_at': '2026-09-30T10:00:00+00:00',
};
bool _rpc(http.Request r, String name) => r.url.path.endsWith('/$name');
Map<String, dynamic> _body(http.Request r) =>
    jsonDecode(r.body) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cached defaults never invent revision zero or authorize a save',
    () async {
      final h = await _Harness.create();
      expect(h.repo.notificationPreferencesRevision, isNull);
      await expectLater(
        h.repo.updateNotificationPreferences(_edit),
        throwsStateError,
      );
      expect(h.saves, isEmpty);
      expect(h.repo.state.notificationPreferences.paymentReminders, isTrue);
      expect(h.repo.pendingNotificationPreferences?.paymentReminders, isFalse);
    },
  );

  test(
    'authorized preview fixture permits local choices without inventing a server revision',
    () async {
      final repo = CollectRepository.fixture(
        initialState: CollectState(
          currentProfile: _profile(_a),
          collections: const [],
          paymentIntents: const [],
          contributions: const [],
        ),
      );
      addTearDown(repo.dispose);
      expect(repo.notificationPreferencesNeedsRefresh, isFalse);
      expect(repo.notificationPreferencesRevision, isNull);
      await repo.updateNotificationPreferences(_edit);
      expect(repo.state.notificationPreferences.paymentReminders, isFalse);
      expect(repo.notificationPreferencesRevision, isNull);
      final production = CollectRepository();
      addTearDown(production.dispose);
      expect(production.notificationPreferencesNeedsRefresh, isTrue);
      await expectLater(
        production.updateNotificationPreferences(_edit),
        throwsStateError,
      );
    },
  );

  test(
    'discard after uncertainty retains null revision and required explicit refresh',
    () async {
      final h = await _Harness.create(
        respond: (r) => _rpc(r, 'set_notification_preferences_v2')
            ? _json({
                'code': '40001',
                'message': 'runtime_control_conflict',
              }, 409)
            : _fallback(r),
      );
      await h.repo.refreshNotificationPreferences();
      await expectLater(
        h.repo.updateNotificationPreferences(_edit),
        throwsA(isA<PostgrestException>()),
      );
      h.repo.discardPendingNotificationPreferences();
      expect(h.repo.pendingNotificationPreferences, isNull);
      expect(h.repo.notificationPreferencesRevision, isNull);
      expect(h.repo.notificationPreferencesNeedsRefresh, isTrue);
      expect(h.repo.state.notificationPreferences.paymentReminders, isTrue);
      await expectLater(
        h.repo.updateNotificationPreferences(_newer),
        throwsStateError,
      );
      expect(h.saves, hasLength(1));
    },
  );

  test(
    'discard after refreshed review preserves server revision and never dispatches a save',
    () async {
      final h = await _Harness.create();
      await expectLater(
        h.repo.updateNotificationPreferences(_edit),
        throwsStateError,
      );
      await h.repo.refreshNotificationPreferences();
      h.repo.discardPendingNotificationPreferences();
      expect(h.repo.pendingNotificationPreferences, isNull);
      expect(h.repo.notificationPreferencesRevision, 1);
      expect(h.repo.notificationPreferencesNeedsRefresh, isFalse);
      expect(h.saves, isEmpty);
    },
  );

  final badReads = <String, Object?>{
    'null': null,
    'array': [],
    'missing': {},
    'unknown field': {..._read(), 'private': 'ignored'},
    'version string': {..._read(), 'contract_version': '2'},
    'version double': {..._read(), 'contract_version': 2.0},
    'wrong owner': {..._read(), 'user_id': _b},
    'revision string': {..._read(), 'revision': '1'},
    'negative revision': {..._read(), 'revision': -1},
    'large revision': {..._read(), 'revision': 1000000001},
    'existing zero': _read(revision: 0),
    'nullable exists': {..._read(), 'exists': null},
    'missing preference': {
      ..._read(),
      'preferences': {'payment_reminders': false},
    },
    'nullable bool': {
      ..._read(),
      'preferences': {
        ...NotificationPreferences.defaults.toJson(),
        'payment_reminders': null,
      },
    },
    'string bool': {
      ..._read(),
      'preferences': {
        ...NotificationPreferences.defaults.toJson(),
        'payment_reminders': 'false',
      },
    },
    'extra bool': {
      ..._read(),
      'preferences': {
        ...NotificationPreferences.defaults.toJson(),
        'private': true,
      },
    },
    'absent nondefault': {
      ..._read(revision: 0, exists: false),
      'preferences': _edit.toJson(),
    },
  };
  for (final entry in badReads.entries) {
    test(
      'actual preference read rejects ${entry.key} and invalidates prior revision',
      () async {
        final h = await _Harness.create();
        await h.repo.refreshNotificationPreferences();
        h.respond = (r) => _rpc(r, 'get_notification_preferences_v2')
            ? _json(entry.value)
            : _fallback(r);
        await expectLater(
          h.repo.refreshNotificationPreferences(),
          throwsFormatException,
        );
        expect(h.repo.notificationPreferencesRevision, isNull);
        expect(h.repo.notificationPreferencesNeedsRefresh, isTrue);
        await expectLater(
          h.repo.updateNotificationPreferences(_edit),
          throwsStateError,
        );
        expect(h.saves, isEmpty);
      },
    );
  }

  test(
    'fresh absent receipt supplies legitimate zero; exact four booleans create revision one',
    () async {
      final h = await _Harness.create(
        respond: (r) => _rpc(r, 'get_notification_preferences_v2')
            ? _json(_read(revision: 0, exists: false))
            : _rpc(r, 'set_notification_preferences_v2')
            ? _json(_ack(previous: 0))
            : _fallback(r),
      );
      await h.repo.refreshNotificationPreferences();
      expect(h.repo.notificationPreferencesRevision, 0);
      await h.repo.updateNotificationPreferences(_edit);
      expect(_body(h.saves.single), {
        'p_preferences': _edit.toJson(),
        'p_expected_revision': 0,
      });
      expect(h.repo.notificationPreferencesRevision, 1);
      expect(h.repo.state.notificationPreferences.paymentReminders, isFalse);
      expect(h.repo.pendingNotificationPreferences, isNull);
    },
  );

  test(
    'unchanged ACK retains loaded revision without optimistic invention',
    () async {
      final h = await _Harness.create(
        respond: (r) => _rpc(r, 'set_notification_preferences_v2')
            ? _json(_ack(changed: false))
            : _fallback(r),
      );
      await h.repo.refreshNotificationPreferences();
      await h.repo.updateNotificationPreferences(
        NotificationPreferences.defaults,
      );
      expect(h.repo.notificationPreferencesRevision, 1);
      expect(h.saves, hasLength(1));
      expect(h.repo.pendingNotificationPreferences, isNull);
    },
  );

  final badAcks = <String, Object?>{
    'null': null,
    'array': [],
    'missing': {},
    'extra field': {..._ack(), 'preferences': _edit.toJson()},
    'wrong owner': {..._ack(), 'user_id': _b},
    'version string': {..._ack(), 'contract_version': '2'},
    'version double': {..._ack(), 'contract_version': 2.0},
    'nullable changed': {..._ack(), 'changed': null},
    'string changed': {..._ack(), 'changed': 'true'},
    'previous mismatch': {..._ack(), 'previous_revision': 2},
    'string revision': {..._ack(), 'revision': '2'},
    'revision double': {..._ack(), 'revision': 2.0},
    'large revision': {..._ack(), 'revision': 1000000001},
    'nonincrement': {..._ack(), 'revision': 1},
    'noop increment': {..._ack(), 'changed': false},
    'timestamp null': {..._ack(), 'updated_at': null},
    'timestamp invalid': {..._ack(), 'updated_at': '2026-02-30T10:00:00Z'},
    'timestamp overflow': {..._ack(), 'updated_at': '2026-09-30T25:00:00Z'},
  };
  for (final entry in badAcks.entries) {
    test(
      'actual preference save rejects ${entry.key}; retains dirty intent and saved state',
      () async {
        final h = await _Harness.create(
          respond: (r) => _rpc(r, 'set_notification_preferences_v2')
              ? _json(entry.value)
              : _fallback(r),
        );
        await h.repo.refreshNotificationPreferences();
        await expectLater(
          h.repo.updateNotificationPreferences(_edit),
          throwsFormatException,
        );
        expect(h.repo.state.notificationPreferences.paymentReminders, isTrue);
        expect(
          h.repo.pendingNotificationPreferences?.paymentReminders,
          isFalse,
        );
        expect(h.repo.notificationPreferencesRevision, isNull);
        expect(h.repo.notificationPreferencesNeedsRefresh, isTrue);
        await expectLater(
          h.repo.updateNotificationPreferences(_edit),
          throwsStateError,
        );
        expect(h.saves, hasLength(1));
      },
    );
  }

  test(
    '40001 sends once; explicit refresh retains intent and permits only a user retry',
    () async {
      final h = await _Harness.create(
        respond: (r) => _rpc(r, 'set_notification_preferences_v2')
            ? _json({
                'code': '40001',
                'message': 'runtime_control_conflict',
              }, 409)
            : _fallback(r),
      );
      await h.repo.refreshNotificationPreferences();
      await expectLater(
        h.repo.updateNotificationPreferences(_edit),
        throwsA(isA<PostgrestException>()),
      );
      await expectLater(
        h.repo.updateNotificationPreferences(_edit),
        throwsStateError,
      );
      expect(h.saves, hasLength(1));
      h.respond = (r) => _rpc(r, 'get_notification_preferences_v2')
          ? _json(_read(revision: 5))
          : _rpc(r, 'set_notification_preferences_v2')
          ? _json(_ack(previous: 5))
          : _fallback(r);
      await h.repo.refreshNotificationPreferences();
      expect(h.saves, hasLength(1));
      expect(h.repo.pendingNotificationPreferences?.paymentReminders, isFalse);
      await h.repo.updateNotificationPreferences(
        h.repo.pendingNotificationPreferences!,
      );
      expect(_body(h.saves.last)['p_expected_revision'], 5);
      expect(h.repo.notificationPreferencesRevision, 6);
    },
  );

  for (final direction in ['other user', 'same user new session', 'A-B-A']) {
    for (final operation in ['read', 'save']) {
      test(
        '$operation rejects late $direction reply using captured bearer',
        () async {
          final h = await _Harness.create();
          await h.repo.refreshNotificationPreferences();
          final barrier = _Barrier();
          final name = operation == 'read'
              ? 'get_notification_preferences_v2'
              : 'set_notification_preferences_v2';
          h.respond = (r) => _rpc(r, name) ? barrier.hold() : _fallback(r);
          final bearer = h.client.auth.currentSession!.accessToken;
          final assertion = expectLater(
            operation == 'read'
                ? h.repo.refreshNotificationPreferences()
                : h.repo.updateNotificationPreferences(_edit),
            throwsStateError,
          );
          await barrier.entered.future;
          await h.login(direction == 'same user new session' ? _a : _b, _s2);
          if (direction == 'A-B-A') await h.login(_a, _s1, nonce: 2);
          barrier.reply.complete(_json(operation == 'read' ? _read() : _ack()));
          await assertion;
          expect(
            h.requests
                .where((r) => _rpc(r, name))
                .last
                .headers['Authorization'],
            'Bearer $bearer',
          );
          expect(h.repo.notificationPreferencesRevision, isNull);
          expect(h.repo.pendingNotificationPreferences, isNull);
          expect(h.repo.state.notificationPreferences.paymentReminders, isTrue);
        },
      );
    }
  }

  test(
    'same-session token refresh permits ACK but pins original authorization',
    () async {
      final h = await _Harness.create();
      await h.repo.refreshNotificationPreferences();
      final barrier = _Barrier();
      h.respond = (r) => _rpc(r, 'set_notification_preferences_v2')
          ? barrier.hold()
          : _fallback(r);
      final bearer = h.client.auth.currentSession!.accessToken;
      final save = h.repo.updateNotificationPreferences(_edit);
      await barrier.entered.future;
      await h.login(_a, _s1, nonce: 2);
      barrier.reply.complete(_json(_ack()));
      await save;
      expect(h.saves.single.headers['Authorization'], 'Bearer $bearer');
      expect(h.repo.notificationPreferencesRevision, 2);
    },
  );

  test(
    'late full live reload cannot undo a newer acknowledged write',
    () async {
      final h = await _Harness.create();
      await h.repo.refreshNotificationPreferences();
      final barrier = _Barrier();
      h.respond = (r) => _rpc(r, 'get_notification_preferences_v2')
          ? barrier.hold()
          : _fallback(r);
      final reload = h.repo.reloadFull();
      await barrier.entered.future;
      await h.repo.updateNotificationPreferences(_edit);
      barrier.reply.complete(_json(_read()));
      await reload;
      expect(h.repo.notificationPreferencesRevision, 2);
      expect(h.repo.state.notificationPreferences.paymentReminders, isFalse);
      expect(h.repo.state.lastError, isNull);
    },
  );

  test(
    'a reload begun during pending write cannot overwrite its later ACK',
    () async {
      final h = await _Harness.create();
      await h.repo.refreshNotificationPreferences();
      final write = _Barrier(), read = _Barrier();
      h.respond = (r) => _rpc(r, 'set_notification_preferences_v2')
          ? write.hold()
          : _rpc(r, 'get_notification_preferences_v2')
          ? read.hold()
          : _fallback(r);
      final save = h.repo.updateNotificationPreferences(_edit);
      await write.entered.future;
      final reload = h.repo.reloadFull();
      await read.entered.future;
      write.reply.complete(_json(_ack()));
      await save;
      read.reply.complete(_json(_read()));
      await reload;
      expect(h.repo.notificationPreferencesRevision, 2);
      expect(h.repo.state.notificationPreferences.paymentReminders, isFalse);
    },
  );

  test(
    'background reload after conflict cannot authorize a hidden rebase',
    () async {
      final h = await _Harness.create();
      await h.repo.refreshNotificationPreferences();
      h.respond = (r) => _rpc(r, 'set_notification_preferences_v2')
          ? _json({'code': '40001', 'message': 'runtime_control_conflict'}, 409)
          : _fallback(r);
      await expectLater(
        h.repo.updateNotificationPreferences(_edit),
        throwsA(isA<PostgrestException>()),
      );
      h.respond = (r) => _rpc(r, 'get_notification_preferences_v2')
          ? _json({..._read(revision: 5), 'preferences': _newer.toJson()})
          : _fallback(r);
      await h.repo.reloadFull();
      expect(h.repo.notificationPreferencesRevision, isNull);
      expect(h.repo.state.notificationPreferences.groupUpdates, isTrue);
      expect(h.repo.pendingNotificationPreferences?.paymentReminders, isFalse);
      await expectLater(
        h.repo.updateNotificationPreferences(_edit),
        throwsStateError,
      );
      expect(h.saves, hasLength(1));
    },
  );

  test(
    'old-session read error is replaced before private error text can escape',
    () async {
      final h = await _Harness.create();
      final read = _Barrier();
      h.respond = (r) => _rpc(r, 'get_notification_preferences_v2')
          ? read.hold()
          : _fallback(r);
      final result = expectLater(
        h.repo.refreshNotificationPreferences(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            isNot(contains('private error')),
          ),
        ),
      );
      await read.entered.future;
      await h.login(_b, _s2);
      read.reply.complete(
        _json({
          'code': '42501',
          'message': 'private error from old session',
        }, 403),
      );
      await result;
      expect(h.repo.notificationPreferencesRevision, isNull);
    },
  );

  test(
    'pending save refuses refresh/second dispatch and keeps newer dirty intent',
    () async {
      final h = await _Harness.create();
      await h.repo.refreshNotificationPreferences();
      final barrier = _Barrier();
      h.respond = (r) => _rpc(r, 'set_notification_preferences_v2')
          ? barrier.hold()
          : _fallback(r);
      final save = h.repo.updateNotificationPreferences(_edit);
      await barrier.entered.future;
      await expectLater(
        h.repo.refreshNotificationPreferences(),
        throwsStateError,
      );
      await expectLater(
        h.repo.updateNotificationPreferences(_newer),
        throwsStateError,
      );
      expect(
        () => h.repo.discardPendingNotificationPreferences(),
        throwsStateError,
      );
      expect(h.repo.pendingNotificationPreferences?.groupUpdates, isFalse);
      barrier.reply.complete(_json(_ack()));
      await save;
      expect(h.saves, hasLength(1));
      expect(h.repo.state.notificationPreferences.paymentReminders, isFalse);
      expect(h.repo.pendingNotificationPreferences?.groupUpdates, isFalse);
      expect(h.repo.notificationPreferencesRevision, 2);
    },
  );

  test(
    'older explicit refresh cannot replace a newer explicit refresh',
    () async {
      final h = await _Harness.create();
      final barrier = _Barrier();
      h.respond = (r) => _rpc(r, 'get_notification_preferences_v2')
          ? barrier.hold()
          : _fallback(r);
      final old = expectLater(
        h.repo.refreshNotificationPreferences(),
        throwsStateError,
      );
      await barrier.entered.future;
      h.respond = (r) => _rpc(r, 'get_notification_preferences_v2')
          ? _json(_read(revision: 4))
          : _fallback(r);
      await h.repo.refreshNotificationPreferences();
      barrier.reply.complete(_json(_read()));
      await old;
      expect(h.repo.notificationPreferencesRevision, 4);
    },
  );
}

typedef _Respond = FutureOr<http.Response> Function(http.Request);

class _Harness {
  _Harness(this.client, this.repo, this.requests, this.respond);
  final SupabaseClient client;
  final _Repository repo;
  final List<http.Request> requests;
  _Respond respond;
  Iterable<http.Request> get saves =>
      requests.where((r) => _rpc(r, 'set_notification_preferences_v2'));
  static Future<_Harness> create({_Respond? respond}) async {
    late _Harness harness;
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        http.Response result;
        if (r.url.path.endsWith('/verify')) {
          final parts = (_body(r)['token'] as String).split('|');
          result = _json(_auth(parts[0], parts[1], parts[2]));
        } else {
          requests.add(r);
          result = await harness.respond(r);
        }
        return http.Response.bytes(
          result.bodyBytes,
          result.statusCode,
          headers: result.headers,
          request: r,
        );
      }),
    );
    await client.auth.verifyOTP(
      phone: '+250788972001',
      token: '$_a|$_s1|0',
      type: OtpType.sms,
    );
    final repo = _Repository(client);
    harness = _Harness(client, repo, requests, respond ?? _fallback);
    addTearDown(() async {
      repo.dispose();
      await client.dispose();
    });
    return harness;
  }

  Future<void> login(String user, String session, {int nonce = 0}) async {
    await client.auth.verifyOTP(
      phone: '+250788972001',
      token: '$user|$session|$nonce',
      type: OtpType.sms,
    );
    // Allow the real Auth stream and repository reload generation to settle.
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(repo.state.currentProfile?.id, user);
  }
}

Map<String, dynamic> _auth(String user, String session, String nonce) => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'session_id': session, 'nonce': nonce, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
  'refresh_token': 'synthetic-refresh',
  'token_type': 'bearer',
  'user': {
    'id': user,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-09-30T00:00:00Z',
  },
};
CollectProfile _profile(String user) => CollectProfile(
  id: user,
  publicId: '997201',
  whatsappPhone: '+250788972001',
  countryCode: 'RW',
  currencyCode: 'RWF',
);

class _Repository extends CollectRepository {
  _Repository(this.client)
    : super.fixture(
        initialState: CollectState(
          currentProfile: _profile(_a),
          collections: const [],
          paymentIntents: const [],
          contributions: const [],
        ),
        supabase: client,
        smsAccessChannel: _Sms(),
        offlineCache: _Cache(),
      );
  final SupabaseClient client;
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    state = state.copyWith(
      currentProfile: _profile(client.auth.currentUser!.id),
    );
  }

  Future<void> reloadFull() => super.loadInitial();
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

class _Barrier {
  final entered = Completer<void>();
  final reply = Completer<http.Response>();
  Future<http.Response> hold() {
    entered.complete();
    return reply.future;
  }
}

http.Response _fallback(http.Request r) {
  if (_rpc(r, 'get_notification_preferences_v2')) return _json(_read());
  if (_rpc(r, 'set_notification_preferences_v2')) return _json(_ack());
  if (_rpc(r, 'get_current_member_profile')) {
    return _json({
      'id': _a,
      'public_id': '997201',
      'whatsapp_phone': '+250788972001',
      'country_code': 'RW',
      'currency_code': 'RWF',
    });
  }
  if (_rpc(r, 'list_current_member_recent_intents')) {
    return _json({'items': [], 'pending_count': 0});
  }
  if (_rpc(r, 'list_current_member_history_page')) {
    return _json({
      'items': [],
      'total_count': 0,
      'totals': {},
      'own_totals': {},
      'own_collection_ids': [],
      'revision': '00000000000000000000000000000000',
      'next_cursor': null,
    });
  }
  if (_rpc(r, 'list_current_user_collections') ||
      _rpc(r, 'list_current_member_collection_balances') ||
      _rpc(r, 'notification_events')) {
    return _json([]);
  }
  throw StateError('Unexpected local HTTP fixture path: ${r.url.path}');
}
