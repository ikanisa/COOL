import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_receipt_operations_models.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_checkpoint.dart';
import 'package:collect_app/admin/core/admin_receipt_principal_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_action_session_test.dart' as auth;

const _fixtureRoot =
    'test/fixtures/admin_receipt_principal_v3';
Map<String, dynamic> _observed(String name) =>
    jsonDecode(File('$_fixtureRoot/observed-$name-v3.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, dynamic> _copy(Map<String, dynamic> raw) =>
    jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
DateTime _at(Map<String, dynamic> raw, String key) =>
    DateTime.parse(raw[key] as String);
List<Map<String, dynamic>> _observedPages() =>
    (jsonDecode(
              File(
                '$_fixtureRoot/observed-identity-pages-v3.json',
              ).readAsStringSync(),
            )
            as List)
        .cast<Map<String, dynamic>>();
Map<String, dynamic> _metadata() {
  final input = _observed('enroll-input');
  return {
    'contract_version': 2,
    'scope': 'rw_receipt_operations',
    'public_key_spki_base64': input['public_key_spki_base64'],
    'key_sha256': input['key_sha256'],
  };
}

AdminReceiptPrincipalIntent _observedIntent(String action) {
  final raw = _observed(action),
      deadline = _at(raw, 'request_expires_at'),
      created = deadline.subtract(const Duration(seconds: 90));
  if (action == 'enroll') {
    return AdminReceiptPrincipalIntent.enroll(
      requestId: raw['request_id'] as String,
      createdAt: created,
      requestExpiresAt: deadline,
      identityExpiresAt: _at(raw, 'identity_expires_at'),
      publicKey: AdminReceiptPrincipalPublicKey.parse(_metadata()),
    );
  }
  if (action == 'activate') {
    return AdminReceiptPrincipalIntent.activate(
      requestId: raw['request_id'] as String,
      createdAt: created,
      requestExpiresAt: deadline,
      identityExpiresAt: _at(raw, 'identity_expires_at'),
      principalId: raw['principal_id'] as String,
      keySha256: raw['key_sha256'] as String,
    );
  }
  return AdminReceiptPrincipalIntent.revoke(
    requestId: raw['request_id'] as String,
    createdAt: created,
    requestExpiresAt: deadline,
    identityExpiresAt: _at(raw, 'identity_expires_at'),
    principalId: raw['principal_id'] as String,
    keySha256: raw['key_sha256'] as String,
    reason: _observed('revoke-input')['reason'] as String,
  );
}

const _owner = AdminIdentity(
  userId: auth.actor,
  displayName: 'Synthetic identity owner',
  roles: ['platform_owner'],
  permissions: [
    'admin_users.manage',
    'notifications.manage',
    'system_health.read',
  ],
);
final _now = DateTime.utc(2026, 10, 1, 13, 3, 21);

class _Sdk {
  late SupabaseClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
    respond = (_) async => auth.response(_observed('revoke-lookup'));
    client = SupabaseClient(
      'https://synthetic.invalid',
      'synthetic-public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/verify')) {
          final parts = (jsonDecode(request.body)['token'] as String).split(
            '|',
          );
          return auth.response(auth.authReceipt(parts[0], parts[1]));
        }
        if (request.url.path.endsWith('/logout')) {
          return auth.response({});
        }
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    // Pinned SDK synthetic Auth fixture; this makes no hosted-email claim.
    await auth.session(client, 'principal-integration-a');
    repository = AdminRepository(client);
  }

  Future<Map<String, dynamic>> lookup() =>
      repository.receiptPrincipalOwnerRequest(_observedIntent('revoke'));
}

/// Async owner-scoped durable-store test double. It preserves immutable
/// originals and separate resolution markers, and checks authority at commit.
class _Store extends AdminReceiptPrincipalCheckpointStore {
  final originals = <String, String>{};
  final resolutions = <String, String>{};
  final events = <String>[];
  Object? readError;
  Completer<void>? publicationGate;
  @override
  Future<List<String>> read(String ownerDigest) async {
    events.add('read');
    if (readError != null) {
      throw readError!;
    }
    return originals.values.where((encoded) {
      final checkpoint = AdminReceiptPrincipalCheckpoint.parse(
        encoded,
        ownerDigest,
      );
      return !resolutions.containsKey(checkpoint.requestId);
    }).toList();
  }

  @override
  Future<void> write(
    String ownerDigest,
    String requestId,
    String encoded, {
    required bool Function() isCurrent,
  }) async {
    final gate = publicationGate;
    events.add('publication-entered');
    if (gate != null) {
      await gate.future;
    }
    if (!isCurrent()) {
      throw const AdminSessionChanged();
    }
    final checkpoint = AdminReceiptPrincipalCheckpoint.parse(
      encoded,
      ownerDigest,
    );
    if (checkpoint.requestId != requestId) {
      throw const FormatException();
    }
    final pending = (await read(ownerDigest))
        .map((row) => AdminReceiptPrincipalCheckpoint.parse(row, ownerDigest))
        .toList();
    if (!isCurrent() ||
        !adminReceiptPrincipalMayPublish(pending, checkpoint.binding) ||
        originals.containsKey(requestId)) {
      throw const FormatException();
    }
    originals[requestId] = encoded;
    events.add('published');
  }

