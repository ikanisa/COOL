import 'dart:async';
import 'dart:convert';

import 'package:collect_app/core/cloudflare/collect_cloudflare_client.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/repositories/payment_help_pending_store.dart';
import 'package:collect_app/shared/repositories/payment_help_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _actor = '10000000-0000-0000-0000-000000000001';
const _other = '10000000-0000-0000-0000-000000000002';
const _firstSession = '20000000-0000-0000-0000-000000000001';
const _nextSession = '20000000-0000-0000-0000-000000000002';

String _token(String user, String session, {int serial = 0}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'role': 'authenticated', 'sub': user, 'session_id': session, 'exp': 4102444800, 'iat': 1700000000 + serial})}.synthetic';
}

String _session(String user, String session, {int serial = 0}) => jsonEncode({
  'access_token': _token(user, session, serial: serial),
  'refresh_token': 'synthetic-$session',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': user,
    'aud': 'authenticated',
    'app_metadata': {},
    'user_metadata': {},
  },
});

CollectProfile _profile({
  String user = _actor,
  String code = '111111',
  String number = '0788123456',
}) => CollectProfile(
  id: user,
  publicId: '123456',
  whatsappPhone: '+250788123456',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'mtn_momo',
  momoNumber: number,
  momoPayCode: code,
);

CollectState _state({
  String user = _actor,
  String code = '111111',
  String number = '0788123456',
}) => CollectState(
  currentProfile: _profile(user: user, code: code, number: number),
  collections: const [],
  paymentIntents: const [],
  contributions: const [],
  smsAccessEnabled: true,
);

Map<String, dynamic> _row({
  String code = '008000',
  String number = '0788123456',
}) => {
  'id': _actor,
  'public_id': '123456',
  'whatsapp_phone': '+250788123456',
  'country_code': 'RW',
  'currency_code': 'RWF',
  'momo_provider': 'mtn_momo',
  'momo_number': number,
  'momo_pay_code': code,
};

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

