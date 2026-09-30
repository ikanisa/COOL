import 'dart:async';
import 'dart:convert';

import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/features/settings/settings_subscreens.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _user = '99740000-0000-4000-8000-000000000001';
const _other = '99740000-0000-4000-8000-000000000002';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<_Harness> mount(
    WidgetTester tester, {
    bool fresh = false,
    double scale = 1,
  }) async {
    final h = (await tester.runAsync(_Harness.create))!;
    if (fresh) await tester.runAsync(h.repo.refreshNotificationPreferences);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((ref) => h.repo)],
        child: MaterialApp(
          theme: CollectTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const NotificationSettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'fresh server read explicitly enables editing without any write',
    (tester) async {
      final h = await mount(tester);
      expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((s) => s.onChanged == null),
        isTrue,
      );
      expect(h.saves, isEmpty);
      await tapButton(tester, 'Refresh preferences');
      expect(h.reads, 1);
      expect(h.saves, isEmpty);
      expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((s) => s.onChanged != null),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'conflict retains intent; refresh reviews all differences and never silently retries',
    (tester) async {
      final h = await mount(tester, fresh: true);
      h.conflicts = 1;
      await tester.ensureVisible(find.byType(Switch).first);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(h.saves, hasLength(1));
      expect(h.repo.pendingNotificationPreferences, isNotNull);
      expect(
        tester
            .widget<CollectButton>(
              find.widgetWithText(CollectButton, 'Save pending change'),
            )
            .onPressed,
        isNull,
      );
      await tapButton(tester, 'Refresh preferences');
      expect(h.saves, hasLength(1));
      expect(
        find.text('Contribution confirmations: saved On, intended Off'),
        findsOneWidget,
      );
      expect(
        find.text('Group updates: saved Off, intended On'),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((s) => s.onChanged == null),
        isTrue,
      );
      await tapButton(tester, 'Save pending change');
      expect(h.saves, hasLength(2));
      expect(h.saves.last['p_expected_revision'], 2);
      expect(
        h.saves.last['p_preferences'],
        const NotificationPreferences(
          contributionConfirmations: false,
        ).toJson(),
      );
      expect(h.repo.notificationPreferencesRevision, 3);
      expect(h.repo.pendingNotificationPreferences, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'discard after uncertainty never writes or authorizes an unseen revision',
    (tester) async {
      final h = await mount(tester, fresh: true);
      h.conflicts = 1;
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Discard pending change');
      expect(h.saves, hasLength(1));
      expect(h.repo.pendingNotificationPreferences, isNull);
      expect(h.repo.notificationPreferencesNeedsRefresh, isTrue);
      expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((s) => s.onChanged == null),
        isTrue,
      );
      await tapButton(tester, 'Refresh preferences');
      expect(h.saves, hasLength(1));
      expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .every((s) => s.onChanged != null),
        isTrue,
      );
    },
  );

  testWidgets('an old refresh failure has no toast after account switch', (
    tester,
  ) async {
    final h = await mount(tester);
    final reply = Completer<http.Response>();
    h.readBarrier = reply;
    await tester.tap(find.text('Refresh preferences'));
    await tester.pump();
    await tester.runAsync(() => h.login(_other));
    await tester.pumpAndSettle();
    reply.complete(
      _json({'code': '42501', 'message': 'private prior-account detail'}, 403),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not refresh preferences'), findsNothing);
    expect(find.textContaining('private prior-account'), findsNothing);
    expect(h.repo.pendingNotificationPreferences, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact enlarged recovery controls remain scrollable without overflow',
    (tester) async {
      final h = await mount(tester, fresh: true, scale: 2);
      h.conflicts = 1;
      await tester.ensureVisible(find.byType(Switch).first);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Refresh preferences');
      await tester.ensureVisible(find.text('Save pending change'));
      expect(
        tester
            .widget<CollectButton>(
              find.widgetWithText(CollectButton, 'Save pending change'),
            )
            .onPressed,
        isNotNull,
      );
      await tapButton(tester, 'Discard pending change');
      expect(h.saves, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}

http.Response _json(Object? body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _Harness {
  _Harness(this.client, this.repo);
  final SupabaseClient client;
  final _Repository repo;
  final saves = <Map<String, dynamic>>[];
  int reads = 0, revision = 1, conflicts = 0;
  NotificationPreferences preferences = NotificationPreferences.defaults;
  Completer<http.Response>? readBarrier;
  static Future<_Harness> create() async {
    late _Harness h;
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'synthetic-anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final input = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/verify')) {
          final user = input['token'] as String;
          return _json(_auth(user));
        }
        if (request.url.path.endsWith('/get_notification_preferences_v2')) {
          h.reads++;
          if (h.readBarrier != null) return h.readBarrier!.future;
          return _json({
            'contract_version': 2,
            'ok': true,
            'user_id': client.auth.currentUser!.id,
            'revision': h.revision,
            'exists': true,
            'preferences': h.preferences.toJson(),
          });
        }
        if (request.url.path.endsWith('/set_notification_preferences_v2')) {
          h.saves.add(input);
          if (h.conflicts-- > 0) {
            h.revision++;
            h.preferences = const NotificationPreferences(groupUpdates: false);
            return _json({
              'code': '40001',
              'message': 'runtime_control_conflict',
            }, 409);
          }
          final previous = h.revision++;
          h.preferences = NotificationPreferences.fromJson(
            input['p_preferences'] as Map<String, dynamic>,
          );
          return _json({
            'contract_version': 2,
            'ok': true,
            'user_id': client.auth.currentUser!.id,
            'previous_revision': previous,
            'revision': h.revision,
            'changed': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
        throw StateError('Unexpected fixture path ${request.url.path}');
      }),
    );
    await client.auth.verifyOTP(
      phone: '+250788974001',
      token: _user,
      type: OtpType.sms,
    );
    h = _Harness(client, _Repository(client));
    addTearDown(() async {
      if (h.repo.mounted) h.repo.dispose();
      await client.dispose();
    });
    return h;
  }

  Future<void> login(String user) async {
    await client.auth.verifyOTP(
      phone: '+250788974001',
      token: user,
      type: OtpType.sms,
    );
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

Map<String, dynamic> _auth(String user) => {
  'access_token':
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'sub': user, 'session_id': user == _user ? '99740000-0000-4000-8000-000000000011' : '99740000-0000-4000-8000-000000000012', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
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
  publicId: '997401',
  whatsappPhone: '+250788974001',
  countryCode: 'RW',
  currencyCode: 'RWF',
);

class _Repository extends CollectRepository {
  _Repository(this.client)
    : super.fixture(
        initialState: CollectState(
          currentProfile: _profile(_user),
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
    final user = client.auth.currentUser?.id;
    state = CollectState(
      currentProfile: user == null ? null : _profile(user),
      collections: const [],
      paymentIntents: const [],
      contributions: const [],
    );
  }
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
