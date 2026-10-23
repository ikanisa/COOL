part of '../cloudflare_operating_pages_test.dart';

void _registerOperatingDetailPageCases() {
  testWidgets(
    'operator-only user detail renders tables without financial edit actions',
    (tester) async {
      final repo = await operatingRepository((request) async {
        expect(request.method, 'GET');
        return operatingResponse(operatorOnlyDetail());
      });
      await pumpOperating(
        tester,
        repo,
        const CloudflareOperatingDetailPage(
          type: 'users',
          id: coreId,
          backPath: '/admin/users',
        ),
      );
      expect(
        find.text('Team access record · Managed in Admins and staff'),
        findsOneWidget,
      );
      expect(find.byType(AdminDataTable), findsWidgets);
      expect(
        find.text(
          'The service response could not be verified. Refresh the record before continuing.',
        ),
        findsNothing,
      );
      expect(find.text('Edit person'), findsNothing);
      expect(find.text('Version null'), findsNothing);
      await clean(tester, repo);
    },
  );
  for (final type in ['groups', 'users']) {
    for (final wrongTarget in [false, true]) {
      testWidgets(
        '$type terminal record reload ${wrongTarget ? 'rejects another' : 'recovers exact'} membership request without replay',
        (tester) async {
          final storage = MemoryAdminPendingAttemptStorage();
          final originalTarget = type == 'groups'
              ? '$coreId:$otherId'
              : '$otherId:$coreId';
          final first = await operatingRepository(
            (_) async => operatingResponse({}),
          );
          final initial = await pumpOperating(
            tester,
            first,
            const SizedBox.shrink(),
            storage: storage,
          );
          final store = initial.read(adminPendingAttemptStoreProvider);
          const membershipSchema = AdminPendingAttemptSchema(
            fields: {'expected_version', 'reason', 'role', 'status'},
          );
          for (final (resource, key) in [
            (originalTarget, journalRecoveryKey),
            ('$otherId:$otherId', 'unrelated-membership-reference'),
            ('$coreId:invalid', 'malformed-membership-reference'),
          ]) {
            store.retain(
              family: 'operating-updatemembership',
              resourceId: resource,
              requestKey: key,
              permission: 'users.manage',
              intent: {
                'expected_version': 4,
                'reason': 'Reviewed recorded membership evidence',
                'role': 'member',
                'status': 'removed',
              },
              schema: membershipSchema,
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          initial.dispose();
          var lookups = 0;
          final next = await operatingRepository((request) async {
            expect(request.method, 'GET');
            if (request.url.path == '/api/admin/operations/$type/$coreId') {
              return operatingResponse({
                'resource_type': type,
                'resource': {
                  'id': coreId,
                  'version': 8,
                  'status': type == 'groups' ? 'archived' : 'closed',
                  'title': 'Recorded group',
                  'display_name': 'Recorded member',
                },
                'current_actor_id': coreId,
                'can_manage': false,
                'related': {'memberships': []},
                'related_truncated': false,
              });
            }
            lookups++;
            expect(
              request.url.path,
              '/api/admin/operations/requests/$journalRecoveryKey',
            );
            return operatingResponse({
              'status': 'succeeded',
              'request_id': otherId,
              'receipt': operatingReceipt(
                type: 'memberships',
                id: wrongTarget
                    ? '$otherId/$otherId'
                    : originalTarget.replaceAll(':', '/'),
                version: 5,
              ),
            });
          });
          await pumpOperating(
            tester,
            next,
            CloudflareOperatingDetailPage(
              type: type,
              id: coreId,
              backPath: '/admin/$type',
            ),
            storage: storage,
          );
          expect(find.text('Request recovery'), findsOneWidget);
          expect(find.text(journalRecoveryKey), findsOneWidget);
          expect(find.text('unrelated-membership-reference'), findsNothing);
          expect(find.text('malformed-membership-reference'), findsNothing);
          expect(
            find.widgetWithText(TextButton, 'Edit membership'),
            findsNothing,
          );
          expect(lookups, 0);
          await tester.ensureVisible(find.text('Check request status'));
          await tester.tap(find.text('Check request status'));
          await tester.pumpAndSettle();
          expect(lookups, 1);
          expect(find.text('Retry identical request'), findsNothing);
          if (wrongTarget) {
            expect(find.text('Change saved'), findsNothing);
            expect(
              find.textContaining('response could not be verified'),
              findsOneWidget,
            );
          } else {
            expect(find.text('Change saved'), findsOneWidget);
            expect(find.text('Check request status'), findsNothing);
          }
          final stored = jsonDecode(storage.values.values.single) as Map;
          expect(stored['entries'], hasLength(wrongTarget ? 3 : 2));
          expect(tester.takeException(), isNull);
          await clean(tester, next);
        },
      );
    }
  }

  for (final pendingResponse in [false, true]) {
    testWidgets(
      'committed journal ${pendingResponse ? '409 pending' : 'lost response'} restores original lookup after posted detail reload without another write',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        var writes = 0, lookups = 0;
        String? originalKey;
        const draft = CloudflareOperatingDetail(
          type: 'journals',
          resource: {
            'id': coreId,
            'group_id': otherId,
            'version': 1,
            'description': 'Contribution journal',
            'status': 'draft',
            'created_by_admin_id': otherId,
            'edited_by_admin_id': otherId,
          },
          actorId: coreId,
          canManage: true,
          related: {'entries': []},
          truncated: false,
        );
        final first = await operatingRepository((request) async {
          if (request.method == 'GET') {
            expect(request.url.queryParameters, {
              'relation': 'entries',
              'limit': '100',
              'offset': '0',
            });
            return operatingResponse(journalPostingResponse());
          }
          writes++;
          expect(request.method, 'POST');
          expect(
            request.url.path,
            '/api/admin/operations/journals/$coreId/post',
          );
          expect((jsonDecode(request.body) as Map)['expected_version'], 1);
          originalKey = request.headers['Idempotency-Key'];
          if (pendingResponse) {
            return operatingResponse({
              'error': 'request_pending',
              'message': 'Check the original receipt.',
            }, status: 409);
          }
          throw http.ClientException('committed response was lost');
        });
        final old = await pumpOperating(
          tester,
          first,
          const CloudflareOperatingForm(
            operation: CloudflareOperation.postJournal,
            detail: draft,
          ),
          storage: storage,
        );
        await reasonAndReview(tester);
        await tester.tap(find.text('Confirm permanent posting'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(storage.values, isNotEmpty);
        expect(find.text('Change saved'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        old.dispose();

        final next = await operatingRepository((request) async {
          expect(request.method, 'GET');
          if (request.url.path == '/api/admin/operations/journals/$coreId') {
            return operatingResponse(postedJournalDetail());
          }
          lookups++;
          expect(
            request.url.path,
            '/api/admin/operations/requests/$originalKey',
          );
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': operatingReceipt(type: 'journals', version: 2),
          });
        });
        await pumpOperating(
          tester,
          next,
          journalRecoveryPage,
          storage: storage,
        );
        expect(find.text('Request recovery'), findsOneWidget);
        expect(find.text('Original request'), findsOneWidget);
        expect(find.text(originalKey!), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Post journal'),
          findsNothing,
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Replace journal draft'),
          findsNothing,
        );
        expect(find.text('Review change'), findsNothing);
        expect(lookups, 0);
        await tester.ensureVisible(find.text('Check request status'));
        await tester.tap(find.text('Check request status'));
        await tester.pumpAndSettle();
        expect(lookups, 1);
        expect(writes, 1);
        expect(find.text('Change saved'), findsOneWidget);
        expect(find.text(originalKey!), findsOneWidget);
        expect(find.text('Retry identical request'), findsNothing);
        expect(find.text('Check request status'), findsNothing);
        expect(storage.values, isEmpty);
        expect(tester.takeException(), isNull);
        await clean(tester, next);
      },
    );
  }

  for (final status in ['pending', 'not_found', 'failed']) {
    testWidgets('posted journal $status lookup retains key without replay', (
      tester,
    ) async {
      final storage = MemoryAdminPendingAttemptStorage();
      var lookups = 0;
      final repo = await operatingRepository((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/operations/journals/$coreId') {
          return operatingResponse(postedJournalDetail());
        }
        lookups++;
        expect(
          request.url.path,
          '/api/admin/operations/requests/$journalRecoveryKey',
        );
        return operatingResponse({'status': status});
      });
      final container = await pumpOperating(
        tester,
        repo,
        journalRecoveryPage,
        storage: storage,
      );
      retainJournalPost(container);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check request status'));
      await tester.tap(find.text('Check request status'));
      await tester.pumpAndSettle();
      expect(lookups, 1);
      expect(storage.values, isNotEmpty);
      expect(find.text('Change saved'), findsNothing);
      expect(find.text('Retry identical request'), findsNothing);
      expect(find.text('Check request status'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await clean(tester, repo);
    });
  }

  for (final invalidReceipt in [
    operatingReceipt(type: 'groups', version: 2),
    operatingReceipt(type: 'journals', id: otherId, version: 2),
    operatingReceipt(type: 'journals', version: 3),
  ]) {
    testWidgets(
      'posted journal recovery rejects mismatched ${invalidReceipt['resource_type']}/${invalidReceipt['resource_id']}/${invalidReceipt['version']} receipt',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        final repo = await operatingRepository((request) async {
          expect(request.method, 'GET');
          if (request.url.path == '/api/admin/operations/journals/$coreId') {
            return operatingResponse(postedJournalDetail());
          }
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': invalidReceipt,
          });
        });
        final container = await pumpOperating(
          tester,
          repo,
          journalRecoveryPage,
          storage: storage,
        );
        retainJournalPost(container);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Check request status'));
        await tester.tap(find.text('Check request status'));
        await tester.pumpAndSettle();
        expect(find.text('Change saved'), findsNothing);
        expect(
          find.textContaining('response could not be verified'),
          findsOneWidget,
        );
        expect(storage.values, isNotEmpty);
        expect(find.text('Check request status'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await clean(tester, repo);
      },
    );
  }

  for (final boundary in ['session', 'permission']) {
    testWidgets(
      'posted journal recovery excludes another $boundary authority',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        var sessionId = 'core-session', canManage = true, lookups = 0;
        final session = CloudflareAdminSession(
          MockClient((request) async {
            if (request.url.path.endsWith('/auth/session')) {
              return operatingResponse(
                coreSession(
                  sessionId: sessionId,
                  permissions: [
                    'overview.read',
                    'ledger.read',
                    if (canManage) 'ledger.manage',
                  ],
                ),
              );
            }
            expect(request.method, 'GET');
            if (request.url.path == '/api/admin/operations/journals/$coreId') {
              return operatingResponse(postedJournalDetail());
            }
            lookups++;
            return operatingResponse({'status': 'not_found'});
          }),
          origin: Uri.parse('https://admin.example.test/'),
          environment: legacyBackendFixtureEnvironment,
        );
        addTearDown(() {
          if (session.mounted) session.dispose();
        });
        await session.refresh();
        final repo = CloudflareAdminRepository(session);
        final container = await pumpOperating(
          tester,
          repo,
          journalRecoveryPage,
          storage: storage,
        );
        retainJournalPost(container);
        await tester.pumpAndSettle();
        expect(find.text('Check request status'), findsOneWidget);
        if (boundary == 'session') {
          sessionId = 'different-authority';
        } else {
          canManage = false;
        }
        await session.refresh();
        await tester.pumpAndSettle();
        expect(find.text('Request recovery'), findsNothing);
        expect(find.text('Check request status'), findsNothing);
        expect(storage.values, isEmpty);
        expect(lookups, 0);
        expect(tester.takeException(), isNull);
        await clean(tester, repo);
      },
    );
  }

  for (final boundary in ['session', 'permission']) {
    testWidgets('late journal receipt after $boundary change stays hidden', (
      tester,
    ) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final response = Completer<http.Response>();
      var sessionId = 'core-session', canManage = true, lookups = 0;
      final session = CloudflareAdminSession(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/session')) {
            return operatingResponse(
              coreSession(
                sessionId: sessionId,
                permissions: [
                  'overview.read',
                  'ledger.read',
                  if (canManage) 'ledger.manage',
                ],
              ),
            );
          }
          expect(request.method, 'GET');
          if (request.url.path == '/api/admin/operations/journals/$coreId') {
            return operatingResponse(postedJournalDetail());
          }
          lookups++;
          return response.future;
        }),
        origin: Uri.parse('https://admin.example.test/'),
        environment: legacyBackendFixtureEnvironment,
      );
      addTearDown(() {
        if (session.mounted) session.dispose();
      });
      await session.refresh();
      final repo = CloudflareAdminRepository(session);
      final container = await pumpOperating(
        tester,
        repo,
        journalRecoveryPage,
        storage: storage,
      );
      retainJournalPost(container);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check request status'));
      await tester.tap(find.text('Check request status'));
      await tester.pump();
      expect(lookups, 1);
      if (boundary == 'session') {
        sessionId = 'different-authority';
      } else {
        canManage = false;
      }
      await session.refresh();
      await tester.pumpAndSettle();
      response.complete(
        operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(type: 'journals', version: 2),
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Request recovery'), findsNothing);
      expect(find.text('Change saved'), findsNothing);
      expect(storage.values, isEmpty);
      expect(tester.takeException(), isNull);
      await clean(tester, repo);
    });
  }

  testWidgets(
    'removed journal checkpoint cannot resolve or clear a newer request',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final response = Completer<http.Response>();
      const replacementKey = '55555555-5555-4555-8555-555555555555';
      var lookups = 0;
      final repo = await operatingRepository((request) async {
        expect(request.method, 'GET');
        if (request.url.path == '/api/admin/operations/journals/$coreId') {
          return operatingResponse(postedJournalDetail());
        }
        lookups++;
        if (request.url.path.endsWith(journalRecoveryKey)) {
          return response.future;
        }
        expect(
          request.url.path,
          '/api/admin/operations/requests/$replacementKey',
        );
        return operatingResponse({'status': 'not_found'});
      });
      final container = await pumpOperating(
        tester,
        repo,
        journalRecoveryPage,
        storage: storage,
      );
      retainJournalPost(container);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check request status'));
      await tester.tap(find.text('Check request status'));
      await tester.pump();
      expect(lookups, 1);
      final store = container.read(adminPendingAttemptStoreProvider);
      store.clear(family: 'operating-postjournal', resourceId: coreId);
      store.retain(
        family: 'operating-postjournal',
        resourceId: coreId,
        requestKey: replacementKey,
        permission: 'ledger.manage',
        intent: {
          'expected_version': 2,
          'reason': 'Review the newer request independently',
        },
        schema: const AdminPendingAttemptSchema(
          fields: {'reason', 'expected_version'},
        ),
      );
      await tester.pumpAndSettle();
      response.complete(
        operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(type: 'journals', version: 2),
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Change saved'), findsNothing);
      expect(find.text(journalRecoveryKey), findsNothing);
      expect(find.text(replacementKey), findsOneWidget);
      expect(storage.values, isNotEmpty);
      await tester.tap(find.text('Check request status'));
      await tester.pumpAndSettle();
      expect(lookups, 2);
      expect(find.text('Not found'), findsOneWidget);
      expect(storage.values, isNotEmpty);
      expect(tester.takeException(), isNull);
      await clean(tester, repo);
    },
  );

  for (final invalidReceipt in [
    operatingReceipt(type: 'groups', version: 2),
    operatingReceipt(type: 'journals', id: otherId, version: 2),
    operatingReceipt(type: 'journals', version: 3),
    {...operatingReceipt(type: 'journals', version: 2), 'version': null},
  ]) {
    testWidgets(
      'journal form recovery retains its key for invalid ${invalidReceipt['resource_type']}/${invalidReceipt['resource_id']}/${invalidReceipt['version']} receipt',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        var writes = 0, lookups = 0;
        String? originalKey;
        final repo = await operatingRepository((request) async {
          if (request.url.path == '/api/admin/operations/journals/$coreId') {
            expect(request.method, 'GET');
            return operatingResponse(journalPostingResponse());
          }
          if (request.method == 'POST') {
            writes++;
            originalKey = request.headers['Idempotency-Key'];
            throw http.ClientException('committed response was lost');
          }
          expect(request.method, 'GET');
          expect(
            request.url.path,
            '/api/admin/operations/requests/$originalKey',
          );
          lookups++;
          return operatingResponse({
            'status': 'succeeded',
            'request_id': otherId,
            'receipt': invalidReceipt,
          });
        });
        await pumpOperating(
          tester,
          repo,
          const CloudflareOperatingForm(
            operation: CloudflareOperation.postJournal,
            detail: draftJournalForPosting,
          ),
          storage: storage,
        );
        await reasonAndReview(tester);
        await tester.tap(find.text('Confirm permanent posting'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Check request status'));
        await tester.tap(find.text('Check request status'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(lookups, 1);
        expect(find.text('Change saved'), findsNothing);
        expect(
          find.textContaining('response could not be verified'),
          findsOneWidget,
        );
        expect(find.textContaining(originalKey!), findsOneWidget);
        expect(find.text('Retry identical request'), findsNothing);
        expect(storage.values, isNotEmpty);
        expect(tester.takeException(), isNull);
        await clean(tester, repo);
      },
    );
  }

  for (final pendingResponse in [false, true]) {
    testWidgets(
      'staff private group ${pendingResponse ? 'request pending' : 'lost response'} reaches POST and restores original-key recovery',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        String? key, originalBody;
        var writes = 0, lookups = 0;
        final first = await operatingRepository(
          (request) async {
            if (request.method == 'GET') {
              return operatingResponse({'rows': <Object>[]});
            }
            writes++;
            expect(request.method, 'POST');
            expect(request.url.path, '/api/admin/operations/groups');
            key = request.headers['Idempotency-Key'];
            originalBody = request.body;
            final body = jsonDecode(request.body) as Map;
            expect(body['visibility'], 'private');
            expect(body['is_platform_sponsored'], isFalse);
            expect(body['title'], 'Staff private draft');
            if (pendingResponse) {
              return operatingResponse({
                'error': 'request_pending',
                'message': 'Check the original receipt.',
              }, status: 409);
            }
            throw http.ClientException('connection lost');
          },
          staff: true,
          additionalPermissions: ['collections.create'],
        );
        expect(first.session.user!.permissions, contains('collections.create'));
        expect(
          first.session.user!.permissions,
          isNot(contains(CloudflareOperation.createGroup.permission)),
        );
        const form = CloudflareOperatingForm(
          operation: CloudflareOperation.createGroup,
          initial: {
            'title': 'Staff private draft',
            'slug': 'staff-private-draft',
            'collection_type': 'ikimina',
            'status': 'draft',
            'visibility': 'public_approved',
            'is_platform_sponsored': true,
          },
        );
        final old = await pumpOperating(tester, first, form, storage: storage);
        expect(find.text('Visibility'), findsNothing);
        expect(find.text('Platform sponsored'), findsNothing);
        await reasonAndReview(tester);
        expect(writes, 0);
        final confirmation = tester.widget<AdminDataTable>(
          find.byWidgetPredicate(
            (widget) =>
                widget is AdminDataTable &&
                widget.tableLabel == 'Change confirmation',
          ),
        );
        expect(confirmation.rows.single.extra['visibility'], 'private');
        expect(
          confirmation.rows.single.extra['is_platform_sponsored'],
          isFalse,
        );
        expect(
          confirmation.columns!.map((column) => column.label),
          containsAll(['Visibility', 'Is Platform Sponsored']),
        );
        await tester.tap(find.text('Confirm change'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(key, isNotNull);
        expect(storage.values, isNotEmpty);
        expect(find.text('Change saved'), findsNothing);
        expect(find.text('Review change'), findsNothing);
        expect(find.textContaining('Request reference: $key'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Group name'),
              )
              .enabled,
          isFalse,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        old.dispose();
        final next = await operatingRepository(
          (request) async {
            if (request.method == 'GET') {
              if (request.url.path.contains('/operations/requests/')) {
                lookups++;
                expect(request.url.path, '/api/admin/operations/requests/$key');
                return operatingResponse({'status': 'not_found'});
              }
              return operatingResponse({'rows': <Object>[]});
            }
            writes++;
            expect(request.url.path, '/api/admin/operations/groups');
            expect(request.headers['Idempotency-Key'], key);
            expect(jsonDecode(request.body), jsonDecode(originalBody!));
            return operatingResponse(operatingReceipt());
          },
          staff: true,
          additionalPermissions: ['collections.create'],
        );
        await pumpOperating(tester, next, form, storage: storage);
        expect(writes, 1);
        expect(lookups, 0);
        expect(find.textContaining('Request reference: $key'), findsOneWidget);
        expect(find.text('Review change'), findsNothing);
        expect(find.text('Retry identical request'), findsNothing);
        await tester.ensureVisible(find.text('Check request status'));
        await tester.tap(find.text('Check request status'));
        await tester.pumpAndSettle();
        expect(lookups, 1);
        expect(writes, 1);
        await tester.ensureVisible(find.text('Retry identical request'));
        await tester.tap(find.text('Retry identical request'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        await tester.tap(find.text('Confirm identical retry'));
        await tester.pumpAndSettle();
        expect(writes, 2);
        expect(find.text('Change saved'), findsOneWidget);
        expect(storage.values, isEmpty);
        expect(tester.takeException(), isNull);
        await clean(tester, next);
      },
    );
  }
  for (final pendingResponse in [false, true]) {
    testWidgets(
      'operating ${pendingResponse ? '409 pending' : 'lost response'} hard reload requires lookup and reviewed same-key retry',
      (tester) async {
        final storage = MemoryAdminPendingAttemptStorage();
        String? key, originalBody;
        var writes = 0;
        final first = await operatingRepository((request) async {
          if (request.method == 'GET') {
            expect(request.url.queryParameters, {
              'relation': 'entries',
              'limit': '100',
              'offset': '0',
            });
            return operatingResponse(journalPostingResponse());
          }
          writes++;
          key = request.headers['Idempotency-Key'];
          originalBody = request.body;
          if (pendingResponse) {
            return operatingResponse({
              'error': 'request_pending',
              'message': 'Check the original receipt.',
            }, status: 409);
          }
          throw http.ClientException('connection lost');
        });
        const form = CloudflareOperatingForm(
          operation: CloudflareOperation.createUser,
          initial: {
            'display_name': 'Example Member',
            'email': 'member@example.test',
          },
        );
        final old = await pumpOperating(tester, first, form, storage: storage);
        await reasonAndReview(tester);
        await tester.tap(find.text('Confirm change'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(storage.values, isNotEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        old.dispose();
        final next = await operatingRepository((request) async {
          if (request.method == 'GET') {
            expect(request.url.path, '/api/admin/operations/requests/$key');
            return operatingResponse({'status': 'not_found'});
          }
          writes++;
          expect(request.headers['Idempotency-Key'], key);
          // Canonical storage sorts map keys while preserving the exact intent.
          expect(jsonDecode(request.body), jsonDecode(originalBody!));
          return operatingResponse(operatingReceipt(type: 'users'));
        });
        await pumpOperating(tester, next, form, storage: storage);
        expect(writes, 1);
        expect(find.text('Review change'), findsNothing);
        await tester.tap(find.text('Check request status'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retry identical request'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        await tester.tap(find.text('Confirm identical retry'));
        await tester.pumpAndSettle();
        expect(writes, 2);
        expect(find.text('Change saved'), findsOneWidget);
        expect(storage.values, isEmpty);
        await clean(tester, next);
      },
    );
  }
}
