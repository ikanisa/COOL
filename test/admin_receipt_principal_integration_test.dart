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
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'admin_action_session_test.dart' as auth;

part 'admin_receipt_principal_workflow_cases.dart';

const _fixtureRoot = 'test/fixtures/admin_receipt_principal_v3';
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
  late CollectCloudflareClient client;
  late AdminRepository repository;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  Future<void> start() async {
    respond = (_) async => auth.response(_observed('revoke-lookup'));
    client = CollectCloudflareClient(
      'https://synthetic.invalid',
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
            '/v1/rpc/admin_${action}_receipt_operations_identity_v3',
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
          '/v1/rpc/admin_list_receipt_operations_identities_v3',
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
        '/v1/rpc/admin_get_receipt_operations_identity_v3',
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
        '/v1/rpc/admin_get_receipt_operations_enrollment_request_v3',
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
                  ? isA<CollectApiException>()
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

  _registerPrincipalWorkflowCases();
}
