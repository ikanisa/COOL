import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_invitation_recovery.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../core/supabase_backend_test.dart' as fixtures;

const staffId = '10000000-0000-4000-8000-000000000002';
const serverRequest = '10000000-0000-4000-8000-000000000003';
const origin = 'https://platform-admin.collect.ikanisa.com';
Map<String, dynamic> receipt({
  String status = 'accepted',
  String operation = 'invite',
  bool duplicate = false,
  String id = staffId,
}) => {
  'id': id,
  'requestId': serverRequest,
  'emailStatus': status,
  'accessStatus': 'invited',
  'operation': operation,
  'replayed': false,
  'duplicate': duplicate,
};
http.Response reply(Map<String, dynamic> value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
Map<String, dynamic> owner() => {
  'ownerEmail': 'info@ikanisa.com',
  'user': {
    'id': '10000000-0000-4000-8000-000000000001',
    'email': 'info@ikanisa.com',
    'role': 'owner',
    'sessionId': 'synthetic-owner-session',
    'permissions': ['admin_users.manage', 'admin_users.read'],
    'assuranceLevel': 1,
    'mfaAt': null,
    'principalId': fixtures.principal,
    'financialModel': 'canonical_evidence_ledger',
  },
  'expiresAt': DateTime.now()
      .add(const Duration(minutes: 20))
      .toIso8601String(),
  'csrfToken': 'a' * 64,
};

class Harness {
  Harness(this.session, this.api, this.store, this.storage);
  final CloudflareAdminSession session;
  final CloudflareAdminAccountApi api;
  final AdminPendingAttemptStore store;
  final AdminPendingAttemptStorage storage;
  AdminInvitationCoordinator coordinator({
    AdminPendingAttemptStore? using,
    String Function()? key,
    bool Function()? canManage,
  }) => AdminInvitationCoordinator(
    api: api,
    store: using ?? store,
    canManageTeam: canManage ?? () => true,
    requestKey: key ?? () => 'client-original-invitation-key',
  );
}

Future<Harness> harness(
  Future<http.Response> Function(http.Request) send, {
  AdminPendingAttemptStorage? storage,
  Map<String, dynamic> Function()? account,
  Duration? proofAge = const Duration(seconds: 1),
}) async {
  final session = CloudflareAdminSession(
    MockClient((request) async {
      if (request.url.path.endsWith('/auth/session')) {
        return reply((account ?? owner)());
      }
      if (request.url.path.endsWith('/auth/email-verification')) {
        return reply({
          'contractVersion': 1,
          'sessionId': ((account ?? owner)()['user'] as Map)['sessionId'],
          'emailVerifiedAt': proofAge == null
              ? null
              : DateTime.now().toUtc().subtract(proofAge).toIso8601String(),
        });
      }
      return send(
        request,
      ); // All HTTP is intercepted; no provider is contacted.
    }),
    origin: Uri.parse(origin),
    environment: fixtures.environment(api: origin, admin: origin),
  );
  addTearDown(session.dispose);
  await session.refresh();
  expect(session.user, isNotNull);
  final actual = storage ?? MemoryAdminPendingAttemptStorage();
  final store = AdminPendingAttemptStore(storage: actual)..bind(session.user);
  addTearDown(store.dispose);
  return Harness(
    session,
    CloudflareAdminAccountApi(session, invitationVersion: 1),
    store,
    actual,
  );
}

void main() {
  test(
    'lost POST restores original body and only exact found:false enables confirmed replay',
    () async {
      final calls = <http.Request>[];
      final storage = MemoryAdminPendingAttemptStorage();
      final h = await harness((request) async {
        calls.add(request);
        if (request.method == 'GET') return reply({'ok': true, 'found': false});
        expect(
          storage.values.values.single,
          contains('client-original-key-001'),
        );
        expect(storage.values.values.single, contains('teammate@example.test'));
        if (calls.where((row) => row.method == 'POST').length == 1) {
          throw http.ClientException('Synthetic lost acknowledgment');
        }
        return reply({'ok': true, ...receipt(), 'outcome': 'accepted'});
      }, storage: storage);
      var keys = 0;
      final first = h.coordinator(
        key: () {
          keys++;
          return 'client-original-key-001';
        },
      );
      final attempt = first.prepareInvite(
        '  Teammate@Example.test ',
        AdminAccountRole.staff,
        displayName: '  Synthetic Teammate ',
      );
      await expectLater(
        first.submit(attempt),
        throwsA(isA<AdminInvitationFailure>()),
      );
      expect(keys, 1);
      expect(calls, hasLength(1));
      expect(attempt.intent.requestKey, isNot(serverRequest));
      final stored =
          (h.storage as MemoryAdminPendingAttemptStorage).values.values.single;
      expect(stored, contains('teammate@example.test'));
      expect(stored, contains('Synthetic Teammate'));
      expect(
        () => attempt.intent.body['email'] = 'edited@example.test',
        throwsUnsupportedError,
      );
      final reloadedStore = AdminPendingAttemptStore(storage: h.storage)
        ..bind(h.session.user);
      addTearDown(reloadedStore.dispose);
      final reloaded = h.coordinator(
        using: reloadedStore,
        key: () => throw StateError('Restore must not generate a new key'),
      );
      final original = reloaded.pending.single;
      expect(original.restored, isTrue);
      expect(calls, hasLength(1));
      await expectLater(
        reloaded.submit(original),
        throwsA(isA<AdminAccountException>()),
      );
      final lookup = await reloaded.lookup(original);
      expect(lookup.found, isFalse);
      expect(original.canRetry, isTrue);
      expect(calls.last.method, 'GET');
      expect(calls.last.body, isEmpty);
      expect(calls.last.url.path.endsWith('/team/invitation-status'), isTrue);
      await expectLater(
        reloaded.submit(original),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls.where((row) => row.method == 'POST'), hasLength(1));
      final accepted = await reloaded.submit(
        original,
        confirmedSameIntentRetry: true,
      );
      expect(accepted.requestId, serverRequest);
      expect(original.completed, isTrue);
      final posts = calls.where((row) => row.method == 'POST').toList();
      expect(posts, hasLength(2));
      expect(posts[0].body, posts[1].body);
      expect(calls.map((row) => row.headers['Idempotency-Key']).toSet(), {
        'client-original-key-001',
      });
      expect(reloaded.pending, isEmpty);
    },
  );

  for (final state in ['operation_unknown', 'delivery_unknown', 'claim403']) {
    test(
      '$state retains checkpoint without auto resend or arbitrary error copy',
      () async {
        var posts = 0;
        final h = await harness((request) async {
          posts++;
          if (state == 'claim403') {
            return reply({
              'error': {
                'code': 'admin_access_changed',
                'message': 'RAW_PROVIDER_OR_SQL_DETAIL',
              },
            }, 403);
          }
          return reply({
            'ok': false,
            'outcome': state,
            if (state == 'delivery_unknown') ...receipt(status: 'unknown'),
            'error': {
              'code': state == 'operation_unknown'
                  ? 'invitation_operation_unknown'
                  : 'invitation_delivery_unknown',
              'message': 'RAW_PROVIDER_OR_SQL_DETAIL',
            },
          }, 503);
        });
        final coordinator = h.coordinator(),
            attempt = coordinator.prepareInvite(
              'synthetic@example.test',
              AdminAccountRole.admin,
            );
        await expectLater(
          coordinator.submit(attempt),
          throwsA(
            isA<AdminInvitationFailure>().having(
              (value) => value.message,
              'allowlisted copy',
              isNot(contains('RAW_PROVIDER_OR_SQL_DETAIL')),
            ),
          ),
        );
        expect(posts, 1);
        expect(coordinator.pending, hasLength(1));
        expect(attempt.canRetry, isFalse);
        expect(
          attempt.outcome,
          state == 'delivery_unknown'
              ? AdminInvitationOutcome.deliveryUnknown
              : AdminInvitationOutcome.operationUnknown,
        );
        await expectLater(
          coordinator.submit(attempt),
          throwsA(isA<AdminAccountException>()),
        );
        expect(posts, 1);
        expect(
          (h.storage as MemoryAdminPendingAttemptStorage).values.values.single,
          contains(attempt.intent.requestKey),
        );
      },
    );
  }

  test(
    'duplicate409 accepted alias stays held until original GET; no new-send result',
    () async {
      var posts = 0, reads = 0;
      final h = await harness((request) async {
        if (request.method == 'GET') {
          reads++;
          return reply({
            'ok': true,
            'found': true,
            ...receipt(duplicate: true),
          });
        }
        posts++;
        return reply({
          'ok': false,
          ...receipt(duplicate: true),
          'outcome': 'existing_request',
          'error': {'code': 'invitation_existing_request'},
        }, 409);
      });
      final coordinator = h.coordinator(),
          attempt = coordinator.prepareInvite(
            'synthetic@example.test',
            AdminAccountRole.staff,
          );
      await expectLater(
        coordinator.submit(attempt),
        throwsA(
          isA<AdminInvitationFailure>().having(
            (value) => value.outcome,
            'duplicate',
            AdminInvitationOutcome.existingRequest,
          ),
        ),
      );
      expect(coordinator.pending, hasLength(1));
      expect(attempt.completed, isFalse);
      expect(attempt.receipt?.requestId, serverRequest);
      expect(attempt.receipt?.duplicate, isTrue);
      expect(
        () => coordinator.prepareInvite(
          'other@example.test',
          AdminAccountRole.staff,
        ),
        throwsA(isA<AdminAccountException>()),
      );
      final result = await coordinator.lookup(attempt);
      expect(result.receipt?.duplicate, isTrue);
      expect(attempt.completed, isTrue);
      expect(posts, 1);
      expect(reads, 1);
    },
  );

  for (final notification in [false, true]) {
    test(
      'known ${notification ? 'registered account' : 'rejection'} settles without inbox or access grant',
      () async {
        var calls = 0;
        final h = await harness((_) async {
          calls++;
          return reply({
            'ok': false,
            ...receipt(
              status: notification ? 'already_registered' : 'rejected',
            ),
            'outcome': notification
                ? 'notification_pending'
                : 'delivery_rejected',
            'error': {
              'code': notification
                  ? 'invitation_notification_required'
                  : 'invitation_rejected',
            },
          }, notification ? 409 : 422);
        });
        final coordinator = h.coordinator(),
            attempt = coordinator.prepareInvite(
              'synthetic@example.test',
              AdminAccountRole.staff,
            );
        await expectLater(
          coordinator.submit(attempt),
          throwsA(isA<AdminInvitationFailure>()),
        );
        expect(attempt.completed, isTrue);
        expect(coordinator.pending, isEmpty);
        expect(attempt.receipt?.accessStatus, AdminAccountStatus.invited);
        expect(
          attempt.receipt?.emailStatus,
          notification
              ? AdminInvitationEmailStatus.alreadyRegistered
              : AdminInvitationEmailStatus.rejected,
        );
        expect(calls, 1);
      },
    );
  }

  for (final invalid in [
    {'emailStatus': 'future_state'},
    {'requestId': 'not-a-server-uuid'},
    {'operation': 'resend'},
    {'duplicate': 'false'},
    {'accessStatus': 'accepted'},
  ]) {
    test(
      'malformed or mismatched success ${invalid.keys.single} never settles',
      () async {
        final h = await harness(
          (_) async => reply({
            'ok': true,
            ...receipt(),
            ...invalid,
            'outcome': 'accepted',
          }),
        );
        final coordinator = h.coordinator(),
            attempt = coordinator.prepareInvite(
              'synthetic@example.test',
              AdminAccountRole.staff,
            );
        await expectLater(
          coordinator.submit(attempt),
          throwsA(isA<AdminInvitationFailure>()),
        );
        expect(coordinator.pending, hasLength(1));
        expect(attempt.canRetry, isFalse);
      },
    );
  }

  test(
    'non-200 success cannot satisfy the managed invitation contract',
    () async {
      final h = await harness(
        (_) async =>
            reply({'ok': true, ...receipt(), 'outcome': 'accepted'}, 201),
      );
      final coordinator = h.coordinator(),
          attempt = coordinator.prepareInvite(
            'synthetic@example.test',
            AdminAccountRole.staff,
          );
      await expectLater(
        coordinator.submit(attempt),
        throwsA(isA<AdminInvitationFailure>()),
      );
      expect(attempt.completed, isFalse);
    },
  );

  test('malformed GET and unknown receipt never enable replay', () async {
    var mode = 0, posts = 0;
    final h = await harness((request) async {
      if (request.method == 'POST') {
        posts++;
        throw http.ClientException('lost');
      }
      return mode == 0
          ? reply({'ok': true, 'found': false, 'unexpected': 'not-qualified'})
          : reply({'ok': true, 'found': true, ...receipt(status: 'unknown')});
    });
    final coordinator = h.coordinator(),
        attempt = coordinator.prepareInvite(
          'synthetic@example.test',
          AdminAccountRole.staff,
        );
    await expectLater(
      coordinator.submit(attempt),
      throwsA(isA<AdminInvitationFailure>()),
    );
    await expectLater(
      coordinator.lookup(attempt),
      throwsA(isA<AdminInvitationFailure>()),
    );
    expect(attempt.canRetry, isFalse);
    mode = 1;
    await coordinator.lookup(attempt);
    expect(attempt.canRetry, isFalse);
    expect(attempt.completed, isFalse);
    expect(posts, 1);
  });

  test(
    'double click cannot dispatch twice while the original POST is in flight',
    () async {
      final arrived = Completer<void>(), answer = Completer<http.Response>();
      var posts = 0;
      final h = await harness((_) async {
        posts++;
        arrived.complete();
        return answer.future;
      });
      final coordinator = h.coordinator(),
          attempt = coordinator.prepareInvite(
            'synthetic@example.test',
            AdminAccountRole.staff,
          );
      final sending = coordinator.submit(attempt);
      await arrived.future;
      await expectLater(
        coordinator.submit(attempt),
        throwsA(isA<AdminAccountException>()),
      );
      expect(posts, 1);
      answer.complete(reply({'ok': true, ...receipt(), 'outcome': 'accepted'}));
      await sending;
      expect(attempt.completed, isTrue);
    },
  );

  test('new session and A-to-B-to-A cannot revive old work', () async {
    var calls = 0;
    final h = await harness((_) async {
      calls++;
      throw http.ClientException('lost');
    });
    final coordinator = h.coordinator(),
        attempt = coordinator.prepareInvite(
          'synthetic@example.test',
          AdminAccountRole.staff,
        );
    await expectLater(
      coordinator.submit(attempt),
      throwsA(isA<AdminInvitationFailure>()),
    );
    h.session.clear();
    h.store.bind(null);
    await h.session.refresh();
    h.store.bind(h.session.user);
    await expectLater(
      coordinator.lookup(attempt),
      throwsA(isA<AdminAccountException>()),
    );
    expect(calls, 1);
    expect(h.coordinator().pending, isEmpty);
    // Current store security clears on logout; this is not cross-login recovery.
  });

  for (final phase in ['submit', 'lookup']) {
    test(
      'late $phase after logout-relogin ABA cannot settle or clear replacement checkpoint',
      () async {
        final arrived = Completer<void>(), answer = Completer<http.Response>();
        final requests = <http.Request>[];
        const originalKey = 'client-old-authority-invitation-key';
        const replacementKey = 'client-replacement-invitation-key';
        final h = await harness((request) async {
          requests.add(request);
          if (request.headers['Idempotency-Key'] == replacementKey) {
            throw http.ClientException(
              'Synthetic replacement acknowledgment lost',
            );
          }
          if (phase == 'lookup' && request.method == 'POST') {
            throw http.ClientException(
              'Synthetic original acknowledgment lost',
            );
          }
          arrived.complete();
          return answer.future;
        });
        final original = h.coordinator(key: () => originalKey);
        final attempt = original.prepareInvite(
          'synthetic@example.test',
          AdminAccountRole.staff,
        );
        final Future<void> rejected;
        if (phase == 'submit') {
          rejected = expectLater(
            original.submit(attempt),
            throwsA(isA<AdminAccountException>()),
          );
        } else {
          await expectLater(
            original.submit(attempt),
            throwsA(isA<AdminInvitationFailure>()),
          );
          rejected = expectLater(
            original.lookup(attempt),
            throwsA(isA<AdminAccountException>()),
          );
        }
        await arrived.future;
        final oldFence = h.api.invitationAuthorityFence;
        h.session.clear();
        h.store.bind(null);
        await h.session.refresh();
        h.store.bind(h.session.user);
        final currentUser = h.session.user;
        final currentFence = h.api.invitationAuthorityFence;
        expect(currentFence, isNot(oldFence));
        final replacement = h.coordinator(key: () => replacementKey);
        final retained = replacement.prepareInvite(
          'synthetic@example.test',
          AdminAccountRole.staff,
        );
        // Retain the same resource under the new authority, then lose its POST
        // acknowledgment. The old completion must not delete this checkpoint.
        await expectLater(
          replacement.submit(retained),
          throwsA(isA<AdminInvitationFailure>()),
        );
        final storage = h.storage as MemoryAdminPendingAttemptStorage;
        final beforeLateResponse = jsonEncode(storage.values);
        expect(beforeLateResponse, contains(replacementKey));
        expect(beforeLateResponse, isNot(contains(originalKey)));
        answer.complete(
          phase == 'submit'
              ? reply({'ok': true, ...receipt(), 'outcome': 'accepted'})
              : reply({'ok': true, 'found': true, ...receipt()}),
        );
        await rejected;
        expect(h.session.user, same(currentUser));
        expect(h.api.invitationAuthorityFence, currentFence);
        expect(original.isCurrent, isFalse);
        expect(attempt.completed, isFalse);
        expect(attempt.receipt, isNull);
        expect(attempt.canRetry, isFalse);
        expect(jsonEncode(storage.values), beforeLateResponse);
        expect(replacement.pending.single, same(retained));
        expect(retained.completed, isFalse);
        expect(retained.intent.requestKey, replacementKey);
        expect(requests.where((row) => row.method == 'POST'), hasLength(2));
        expect(
          requests.where((row) => row.method == 'GET'),
          hasLength(phase == 'lookup' ? 1 : 0),
        );
      },
    );
  }

  test(
    'resend duplicate alias retains requested operation while GET resolves original invite requestId',
    () async {
      const aliasKey = 'client-explicit-resend-alias-key';
      final requests = <http.Request>[];
      final h = await harness((request) async {
        requests.add(request);
        expect(request.headers['Idempotency-Key'], aliasKey);
        if (request.method == 'GET') {
          expect(request.url.path.endsWith('/team/invitation-status'), isTrue);
          expect(request.body, isEmpty);
          return reply({
            'ok': true,
            'found': true,
            ...receipt(operation: 'resend', duplicate: true),
          });
        }
        expect(request.url.path.endsWith('/team/$staffId/resend'), isTrue);
        expect(jsonDecode(request.body), isEmpty);
        return reply({
          'ok': false,
          ...receipt(operation: 'resend', duplicate: true),
          'outcome': 'existing_request',
          'error': {'code': 'invitation_existing_request'},
        }, 409);
      });
      final coordinator = h.coordinator(key: () => aliasKey);
      const member = AdminAccountMember(
        id: staffId,
        email: 'synthetic@example.test',
        role: AdminAccountRole.staff,
        status: AdminAccountStatus.invited,
        emailStatus: 'accepted',
        invitationRequestId: serverRequest,
        invitationOperation: AdminInvitationOperation.invite,
      );
      final attempt = coordinator.prepareResend(member);
      expect(attempt.intent.priorRequestId, serverRequest);
      expect(attempt.intent.priorOperation, AdminInvitationOperation.invite);
      await expectLater(
        coordinator.submit(attempt),
        throwsA(
          isA<AdminInvitationFailure>().having(
            (value) => value.outcome,
            'duplicate alias',
            AdminInvitationOutcome.existingRequest,
          ),
        ),
      );
      expect(attempt.completed, isFalse);
      expect(attempt.canRetry, isFalse);
      expect(coordinator.pending.single, same(attempt));
      expect(attempt.receipt?.requestId, serverRequest);
      expect(attempt.receipt?.operation, AdminInvitationOperation.resend);
      expect(attempt.receipt?.duplicate, isTrue);
      await expectLater(
        coordinator.submit(attempt),
        throwsA(isA<AdminAccountException>()),
      );
      expect(requests, hasLength(1));
      final found = await coordinator.lookup(attempt);
      expect(found.receipt?.requestId, serverRequest);
      expect(found.receipt?.operation, AdminInvitationOperation.resend);
      expect(found.receipt?.duplicate, isTrue);
      expect(found.receipt?.accessStatus, AdminAccountStatus.invited);
      expect(
        found.receipt?.statusMessage,
        'Original invitation accepted for sending. Inbox delivery is not confirmed.',
      );
      expect(attempt.completed, isTrue);
      expect(coordinator.pending, isEmpty);
      expect((h.storage as MemoryAdminPendingAttemptStorage).values, isEmpty);
      expect(requests.where((row) => row.method == 'POST'), hasLength(1));
      expect(requests.where((row) => row.method == 'GET'), hasLength(1));
      // The backend exposes p_attempt.kind (resend), even when requestId resolves
      // an original invite. A successful GET is recovery, not another send.
    },
  );

  test('failed storage acknowledgement prevents POST', () async {
    var calls = 0;
    final h = await harness((_) async {
      calls++;
      return reply({});
    }, storage: _UnacknowledgedStorage());
    final coordinator = h.coordinator(),
        attempt = coordinator.prepareInvite(
          'synthetic@example.test',
          AdminAccountRole.staff,
        );
    await expectLater(
      coordinator.submit(attempt),
      throwsA(isA<AdminAccountException>()),
    );
    expect(calls, 0);
    expect(h.store.storageAvailable, isFalse);
    expect(
      coordinator.pending.single.intent.requestKey,
      attempt.intent.requestKey,
    );
  });

  for (final denied in ['role', 'permission', 'email', 'team']) {
    test(
      '$denied admission prevents preparation and network dispatch',
      () async {
        var calls = 0, keys = 0;
        final h = await harness(
          (_) async {
            calls++;
            return reply({});
          },
          account: () {
            final value = owner(), user = value['user'] as Map<String, dynamic>;
            if (denied == 'role') user['role'] = 'admin';
            if (denied == 'permission') user['permissions'] = <String>[];

            return value;
          },
          proofAge: denied == 'email'
              ? const Duration(minutes: 6)
              : const Duration(seconds: 1),
        );
        final coordinator = h.coordinator(
          canManage: () => denied != 'team',
          key: () {
            keys++;
            return 'unexpected-new-request-key';
          },
        );
        expect(
          () => coordinator.prepareInvite(
            'synthetic@example.test',
            AdminAccountRole.staff,
          ),
          throwsA(isA<AdminAccountException>()),
        );
        expect(calls, 0);
        expect(keys, 0);
      },
    );
  }

  test(
    'new resend requires known history, retains prior reference and sends exact empty body',
    () async {
      final storage = MemoryAdminPendingAttemptStorage();
      var calls = 0;
      final h = await harness((request) async {
        calls++;
        expect(request.url.path.endsWith('/team/$staffId/resend'), isTrue);
        expect(jsonDecode(request.body), isEmpty);
        expect(storage.values.values.single, contains('prior_request_id'));
        expect(
          storage.values.values.single,
          contains('10000000-0000-4000-8000-000000000004'),
        );
        return reply({
          'ok': true,
          ...receipt(operation: 'resend'),
          'outcome': 'accepted',
        });
      }, storage: storage);
      final coordinator = h.coordinator();
      for (final status in [null, 'unknown', 'already_registered']) {
        final member = AdminAccountMember(
          id: staffId,
          email: 'synthetic@example.test',
          role: AdminAccountRole.staff,
          status: AdminAccountStatus.invited,
          emailStatus: status,
          invitationRequestId: '10000000-0000-4000-8000-000000000004',
          invitationOperation: AdminInvitationOperation.invite,
        );
        expect(coordinator.canResend(member), isFalse);
        expect(
          () => coordinator.prepareResend(member),
          throwsA(isA<AdminAccountException>()),
        );
      }
      const member = AdminAccountMember(
        id: staffId,
        email: 'synthetic@example.test',
        role: AdminAccountRole.staff,
        status: AdminAccountStatus.invited,
        emailStatus: 'rejected',
        invitationRequestId: '10000000-0000-4000-8000-000000000004',
        invitationOperation: AdminInvitationOperation.invite,
      );
      await coordinator.submit(coordinator.prepareResend(member));
      expect(calls, 1);
    },
  );
}

class _UnacknowledgedStorage implements AdminPendingAttemptStorage {
  @override
  String? read(String key) => null;
  @override
  void write(String key, String value) {}
  @override
  void remove(String key) {}
}