  @override
  Future<void> resolve(
    AdminReceiptPrincipalCheckpoint checkpoint,
    String status, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) {
      throw const AdminSessionChanged();
    }
    if (originals[checkpoint.requestId] != checkpoint.encode() ||
        !['recorded', 'not_recorded_after_deadline'].contains(status)) {
      throw const FormatException();
    }
    resolutions[checkpoint.requestId] = status;
    events.add('resolved:$status');
  }
}

/// The UI creates new UUIDs. These declared service doubles preserve the exact
/// observed v3 wire shape while binding those UI inputs; they are not SQL rows.
Map<String, dynamic> _receipt(
  AdminReceiptPrincipalBinding binding, {
  DateTime? recordedAt,
}) => {
  'contract_version': 3,
  'action': binding.action.name,
  'request_id': binding.requestId,
  'principal_id': binding.principalId ?? _observed('enroll')['principal_id'],
  'state_at_action': binding.action.resultState.name,
  'scope': 'rw_receipt_operations',
  'key_sha256': binding.keySha256,
  'identity_expires_at': operationsUtc(binding.identityExpiresAt),
  // This declared immediate service double records at the captured clock.
  // Its subsequent same-clock lookup must never precede its own receipt.
  'recorded_at': operationsUtc(recordedAt ?? binding.createdAt),
  'request_expires_at': operationsUtc(binding.requestExpiresAt),
  if (binding.action == AdminReceiptPrincipalAction.revoke)
    'reason_sha256': binding.reasonSha256,
};
Map<String, dynamic> _lookup(
  AdminReceiptPrincipalBinding binding,
  DateTime now, {
  String status = 'recorded',
}) => {
  'contract_version': 3,
  'request_id': binding.requestId,
  'action': status == 'recorded' ? binding.action.name : null,
  'status': status,
  'checked_at': operationsUtc(now),
  'sample_valid_until': operationsUtc(now.add(const Duration(seconds: 60))),
  'request_expires_at': status == 'recorded'
      ? operationsUtc(binding.requestExpiresAt)
      : null,
  'receipt': status == 'recorded' ? _receipt(binding) : null,
};

Map<String, dynamic> _observation(
  Map<String, dynamic> identity,
  DateTime now,
) => {
  'contract_version': 3,
  'checked_at': operationsUtc(now),
  'sample_valid_until': operationsUtc(now.add(const Duration(seconds: 60))),
  'found': true,
  'identity': _copy(identity),
};
Map<String, dynamic> _pending() {
  // Declared pending presentation using the actual enrolled identity snapshot.
  return _copy(_observed('identity-active')['identity'] as Map<String, dynamic>)
    ..addAll({'state': 'pending', 'activated_at': null});
}

class _Repository extends AdminEvidenceRepository {
  _Repository(this.store) {
    observation = _observation(_pending(), _now);
    pages = [
      _directory([_pending()]),
    ];
  }
  final _Store store;
  DateTime now = _now;
  late Map<String, dynamic> observation;
  late List<Map<String, dynamic>> pages;
  final queries = <AdminReceiptPrincipalDirectoryQuery>[];
  final identityQueries = <String>[];
  final actions = <AdminReceiptPrincipalIntent>[];
  final lookups = <AdminReceiptPrincipalBinding>[];
  Completer<void>? directoryGate;
  Completer<void>? identityGate;
  Object? directoryError, actionError, lookupError;
  Map<String, dynamic> Function(String id, int count)? readIdentity;
  Map<String, dynamic> Function(AdminReceiptPrincipalBinding)? readLookup;
  void useObservation(Map<String, dynamic> value) {
    observation = _copy(value);
    pages = [
      _directory([_copy(value['identity'] as Map<String, dynamic>)]),
    ];
  }

  Map<String, dynamic> _directory(
    List<Map<String, dynamic>> rows, {
    bool next = false,
  }) => {
    'contract_version': 3,
    'checked_at': operationsUtc(now),
    'sample_valid_until': operationsUtc(now.add(const Duration(seconds: 60))),
    'rows': rows,
    'next_cursor': next
        ? {
            'created_at': rows.last['created_at'],
            'principal_id': rows.last['principal_id'],
          }
        : null,
  };

