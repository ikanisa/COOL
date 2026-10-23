import 'dart:async';
import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_invitation_recovery.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/cloudflare_admin_account_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'admin_invitation_recovery_test.dart' as v1;

const staffId = v1.staffId;
const serverRequest = v1.serverRequest;
const repairRequest = '10000000-0000-4000-8000-000000000004';
Map<String, dynamic> receipt({
  String kind = 'access_notice',
  String status = 'accepted',
  String operation = 'invite',
  bool duplicate = false,
  String requestId = serverRequest,
  String? sourceRequestId,
}) => {
  'contractVersion': 2,
  'id': staffId,
  'requestId': requestId,
  'messageKind': kind,
  if (kind == 'auth_invite') 'emailStatus': status else 'noticeStatus': status,
  'accessStatus': 'invited',
  'operation': operation,
  'replayed': false,
  'duplicate': duplicate,
  'sourceRequestId': sourceRequestId,
};
Map<String, dynamic> failure(
  String outcome,
  String code,
  Map<String, dynamic> value,
) => {
  'ok': false,
  ...value,
  'outcome': outcome,
  'error': {'code': code, 'message': 'RAW_PROVIDER_DO_NOT_RENDER'},
};

Future<v1.Harness> harness(
  Future<http.Response> Function(http.Request) send, {
  AdminPendingAttemptStorage? storage,
  Map<String, dynamic> Function()? account,
  Duration? proofAge = const Duration(seconds: 1),
}) async {
  final old = await v1.harness(
    send,
    storage: storage,
    account: account,
    proofAge: proofAge,
  );
  return v1.Harness(
    old.session,
    CloudflareAdminAccountApi(old.session),
    old.store,
    old.storage,
  );
}

AdminAccountMember member(Map<String, dynamic> value) => AdminAccountMember(
  id: staffId,
  email: 'synthetic@example.test',
  role: AdminAccountRole.staff,
  status: AdminAccountStatus.invited,
  invitation: AdminInvitationReceipt.parse(value, contractVersion: 2),
);

Map<String, dynamic> team({Map<String, dynamic>? invitation}) => {
  'contractVersion': 2,
  'currentEmail': 'info@ikanisa.com',
  'canManage': true,
  'permissionsByRole': {
    'owner': ['admin_users.manage', 'admin_users.read'],
    'admin': <String>[],
    'staff': <String>[],
  },
  'members': [
    {
      'id': staffId,
      'email': 'synthetic@example.test',
      'role': 'staff',
      'status': 'invited',
      'displayName': 'Synthetic Teammate',
      'createdAt': '2026-10-20T10:00:00Z',
      'invitedAt': '2026-10-20T10:00:00Z',
      'acceptedAt': null,
      'invitation': invitation,
    },
  ],
};

