part of '../cloudflare_admin_notification_management_page_test.dart';

void _registerNotificationPagingResponsivePageCases() {
  testWidgets('SMS history disclosure opens immediately with reduced motion', (
    tester,
  ) async {
    final fixture = _Fixture();
    final container = await _mount(
      tester,
      fixture,
      MemoryAdminPendingAttemptStorage(),
      size: const Size(320, 800),
      scale: 2,
      reduceMotion: true,
    );
    try {
      final tile = find.byKey(
        const Key('notification-management-history-context'),
      );
      await _reveal(tester, tile);
      final collapsedHeight = tester.getSize(tile).height;
      final before = fixture.requests.length;
      await tester.tap(find.text('History details'));
      await tester.pump();
      final expandedHeight = tester.getSize(tile).height;
      expect(expandedHeight, greaterThan(collapsedHeight));
      expect(_facts('Request history scope details'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getSize(tile).height, expandedHeight);
      expect(fixture.requests, hasLength(before));
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _close(tester, container);
    }
  });

  testWidgets(
    'history scope is available before lookup without dispatch or new authority',
    (tester) async {
      final fixture = _Fixture();
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
        size: const Size(320, 800),
        scale: 2,
      );
      try {
        expect(find.text('Never resolves an original UUID.'), findsNothing);
        expect(find.text('Not granted'), findsNWidgets(2));
        final before = fixture.requests.length;
        await _toggleDetails(
          tester,
          const Key('notification-management-history-context'),
        );
        final details = _facts('Request history scope details');
        expect(details, findsOneWidget);
        for (final value in [
          'Server-recorded history is separate from this tab’s original request references.',
          'Metadata does not grant access.',
          'Not authorized by history.',
          'Never resolves an original UUID.',
          'Metadata only here. No batch preparation, resume or sender action is available.',
        ]) {
          final fact = find.descendant(of: details, matching: find.text(value));
          await _reveal(tester, fact);
          expect(fact, findsOneWidget);
        }
        expect(fixture.requests, hasLength(before));
        expect(fixture.writes, isEmpty);
        await _toggleDetails(
          tester,
          const Key('notification-management-history-context'),
        );
        expect(details, findsNothing);
        expect(
          find.text(
            'Sending is unavailable. Sender and release approvals are still required.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _close(tester, container);
      }
    },
  );

  testWidgets(
    'bounded history seek preserves its page on error and rejects an obsolete paging callback',
    (tester) async {
      final firstItems = [
        for (var value = 50; value >= 26; value--)
          _historyItem(
            '50000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
          ),
      ];
      var nextAttempts = 0;
      final fixture = _Fixture(
        handler: (request) async {
          if (request.url.path == _historyPath) {
            expect(request.method, 'GET');
            expect(request.url.queryParameters['limit'], '25');
            if (request.url.queryParameters.containsKey('after_request_id')) {
              expect(
                request.url.queryParameters['after_request_id'],
                firstItems.last['request_id'],
              );
              expect(
                request.url.queryParameters['after_created_at'],
                firstItems.last['recorded_at'],
              );
              if (++nextAttempts == 1) {
                return _json({
                  'ok': false,
                  'error': {
                    'code': 'history_unavailable',
                    'message': 'Controlled history unavailable.',
                  },
                }, 503);
              }
              return _result(
                _historyResponse(
                  items: [_historyItem('50000000-0000-4000-8000-000000000025')],
                ),
              );
            }
            expect(request.url.queryParameters, {'limit': '25'});
            return _result(
              _historyResponse(
                items: firstItems,
                nextCursor: {
                  'after_created_at': firstItems.last['recorded_at'],
                  'after_request_id': firstItems.last['request_id'],
                },
              ),
            );
          }
          return null;
        },
      );
      final container = await _mount(
        tester,
        fixture,
        MemoryAdminPendingAttemptStorage(),
      );
      await _loadHistory(tester);
      expect(
        tester.widget<AdminDataTable>(_serverHistory()).rows,
        hasLength(25),
      );
      final next = find.byKey(
        const Key('notification-management-history-next'),
      );
      final obsolete = tester.widget<OutlinedButton>(next).onPressed!;
      await _tapKey(tester, const Key('notification-management-history-next'));
      expect(
        find.text('The records could not be loaded. Refresh and try again.'),
        findsOneWidget,
      );
      expect(find.text('Controlled history unavailable.'), findsNothing);
      expect(
        tester.widget<AdminDataTable>(_serverHistory()).rows,
        hasLength(25),
      );
      final before = fixture.requests.length;
      obsolete();
      await tester.pumpAndSettle();
      expect(fixture.requests, hasLength(before));
      await _tapKey(tester, const Key('notification-management-history-next'));
      expect(
        tester.widget<AdminDataTable>(_serverHistory()).rows.single.id,
        '50000000-0000-4000-8000-000000000025',
      );
      await _tapKey(
        tester,
        const Key('notification-management-history-previous'),
      );
      expect(
        tester.widget<AdminDataTable>(_serverHistory()).rows,
        hasLength(25),
      );
      final filter = find.descendant(
        of: _serverHistory(),
        matching: find.byTooltip('Filter loaded rows'),
      );
      await _reveal(tester, filter);
      await tester.tap(filter);
      await tester.pumpAndSettle();
      final dropdown = find.descendant(
        of: _serverHistory(),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(dropdown)
            .decoration
            .labelText,
        'Filter column',
      );
      await _reveal(tester, dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await _loadHistory(tester);
      expect(
        tester.widget<AdminDataTable>(_serverHistory()).rows,
        hasLength(25),
      );
      expect(
        find.textContaining('Reopen controls with the actual Owner account'),
        findsNothing,
      );
      expect(
        fixture.requests.where((request) => request.url.path == _historyPath),
        hasLength(5),
      );
      expect(
        fixture.requests.every((request) => request.method == 'GET'),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await _close(tester, container);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '320x800 ${scale}x recorded history keeps all columns horizontally reachable and Owner lookup usable',
      (tester) async {
        final fixture = _Fixture(
          handler: (request) async {
            if (request.url.path == _historyPath) {
              return _result(
                _historyResponse(
                  items: [
                    _historyItem(_historyAccessId),
                    _historyItem(_historyPolicyId, kind: 'policy'),
                    _historyItem(_historyPlanId, kind: 'materialization'),
                  ],
                ),
              );
            }
            return null;
          },
        );
        final semantics = tester.ensureSemantics();
        ProviderContainer? container;
        try {
          container = await _mount(
            tester,
            fixture,
            MemoryAdminPendingAttemptStorage(),
            size: const Size(320, 800),
            scale: scale,
          );
          await _loadHistory(tester);
          final history = _serverHistory();
          final columns = tester.widget<AdminDataTable>(history).columns;
          expect(columns, isNotNull);
          expect(
            columns!.map((column) => column.label),
            containsAll([
              'Original UUID',
              'Kind',
              'Recorded at',
              'Recorded outcome',
              'Lookup availability',
            ]),
          );
          final dataTable = find.descendant(
            of: history,
            matching: find.byType(DataTable),
          );
          expect(dataTable, findsOneWidget);
          final position = Scrollable.of(
            tester.element(dataTable),
            axis: Axis.horizontal,
          ).position;
          expect(position.maxScrollExtent, greaterThan(0));
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          await _reveal(
            tester,
            find.descendant(
              of: history,
              matching: find.text('Lookup availability'),
            ),
          );
          position.jumpTo(0);
          await tester.pumpAndSettle();
          final status = find.byKey(
            const ValueKey('management-history-status:$_historyAccessId'),
          );
          expect(tester.widget<OutlinedButton>(status).onPressed, isNotNull);
          // Intrinsic table cells can be wider than this viewport at 200%.
          // Center the actual action before testing its ordinary tap target.
          await Scrollable.ensureVisible(
            tester.element(status),
            alignment: 0.5,
          );
          await tester.pumpAndSettle();
          expect(status.hitTestable(), findsOneWidget);
          await tester.tap(status);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('No recorded result was observed.'),
            findsOneWidget,
          );
          expect(fixture.writes, isEmpty);
          expect(
            fixture.requests.every((request) => request.method == 'GET'),
            isTrue,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          if (container != null) {
            await _close(tester, container);
          }
        }
      },
    );
  }

  for (final departure in ['hidden', 'navigation']) {
    testWidgets(
      'late recorded history after $departure is discarded and cannot revive on return',
      (tester) async {
        final reply = Completer<http.Response>();
        final fixture = _Fixture(
          handler: (request) async {
            if (request.url.path == _historyPath) {
              return reply.future;
            }
            return null;
          },
        );
        final container = await _mount(
          tester,
          fixture,
          MemoryAdminPendingAttemptStorage(),
        );
        final load = find.byKey(
          const Key('notification-management-history-load'),
        );
        final retained = tester.widget<OutlinedButton>(load).onPressed!;
        await _reveal(tester, load);
        await tester.tap(load);
        await tester.pump();
        retained();
        await tester.pump();
        expect(
          fixture.requests.where((request) => request.url.path == _historyPath),
          hasLength(1),
        );
        NavigatorState? navigator;
        if (departure == 'hidden') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          await tester.pump();
        } else {
          navigator = Navigator.of(
            tester.element(
              find.byType(CloudflareAdminNotificationManagementPage),
            ),
          );
          unawaited(
            navigator.push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other review')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        reply.complete(
          _result(_historyResponse(items: [_historyItem(_historyAccessId)])),
        );
        await tester.pumpAndSettle();
        if (departure == 'hidden') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
        } else {
          navigator!.pop();
          await tester.pumpAndSettle();
        }
        expect(_serverHistory(), findsNothing);
        expect(find.text(_historyAccessId), findsNothing);
        expect(
          fixture.requests.where((request) => request.url.path == _historyPath),
          hasLength(1),
        );
        expect(fixture.writes, isEmpty);
        expect(tester.takeException(), isNull);
        await _close(tester, container);
      },
    );
  }

  testWidgets(
    'late dedicated history status after principal change cannot restore a receipt or current-access view',
    (tester) async {
      final reply = Completer<http.Response>();
      final fixture = _Fixture(
        handler: (request) async {
          if (request.url.path == _historyPath) {
            return _result(
              _historyResponse(items: [_historyItem(_historyAccessId)]),
            );
          }
          if (request.url.path == '$_accessPath/operations/$_historyAccessId') {
            return reply.future;
          }
          return null;
        },
      );
      final storage = MemoryAdminPendingAttemptStorage();
      final container = await _mount(tester, fixture, storage);
      await _loadHistory(tester);
      final status = find.byKey(
        const ValueKey('management-history-status:$_historyAccessId'),
      );
      final retained = tester.widget<OutlinedButton>(status).onPressed!;
      await _reveal(tester, status);
      await tester.tap(status);
      await tester.pump();
      fixture.principal = _otherPrincipal;
      await tester.runAsync(fixture.session.refresh);
      await tester.pump();
      reply.complete(_result(fixture.accessOperation(_historyAccessId)));
      await tester.pumpAndSettle();
      retained();
      await tester.pumpAndSettle();
      expect(_serverHistory(), findsNothing);
      expect(
        _facts(
          'Current access observed with recorded request $_historyAccessId',
        ),
        findsNothing,
      );
      expect(
        _facts('Server recorded historical decision $_historyAccessId'),
        findsNothing,
      );
      expect(find.text(_historyAccessId), findsNothing);
      expect(
        fixture.requests.where(
          (request) =>
              request.url.path == '$_accessPath/operations/$_historyAccessId',
        ),
        hasLength(1),
      );
      expect(storage.values, isEmpty);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await _close(tester, container);
    },
  );

  testWidgets(
    '320x800 2x account and recorded details disclose technical facts without granting action authority',
    (tester) async {
      late _Fixture fixture;
      late Map<String, dynamic> recorded;
      fixture = _Fixture(
        decisionRevision: 4,
        handler: (request) async {
          if (request.url.path == _historyPath) {
            return _result(
              _historyResponse(items: [_historyItem(_historyAccessId)]),
            );
          }
          if (request.url.path == '$_accessPath/operations/$_historyAccessId') {
            recorded = fixture.accessReceipt({
              'request_id': _historyAccessId,
              'expected_decision_revision': 0,
              'enabled': true,
            });
            return _result(
              fixture.accessOperation(_historyAccessId, recorded: recorded),
            );
          }
          return null;
        },
      );
      final semantics = tester.ensureSemantics();
      ProviderContainer? container;
      try {
        container = await _mount(
          tester,
          fixture,
          MemoryAdminPendingAttemptStorage(),
          size: const Size(320, 800),
          scale: 2,
        );
        expect(find.text('Canonical principal ID'), findsNothing);
        expect(find.text(_principal), findsNothing);
        expect(find.text('assisted_sms.read'), findsNothing);
        expect(find.text('assisted_sms.manage'), findsNothing);
        expect(find.text('Not granted'), findsNWidgets(2));
        expect(
          find.descendant(
            of: _facts('Actual current assisted SMS grants'),
            matching: find.text('4'),
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Sending is unavailable'), findsOneWidget);
        final before = fixture.requests.length;
        await _toggleDetails(
          tester,
          const Key('notification-management-access-details'),
        );
        final account = _facts('Current account access technical details');
        expect(account, findsOneWidget);
        final principal = find.descendant(
          of: account,
          matching: find.text(_principal),
        );
        await _reveal(tester, principal);
        expect(tester.getSize(principal).width, lessThanOrEqualTo(288));
        expect(
          find.descendant(
            of: account,
            matching: find.text('assisted_sms.read'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: account,
            matching: find.text('assisted_sms.manage'),
          ),
          findsOneWidget,
        );
        expect(fixture.requests, hasLength(before));
        await _toggleDetails(
          tester,
          const Key('notification-management-access-details'),
        );
        expect(find.text(_principal), findsNothing);
        expect(find.text('assisted_sms.read'), findsNothing);
        await _checkBox(tester, _accessCheckbox);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.widgetWithText(CheckboxListTile, _accessCheckbox),
              )
              .value,
          isTrue,
        );
        await _loadHistory(tester);
        final status = find.byKey(
          const ValueKey('management-history-status:$_historyAccessId'),
        );
        await Scrollable.ensureVisible(tester.element(status), alignment: 0.5);
        await tester.pumpAndSettle();
        expect(status.hitTestable(), findsOneWidget);
        await tester.tap(status);
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: _facts('Server recorded historical decision $_historyAccessId'),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _facts(
              'Current access observed with recorded request $_historyAccessId',
            ),
            matching: find.text('4'),
          ),
          findsOneWidget,
        );
        expect(find.text('Decision SHA-256'), findsNothing);
        expect(find.text('Grant transaction ID'), findsNothing);
        expect(find.text('Legal release approved'), findsNothing);
        expect(find.text('Provider approved'), findsNothing);
        expect(find.text('Delivery confirmed'), findsNothing);
        final beforeRecorded = fixture.requests.length;
        await _expectCollapsedDetailsName(
          tester,
          const ValueKey('management-history-details:$_historyAccessId'),
          'Recorded request technical details $_historyAccessId',
        );
        await _toggleDetails(
          tester,
          const ValueKey('management-history-details:$_historyAccessId'),
        );
        final details = _facts(
          'Recorded request technical details $_historyAccessId',
        );
        final digest = find.descendant(
          of: details,
          matching: find.text(recorded['decision_sha256'] as String),
        );
        await _reveal(tester, digest);
        expect(tester.getSize(digest).width, lessThanOrEqualTo(288));
        expect(
          find.descendant(of: details, matching: find.text(_transaction)),
          findsOneWidget,
        );
        expect(fixture.requests, hasLength(beforeRecorded));
        await _toggleDetails(
          tester,
          const ValueKey('management-history-details:$_historyAccessId'),
        );
        expect(find.text('Decision SHA-256'), findsNothing);
        expect(
          find.text('Check or resume exact original request'),
          findsNothing,
        );
        // This Owner has no operations grant and has not loaded a policy.
        // Disclosure must not introduce policy controls or enable its lookup.
        expect(
          find.widgetWithText(FilledButton, 'Enable receipt SMS policy'),
          findsNothing,
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(
                  TextButton,
                  'Check current collection policy',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(
                  OutlinedButton,
                  'Prepare bounded receipt SMS jobs',
                ),
              )
              .onPressed,
          isNull,
        );
        expect(fixture.writes, isEmpty);
        expect(
          fixture.requests.every((request) => request.method == 'GET'),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        if (container != null) {
          await _close(tester, container);
        }
      }
    },
  );

  testWidgets(
    '320x800 2x unresolved UUID status and expected revision stay exposed outside request details',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      final fixture = _Fixture(
        handler: (request) async {
          if (request.url.path == _accessPath && request.method == 'POST') {
            throw http.ClientException('Lost response');
          }
          return null;
        },
      );
      final semantics = tester.ensureSemantics();
      ProviderContainer? container;
      try {
        container = await _mount(
          tester,
          fixture,
          storage,
          size: const Size(320, 800),
          scale: 2,
        );
        await _checkBox(tester, _accessCheckbox);
        await _tap(tester, 'Enable access');
        final id = _body(fixture.writes.single)['request_id'] as String;
        final summary = _facts('Unresolved original request $id');
        expect(summary, findsOneWidget);
        for (final value in [
          id,
          'Self-access',
          'Outcome unknown: keep this exact original UUID',
          '0',
        ]) {
          await _reveal(
            tester,
            find.descendant(of: summary, matching: find.text(value)),
          );
        }
        expect(find.text('Resource ID'), findsNothing);
        expect(find.text(_principal), findsNothing);
        expect(_retainedReference(storage)['request_key'], id);
        expect(
          _retainedReference(storage)['intent'],
          containsPair('expected_decision_revision', 0),
        );
        final before = fixture.requests.length;
        await _expectCollapsedDetailsName(
          tester,
          ValueKey('management-original-details:$id'),
          'Original request details $id',
        );
        await _toggleDetails(
          tester,
          ValueKey('management-original-details:$id'),
        );
        final details = _facts('Original request details $id');
        await _reveal(
          tester,
          find.descendant(of: details, matching: find.text(_principal)),
        );
        expect(fixture.requests, hasLength(before));
        await _toggleDetails(
          tester,
          ValueKey('management-original-details:$id'),
        );
        expect(details, findsNothing);
        expect(summary, findsOneWidget);
        expect(storage.values.values.join(), contains(id));
        expect(fixture.writes, hasLength(1));
        expect(
          find.textContaining('Another UUID cannot be submitted'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(
                  OutlinedButton,
                  'Check or resume exact original request',
                ),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        if (container != null) {
          await _close(tester, container);
        }
      }
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'compact 320x800 ${scale}x Owner control preserves facts and reachable confirmation',
      (tester) async {
        final fixture = _Fixture();
        final semantics = tester.ensureSemantics();
        ProviderContainer? container;
        try {
          container = await _mount(
            tester,
            fixture,
            MemoryAdminPendingAttemptStorage(),
            size: const Size(320, 800),
            scale: scale,
          );
          expect(find.byType(AdminRecordFactsTable), findsOneWidget);
          expect(find.text('Not granted'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
          await _checkBox(tester, _accessCheckbox);
          expect(
            find.bySemanticsLabel(RegExp('^${RegExp.escape(_accessCheckbox)}')),
            findsOneWidget,
          );
          final enable = find.widgetWithText(FilledButton, 'Enable access');
          await _reveal(tester, enable);
          expect(find.bySemanticsLabel('Enable access'), findsOneWidget);
          final bounds = tester.getRect(enable);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(320));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(800));
          expect(tester.takeException(), isNull);
          expect(fixture.writes, isEmpty);
        } finally {
          semantics.dispose();
          if (container != null) {
            await _close(tester, container);
          }
        }
      },
    );
  }
}
