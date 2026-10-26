part of '../cloudflare_admin_notification_management_api_test.dart';

extension _NotificationStatusCases on _NotificationManagementApiSuite {
  void _registerNotificationStatusCases() {
    test(
      'access original-status remains readable after assisted self-disable and separates current head',
      () async {
        fixture.permissions = ['admin_users.manage'];
        fixture.decisionRevision = 3;
        await fixture.open();
        final receipt = fixture.accessReceipt({
          'request_id': _request,
          'enabled': true,
          'expected_decision_revision': 0,
        });
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _operationStatus(
            'access',
            _request,
            receipt,
            current: fixture.access(),
          ),
        });
        final status = await fixture.api.getAccessOperation(_request);
        expect(status.observed, isTrue);
        expect(status.status, NotificationManagementRecordedStatus.recorded);
        expect(status.mayBeInFlight, isFalse);
        expect(status.recordedDecision!.enabled, isTrue);
        expect(status.recordedDecision!.decisionRevision, 1);
        expect(status.currentAccess.canOperate, isFalse);
        expect(status.currentAccess.decisionRevision, 3);
        expect(status.replayAuthorized, isFalse);
        expect(status.maySend, isFalse);
        expect(fixture.session.user!.permissions, ['admin_users.manage']);
        expect(fixture.requests.single.method, 'GET');
        expect(
          fixture.requests.single.url.path,
          '/api/admin/notification-operator/access/operations/$_request',
        );
        final count = fixture.requests.length;
        await expectLater(
          fixture.api.getPolicyOperation(_request),
          throwsA(isA<AdminAccountException>()),
        );
        await expectLater(
          fixture.api.getOperation(_request),
          throwsA(isA<AdminAccountException>()),
        );
        expect(fixture.requests, hasLength(count));
      },
    );

    test(
      'absent access original-status may be in flight even with a later current head',
      () async {
        fixture.decisionRevision = 7;
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _operationStatus(
            'access',
            _request,
            null,
            current: fixture.access(),
          ),
        });
        final status = await fixture.api.getAccessOperation(_request);
        expect(status.status, NotificationManagementRecordedStatus.notRecorded);
        expect(status.recordedDecision, isNull);
        expect(status.mayBeInFlight, isTrue);
        expect(status.currentAccess.decisionRevision, 7);
        expect(fixture.requests, hasLength(1));
        expect(fixture.requests.single.body, isEmpty);
      },
    );

    test(
      'access status rejects malformed envelopes, foreign actual identity and regressed current head',
      () async {
        fixture.decisionRevision = 2;
        final receipt = fixture.accessReceipt({
          'request_id': _request,
          'enabled': false,
          'expected_decision_revision': 0,
        });
        final row = _operationStatus(
          'access',
          _request,
          receipt,
          current: fixture.access(),
        );
        for (final patch in <Map<String, dynamic>>[
          {'request_id': _other},
          {'status': 'failed'},
          {'observed': false},
          {'may_be_in_flight': true},
          {'replay_authorized': true},
          {'may_send': true},
          {
            'current_access': {
              ...fixture.access(),
              'current_principal_id': _other,
            },
          },
          {
            'current_access': {...fixture.access(), 'decision_revision': 0},
          },
          {
            'recorded_decision': {...receipt, 'decision_sha256': 'f' * 64},
          },
          {
            'recorded_decision': {...receipt, 'replay': true},
          },
          {'recorded_decision': null},
          {'current_policy': fixture.policy()},
        ]) {
          fixture.handler = (_) async => _json({
            'ok': true,
            'result': {...row, ...patch},
          });
          await expectLater(
            fixture.api.getAccessOperation(_request),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'policy original-status is historical and current policy is an explicit separate GET',
      () async {
        final receipt = fixture.policyReceipt({
          'request_id': _request,
          'expected_revision': 0,
          'enabled': true,
        });
        fixture.handler = (request) async => _json({
          'ok': true,
          'result': request.url.path.endsWith('/policies/$_collection')
              ? fixture.policy()
              : _operationStatus('policy', _request, receipt),
        });
        final status = await fixture.api.getPolicyOperation(_request);
        expect(status.recordedDecision!.enabled, isTrue);
        expect(status.recordedDecision!.revision, 1);
        expect(status.maySend, isFalse);
        expect(status.replayAuthorized, isFalse);
        expect(fixture.requests, hasLength(1));
        final current = await fixture.api.getPolicy(
          status.recordedDecision!.collectionId,
        );
        expect(current.revision, 3);
        expect(current.enabled, isFalse);
        expect(fixture.requests, hasLength(2));
        expect(
          fixture.requests.every((x) => x.method == 'GET' && x.body.isEmpty),
          isTrue,
        );
      },
    );

    test(
      'absent policy status is not failure and extra current-policy data is refused',
      () async {
        final row = _operationStatus('policy', _request, null);
        fixture.handler = (_) async => _json({'ok': true, 'result': row});
        final status = await fixture.api.getPolicyOperation(_request);
        expect(status.observed, isFalse);
        expect(status.mayBeInFlight, isTrue);
        expect(status.recordedDecision, isNull);
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': {...row, 'may_be_in_flight': false},
        });
        await expectLater(
          fixture.api.getPolicyOperation(_request),
          throwsFormatException,
        );
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': {...row, 'current_policy': fixture.policy()},
        });
        await expectLater(
          fixture.api.getPolicyOperation(_request),
          throwsFormatException,
        );
      },
    );

    test(
      'dedicated status original matching cannot adopt a foreign API operation or wrong action',
      () async {
        final original = await fixture.accessOperation();
        final count = fixture.requests.length;
        await expectLater(
          fixture.api.getPolicyOperation(_request, originalOperation: original),
          throwsArgumentError,
        );
        await expectLater(
          fixture.api.getAccessOperation(_other, originalOperation: original),
          throwsArgumentError,
        );
        final api = CloudflareAdminNotificationManagementApi(fixture.session);
        await expectLater(
          api.getAccessOperation(_request, originalOperation: original),
          throwsA(isA<AdminAccountException>()),
        );
        expect(fixture.requests, hasLength(count));
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _operationStatus(
            'access',
            _request,
            null,
            current: fixture.access(),
          ),
        });
        await fixture.api.getAccessOperation(
          _request,
          originalOperation: original,
        );
        expect(original.dispatched, isFalse);
        expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    test(
      'generic-only grants do not authorize any dedicated history or status read',
      () async {
        fixture.permissions = ['notifications.read', 'notifications.manage'];
        await fixture.open();
        await expectLater(
          fixture.api.getHistory(),
          throwsA(isA<AdminAccountException>()),
        );
        await expectLater(
          fixture.api.getAccessOperation(_request),
          throwsA(isA<AdminAccountException>()),
        );
        await expectLater(
          fixture.api.getPolicyOperation(_request),
          throwsA(isA<AdminAccountException>()),
        );
        expect(fixture.requests, isEmpty);
      },
    );

    test(
      'permission refresh during history read fences response and saved cursor',
      () async {
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _history(
            [_historyItem(_request, 'access', fixture.now)],
            next: {
              'after_created_at': fixture.now.toIso8601String(),
              'after_request_id': _request,
            },
          ),
        });
        final cursor = (await fixture.api.getHistory(limit: 1)).nextCursor!;
        final reply = Completer<http.Response>();
        fixture.handler = (_) => reply.future;
        final pending = fixture.api.getHistory(after: cursor);
        await Future<void>.delayed(Duration.zero);
        fixture.permissions = ['admin_users.manage'];
        await fixture.session.refresh();
        reply.complete(_json({'ok': true, 'result': _history([])}));
        await expectLater(
          pending,
          throwsA(isA<CloudflareAdminRequestException>()),
        );
        final count = fixture.requests.length;
        await expectLater(
          fixture.api.getHistory(after: cursor),
          throwsA(isA<AdminAccountException>()),
        );
        final fresh = CloudflareAdminNotificationManagementApi(fixture.session);
        await expectLater(
          fresh.getHistory(after: cursor),
          throwsA(isA<AdminAccountException>()),
        );
        expect(fixture.requests, hasLength(count));
      },
    );

    test(
      'dedicated status refuses digest-valid foreign public sessions and principals',
      () async {
        fixture.decisionRevision = 2;
        for (final access in [true, false]) {
          final receipt = access
              ? fixture.accessReceipt({
                  'request_id': _request,
                  'enabled': false,
                  'expected_decision_revision': 0,
                })
              : fixture.policyReceipt({
                  'request_id': _request,
                  'enabled': false,
                  'expected_revision': 0,
                });
          final principalField = access
              ? 'current_principal_id'
              : 'owner_user_id';
          for (final patch in [
            {'public_session_id': _other},
            {principalField: _other},
          ]) {
            final foreign = _resignStatusReceipt({...receipt, ...patch});
            fixture.handler = (_) async => _json({
              'ok': true,
              'result': _operationStatus(
                access ? 'access' : 'policy',
                _request,
                foreign,
                current: access ? fixture.access() : null,
              ),
            });
            await expectLater(
              access
                  ? fixture.api.getAccessOperation(_request)
                  : fixture.api.getPolicyOperation(_request),
              throwsFormatException,
            );
          }
        }
        fixture.handler = (_) async =>
            _json({'error': 'request_conflict'}, 409);
        await expectLater(
          fixture.api.getAccessOperation(_request),
          throwsA(
            isA<CloudflareAdminRequestException>().having(
              (e) => e.statusCode,
              'original sign-in conflict',
              409,
            ),
          ),
        );
      },
    );

    test(
      'dedicated access status checks original expected head without adopting current head',
      () async {
        final original = await fixture.accessOperation();
        fixture.decisionRevision = 4;
        final receipt = fixture.accessReceipt({
          'request_id': _request,
          'enabled': true,
          'expected_decision_revision': 1,
        });
        fixture.handler = (_) async => _json({
          'ok': true,
          'result': _operationStatus(
            'access',
            _request,
            receipt,
            current: fixture.access(),
          ),
        });
        await expectLater(
          fixture.api.getAccessOperation(_request, originalOperation: original),
          throwsFormatException,
        );
        expect(original.expectedDecisionRevision, 0);
        expect(original.dispatched, isFalse);
        expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );

    test(
      'permission refresh while access status is pending discards its later read',
      () async {
        final row = _operationStatus(
          'access',
          _request,
          null,
          current: fixture.access(),
        );
        final reply = Completer<http.Response>();
        fixture.handler = (_) => reply.future;
        final pending = fixture.api.getAccessOperation(_request);
        await Future<void>.delayed(Duration.zero);
        fixture.permissions = ['admin_users.manage'];
        await fixture.session.refresh();
        reply.complete(_json({'ok': true, 'result': row}));
        await expectLater(
          pending,
          throwsA(isA<CloudflareAdminRequestException>()),
        );
        expect(fixture.api.authorityCurrent, isFalse);
        expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
      },
    );
  }
}