class _Cache extends CollectOfflineCache {
  int saves = 0, clears = 0;
  CollectOfflineSnapshot? last;
  Completer<void>? nextSaveEntered, nextSaveRelease;
  @override
  Future<void> save(CollectOfflineSnapshot snapshot) async {
    saves++;
    last = snapshot;
    final release = nextSaveRelease;
    if (release != null) {
      nextSaveRelease = null;
      final entered = nextSaveEntered;
      if (entered != null && !entered.isCompleted) entered.complete();
      await release.future;
    }
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

class _Sms extends SmsAccessChannel {
  int disables = 0;
  int enables = 0;
  Completer<void>? stopStarted, stopRelease;

  @override
  Future<bool> suspendUnlessOwner(String? currentUserId) async => true;

  @override
  Future<bool> setEnabled(bool enabled, {String? ownerUserId}) async {
    if (enabled) enables++;
    if (!enabled) {
      disables++;
      if (stopStarted case final started?) {
        if (!started.isCompleted) started.complete();
      }
      if (stopRelease case final release?) await release.future;
    }
    return true;
  }
}

class _HelpStorage implements PaymentHelpProtectedStorage {
  @override
  Future<T> exclusive<T>(Future<T> Function() action) => action();
  @override
  Future<String?> read(String ownerId) async => null;
  @override
  Future<void> write(String ownerId, String value) async {}
  @override
  Future<void> clear(String ownerId) async {}
}

class _Repository extends CollectRepository {
  _Repository(
    this.client,
    _Sms sms,
    _Cache cache, {
    String code = '111111',
    String number = '0788123456',
  }) : super.fixture(
         initialState: _state(code: code, number: number),
         backend: client,
         smsAccessChannel: sms,
         offlineCache: cache,
         paymentHelpPendingStore: PaymentHelpPendingStore(
           storage: _HelpStorage(),
         ),
       );

  final CollectCloudflareClient client;
  Completer<void>? nextLoad;

  void setSmsChoice(bool enabled) {
    state = state.copyWith(smsAccessEnabled: enabled);
  }

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {
    final signal = nextLoad;
    if (signal == null) return;
    final user = client.auth.currentUser?.id;
    if (user != null) state = _state(user: user);
    nextLoad = null;
    if (!signal.isCompleted) signal.complete();
  }
}

typedef _Handler = FutureOr<http.Response> Function(http.Request request);

class _Harness {
  _Harness(this.client, this.repo, this.sms, this.cache, this.requests);
  final CollectCloudflareClient client;
  final _Repository repo;
  final _Sms sms;
  final _Cache cache;
  final List<http.Request> requests;

  static Future<_Harness> create(
    _Handler handler, {
    String code = '111111',
    String number = '0788123456',
  }) async {
    final requests = <http.Request>[];
    final client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await handler(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await client.auth.recoverSession(_session(_actor, _firstSession));
    final sms = _Sms();
    final cache = _Cache();
    final repo = _Repository(client, sms, cache, code: code, number: number);
    addTearDown(() async {
      if (sms.stopRelease case final release?) {
        if (!release.isCompleted) release.complete();
      }
      repo.dispose();
      await client.dispose();
    });
    return _Harness(client, repo, sms, cache, requests);
  }

  Future<void> login(String user, String session) async {
    final loaded = Completer<void>();
    repo.nextLoad = loaded;
    await client.auth.recoverSession(_session(user, session));
    await loaded.future.timeout(const Duration(seconds: 3));
  }

  Future<CollectProfile> save({
    String number = '0788123456',
    String code = '008000',
  }) => repo.updateCurrentProfile(
    countryCode: 'RW',
    momoProvider: 'mtn_momo',
    momoNumber: number,
    momoPayCode: code,
  );
}

class _LiveLoadHarness {
  final sms = _Sms();
  final cache = _Cache();
  final oldMemberEntered = Completer<void>();
  final oldMemberReply = Completer<http.Response>();
  final freshPublished = Completer<void>();
  final denialReadEntered = Completer<void>();
  final denialReadReply = Completer<http.Response>();
  final heldProfileEntered = Completer<void>();
  final heldProfileReply = Completer<http.Response>();
  final requests = <http.Request>[];
  late final CollectCloudflareClient client;
  late final CollectRepository repo;
  int memberReads = 0;
  int profileReads = 0;
  int? heldProfileReadNumber;
  String serverCode = '111111';
  bool holdDenialRead = false;

  Future<void> start() async {
    client = CollectCloudflareClient(
      'http://127.0.0.1:1',
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        Object? value;
        if (path.endsWith('/get_current_member_profile')) {
          profileReads++;
          if (holdDenialRead) {
            holdDenialRead = false;
            denialReadEntered.complete();
            return denialReadReply.future;
          }
          if (profileReads == heldProfileReadNumber) {
            heldProfileEntered.complete();
            return heldProfileReply.future;
          }
          value = _row(code: serverCode);
        } else if (path.endsWith('/update_current_member_profile')) {
          serverCode =
              (jsonDecode(request.body) as Map)['p_momo_pay_code'] as String;
          value = null;
        } else if (path.endsWith('/list_current_user_collections')) {
          memberReads++;
          if (memberReads == 1) {
            oldMemberEntered.complete();
            return oldMemberReply.future;
          }
          value = [];
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
          value = [];
        } else if (path.endsWith('/get_notification_preferences_v2')) {
          value = {
            'contract_version': 2,
            'ok': true,
            'user_id': _actor,
            'revision': 0,
            'exists': false,
            'preferences': NotificationPreferences.defaults.toJson(),
          };
        } else if (path.endsWith('/query/notification-events')) {
          value = [];
        } else if (path.endsWith('/query/public-collections')) {
          if (!freshPublished.isCompleted) freshPublished.complete();
          value = [];
        } else if (path.endsWith('/v1/sync')) {
          value = {'events': [], 'cursor': '0'};
        } else {
          throw StateError('Unexpected synthetic route: $path');
        }
        return _json(value);
      }),
    );
    await client.auth.recoverSession(_session(_actor, _firstSession));
    repo = CollectRepository.fixture(
      initialState: _state(),
      backend: client,
      smsAccessChannel: sms,
      offlineCache: cache,
      paymentHelpPendingStore: PaymentHelpPendingStore(storage: _HelpStorage()),
    );
    addTearDown(() async {
      if (!oldMemberReply.isCompleted) oldMemberReply.complete(_json([]));
      if (!denialReadReply.isCompleted) {
        denialReadReply.complete(_json(_row(code: serverCode)));
      }
      if (!heldProfileReply.isCompleted) {
        heldProfileReply.complete(_json(_row(code: serverCode)));
      }
      repo.dispose();
      await client.dispose();
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final number in [
    '0788123456',
    '+250 788 123 456',
    '00250 788 123 456',
  ]) {
    test(
      'null mutation ACK reads and publishes the same verified phone: $number',
      () async {
        final h = await _Harness.create((request) {
          final operation = request.url.path.split('/').last;
          if (operation == 'update_current_member_profile') return _json(null);
          if (operation == 'get_current_member_profile') {
            return _json(_row(number: number));
          }
          throw StateError('Unexpected synthetic route');
        });
        final updated = await h.save();
        expect(h.requests.map((r) => r.url.path.split('/').last), [
          'update_current_member_profile',
          'get_current_member_profile',
        ]);
        for (final request in h.requests) {
          expect(
            request.headers['Authorization'],
            'Bearer ${_token(_actor, _firstSession)}',
          );
        }
        expect(jsonDecode(h.requests.first.body), {
          'p_country_code': 'RW',
          'p_momo_provider': 'mtn_momo',
          'p_momo_number': '0788123456',
          'p_momo_pay_code': '008000',
        });
        expect(updated.id, _actor);
        expect(updated.momoNumber, '0788123456');
        expect(updated.momoPayCode, '008000');
        expect(h.repo.state.currentProfile?.momoPayCode, '008000');
        expect(h.repo.state.smsAccessEnabled, isTrue);
        expect(h.sms.disables, 0);
        expect(h.cache.saves, 1);
      },
    );
  }

  test(
    'compatible map ACK needs no readback and preserves an omitted unchanged empty code',
    () async {
      final h = await _Harness.create((request) {
        expect(request.url.path, endsWith('/update_current_member_profile'));
        return _json(_row(code: '')..remove('momo_pay_code'));
      }, code: '');
      final updated = await h.save(code: '');
      expect(updated.momoPayCode, isEmpty);
      expect(h.requests, hasLength(1));
      expect(h.repo.state.smsAccessEnabled, isTrue);
      expect(h.sms.disables, 0);
    },
  );

  test('compatible map ACK validates changed code without readback', () async {
    final h = await _Harness.create((_) => _json(_row()));
    final updated = await h.save();
    expect(updated.momoPayCode, '008000');
    expect(h.requests, hasLength(1));
    expect(h.sms.disables, 0);
  });

  test('compatible map ACK may omit an unchanged currency', () async {
    final h = await _Harness.create(
      (_) => _json(_row()..remove('currency_code')),
    );
    final updated = await h.save();
    expect(updated.currencyCode, 'RWF');
    expect(h.requests, hasLength(1));
  });

  for (final original in ['+250788123456', '00250788123456']) {
    test(
      'same phone stored as $original does not disable member SMS',
      () async {
        final h = await _Harness.create((request) {
          if (request.url.path.endsWith('/update_current_member_profile')) {
            return _json(null);
          }
          return _json(_row());
        }, number: original);
        final updated = await h.save();
        expect(updated.momoNumber, '0788123456');
        expect(h.repo.state.smsAccessEnabled, isTrue);
        expect(h.sms.disables, 0);
      },
    );
  }

  for (final enabled in [true, false]) {
    test('changed MoMo number preserves SMS choice $enabled', () async {
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          return _json(null);
        }
        if (request.url.path.endsWith('/get_current_member_profile')) {
          return _json(_row(number: '0788999000'));
        }
        throw StateError('Unexpected request');
      }, number: '0788111222');
      h.repo.setSmsChoice(enabled);
      final updated = await h.save(number: '0788999000');
      expect(updated.momoNumber, '0788999000');
      expect(h.repo.state.smsAccessEnabled, enabled);
      expect(h.sms.enables, 0);
      expect(h.sms.disables, 0);
      expect(h.requests.map((r) => r.url.path.split('/').last), [
        'update_current_member_profile',
        'get_current_member_profile',
      ]);
    });
  }

