part of '../cloudflare_operating_pages_test.dart';

void _registerOperatingMutationPageCases() {
  test('RWF parsing is whole, exact and bounded', () {
    for (final invalid in [
      '1.25',
      '-1',
      '1e3',
      '1,000',
      '9007199254740992',
      '01',
      '',
    ]) {
      expect(parseOperatingRwf(invalid), isNull);
    }
    expect(parseOperatingRwf('9007199254740991'), 9007199254740991);
    expect(parseOperatingRwf('0'), isNull);
    expect(parseOperatingRwf('0', allowZero: true), 0);
  });
  testWidgets(
    'user form requires review and shows only authoritative server receipt',
    (tester) async {
      var writes = 0;
      final repo = await operatingRepository((request) async {
        writes++;
        expect(request.method, 'POST');
        return operatingResponse(operatingReceipt(type: 'users'));
      });
      await pumpOperating(
        tester,
        repo,
        const CloudflareOperatingForm(
          operation: CloudflareOperation.createUser,
          initial: {
            'display_name': 'Example Member',
            'email': 'member@example.test',
          },
        ),
      );
      await reasonAndReview(tester);
      expect(writes, 0);
      expect(find.text('Review: create person'), findsOneWidget);
      final confirmation = tester.widget<AdminDataTable>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AdminDataTable &&
              widget.tableLabel == 'Change confirmation',
        ),
      );
      expect(confirmation.rows.single.extra['display_name'], 'Example Member');
      expect(confirmation.rows.single.extra['email'], 'member@example.test');
      expect(
        confirmation.columns!.map((column) => column.label),
        containsAll(['Name', 'Email', 'Reason']),
      );
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Change saved'), findsOneWidget);
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Version'), findsOneWidget);
      await clean(tester, repo);
    },
  );
  testWidgets(
    'uncertain save locks edits and reconciles through GET without resending',
    (tester) async {
      var writes = 0, lookups = 0;
      final repo = await operatingRepository((request) async {
        if (request.method == 'POST') {
          writes++;
          throw http.ClientException('connection lost');
        }
        lookups++;
        return operatingResponse({
          'status': 'succeeded',
          'request_id': otherId,
          'receipt': operatingReceipt(type: 'users'),
        });
      });
      await pumpOperating(
        tester,
        repo,
        const CloudflareOperatingForm(
          operation: CloudflareOperation.createUser,
          initial: {
            'display_name': 'Example Member',
            'email': 'member@example.test',
          },
        ),
      );
      await reasonAndReview(tester);
      await tester.tap(find.text('Confirm change'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Review change'), findsNothing);
      expect(find.textContaining('Request reference:'), findsOneWidget);
      final field = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Full name on MoMo'),
      );
      expect(field.enabled, isFalse);
      await tester.ensureVisible(find.text('Check request status'));
      await tester.tap(find.text('Check request status'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(lookups, 1);
      expect(find.text('Change saved'), findsOneWidget);
      await clean(tester, repo);
    },
  );
  testWidgets('staff cannot render or submit create controls', (tester) async {
    var calls = 0;
    final repo = await operatingRepository((_) async {
      calls++;
      return operatingResponse({});
    }, staff: true);
    await pumpOperating(
      tester,
      repo,
      const CloudflareOperatingForm(operation: CloudflareOperation.createGroup),
    );
    expect(find.text('Review change'), findsNothing);
    expect(find.textContaining('cannot perform this action'), findsOneWidget);
    expect(calls, 0);
    await clean(tester, repo);
  });
  testWidgets('membership creation does not inherit draft group status', (
    tester,
  ) async {
    final repo = await operatingRepository(
      (request) async => operatingResponse({
        'rows': [
          {'id': otherId, 'label': 'Example user · 123456', 'version': 1},
        ],
      }),
    );
    const detail = CloudflareOperatingDetail(
      type: 'groups',
      resource: {
        'id': coreId,
        'version': 1,
        'status': 'draft',
        'title': 'Example Group',
      },
      actorId: coreId,
      canManage: true,
      related: {},
      truncated: false,
    );
    await pumpOperating(
      tester,
      repo,
      const CloudflareOperatingForm(
        operation: CloudflareOperation.createMembership,
        detail: detail,
        fixed: {'group_id': coreId},
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Member'), findsNWidgets(2));
    await clean(tester, repo);
  });
  testWidgets('unbalanced journal cannot reach confirmation or transport', (
    tester,
  ) async {
    var writes = 0;
    final repo = await operatingRepository((request) async {
      if (request.method != 'GET') writes++;
      return operatingResponse({
        'rows': [
          {'id': coreId, 'label': 'Cash', 'version': 1},
          {'id': otherId, 'label': 'Contributions', 'version': 1},
        ],
      });
    });
    const detail = CloudflareOperatingDetail(
      type: 'journals',
      resource: {
        'id': coreId,
        'group_id': coreId,
        'version': 2,
        'description': 'Member contribution',
        'status': 'draft',
      },
      actorId: coreId,
      canManage: true,
      related: {
        'entries': [
          {'account_id': coreId, 'debit_rwf': 100, 'credit_rwf': 0},
          {'account_id': otherId, 'debit_rwf': 0, 'credit_rwf': 50},
        ],
      },
      truncated: false,
    );
    await pumpOperating(
      tester,
      repo,
      const CloudflareOperatingForm(
        operation: CloudflareOperation.updateJournal,
        detail: detail,
      ),
    );
    await reasonAndReview(tester);
    expect(
      find.text('Total debits and credits must be equal and positive.'),
      findsOneWidget,
    );
    expect(find.text('Confirm change'), findsNothing);
    expect(writes, 0);
    await clean(tester, repo);
  });
  testWidgets(
    'creator sees independent posting requirement in actual journal detail',
    (tester) async {
      final repo = await operatingRepository(
        (_) async => operatingResponse({
          'resource_type': 'journals',
          'resource': {
            'id': coreId,
            'group_id': otherId,
            'version': 1,
            'description': 'Contribution journal',
            'status': 'draft',
            'created_by_admin_id': coreId,
            'edited_by_admin_id': coreId,
          },
          'current_actor_id': coreId,
          'can_manage': true,
          'related': {'entries': []},
          'related_truncated': false,
        }),
      );
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          adminRepositoryProvider.overrideWithValue(repo),
          cloudflareAdminSessionProvider.overrideWith((ref) => repo.session),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: CloudflareOperatingDetailPage(
                type: 'journals',
                id: coreId,
                backPath: '/admin/ledgers',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Post journal'), findsNothing);
      expect(
        find.text('A different administrator must post this draft.'),
        findsOneWidget,
      );
      await clean(tester, repo);
    },
  );
}
