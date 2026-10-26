part of '../cloudflare_admin_notification_management_api_test.dart';

extension _NotificationAuthorityCases on _NotificationManagementApiSuite {
  void _registerNotificationAuthorityCases() {
    test('Supabase Owner uses recent email proof at truthful AAL1', () async {
      final fresh = _Fixture(supabase: true);
      fresh.permissions = ['admin_users.manage'];
      await fresh.open();
      try {
        expect(fresh.session.user!.assuranceLevel, 1);
        expect(fresh.session.user!.mfaAt, isNull);
        expect(fresh.session.user!.usesEmailVerification, isTrue);
        expect(fresh.api.canManageAccess, isTrue);
        expect(fresh.api.canManagePolicy, isFalse);
        expect((await fresh.api.getAccess()).adminId, _admin);
        expect(
          fresh.requests.single.url.path,
          '/functions/v1/admin-api/api/admin/notification-operator/access',
        );
      } finally {
        fresh.dispose();
      }
    });

    test(
      'Supabase invalid email proof denies before management transport',
      () async {
        for (final change in <void Function(_Fixture)>[
          (f) => f.emailVerifiedAt = null,
          (f) => f.emailVerifiedAt = f.now.subtract(const Duration(minutes: 6)),
          (f) => f.emailVerifiedAt = f.now.add(const Duration(minutes: 2)),
          (f) => f.proofSession = _other,
          (f) => f.role = 'staff',
          (f) => f.email = 'other@example.test',
          (f) => f.principal = null,
          (f) => f.permissions = [],
        ]) {
          final fresh = _Fixture(supabase: true);
          change(fresh);
          await fresh.open();
          try {
            expect(fresh.api.canManageAccess, isFalse);
            await expectLater(
              fresh.api.getAccess(),
              throwsA(isA<AdminAccountException>()),
            );
            expect(fresh.requests, isEmpty);
          } finally {
            fresh.dispose();
          }
        }
      },
    );

    test(
      'Supabase email proof expiry refuses a delayed management read',
      () async {
        final fresh = _Fixture(supabase: true);
        await fresh.open();
        final pending = Completer<http.Response>();
        fresh.handler = (_) => pending.future;
        try {
          final read = fresh.api.getAccess();
          final refused = expectLater(
            read,
            throwsA(isA<AdminAccountException>()),
          );
          fresh.clock = fresh.now.add(const Duration(minutes: 6));
          pending.complete(_json({'ok': true, 'result': fresh.access()}));
          await refused;
          expect(fresh.api.canManageAccess, isFalse);
        } finally {
          fresh.dispose();
        }
      },
    );

    test(
      'same-session email renewal preserves the original management operation',
      () async {
        final fresh = _Fixture(supabase: true);
        fresh.emailVerifiedAt = fresh.now.subtract(const Duration(minutes: 1));
        await fresh.open();
        try {
          final operation = await fresh.accessOperation(enabled: false);
          final originalFence = fresh.session.authorityFence;
          final originalSession = fresh.session.user!.sessionId;
          fresh.emailVerifiedAt = fresh.now;
          await fresh.session.refresh();
          expect(fresh.session.authorityFence, originalFence);
          expect(fresh.session.user!.sessionId, originalSession);
          expect(fresh.session.user!.assuranceLevel, 1);
          expect(fresh.session.user!.mfaAt, isNull);
          final first = await fresh.api.setAccess(operation);
          final originalBody = fresh.requests.last.body;
          final replay = await fresh.api.replayAccess(operation);
          expect(replay.requestId, first.requestId);
          expect(fresh.requests.last.body, originalBody);
          expect(fresh.retained, hasLength(1));
        } finally {
          fresh.dispose();
        }
      },
    );

    test(
      'access current state requires a nonnegative safe integer decision head',
      () async {
        final missing = fixture.access()..remove('decision_revision');
        fixture.handler = (_) async => _json({'ok': true, 'result': missing});
        await expectLater(fixture.api.getAccess(), throwsFormatException);
        for (final invalid in <Object?>[
          null,
          true,
          -1,
          1.0,
          '1',
          9007199254740992,
        ]) {
          fixture.handler = (_) async => _json({
            'ok': true,
            'result': {...fixture.access(), 'decision_revision': invalid},
          });
          await expectLater(fixture.api.getAccess(), throwsFormatException);
        }
        fixture.handler = null;
        fixture.decisionRevision = 9007199254740991;
        final maximum = await fixture.api.getAccess();
        expect(maximum.decisionRevision, 9007199254740991);
        final requests = fixture.requests.length;
        expect(
          () => fixture.api.prepareAccess(
            expected: maximum,
            enabled: false,
            ownerConfirmation: false,
          ),
          throwsStateError,
        );
        expect(fixture.requests, hasLength(requests));
      },
    );

    test(
      'access operation freezes expected head and explicit replay keeps its body',
      () async {
        fixture.decisionRevision = 7;
        final state = await fixture.api.getAccess();
        final operation = fixture.api.prepareAccess(
          expected: state,
          enabled: false,
          ownerConfirmation: false,
          requestId: _request,
        );
        expect(operation.expectedDecisionRevision, 7);
        expect(operation.dispatched, isFalse);
        final receipt = await fixture.api.setAccess(operation);
        final body = fixture.requests.last.body;
        expect((jsonDecode(body) as Map)['expected_decision_revision'], 7);
        expect(receipt.decisionRevision, 8);
        fixture.decisionRevision = 11;
        expect((await fixture.api.getAccess()).decisionRevision, 11);
        final replay = await fixture.api.replayAccess(operation);
        expect(fixture.requests.last.body, body);
        expect(operation.expectedDecisionRevision, 7);
        expect(replay.decisionRevision, 8);
        expect(replay.recordedStateOnly, isTrue);
        expect((await fixture.api.getAccess()).decisionRevision, 11);
      },
    );

    test(
      'each new no-op disable decision advances while exact replay does not',
      () async {
        final firstOperation = await fixture.accessOperation(enabled: false);
        final first = await fixture.api.setAccess(firstOperation);
        expect(first.decisionRevision, 1);
        final nextState = await fixture.api.getAccess();
        expect(nextState.readGranted, isFalse);
        expect(nextState.manageGranted, isFalse);
        expect(nextState.decisionRevision, 1);
        final secondOperation = fixture.api.prepareAccess(
          expected: nextState,
          enabled: false,
          ownerConfirmation: false,
          requestId: _other,
        );
        final second = await fixture.api.setAccess(secondOperation);
        expect(second.decisionRevision, 2);
        expect(first.decisionSha256, isNot(second.decisionSha256));
        final historical = await fixture.api.replayAccess(firstOperation);
        expect(historical.decisionRevision, 1);
        expect((await fixture.api.getAccess()).decisionRevision, 2);
      },
    );

    test(
      'access receipt requires the head in its decision hash and exact original CAS',
      () async {
        final original = fixture.accessReceipt({
          'request_id': _request,
          'expected_decision_revision': 0,
          'enabled': false,
        });
        final next = fixture.accessReceipt({
          'request_id': _request,
          'expected_decision_revision': 1,
          'enabled': false,
        });
        expect(original['decision_sha256'], isNot(next['decision_sha256']));
        for (final patch in <Map<String, dynamic>>[
          {...original}..remove('decision_revision'),
          {...original, 'decision_revision': -1},
          {...original, 'decision_revision': 1.0},
          {...original, 'decision_revision': 9007199254740992},
          {...original, 'decision_revision': 2},
          next,
        ]) {
          final fresh = _Fixture();
          await fresh.open();
          try {
            final operation = await fresh.accessOperation(enabled: false);
            fresh.handler = (_) async => _json({'ok': true, 'result': patch});
            await expectLater(
              fresh.api.setAccess(operation),
              throwsA(
                isA<NotificationManagementRequestException>()
                    .having((error) => error.outcomeUnknown, 'unknown', isTrue)
                    .having(
                      (error) => identical(error.operation, operation),
                      'original operation',
                      isTrue,
                    ),
              ),
            );
          } finally {
            fresh.dispose();
          }
        }
      },
    );

    test(
      'generic notification grants cannot manage assisted SMS configuration',
      () async {
        fixture.permissions = ['notifications.read', 'notifications.manage'];
        await fixture.session.refresh();
        final api = CloudflareAdminNotificationManagementApi(fixture.session);
        expect(api.canManageAccess, isFalse);
        expect(api.canManagePolicy, isFalse);
        expect(api.canResolveOperations, isFalse);
        final before = fixture.requests.length;
        await expectLater(
          api.getPolicy(_collection),
          throwsA(isA<AdminAccountException>()),
        );
        await expectLater(
          api.getOperation(_request),
          throwsA(isA<AdminAccountException>()),
        );
        await expectLater(
          api.getAccess(),
          throwsA(isA<AdminAccountException>()),
        );
        expect(fixture.requests, hasLength(before));
      },
    );

    test(
      'owner self-access bootstrap stays independent of generic notification grants',
      () async {
        fixture.permissions = [
          'admin_users.manage',
          'notifications.read',
          'notifications.manage',
        ];
        await fixture.session.refresh();
        final api = CloudflareAdminNotificationManagementApi(fixture.session);
        expect(api.canManageAccess, isTrue);
        expect(api.canManagePolicy, isFalse);
        final state = await api.getAccess();
        final operation = api.prepareAccess(
          expected: state,
          enabled: true,
          ownerConfirmation: true,
          requestId: _request,
        );
        final receipt = await api.setAccess(operation);
        expect(receipt.enabled, isTrue);
        expect(receipt.recordedStateOnly, isTrue);
        expect(api.canManagePolicy, isFalse);
        expect(fixture.session.user!.permissions, [
          'admin_users.manage',
          'notifications.read',
          'notifications.manage',
        ]);
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': {
            ...fixture.access(),
            'permissions': ['notifications.read', 'notifications.manage'],
          },
        });
        await expectLater(api.getAccess(), throwsFormatException);
      },
    );

    test(
      'access GET and CAS POST use the actual original-cookie contract only',
      () async {
        final state = await fixture.api.getAccess();
        expect(state.readGranted, isFalse);
        final operation = fixture.api.prepareAccess(
          expected: state,
          enabled: true,
          ownerConfirmation: true,
          requestId: _request,
        );
        final receipt = await fixture.api.setAccess(operation);
        expect(receipt.recordedStateOnly, isTrue);
        expect(receipt.canOperate, isTrue);
        expect(operation.resourceId, _principal);
        final get = fixture.requests.first, post = fixture.requests.last;
        expect(get.method, 'GET');
        expect(get.body, isEmpty);
        expect(get.url.path, '/api/admin/notification-operator/access');
        expect(post.method, 'POST');
        expect(post.headers['X-Collect-Admin'], '1');
        expect(jsonDecode(post.body), {
          'request_id': _request,
          'expected_read': false,
          'expected_manage': false,
          'expected_decision_revision': 0,
          'enabled': true,
          'owner_confirmation': true,
        });
        expect(post.headers.containsKey('Authorization'), isFalse);
        expect(fixture.session.user!.permissions, [
          'admin_users.manage',
          ..._permissions,
        ]);
      },
    );

    test(
      'historical access receipt never supplies actual state or refreshes authority',
      () async {
        fixture.permissions = ['admin_users.manage'];
        await fixture.session.refresh();
        fixture.api = CloudflareAdminNotificationManagementApi(fixture.session);
        final before = fixture.session.authorityFence;
        final receipt = await fixture.api.setAccess(
          await fixture.accessOperation(),
        );
        expect(receipt.enabled, isTrue);
        expect(fixture.session.authorityFence, before);
        expect(fixture.session.user!.permissions, ['admin_users.manage']);
        expect(fixture.api.canManagePolicy, isFalse);
        expect((await fixture.api.getAccess()).canOperate, isFalse);
        expect(fixture.api.canResolveOperations, isFalse);
        final count = fixture.requests.length;
        await expectLater(
          fixture.api.getOperation(_request),
          throwsA(isA<AdminAccountException>()),
        );
        expect(fixture.requests, hasLength(count));
      },
    );

    test(
      'actual session refresh after grant change invalidates the original API',
      () async {
        final operation = await fixture.accessOperation();
        final receipt = await fixture.api.setAccess(operation);
        expect(receipt.requestId, _request);
        fixture.permissions = ['admin_users.manage'];
        await fixture.session.refresh();
        expect(fixture.api.authorityCurrent, isFalse);
        await expectLater(
          fixture.api.replayAccess(operation),
          throwsA(isA<AdminAccountException>()),
        );
        await expectLater(
          fixture.api.getAccess(),
          throwsA(isA<AdminAccountException>()),
        );
        final fresh = CloudflareAdminNotificationManagementApi(fixture.session);
        await expectLater(
          fresh.replayAccess(operation),
          throwsA(isA<AdminAccountException>()),
        );
      },
    );

    test(
      'owner, exact principal, actual capability and fresh issued AAL2 are required',
      () async {
        for (final change in <void Function(_Fixture)>[
          (f) => f.role = 'admin',
          (f) => f.email = 'other@example.test',
          (f) => f.principal = null,
          (f) => f.assurance = 1,
          (f) => f.permissions = [],
          (f) => f.mfaAt = f.now.subtract(const Duration(minutes: 6)),
          (f) => f.mfaAt = f.now.add(const Duration(minutes: 2)),
        ]) {
          final fresh = _Fixture();
          change(fresh);
          await fresh.open();
          try {
            expect(fresh.api.canManageAccess, isFalse);
            await expectLater(
              fresh.api.getAccess(),
              throwsA(isA<AdminAccountException>()),
            );
            expect(fresh.requests, isEmpty);
          } finally {
            fresh.dispose();
          }
        }
      },
    );
  }
}