  test('withdrawal during a held profile save stays withdrawn', () async {
    final entered = Completer<void>();
    final reply = Completer<http.Response>();
    addTearDown(() {
      if (!reply.isCompleted) reply.complete(_json(null));
    });
    final h = await _Harness.create((request) {
      if (request.url.path.endsWith('/update_current_member_profile')) {
        entered.complete();
        return reply.future;
      }
      if (request.url.path.endsWith('/record_sms_access_consent')) {
        return _json(null);
      }
      if (request.url.path.endsWith('/get_current_member_profile')) {
        return _json(_row(number: '0788999000'));
      }
      throw StateError('Unexpected request');
    }, number: '0788111222');
    final saving = h.save(number: '0788999000');
    await entered.future.timeout(const Duration(seconds: 3));
    await h.repo.setSmsAccess(false);
    reply.complete(_json(null));
    final updated = await saving;
    expect(updated.momoNumber, '0788999000');
    expect(h.repo.state.smsAccessEnabled, isFalse);
    expect(h.sms.enables, 0);
    expect(h.sms.disables, 1);
    final consent = h.requests.singleWhere(
      (r) => r.url.path.endsWith('/record_sms_access_consent'),
    );
    expect(jsonDecode(consent.body), {
      'enabled': false,
      'build_channel': 'android_sms_access',
      'device_label': 'flutter_app',
    });
  });