  void useObservedRowsAs25Pages() {
    // Declared re-pagination: unmodified actual SQL identity rows from all
    // fifteen limit-2 pages, presented through the Admin's limit-25 query.
    final rows = _observedPages()
        .expand((page) => (page['rows'] as List).cast<Map<String, dynamic>>())
        .map(_copy)
        .toList();
    pages = [
      _directory(rows.take(25).toList(), next: true),
      _directory(rows.skip(25).toList()),
    ];
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipals(
    AdminReceiptPrincipalDirectoryQuery query,
  ) async {
    queries.add(query);
    final raw = _copy(pages[query.before == null ? 0 : 1]),
        gate = directoryGate;
    if (gate != null) {
      await gate.future;
    }
    if (directoryError != null) {
      throw directoryError!;
    }
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipal(String principalId) async {
    identityQueries.add(principalId);
    final raw = _copy(
          readIdentity?.call(principalId, identityQueries.length) ??
              observation,
        ),
        gate = identityGate;
    if (gate != null) {
      await gate.future;
    }
    return raw;
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipalAction(
    AdminReceiptPrincipalIntent intent,
  ) async {
    actions.add(intent);
    store.events.add('send');
    if (actionError != null) {
      throw actionError!;
    }
    return _receipt(intent);
  }

  @override
  Future<Map<String, dynamic>> receiptPrincipalOwnerRequest(
    AdminReceiptPrincipalBinding original,
  ) async {
    lookups.add(original);
    if (lookupError != null) {
      throw lookupError!;
    }
    return readLookup?.call(original) ?? _lookup(original, now);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);
Future<void> _tap(WidgetTester tester, String label) async {
  // Text-controller listeners can rebuild a disabled confirmation control.
  // Apply that frame before dispatching; a later pump cannot replay an ignored
  // tap (notably the reason dialog's ValueListenableBuilder).
  await tester.pump();
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _until(
  WidgetTester tester,
  bool Function() reached,
  String description,
) async {
  // Closing dialog/controller continuations and Riverpod invalidation can
  // schedule a fresh read after the last settled frame. Wait only for the
  // required observable side effect; failure retains the original assertion.
  for (var attempt = 0; attempt < 10 && !reached(); attempt++) {
    await _settle(tester);
  }
  expect(reached(), isTrue, reason: description);
}

void main() {
  group('Pinned SDK principal v3 contracts', () {
    late _Sdk sdk;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
    });
    tearDown(() => sdk.client.dispose());
    for (final action in ['enroll', 'activate', 'revoke']) {
      test(
        '$action uses exact RPC parameters and one authenticated dispatch',
        () async {
          final intent = _observedIntent(action),
              expected = <String, dynamic>{
                'p_request_id': intent.requestId,
                if (action == 'enroll') ...{
                  'p_public_key_spki_base64':
                      _metadata()['public_key_spki_base64'],
                  'p_key_sha256': _metadata()['key_sha256'],
                  'p_identity_expires_at': _observed(
                    'enroll',
                  )['identity_expires_at'],
                } else ...{
                  'p_principal_id': _observed(action)['principal_id'],
                  'p_expected_key_sha256': _observed(action)['key_sha256'],
                },
                'p_request_expires_at': _observed(action)['request_expires_at'],
                if (action == 'revoke')
                  'p_reason': _observed('revoke-input')['reason'],
              };
          sdk.respond = (_) async => auth.response(_observed(action));
          final result = await sdk.repository.receiptPrincipalAction(intent),
              request = sdk.requests.single;
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/rest/v1/rpc/admin_${action}_receipt_operations_identity_v3',
          );
          expect(jsonDecode(request.body), expected);
          expect(
            request.headers['authorization'],
            'Bearer ${sdk.client.auth.currentSession!.accessToken}',
          );
          expect(result['request_id'], intent.requestId);
        },
      );
    }
    test(
      'directory sends the paired original keyset cursor and bounded limit',
      () async {
        final pages = _observedPages(),
            cursor = AdminReceiptPrincipalCursor.parse(pages[0]['next_cursor']),
            query = AdminReceiptPrincipalDirectoryQuery(
              limit: 2,
              before: cursor,
            );
        sdk.respond = (_) async => auth.response(pages[1]);
        await sdk.repository.receiptPrincipals(query);
        final request = sdk.requests.single;
        expect(
          request.url.path,
          '/rest/v1/rpc/admin_list_receipt_operations_identities_v3',
        );
        expect(jsonDecode(request.body), {
          'p_limit': 2,
          'p_before_created_at': operationsUtc(cursor.createdAt),
          'p_before_principal_id': cursor.principalId,
        });
        expect(
          request.headers['authorization'],
          'Bearer ${sdk.client.auth.currentSession!.accessToken}',
        );
      },
    );
    test('current identity read binds the exact target ID', () async {
      final raw = _observed('identity-active'),
          id = raw['identity']['principal_id'] as String;
      sdk.respond = (_) async => auth.response(raw);
      await sdk.repository.receiptPrincipal(id);
      final request = sdk.requests.single;
      expect(
        request.url.path,
        '/rest/v1/rpc/admin_get_receipt_operations_identity_v3',
      );
      expect(jsonDecode(request.body), {'p_principal_id': id});
      expect(
        request.headers['authorization'],
        'Bearer ${sdk.client.auth.currentSession!.accessToken}',
      );
    });
    test('owner lookup sends only the original immutable request ID', () async {
      await sdk.lookup();
      final request = sdk.requests.single;
      expect(
        request.url.path,
        '/rest/v1/rpc/admin_get_receipt_operations_enrollment_request_v3',
      );
      expect(jsonDecode(request.body), {
        'p_request_id': _observed('revoke')['request_id'],
      });
      expect(
        request.headers['authorization'],
        'Bearer ${sdk.client.auth.currentSession!.accessToken}',
      );
      expect(
        request.body,
        isNot(contains(_observed('revoke-input')['reason'])),
      );
    });
    for (final failure in [
      '403',
      '503',
      'lost',
      'private',
      'wrong_original',
      'wrong_deadline',
      'wrong_fingerprint',
      'wrong_reason',
    ]) {
      test(
        '$failure rejects original lookup without retry or unbound fallback',
        () async {
          sdk.respond = (_) async {
            if (failure == 'lost') {
              throw TimeoutException('PRIVATE_CANARY');
            }
            if (failure == '403' || failure == '503') {
              return auth.response({
                'code': '42501',
                'message': 'PRIVATE_CANARY',
              }, int.parse(failure));
            }
            final raw = _observed('revoke-lookup'),
                receipt = raw['receipt'] as Map<String, dynamic>;
            if (failure == 'private') {
              raw['authorization'] = 'PRIVATE_CANARY';
            }
            if (failure == 'wrong_original') {
              raw['request_id'] = auth.target;
            }
            if (failure == 'wrong_deadline') {
              raw['request_expires_at'] = operationsUtc(
                _at(
                  raw,
                  'request_expires_at',
                ).add(const Duration(microseconds: 1)),
              );
            }
            if (failure == 'wrong_fingerprint') {
              receipt['key_sha256'] = 'a' * 64;
            }
            if (failure == 'wrong_reason') {
              receipt['reason_sha256'] = 'a' * 64;
            }
            return auth.response(raw);
          };
          await expectLater(
            sdk.lookup(),
            throwsA(
              failure == 'lost'
                  ? isA<TimeoutException>()
                  : failure == '403' || failure == '503'
                  ? isA<PostgrestException>()
                  : isA<FormatException>(),
            ),
          );
          expect(sdk.requests, hasLength(1));
        },
      );
    }
    test('invalid target ID is rejected before HTTP', () async {
      await expectLater(
        sdk.repository.receiptPrincipal('PRIVATE_CANARY'),
        throwsFormatException,
      );
      expect(sdk.requests, isEmpty);
    });
    test('signed-out owner request is denied before dispatch', () async {
      await sdk.client.auth.signOut();
      await expectLater(sdk.lookup(), throwsA(isA<AdminSessionChanged>()));
      expect(sdk.requests, isEmpty);
    });
    test(
      'same-user replacement suppresses a late original owner result',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        sdk.respond = (_) async {
          entered.complete();
          await release.future;
          return auth.response(_observed('revoke-lookup'));
        };
        final assertion = expectLater(
          sdk.lookup(),
          throwsA(isA<AdminSessionChanged>()),
        );
        await entered.future;
        await auth.session(sdk.client, 'principal-integration-b');
        release.complete();
        await assertion;
        expect(sdk.requests, hasLength(1));
      },
    );
    test(
      'unresolved owner read times out at 15 seconds without retry',
      () async {
        final release = Completer<http.Response>();
        sdk.respond = (_) => release.future;
        await expectLater(sdk.lookup(), throwsA(isA<TimeoutException>()));
        expect(sdk.requests, hasLength(1));
        release.complete(auth.response(_observed('revoke-lookup')));
      },
    );
  });

  group('Current-owner principal Admin workflow', () {
    late _Sdk sdk;
    late _Repository repository;
    late _Store store;
    late ProviderContainer container;
    final authority = StateProvider<Future<AdminIdentity?>>(
      (_) async => _owner,
    );
    late StateProvider<DateTime> clock;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
      store = _Store();
      repository = _Repository(store);
      clock = StateProvider((_) => _now);
      container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(sdk.client),
          adminRepositoryProvider.overrideWithValue(repository),
          adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
          adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
          adminReceiptPrincipalCheckpointStoreProvider.overrideWithValue(store),
          adminClockProvider.overrideWith((ref) {
            final value = ref.watch(clock);
            return () => value;
          }),
        ],
      );
      await container.read(adminIdentityProvider.future);
    });
    tearDown(() async {
      container.dispose();
      await sdk.client.dispose();
    });
    Future<void> mount(
      WidgetTester tester, {
      double width = 700,
      double scale = 1,
    }) async {
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: CollectTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1400),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: AdminReceiptPrincipalCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    Future<void> open(WidgetTester tester) =>
        _tap(tester, 'Review signing identity');
    Future<void> enroll(WidgetTester tester) async {
      await _tap(tester, 'Enroll signing identity');
      await tester.enterText(
        _field('Public signing-key metadata'),
        jsonEncode(_metadata()),
      );
      await _tap(tester, 'Record pending identity');
    }

    Future<void> revoke(WidgetTester tester, String reason) async {
      await _tap(tester, 'Revoke signing identity');
      await tester.enterText(_field('Reason'), reason);
      await _tap(tester, 'Record identity revocation');
    }

    void verifyMetadataOnly() {
      final original = store.originals.values.single,
          decoded = jsonDecode(original) as Map<String, dynamic>;
      expect((decoded['binding'] as Map).keys.toSet(), {
        'action',
        'request_id',
        'principal_id',
        'key_sha256',
        'identity_expires_at',
        'created_at',
        'request_expires_at',
        'reason_sha256',
      });
      expect(original, isNot(contains(_metadata()['public_key_spki_base64'])));
      expect(original, isNot(contains('PRIVATE_CANARY')));
    }

    for (final absent in [
      'platform_owner',
      'admin_users.manage',
      'notifications.manage',
      'system_health.read',
    ]) {
      testWidgets('missing $absent prevents all principal reads and actions', (
        tester,
      ) async {
        container.read(authority.notifier).state = Future.value(
          AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic denied owner',
            roles: absent == 'platform_owner' ? ['admin'] : _owner.roles,
            permissions: _owner.permissions.where((p) => p != absent).toList(),
          ),
        );
        await mount(tester);
        expect(find.textContaining('A current platform owner'), findsOneWidget);
        expect(find.text('Enroll signing identity'), findsNothing);
        expect(repository.queries, isEmpty);
        expect(repository.identityQueries, isEmpty);
        expect(repository.actions, isEmpty);
        expect(repository.lookups, isEmpty);
        expect(store.originals, isEmpty);
      });
    }
    testWidgets('another-user identity cannot reveal the owner directory', (
      tester,
    ) async {
      container.read(authority.notifier).state = Future.value(
        AdminIdentity(
          userId: auth.target,
          displayName: 'Different synthetic owner',
          roles: _owner.roles,
          permissions: _owner.permissions,
        ),
      );
      await mount(tester);
      expect(repository.queries, isEmpty);
      expect(find.text('Signing principal ID'), findsNothing);
    });
    testWidgets(
      'directory paging carries the paired cursor and returns safely',
      (tester) async {
        repository.useObservedRowsAs25Pages();
        await mount(tester);
        expect(find.text('Review signing identity'), findsNWidgets(25));
        final cursor = AdminReceiptPrincipalCursor.parse(
          repository.pages.first['next_cursor'],
        );
        await _tap(tester, 'Next identity page');
        expect(
          repository.queries.last,
          AdminReceiptPrincipalDirectoryQuery(before: cursor),
        );
        expect(find.text('Review signing identity'), findsNWidgets(4));
        await _tap(tester, 'Previous identity page');
        expect(repository.queries.last.before, isNull);
        expect(find.text('Review signing identity'), findsNWidgets(25));
        expect(repository.actions, isEmpty);
      },
    );
    testWidgets('expired directory hides IDs and disables enrollment', (
      tester,
    ) async {
      await mount(tester);
      final id = repository.observation['identity']['principal_id'] as String;
      expect(find.text(id), findsOneWidget);
      container.read(clock.notifier).state = _at(
        repository.pages.single,
        'sample_valid_until',
      );
      await _settle(tester);
      expect(
        find.textContaining('Identity directory evidence expired'),
        findsOneWidget,
      );
      expect(find.text(id), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll signing identity'),
            )
            .onPressed,
        isNull,
      );
      expect(repository.queries, hasLength(1));
      expect(repository.actions, isEmpty);
    });
    testWidgets('private directory evidence fails closed without raw output', (
      tester,
    ) async {
      repository.pages.single['authorization'] = 'PRIVATE_CANARY';
      await mount(tester);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(find.text('Signing principal ID'), findsNothing);
      expect(repository.actions, isEmpty);
    });
    testWidgets('loading and redacted failure allow an explicit fresh retry', (
      tester,
    ) async {
      repository.directoryGate = Completer<void>();
      await mount(tester);
      expect(find.text('Loading receipt signing identities…'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Refresh signing identities'),
            )
            .onPressed,
        isNull,
      );
      repository.directoryError = StateError('PRIVATE_CANARY');
      repository.directoryGate!.complete();
      await _settle(tester);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      repository.directoryGate = null;
      repository.directoryError = null;
      await _tap(tester, 'Refresh signing identities');
      expect(find.text('Identity state: Pending'), findsOneWidget);
      expect(repository.queries, hasLength(2));
      expect(repository.actions, isEmpty);
    });
    for (final state in ['revoked', 'expired-active', 'expired-pending']) {
      testWidgets(
        '$state keeps identity state distinct from permitted actions',
        (tester) async {
          final raw = state == 'expired-pending'
              ? _observation(
                  (_observedPages().last['rows'] as List).single
                      as Map<String, dynamic>,
                  _now,
                )
              : _observed('identity-$state');
          repository.useObservation(raw);
          await mount(tester);
          await open(tester);
          final id = raw['identity']['principal_id'] as String;
          expect(repository.identityQueries, [id]);
          expect(find.text('Activate signing identity'), findsNothing);
          expect(
            find.text('Revoke signing identity'),
            state == 'revoked' ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('Identity expiry has elapsed'),
            state == 'revoked' ? findsNothing : findsNWidgets(2),
          );
          expect(repository.actions, isEmpty);
          await _tap(tester, 'Close signing identity');
          expect(find.text('Receipt signing identity'), findsNothing);
        },
      );
    }
    testWidgets(
      'public enrollment saves and verifies metadata before one send',
      (tester) async {
        await mount(tester);
        await _tap(tester, 'Enroll signing identity');
        await tester.enterText(
          _field('Public signing-key metadata'),
          '{"private_key":"PRIVATE_CANARY"}',
        );
        await _tap(tester, 'Record pending identity');
        expect(
          find.textContaining('Use valid public signing-key metadata'),
          findsOneWidget,
        );
        expect(repository.actions, isEmpty);
        expect(store.originals, isEmpty);
        await tester.enterText(
          _field('Public signing-key metadata'),
          jsonEncode(_metadata()),
        );
        await _tap(tester, 'Record pending identity');
        expect(repository.actions, hasLength(1));
        final intent = repository.actions.single;
        expect(intent.action, AdminReceiptPrincipalAction.enroll);
        expect(
          intent.requestExpiresAt.difference(intent.createdAt),
          const Duration(seconds: 90),
        );
        verifyMetadataOnly();
        expect(
          store.events.indexOf('published'),
          lessThan(store.events.indexOf('send')),
        );
        expect(
          store.events.sublist(
            store.events.indexOf('published') + 1,
            store.events.indexOf('send'),
          ),
          contains('read'),
        );
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Enrollment recorded: Pending'), findsOneWidget);
        expect(find.textContaining('original action receipt'), findsOneWidget);
        expect(find.text('Original identity request ID'), findsNothing);
        await _until(
          tester,
          () => repository.queries.length >= 2,
          'Durable enrollment must automatically refresh its directory.',
        );
        expect(repository.queries.length, greaterThanOrEqualTo(2));
      },
    );
    testWidgets('unavailable recovery storage prevents enrollment and sends', (
      tester,
    ) async {
      store.readError = StateError('PRIVATE_CANARY');
      await mount(tester);
      expect(find.text('Check identity recovery storage'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll signing identity'),
            )
            .onPressed,
        isNull,
      );
      expect(repository.actions, isEmpty);
      store.readError = null;
      await _tap(tester, 'Check identity recovery storage');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll signing identity'),
            )
            .onPressed,
        isNotNull,
      );
    });
    testWidgets(
      'expired detail removes its fingerprint and mutation controls',
      (tester) async {
        await mount(tester);
        await open(tester);
        final key = repository.observation['identity']['key_sha256'] as String;
        expect(find.text(key), findsOneWidget);
        container.read(clock.notifier).state = _at(
          repository.observation,
          'sample_valid_until',
        );
        await _settle(tester);
        expect(
          find.textContaining('Signing identity evidence expired'),
          findsOneWidget,
        );
        expect(find.text(key), findsNothing);
        expect(find.text('Activate signing identity'), findsNothing);
        expect(find.text('Revoke signing identity'), findsNothing);
        expect(repository.identityQueries, hasLength(1));
        expect(repository.actions, isEmpty);
      },
    );
    testWidgets(
      'pending enrollment leaves investigation and urgent revoke usable',
      (tester) async {
        final enrolled = _observedIntent('enroll'),
            original = AdminReceiptPrincipalCheckpoint.fromIntent(
              adminReceiptPrincipalOwnerDigest(auth.actor),
              enrolled,
            );
        store.originals[original.requestId] = original.encode();
        await mount(tester);
        await open(tester);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Activate signing identity'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Revoke signing identity'),
              )
              .onPressed,
          isNotNull,
        );
        await revoke(
          tester,
          'Revoke organization key during enrollment uncertainty',
        );
        expect(repository.actions, hasLength(1));
        final revocation = repository.actions.single;
        expect(revocation.action, AdminReceiptPrincipalAction.revoke);
        expect(store.originals, hasLength(2));
        expect(store.resolutions[revocation.requestId], 'recorded');
        expect(store.resolutions[original.requestId], isNull);
        await _tap(tester, 'Close signing identity');
        expect(
          find.text('Enrollment outcome needs reconciliation'),
          findsOneWidget,
        );
        expect(find.text('Revocation recorded: Revoked'), findsOneWidget);
        expect(repository.actions, hasLength(1));
      },
    );
    testWidgets(
      'activation proof refusal retains original and only manual lookup',
      (tester) async {
        repository.actionError = const PostgrestException(
          message: 'PRIVATE_CANARY proof missing',
          code: '42501',
        );
        await mount(tester);
        await open(tester);
        await _tap(tester, 'Activate signing identity');
        expect(repository.identityQueries, hasLength(3));
        expect(repository.actions, hasLength(1));
        final intent = repository.actions.single;
        expect(intent.action, AdminReceiptPrincipalAction.activate);
        verifyMetadataOnly();
        expect(store.resolutions, isEmpty);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(find.textContaining('outcome is unknown'), findsWidgets);
        await _tap(tester, 'Close signing identity');
        await _tap(tester, 'Refresh signing identities');
        expect(repository.actions, hasLength(1));
        expect(
          find.text('Activation outcome needs reconciliation'),
          findsOneWidget,
        );
        await _tap(tester, 'Check original identity request');
        expect(repository.lookups.single.requestId, intent.requestId);
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Activation recorded: Active'), findsOneWidget);
        expect(find.text('Identity state: Pending'), findsOneWidget);
        expect(repository.actions, hasLength(1));
      },
    );
    for (final changed in ['revoked', 'key', 'expiry']) {
      testWidgets(
        '$changed fresh preflight prevents stale activation submission',
        (tester) async {
          repository.readIdentity = (_, count) {
            if (count == 1) {
              return repository.observation;
            }
            final raw = _copy(repository.observation),
                row = raw['identity'] as Map<String, dynamic>;
            if (changed == 'revoked') {
              row['state'] = 'revoked';
              row['revoked_at'] = operationsUtc(_now);
            }
            if (changed == 'key') {
              row['key_sha256'] = 'a' * 64;
            }
            if (changed == 'expiry') {
              row['expires_at'] = operationsUtc(
                _at(row, 'expires_at').add(const Duration(microseconds: 1)),
              );
            }
            return raw;
          };
          await mount(tester);
          await open(tester);
          await _tap(tester, 'Activate signing identity');
          expect(repository.actions, isEmpty);
          expect(store.originals, isEmpty);
          expect(find.textContaining('No request was sent'), findsWidgets);
        },
      );
    }
    testWidgets(
      'unknown revocation keeps reason hash and manually recovers once',
      (tester) async {
        repository.actionError = TimeoutException('PRIVATE_CANARY transport');
        await mount(tester);
        await open(tester);
        await revoke(
          tester,
          'PRIVATE_CANARY revoke organizational signing key',
        );
        expect(repository.actions, hasLength(1));
        final intent = repository.actions.single;
        expect(intent.action, AdminReceiptPrincipalAction.revoke);
        verifyMetadataOnly();
        final original = AdminReceiptPrincipalCheckpoint.parse(
          store.originals.values.single,
          adminReceiptPrincipalOwnerDigest(auth.actor),
        );
        expect(original.binding.reasonSha256, intent.reasonSha256);
        expect(store.resolutions, isEmpty);
        await _tap(tester, 'Close signing identity');
        expect(
          find.text('Revocation outcome needs reconciliation'),
          findsOneWidget,
        );
        repository.lookupError = StateError('PRIVATE_CANARY lookup');
        await _tap(tester, 'Check original identity request');
        expect(store.resolutions, isEmpty);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        repository.lookupError = null;
        await _tap(tester, 'Check original identity request');
        expect(repository.lookups.map((p) => p.requestId), [
          intent.requestId,
          intent.requestId,
        ]);
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Revocation recorded: Revoked'), findsOneWidget);
        expect(store.originals, hasLength(1));
        expect(repository.actions, hasLength(1));
      },
    );
    testWidgets(
      'restored original permits lookup and never reconstructs a send',
      (tester) async {
        final intent = _observedIntent('enroll'),
            checkpoint = AdminReceiptPrincipalCheckpoint.fromIntent(
              adminReceiptPrincipalOwnerDigest(auth.actor),
              intent,
            );
        store.originals[checkpoint.requestId] = checkpoint.encode();
        await mount(tester);
        expect(find.text(intent.requestId), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Enroll signing identity'),
              )
              .onPressed,
          isNull,
        );
        await _tap(tester, 'Check original identity request');
        expect(repository.actions, isEmpty);
        expect(repository.lookups.single.requestId, intent.requestId);
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Enrollment recorded: Pending'), findsOneWidget);
        expect(store.originals[checkpoint.requestId], checkpoint.encode());
      },
    );
    testWidgets(
      'absence clears only with fresh proof after retained deadline',
      (tester) async {
        final intent = _observedIntent('activate'),
            checkpoint = AdminReceiptPrincipalCheckpoint.fromIntent(
              adminReceiptPrincipalOwnerDigest(auth.actor),
              intent,
            );
        store.originals[checkpoint.requestId] = checkpoint.encode();
        repository.readLookup = (binding) =>
            _lookup(binding, repository.now, status: 'not_recorded');
        await mount(tester);
        await _tap(tester, 'Check original identity request');
        expect(store.resolutions, isEmpty);
        expect(
          find.text('Activation outcome needs reconciliation'),
          findsOneWidget,
        );
        repository.now = intent.requestExpiresAt;
        container.read(clock.notifier).state = repository.now;
        await _settle(tester);
        await _tap(tester, 'Check original identity request');
        expect(
          store.resolutions[intent.requestId],
          'not_recorded_after_deadline',
        );
        expect(find.textContaining('No request was replayed'), findsOneWidget);
        expect(repository.actions, isEmpty);
        expect(store.originals[checkpoint.requestId], checkpoint.encode());
      },
    );
    testWidgets(
      'same-user A-B-A replacement closes enrollment and suppresses draft',
      (tester) async {
        await mount(tester);
        await _tap(tester, 'Enroll signing identity');
        await tester.enterText(
          _field('Public signing-key metadata'),
          jsonEncode(_metadata()),
        );
        await tester.runAsync(
          () => auth.session(sdk.client, 'principal-modal-b'),
        );
        await _settle(tester);
        await tester.runAsync(
          () => auth.session(sdk.client, 'principal-integration-a', nonce: 1),
        );
        await _settle(tester);
        expect(find.text('Enroll receipt signing identity'), findsNothing);
        expect(repository.actions, isEmpty);
        expect(store.originals, isEmpty);
      },
    );
    testWidgets(
      'role departure closes current detail before role restoration',
      (tester) async {
        await mount(tester);
        await open(tester);
        container.read(authority.notifier).state = Future.value(null);
        await _settle(tester);
        container.read(authority.notifier).state = Future.value(_owner);
        await _settle(tester);
        expect(find.text('Receipt signing identity'), findsNothing);
        expect(find.text('Activate signing identity'), findsNothing);
        expect(repository.actions, isEmpty);
        expect(repository.identityQueries, hasLength(1));
      },
    );
    testWidgets('late identity read cannot resurrect a departed A-B-A modal', (
      tester,
    ) async {
      repository.identityGate = Completer<void>();
      await mount(tester);
      await open(tester);
      expect(find.text('Loading current signing identity…'), findsOneWidget);
      await tester.runAsync(() => auth.session(sdk.client, 'principal-read-b'));
      await _settle(tester);
      await tester.runAsync(
        () => auth.session(sdk.client, 'principal-integration-a', nonce: 2),
      );
      await _settle(tester);
      repository.identityGate!.complete();
      await _settle(tester);
      expect(find.text('Receipt signing identity'), findsNothing);
      expect(find.text('Public key fingerprint'), findsNothing);
      expect(find.text('Activate signing identity'), findsNothing);
      expect(repository.identityQueries, hasLength(1));
      expect(repository.actions, isEmpty);
      expect(store.originals, isEmpty);
    });
    testWidgets(
      'authority loss during async publication commits no original or send',
      (tester) async {
        store.publicationGate = Completer<void>();
        await mount(tester);
        await enroll(tester);
        expect(store.events, contains('publication-entered'));
        expect(repository.actions, isEmpty);
        container.read(authority.notifier).state = Future.value(null);
        await _settle(tester);
        container.read(authority.notifier).state = Future.value(_owner);
        await _settle(tester);
        store.publicationGate!.complete();
        await _settle(tester);
        expect(repository.actions, isEmpty);
        expect(store.originals, isEmpty);
        expect(find.text('Enrollment recorded: Pending'), findsNothing);
      },
    );
    testWidgets(
      '320px twice-text detail keeps named semantic controls usable',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, width: 320, scale: 2);
          await open(tester);
          expect(tester.takeException(), isNull);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.header == true,
            ),
            findsWidgets,
          );
          await _tap(tester, 'Refresh signing identity');
          expect(repository.identityQueries, hasLength(2));
          await _tap(tester, 'Close signing identity');
          expect(find.text('Receipt signing identity'), findsNothing);
          expect(tester.takeException(), isNull);
          expect(repository.actions, isEmpty);
        } finally {
          semantics.dispose();
        }
      },
    );
  });
}