void main() {
  for (final kind in ['auth_invite', 'access_notice']) {
    test(
      'ordinary Add Staff retains v2 original intent; server selects $kind without extra mutation',
      () async {
        final calls = <http.Request>[],
            storage = MemoryAdminPendingAttemptStorage();
        final h = await harness((request) async {
          calls.add(request);
          expect(request.url.path.endsWith('/team/v2/invite'), isTrue);
          final saved = jsonDecode(storage.values.values.single) as Map;
          expect(jsonEncode(saved), contains('contract_version'));
          expect(jsonEncode(saved), contains('team/v2/invite'));
          expect(jsonEncode(saved), contains('client-original-v2-request'));
          expect(jsonDecode(request.body), {
            'email': 'synthetic@example.test',
            'role': 'staff',
            'displayName': 'Synthetic Teammate',
          });
          expect(request.headers['X-Collect-CSRF'], isNotEmpty);
          return v1.reply({
            'ok': true,
            ...receipt(kind: kind),
            'outcome': 'accepted',
          });
        }, storage: storage);
        final c = h.coordinator(key: () => 'client-original-v2-request');
        final attempt = c.prepareInvite(
          ' Synthetic@Example.test ',
          AdminAccountRole.staff,
          displayName: ' Synthetic Teammate ',
        );
        expect(attempt.intent.contractVersion, 2);
        expect(
          attempt.intent.body.keys,
          unorderedEquals(['email', 'role', 'displayName']),
        );
        final value = await c.submit(attempt);
        expect(calls, hasLength(1));
        expect(attempt.completed, isTrue);
        if (kind == 'access_notice') {
          expect(value.message, isA<AdminAccessNoticeMessage>());
          expect(value.emailStatus, isNull);
          expect(value.noticeStatus, AdminAccessNoticeStatus.accepted);
          expect(
            value.statusMessage,
            contains('Original access notice accepted for sending'),
          );
          expect(
            value.statusMessage,
            isNot(contains('Original invitation accepted')),
          );
        } else {
          expect(value.message, isA<AdminNativeInvitationMessage>());
          expect(value.noticeStatus, isNull);
          expect(value.emailStatus, AdminInvitationEmailStatus.accepted);
        }
        expect(value.statusMessage, contains('not confirmed'));
      },
    );
  }

  test(
    'lost v2 POST reloads original version/key/path/body; found:false needs explicit same-key retry',
    () async {
      final calls = <http.Request>[],
          storage = MemoryAdminPendingAttemptStorage();
      var posts = 0, keys = 0;
      final h = await harness((request) async {
        calls.add(request);
        if (request.method == 'GET') {
          return v1.reply({'ok': true, 'contractVersion': 2, 'found': false});
        }
        if (++posts == 1) throw http.ClientException('lost synthetic response');
        return v1.reply({'ok': true, ...receipt(), 'outcome': 'accepted'});
      }, storage: storage);
      final c = h.coordinator(
        key: () {
          keys++;
          return 'v2-original-lost-request';
        },
      );
      final first = c.prepareInvite(
        'synthetic@example.test',
        AdminAccountRole.staff,
      );
      await expectLater(
        c.submit(first),
        throwsA(isA<AdminInvitationFailure>()),
      );
      final restoredStore = AdminPendingAttemptStore(storage: storage)
        ..bind(h.session.user);
      addTearDown(restoredStore.dispose);
      final restored = h.coordinator(
        using: restoredStore,
        key: () => throw StateError('No rotated key'),
      );
      final pending = restored.pending.single;
      expect(pending.intent.contractVersion, 2);
      expect(pending.intent.path, 'team/v2/invite');
      expect(keys, 1);
      expect(calls, hasLength(1));
      await expectLater(
        restored.submit(pending),
        throwsA(isA<AdminAccountException>()),
      );
      expect((await restored.lookup(pending)).found, isFalse);
      expect(pending.canRetry, isTrue);
      expect(
        calls.last.url.path.endsWith('/team/v2/invitation-status'),
        isTrue,
      );
      await expectLater(
        restored.submit(pending),
        throwsA(isA<AdminAccountException>()),
      );
      await restored.submit(pending, confirmedSameIntentRetry: true);
      final sent = calls.where((r) => r.method == 'POST').toList();
      expect(sent, hasLength(2));
      expect(sent.first.body, sent.last.body);
      expect(sent.first.url, sent.last.url);
      expect(calls.map((r) => r.headers['Idempotency-Key']).toSet(), {
        'v2-original-lost-request',
      });
    },
  );

  test(
    'V2 coordinator restores immutable V1 intent and uses only original V1 GET',
    () async {
      final calls = <http.Request>[];
      final old = await v1.harness((request) async {
        calls.add(request);
        if (request.method == 'POST') {
          throw http.ClientException('lost V1 acknowledgment');
        }
        return v1.reply({'ok': true, 'found': true, ...v1.receipt()});
      });
      final original = old.coordinator(key: () => 'historical-v1-original-key');
      final attempt = original.prepareInvite(
        'synthetic@example.test',
        AdminAccountRole.staff,
      );
      await expectLater(
        original.submit(attempt),
        throwsA(isA<AdminInvitationFailure>()),
      );
      final storage = old.storage as MemoryAdminPendingAttemptStorage;
      final before = storage.values.values.single;
      expect(before, isNot(contains('contract_version')));
      final fresh = AdminInvitationCoordinator(
        api: CloudflareAdminAccountApi(old.session),
        store: old.store,
        canManageTeam: () => true,
        requestKey: () => throw StateError('No migration key'),
      );
      final retained = fresh.pending.single;
      expect(retained.intent.contractVersion, 1);
      expect(retained.intent.path, 'team/invite');
      expect(storage.values.values.single, before);
      await fresh.lookup(retained);
      expect(calls.last.url.path.endsWith('/team/invitation-status'), isTrue);
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(retained.completed, isTrue);
    },
  );

  test(
    'known unavailable notice transport permits only explicit same-intent retry, not new key',
    () async {
      final calls = <http.Request>[];
      var posts = 0;
      final h = await harness((request) async {
        calls.add(request);
        if (++posts == 1) {
          return v1.reply(
            failure(
              'transport_unavailable',
              'invitation_transport_unavailable',
              receipt(status: 'unknown'),
            ),
            503,
          );
        }
        return v1.reply({'ok': true, ...receipt(), 'outcome': 'accepted'});
      });
      final c = h.coordinator(),
          a = c.prepareInvite('synthetic@example.test', AdminAccountRole.staff);
      await expectLater(
        c.submit(a),
        throwsA(
          isA<AdminInvitationFailure>().having(
            (e) => e.outcome,
            'typed no-claim',
            AdminInvitationOutcome.transportUnavailable,
          ),
        ),
      );
      expect(a.canRetry, isTrue);
      expect(a.message, contains('No send was started'));
      expect(a.message, isNot(contains('RAW_PROVIDER')));
      expect(
        () => c.prepareInvite('different@example.test', AdminAccountRole.staff),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(c.submit(a), throwsA(isA<AdminAccountException>()));
      await c.submit(a, confirmedSameIntentRetry: true);
      expect(calls, hasLength(2));
      expect(calls.first.body, calls.last.body);
      expect(
        calls.first.headers['Idempotency-Key'],
        calls.last.headers['Idempotency-Key'],
      );
      expect(a.receipt!.message, isA<AdminAccessNoticeMessage>());
      expect(a.completed, isTrue);
      expect(a.message, isNot(contains('unavailable')));
    },
  );

  test(
    'unknown GET after reload cannot reconstruct definite preclaim-unavailable evidence',
    () async {
      var posts = 0, gets = 0;
      final h = await harness((request) async {
        if (request.method == 'GET') {
          gets++;
          return v1.reply({
            'ok': true,
            'found': true,
            ...receipt(status: 'unknown'),
          });
        }
        posts++;
        return v1.reply(
          failure(
            'transport_unavailable',
            'invitation_transport_unavailable',
            receipt(status: 'unknown'),
          ),
          503,
        );
      });
      final c = h.coordinator(),
          a = c.prepareInvite('synthetic@example.test', AdminAccountRole.staff);
      await expectLater(c.submit(a), throwsA(isA<AdminInvitationFailure>()));
      expect(a.canRetry, isTrue);
      final restoredStore = AdminPendingAttemptStore(storage: h.storage)
        ..bind(h.session.user);
      addTearDown(restoredStore.dispose);
      final restored = h.coordinator(
        using: restoredStore,
        key: () => throw StateError('No new key'),
      );
      final pending = restored.pending.single;
      await restored.lookup(pending);
      expect(pending.canRetry, isFalse);
      expect(pending.completed, isFalse);
      await expectLater(
        restored.submit(pending, confirmedSameIntentRetry: true),
        throwsA(isA<AdminAccountException>()),
      );
      expect(posts, 1);
      expect(gets, 1);
    },
  );

  test(
    'resend duplicate resolves original send but preserves requested operation and read-only recovery',
    () async {
      final calls = <http.Request>[];
      final h = await harness((request) async {
        calls.add(request);
        final value = receipt(operation: 'resend', duplicate: true);
        if (request.method == 'GET') {
          return v1.reply({'ok': true, 'found': true, ...value});
        }
        expect(request.url.path.endsWith('/team/v2/$staffId/resend'), isTrue);
        expect(jsonDecode(request.body), isEmpty);
        return v1.reply(
          failure('existing_request', 'invitation_existing_request', value),
          409,
        );
      });
      final c = h.coordinator();
      final a = c.prepareResend(member(receipt()));
      await expectLater(
        c.submit(a),
        throwsA(
          isA<AdminInvitationFailure>().having(
            (e) => e.outcome,
            'duplicate',
            AdminInvitationOutcome.existingRequest,
          ),
        ),
      );
      expect(a.completed, isFalse);
      expect(a.canRetry, isFalse);
      await c.lookup(a);
      expect(a.completed, isTrue);
      expect(a.receipt!.operation, AdminInvitationOperation.resend);
      expect(a.receipt!.requestId, serverRequest);
      expect(a.receipt!.messageKind, AdminInvitationMessageKind.accessNotice);
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(calls.last.method, 'GET');
    },
  );

  test(
    'only historical already_registered enables explicit notice repair with immutable source lineage',
    () async {
      final calls = <http.Request>[];
      final h = await harness((request) async {
        calls.add(request);
        expect(
          request.url.path.endsWith('/team/v2/$staffId/access-notice'),
          isTrue,
        );
        expect(jsonDecode(request.body), {'sourceRequestId': serverRequest});
        return v1.reply({
          'ok': true,
          ...receipt(
            operation: 'notice_repair',
            requestId: repairRequest,
            sourceRequestId: serverRequest,
          ),
          'outcome': 'accepted',
        });
      });
      final c = h.coordinator();
      final historical = member(
        receipt(kind: 'auth_invite', status: 'already_registered'),
      );
      expect(c.canRepairNotice(historical), isTrue);
      expect(c.canResend(historical), isFalse);
      expect(c.canRepairNotice(member(receipt(status: 'unknown'))), isFalse);
      expect(c.canRepairNotice(member(receipt())), isFalse);
      expect(calls, isEmpty);
      final a = c.prepareNoticeRepair(historical);
      expect(a.intent.body, {'sourceRequestId': serverRequest});
      expect(a.intent.checkpoint['contract_version'], 2);
      expect(a.intent.priorRequestId, serverRequest);
      final result = await c.submit(a);
      expect(result.sourceRequestId, serverRequest);
      expect(result.requestId, repairRequest);
      expect(result.operation, AdminInvitationOperation.noticeRepair);
      expect(calls, hasLength(1));
    },
  );

  for (final bad in [
    'mixed statuses',
    'wrong kind',
    'v1 envelope',
    'numeric version',
    'missing lineage',
    'wrong operation',
    'false acceptance',
    'non200',
    'malformed JSON',
  ]) {
    test(
      'actual v2 transport refuses $bad without settling original checkpoint',
      () async {
        final h = await harness((request) async {
          final value = receipt();
          switch (bad) {
            case 'mixed statuses':
              value['emailStatus'] = 'accepted';
              break;
            case 'wrong kind':
              value['messageKind'] = 'auth_invite';
              break;
            case 'v1 envelope':
              value.remove('contractVersion');
              break;
            case 'numeric version':
              value['contractVersion'] = 2.0;
              break;
            case 'missing lineage':
              value.remove('sourceRequestId');
              break;
            case 'wrong operation':
              value['operation'] = 'resend';
              break;
            case 'false acceptance':
              value['noticeStatus'] = 'unknown';
              break;
            default:
              break;
          }
          if (bad == 'malformed JSON') return http.Response('{raw broken', 200);
          return v1.reply({
            'ok': true,
            ...value,
            'outcome': 'accepted',
          }, bad == 'non200' ? 201 : 200);
        });
        final c = h.coordinator(),
            a = c.prepareInvite(
              'synthetic@example.test',
              AdminAccountRole.staff,
            );
        await expectLater(c.submit(a), throwsA(isA<AdminInvitationFailure>()));
        expect(a.completed, isFalse);
        expect(a.canRetry, isFalse);
        expect(c.pending.single, same(a));
        expect(
          (h.storage as MemoryAdminPendingAttemptStorage).values,
          isNotEmpty,
        );
      },
    );
  }

  for (final phase in ['submit', 'lookup']) {
    test(
      'late V2 $phase after logout/relogin ABA cannot clear replacement checkpoint or session',
      () async {
        final arrived = Completer<void>(), answer = Completer<http.Response>();
        final h = await harness((request) async {
          if (request.headers['Idempotency-Key'] ==
                  'replacement-v2-original-key' ||
              phase == 'lookup' && request.method == 'POST') {
            throw http.ClientException('lost synthetic ack');
          }
          arrived.complete();
          return answer.future;
        });
        final c = h.coordinator(key: () => 'old-v2-original-key'),
            a = c.prepareInvite(
              'synthetic@example.test',
              AdminAccountRole.staff,
            );
        final Future<void> rejected;
        if (phase == 'submit') {
          rejected = expectLater(
            c.submit(a),
            throwsA(isA<AdminAccountException>()),
          );
        } else {
          await expectLater(
            c.submit(a),
            throwsA(isA<AdminInvitationFailure>()),
          );
          rejected = expectLater(
            c.lookup(a),
            throwsA(isA<AdminAccountException>()),
          );
        }
        await arrived.future;
        final oldFence = h.api.invitationAuthorityFence;
        h.session.clear();
        h.store.bind(null);
        await h.session.refresh();
        h.store.bind(h.session.user);
        final currentUser = h.session.user,
            currentFence = h.api.invitationAuthorityFence;
        expect(currentFence, isNot(oldFence));
        final replacement = h.coordinator(
          key: () => 'replacement-v2-original-key',
        );
        final next = replacement.prepareInvite(
          'synthetic@example.test',
          AdminAccountRole.staff,
        );
        await expectLater(
          replacement.submit(next),
          throwsA(isA<AdminInvitationFailure>()),
        );
        final storage = h.storage as MemoryAdminPendingAttemptStorage,
            before = jsonEncode(
              (h.storage as MemoryAdminPendingAttemptStorage).values,
            );
        answer.complete(
          v1.reply(
            phase == 'submit'
                ? {'ok': true, ...receipt(), 'outcome': 'accepted'}
                : {'ok': true, 'found': true, ...receipt()},
          ),
        );
        await rejected;
        expect(h.session.user, same(currentUser));
        expect(h.api.invitationAuthorityFence, currentFence);
        expect(a.completed, isFalse);
        expect(a.receipt, isNull);
        expect(jsonEncode(storage.values), before);
        expect(replacement.pending.single, same(next));
        expect(next.completed, isFalse);
      },
    );
  }

  test(
    'actual v2 overview preserves typed notice history without populating native email status',
    () async {
      final calls = <http.Request>[];
      final h = await harness((request) async {
        calls.add(request);
        return v1.reply(team(invitation: receipt()));
      });
      final value = await h.api.loadTeam();
      expect(calls.single.url.path.endsWith('/team/v2'), isTrue);
      expect(value.members.single.emailStatus, isNull);
      expect(
        value.members.single.invitation!.message,
        isA<AdminAccessNoticeMessage>(),
      );
      expect(h.coordinator().canResend(value.members.single), isTrue);
    },
  );

  test(
    'unknown native receipt cannot switch to an access notice on the original key',
    () async {
      var posts = 0;
      final h = await harness((request) async {
        if (request.method == 'POST') {
          posts++;
          return v1.reply(
            failure(
              'delivery_unknown',
              'invitation_delivery_unknown',
              receipt(kind: 'auth_invite', status: 'unknown'),
            ),
            503,
          );
        }
        return v1.reply({'ok': true, 'found': true, ...receipt()});
      });
      final c = h.coordinator(),
          a = c.prepareInvite('synthetic@example.test', AdminAccountRole.staff);
      await expectLater(c.submit(a), throwsA(isA<AdminInvitationFailure>()));
      expect(a.receipt!.messageKind, AdminInvitationMessageKind.authInvite);
      await expectLater(c.lookup(a), throwsA(isA<AdminInvitationFailure>()));
      expect(a.receipt!.messageKind, AdminInvitationMessageKind.authInvite);
      expect(a.completed, isFalse);
      expect(a.canRetry, isFalse);
      expect(posts, 1);
    },
  );

  test(
    'repair cannot accept a different sourceRequestId even when send status is accepted',
    () async {
      final h = await harness(
        (request) async => v1.reply({
          'ok': true,
          ...receipt(
            operation: 'notice_repair',
            requestId: repairRequest,
            sourceRequestId: repairRequest,
          ),
          'outcome': 'accepted',
        }),
      );
      final c = h.coordinator(),
          a = c.prepareNoticeRepair(
            member(receipt(kind: 'auth_invite', status: 'already_registered')),
          );
      await expectLater(c.submit(a), throwsA(isA<AdminInvitationFailure>()));
      expect(a.completed, isFalse);
      expect(a.receipt, isNull);
      expect(c.pending.single, same(a));
    },
  );

  test(
    'V2 new intent is still refused for stale owner email proof before HTTP or persistence',
    () async {
      var calls = 0;
      final h = await harness((_) async {
        calls++;
        throw StateError('No authority');
      }, proofAge: const Duration(minutes: 6));
      final c = h.coordinator();
      expect(c.authorized, isFalse);
      expect(
        () => c.prepareInvite('synthetic@example.test', AdminAccountRole.staff),
        throwsA(isA<AdminAccountException>()),
      );
      expect(calls, 0);
      expect((h.storage as MemoryAdminPendingAttemptStorage).values, isEmpty);
    },
  );

  test(
    'lost V2 GET preserves original checkpoint and cannot permit retry or a new request key',
    () async {
      var posts = 0, gets = 0;
      final h = await harness((request) async {
        if (request.method == 'POST') {
          posts++;
        } else {
          gets++;
        }
        throw http.ClientException('synthetic missing POST or GET body');
      });
      final c = h.coordinator(key: () => 'v2-original-lost-status-key');
      final a = c.prepareInvite(
        'synthetic@example.test',
        AdminAccountRole.staff,
      );
      await expectLater(c.submit(a), throwsA(isA<AdminInvitationFailure>()));
      final before = jsonEncode(
        (h.storage as MemoryAdminPendingAttemptStorage).values,
      );
      await expectLater(c.lookup(a), throwsA(isA<AdminInvitationFailure>()));
      expect(a.canRetry, isFalse);
      expect(a.completed, isFalse);
      expect(
        jsonEncode((h.storage as MemoryAdminPendingAttemptStorage).values),
        before,
      );
      expect(
        () => c.prepareInvite('another@example.test', AdminAccountRole.staff),
        throwsA(isA<AdminAccountException>()),
      );
      await expectLater(
        c.submit(a, confirmedSameIntentRetry: true),
        throwsA(isA<AdminAccountException>()),
      );
      expect(posts, 1);
      expect(gets, 1);
      expect(c.pending.single.intent.requestKey, 'v2-original-lost-status-key');
    },
  );
}