  test('withdrawal during a held profile readback stays withdrawn', () async {
    final entered = Completer<void>();
    final reply = Completer<http.Response>();
    addTearDown(() {
      if (!reply.isCompleted) reply.complete(_json(_row(number: '0788999000')));
    });
    final h = await _Harness.create((request) {
      if (request.url.path.endsWith('/update_current_member_profile')) {
        return _json(null);
      }
      if (request.url.path.endsWith('/record_sms_access_consent')) {
        return _json(null);
      }
      if (request.url.path.endsWith('/get_current_member_profile')) {
        entered.complete();
        return reply.future;
      }
      throw StateError('Unexpected request');
    }, number: '0788111222');
    final saving = h.save(number: '0788999000');
    await entered.future.timeout(const Duration(seconds: 3));
    await h.repo.setSmsAccess(false);
    reply.complete(_json(_row(number: '0788999000')));
    await saving;
    expect(h.repo.state.smsAccessEnabled, isFalse);
    expect(h.sms.enables, 0);
    expect(h.sms.disables, 1);
    final consent = h.requests.singleWhere(
      (r) => r.url.path.endsWith('/record_sms_access_consent'),
    );
    expect(jsonDecode(consent.body)['enabled'], isFalse);
  });

  test('map ACK with mismatched requested fields is refused', () async {
    final h = await _Harness.create(
      (_) => _json(_row()..['momo_pay_code'] = '999999'),
    );
    await expectLater(h.save(), throwsFormatException);
    expect(h.requests, hasLength(1));
    expect(h.repo.state.currentProfile?.momoPayCode, '111111');
    expect(h.cache.saves, 0);
  });

  test('null ACK accepts an explicitly null stored empty code', () async {
    final h = await _Harness.create((request) {
      if (request.url.path.endsWith('/update_current_member_profile')) {
        return _json(null);
      }
      return _json(_row()..['momo_pay_code'] = null);
    });
    final updated = await h.save(code: '');
    expect(updated.momoPayCode, isEmpty);
    expect(h.requests, hasLength(2));
    expect(h.repo.state.currentProfile?.momoPayCode, isEmpty);
    expect(h.sms.disables, 0);
  });

  final invalidRows = <String, Map<String, dynamic> Function()>{
    'wrong owner': () => _row()..['id'] = _other,
    'wrong public ID': () => _row()..['public_id'] = '654321',
    'wrong verified phone': () => _row()..['whatsapp_phone'] = '+250788000000',
    'missing country': () => _row()..remove('country_code'),
    'wrong country': () => _row()..['country_code'] = 'XX',
    'missing currency': () => _row()..remove('currency_code'),
    'null currency': () => _row()..['currency_code'] = null,
    'wrong currency': () => _row()..['currency_code'] = 'USD',
    'missing provider': () => _row()..remove('momo_provider'),
    'wrong provider': () => _row()..['momo_provider'] = 'airtel_money',
    'missing number': () => _row()..remove('momo_number'),
    'null number': () => _row()..['momo_number'] = null,
    'wrong number': () => _row()..['momo_number'] = '0788000000',
    'invalid number text': () => _row()..['momo_number'] = 'bad0788123456',
    'missing code': () => _row()..remove('momo_pay_code'),
    'wrong code': () => _row()..['momo_pay_code'] = '999999',
    'non-string code': () => _row()..['momo_pay_code'] = 8000,
  };
  for (final entry in invalidRows.entries) {
    test('null ACK rejects ${entry.key} in authoritative readback', () async {
      final h = await _Harness.create(
        (request) => _json(
          request.url.path.endsWith('/update_current_member_profile')
              ? null
              : entry.value(),
        ),
      );
      await expectLater(h.save(), throwsFormatException);
      expect(h.requests.map((r) => r.url.path.split('/').last), [
        'update_current_member_profile',
        'get_current_member_profile',
      ]);
      expect(h.repo.state.currentProfile?.momoPayCode, '111111');
      expect(h.repo.state.smsAccessEnabled, isTrue);
      expect(h.sms.disables, 0);
      expect(h.cache.saves, 0);
    });
  }

  test(
    'map ACK cannot infer a cleared nonempty code from an omitted field',
    () async {
      final h = await _Harness.create(
        (_) => _json(_row(code: '')..remove('momo_pay_code')),
      );
      await expectLater(h.save(code: ''), throwsFormatException);
      expect(h.requests, hasLength(1));
      expect(h.repo.state.currentProfile?.momoPayCode, '111111');
      expect(h.cache.saves, 0);
    },
  );

  test(
    'uncertain mutation does not issue readback or repeat the write',
    () async {
      final h = await _Harness.create(
        (_) => throw http.ClientException('synthetic lost ACK'),
      );
      await expectLater(h.save(), throwsA(isA<Exception>()));
      expect(h.requests, hasLength(1));
      expect(
        h.requests.single.url.path,
        endsWith('/update_current_member_profile'),
      );
      expect(h.repo.state.currentProfile?.momoPayCode, '111111');
      expect(h.repo.state.smsAccessEnabled, isTrue);
      expect(h.sms.disables, 0);
      expect(h.cache.saves, 0);
    },
  );

  test(
    'failed readback after a null ACK does not repeat the mutation',
    () async {
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          return _json(null);
        }
        throw http.ClientException('synthetic readback unavailable');
      });
      await expectLater(h.save(), throwsA(isA<Exception>()));
      expect(h.requests.map((r) => r.url.path.split('/').last), [
        'update_current_member_profile',
        'get_current_member_profile',
      ]);
      expect(h.repo.state.currentProfile?.momoPayCode, '111111');
      expect(h.cache.saves, 0);
    },
  );

  test('non-null non-map ACK is refused without readback', () async {
    final h = await _Harness.create((_) => _json('not an acknowledgement'));
    await expectLater(h.save(), throwsStateError);
    expect(h.requests, hasLength(1));
    expect(h.repo.state.currentProfile?.momoPayCode, '111111');
    expect(h.cache.saves, 0);
  });

  for (final status in [202, 204]) {
    test('$status empty acknowledgement is refused before readback', () async {
      final h = await _Harness.create((_) => http.Response('', status));
      await expectLater(h.save(), throwsStateError);
      expect(h.requests, hasLength(1));
      expect(
        h.requests.single.url.path,
        endsWith('/update_current_member_profile'),
      );
      expect(h.repo.state.currentProfile?.momoPayCode, '111111');
      expect(h.cache.saves, 0);
    });
  }

  test(
    'HTTP 200 empty body is confirmed only by matching current values',
    () async {
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          return http.Response('', 200);
        }
        return _json(_row());
      });
      final updated = await h.save();
      expect(updated.momoPayCode, '008000');
      expect(h.requests.map((r) => r.url.path.split('/').last), [
        'update_current_member_profile',
        'get_current_member_profile',
      ]);
    },
  );

  test(
    'non-success response retains the normal API error and no readback',
    () async {
      final h = await _Harness.create(
        (_) => _json({'code': 'permission_denied'}, 403),
      );
      await expectLater(
        h.save(),
        throwsA(
          isA<CollectApiException>().having(
            (error) => error.code,
            'code',
            'permission_denied',
          ),
        ),
      );
      expect(h.requests, hasLength(1));
      expect(h.cache.saves, 0);
    },
  );

  test(
    'a late null ACK after a session change does not start readback',
    () async {
      final entered = Completer<void>();
      final reply = Completer<http.Response>();
      final h = await _Harness.create((request) {
        expect(request.url.path, endsWith('/update_current_member_profile'));
        entered.complete();
        return reply.future;
      });
      final pending = h.save();
      final failure = expectLater(pending, throwsStateError);
      await entered.future.timeout(const Duration(seconds: 3));
      await h.login(_actor, _nextSession);
      reply.complete(_json(null));
      await failure;
      expect(h.requests, hasLength(1));
      expect(
        h.requests.single.headers['Authorization'],
        'Bearer ${_token(_actor, _firstSession)}',
      );
      expect(h.repo.state.currentProfile?.momoPayCode, '111111');
      expect(h.cache.saves, 0);
    },
  );

  test(
    'overlapping same-session saves refuse the second write until the first completes',
    () async {
      final entered = Completer<void>();
      final firstReply = Completer<http.Response>();
      var code = '';
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          code = (jsonDecode(request.body) as Map)['p_momo_pay_code'] as String;
          return _json(null);
        }
        if (request.url.path.endsWith('/get_current_member_profile')) {
          if (code == '008000') {
            entered.complete();
            return firstReply.future;
          }
          return _json(_row(code: code));
        }
        throw StateError('Unexpected synthetic route');
      });
      final first = h.save();
      await entered.future.timeout(const Duration(seconds: 3));
      await expectLater(
        h.save(code: '009999'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('current profile update'),
          ),
        ),
      );
      expect(h.requests, hasLength(2));
      firstReply.complete(_json(_row()));
      await first;
      final second = await h.save(code: '009999');
      expect(second.momoPayCode, '009999');
      expect(h.repo.state.currentProfile?.momoPayCode, '009999');
      expect(h.requests.map((r) => r.url.path.split('/').last), [
        'update_current_member_profile',
        'get_current_member_profile',
        'update_current_member_profile',
        'get_current_member_profile',
      ]);
    },
  );

  test(
    'a replacement account can save while an earlier account readback is held',
    () async {
      final entered = Completer<void>();
      final oldReply = Completer<http.Response>();
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          return _json(null);
        }
        if (request.url.path.endsWith('/get_current_member_profile')) {
          if (request.headers['Authorization'] ==
              'Bearer ${_token(_actor, _firstSession)}') {
            entered.complete();
            return oldReply.future;
          }
          return _json(_row(code: '009999')..['id'] = _other);
        }
        throw StateError('Unexpected synthetic route');
      });
      final first = h.save();
      final oldFailure = expectLater(first, throwsStateError);
      await entered.future.timeout(const Duration(seconds: 3));
      await h.login(_other, _nextSession);
      final next = await h.save(code: '009999');
      expect(next.id, _other);
      expect(next.momoPayCode, '009999');
      oldReply.complete(_json(_row()));
      await oldFailure;
      expect(h.repo.state.currentProfile?.id, _other);
      expect(h.repo.state.currentProfile?.momoPayCode, '009999');
      expect(h.requests, hasLength(4));
    },
  );

  test('same-session signed-in reinstall fences an older readback', () async {
    final entered = Completer<void>();
    final reply = Completer<http.Response>();
    final h = await _Harness.create((request) {
      if (request.url.path.endsWith('/update_current_member_profile')) {
        return _json(null);
      }
      if (request.url.path.endsWith('/get_current_member_profile')) {
        entered.complete();
        return reply.future;
      }
      throw StateError('Unexpected synthetic route');
    });
    final pending = h.save();
    final failure = expectLater(pending, throwsStateError);
    await entered.future.timeout(const Duration(seconds: 3));
    await h.client.auth.recoverSession(_session(_actor, _firstSession));
    reply.complete(_json(_row()));
    await failure;
    expect(h.repo.state.currentProfile?.momoPayCode, '111111');
    expect(h.cache.saves, 0);
  });

  test(
    'same-session token refresh permits the original captured-bearer readback',
    () async {
      final entered = Completer<void>();
      final reply = Completer<http.Response>();
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          return _json(null);
        }
        if (request.url.path.endsWith('/get_current_member_profile')) {
          entered.complete();
          return reply.future;
        }
        if (request.url.path.endsWith('/auth/refresh')) {
          return _json(jsonDecode(_session(_actor, _firstSession, serial: 1)));
        }
        throw StateError('Unexpected synthetic route');
      });
      final pending = h.save();
      await entered.future.timeout(const Duration(seconds: 3));
      await h.client.auth.refreshSession();
      expect(
        h.client.auth.currentSession?.accessToken,
        _token(_actor, _firstSession, serial: 1),
      );
      reply.complete(_json(_row()));
      expect((await pending).momoPayCode, '008000');
      final readback = h.requests.singleWhere(
        (r) => r.url.path.endsWith('/get_current_member_profile'),
      );
      expect(
        readback.headers['Authorization'],
        'Bearer ${_token(_actor, _firstSession)}',
      );
    },
  );

  for (final transition in [
    'same-user new-session',
    'A to B to A',
    'sign-out',
  ]) {
    test('held readback cannot publish after $transition', () async {
      final entered = Completer<void>();
      final reply = Completer<http.Response>();
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          return _json(null);
        }
        if (request.url.path.endsWith('/get_current_member_profile')) {
          entered.complete();
          return reply.future;
        }
        throw StateError('Unexpected synthetic route');
      });
      final pending = h.save();
      final failure = expectLater(pending, throwsStateError);
      await entered.future.timeout(const Duration(seconds: 3));
      if (transition == 'same-user new-session') {
        await h.login(_actor, _nextSession);
      } else if (transition == 'A to B to A') {
        await h.login(_other, _nextSession);
        await h.login(_actor, _firstSession);
      } else {
        await h.client.auth.clearLocalSession();
      }
      reply.complete(_json(_row()));
      await failure;
      expect(h.requests, hasLength(2));
      for (final request in h.requests) {
        expect(
          request.headers['Authorization'],
          'Bearer ${_token(_actor, _firstSession)}',
        );
      }
      expect(
        h.repo.state.currentProfile?.momoPayCode,
        transition == 'sign-out' ? null : '111111',
      );
      expect(h.cache.saves, 0);
    });
  }

  test(
    'sign-out start fences a readback before native stop completes',
    () async {
      final entered = Completer<void>();
      final reply = Completer<http.Response>();
      final h = await _Harness.create((request) {
        if (request.url.path.endsWith('/update_current_member_profile')) {
          return _json(null);
        }
        if (request.url.path.endsWith('/get_current_member_profile')) {
          entered.complete();
          return reply.future;
        }
        return _json({});
      });
      h.sms.stopStarted = Completer<void>();
      h.sms.stopRelease = Completer<void>();
      final pending = h.save();
      final failure = expectLater(pending, throwsStateError);
      await entered.future.timeout(const Duration(seconds: 3));
      final signingOut = h.repo.signOut();
      await h.sms.stopStarted!.future.timeout(const Duration(seconds: 3));
      reply.complete(_json(_row()));
      await failure;
      expect(h.repo.state.currentProfile?.momoPayCode, '111111');
      expect(h.cache.saves, 0);
      h.sms.stopRelease!.complete();
      await signingOut;
    },
  );

  test(
    'a stalled older member load cannot overwrite a confirmed profile save',
    () async {
      final h = _LiveLoadHarness();
      await h.start();
      final oldLoad = h.repo.loadInitial();
      await h.oldMemberEntered.future.timeout(const Duration(seconds: 3));
      await h.repo.updateCurrentProfile(
        countryCode: 'RW',
        momoProvider: 'mtn_momo',
        momoNumber: '0788123456',
        momoPayCode: '008000',
      );
      await h.freshPublished.future.timeout(const Duration(seconds: 3));
      expect(h.repo.state.currentProfile?.momoPayCode, '008000');
      expect(h.repo.state.isLoading, isFalse);
      expect(h.cache.last?.currentProfile?.momoPayCode, '008000');
      h.oldMemberReply.complete(_json([]));
      await oldLoad;
      expect(h.repo.state.currentProfile?.momoPayCode, '008000');
      expect(h.cache.last?.currentProfile?.momoPayCode, '008000');
    },
  );

  test(
    'a newer authoritative profile is not replaced by an older save result',
    () async {
      final h = _LiveLoadHarness();
      await h.start();
      h.oldMemberReply.complete(_json([]));
      h.heldProfileReadNumber = 2; // The readback is first; refresh is second.
      final cacheEntered = Completer<void>();
      final cacheRelease = Completer<void>();
      h.cache.nextSaveEntered = cacheEntered;
      h.cache.nextSaveRelease = cacheRelease;
      addTearDown(() {
        if (!cacheRelease.isCompleted) cacheRelease.complete();
      });

      final save = h.repo.updateCurrentProfile(
        countryCode: 'RW',
        momoProvider: 'mtn_momo',
        momoNumber: '0788123456',
        momoPayCode: '008000',
      );
      final failure = expectLater(
        save,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Profile changed during the update'),
          ),
        ),
      );
      await cacheEntered.future.timeout(const Duration(seconds: 3));
      await h.heldProfileEntered.future.timeout(const Duration(seconds: 3));
      h.heldProfileReply.complete(_json(_row(code: '009999')));
      await h.freshPublished.future.timeout(const Duration(seconds: 3));
      expect(h.repo.state.currentProfile?.momoPayCode, '009999');
      expect(h.repo.state.isLoading, isFalse);
      cacheRelease.complete();
      await failure;
      expect(h.repo.state.currentProfile?.momoPayCode, '009999');
      expect(
        h.requests.where(
          (r) => r.url.path.endsWith('/update_current_member_profile'),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'a stale access denial still clears authority after the profile save',
    () async {
      final h = _LiveLoadHarness();
      await h.start();
      final oldLoad = h.repo.loadInitial();
      await h.oldMemberEntered.future.timeout(const Duration(seconds: 3));
      await h.repo.updateCurrentProfile(
        countryCode: 'RW',
        momoProvider: 'mtn_momo',
        momoNumber: '0788123456',
        momoPayCode: '008000',
      );
      await h.freshPublished.future.timeout(const Duration(seconds: 3));
      h.holdDenialRead = true;
      h.oldMemberReply.complete(_json({'code': 'permission_denied'}, 403));
      await h.denialReadEntered.future.timeout(const Duration(seconds: 3));
      expect(h.repo.state.currentProfile, isNull);
      expect(h.cache.clears, greaterThanOrEqualTo(1));
      h.denialReadReply.complete(_json(_row(code: '008000')));
      await oldLoad;
    },
  );
}
