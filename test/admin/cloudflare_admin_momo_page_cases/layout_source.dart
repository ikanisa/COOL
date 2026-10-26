part of '../cloudflare_admin_momo_page_test.dart';

void _registerMomoLayoutSourceCases() {
  test(
    'financial label requires committed association and payer remains separate',
    () {
      final row = MomoTransaction.parse(transaction());
      expect(row.payer, 'Synthetic payer · …007');
      expect(row.values['member_name'], isNull);
      expect(row.label, 'Needs allocation');
      final conflicted = MomoTransaction.parse({
        ...transaction(status: 'credited'),
        'payment_id': paymentId,
        'credited_amount_minor': 5000,
        'has_conflict': 1,
      });
      expect(conflicted.label, 'Credited');
      expect(conflicted.hasConflict, isTrue);
      expect(
        () => MomoTransaction.parse(transaction(status: 'credited')),
        throwsFormatException,
      );
      expect(
        () => MomoTransactionPage.parse({...page(), 'total': 2}),
        throwsFormatException,
      );
    },
  );
  test(
    'date filters use inclusive Kigali days regardless of device timezone',
    () {
      final filters = MomoTransactionFilters(
        dates: DateTimeRange(
          start: DateTime(2026, 10, 18),
          end: DateTime(2026, 10, 20),
        ),
      );
      expect(filters.fromUtc, '2026-10-17T22:00:00.000Z');
      expect(filters.toUtc, '2026-10-20T21:59:59.999Z');
      expect(filters.dateLabel, '18 Oct 2026 – 20 Oct 2026');
    },
  );

  for (final width in [320.0, 390.0, 700.0, 1400.0]) {
    testWidgets(
      'MoMo table remains readable at $width with separate payer and beneficiary',
      (tester) async {
        final result = await pump(tester, width: width);
        expect(find.byType(DataTable), findsOneWidget);
        expect(find.byType(Card), findsNothing);
        expect(find.text('Synthetic payer · …007'), findsOneWidget);
        expect(find.text('Beneficiary'), findsOneWidget);
        expect(find.text('Group'), findsOneWidget);
        expect(find.text('Unassigned'), findsNWidgets(2));
        expect(find.text('Credited'), findsNothing);
        expect(find.textContaining('Unallocated 5,000 RWF'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, result.key, 'admin-momo-${width.toInt()}');
        await tester.pumpWidget(const SizedBox.shrink());
        result.dispose();
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('compact enlarged table keeps facts and opens the same payment', (
    tester,
  ) async {
    final result = await pump(
      tester,
      width: 320,
      textScale: 2,
      reduceMotion: true,
    );
    final table = find.byType(DataTable);
    expect(table, findsOneWidget);
    expect(find.byType(Card), findsNothing);
    final tools = find.byTooltip('More MoMo tools');
    await tester.ensureVisible(tools);
    await tester.pumpAndSettle();
    await tester.tap(tools);
    await tester.pumpAndSettle();
    final menu = ModalRoute.of(
      tester.element(find.text('Dedicated gateway (optional)')),
    )!;
    expect(menu.transitionDuration, Duration.zero);
    expect(menu.reverseTransitionDuration, Duration.zero);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    final horizontal = find.ancestor(
      of: table,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      ),
    );
    expect(horizontal, findsOneWidget);
    final position = tester.state<ScrollableState>(horizontal).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final open = find.byTooltip('Open MOMO-SYNTHETIC-001');
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.text('Payment details'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('MOMO-SYNTHETIC-001'),
      ),
      findsOneWidget,
    );
    final route = ModalRoute.of(tester.element(find.text('Payment details')))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'compact payment facts and processing history retain separate fields',
    (tester) async {
      final result = await pump(
        tester,
        width: 320,
        textScale: 2,
        reduceMotion: true,
        transactionSources: [
          {
            'raw_sms_id': rawSmsId,
            'relation': 'accepted',
            'outcome': 'accepted',
            'parser_version': 'synthetic-v1',
            'created_at': '2026-10-18T08:01:00.000Z',
          },
        ],
      );
      try {
        final payer = find.text('Synthetic payer · …007');
        await tester.ensureVisible(payer);
        await tester.pumpAndSettle();
        await tester.tap(payer);
        await tester.pumpAndSettle();
        final facts = find.byWidgetPredicate(
          (widget) =>
              widget is AdminRecordFactsTable &&
              widget.semanticLabel == 'MoMo payment facts',
        );
        expect(facts, findsOneWidget);
        for (final value in [
          '5,000',
          'MOMO-SYNTHETIC-001',
          'Collect synthetic receiver',
          '123456',
          'Synthetic payer',
          '007',
        ]) {
          expect(
            find.descendant(of: facts, matching: find.text(value)),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(of: facts, matching: find.text('Unassigned')),
          findsNWidgets(2),
        );
        expect(
          find.descendant(of: facts, matching: find.textContaining('10:00')),
          findsOneWidget,
        );
        final historyTitle = find.text('Source and processing history');
        await tester.ensureVisible(historyTitle);
        await tester.pumpAndSettle();
        await tester.tap(historyTitle);
        await tester.pumpAndSettle();
        final history = find.byWidgetPredicate(
          (widget) =>
              widget is AdminDataTable &&
              widget.tableLabel == 'Payment source and processing history',
        );
        expect(history, findsOneWidget);
        for (final value in [
          'Source reference',
          'Relationship',
          'Outcome',
          'Parser',
          'Recorded at',
          rawSmsId,
          'synthetic-v1',
          '2026-10-18T08:01:00.000Z',
        ]) {
          expect(
            find.descendant(of: history, matching: find.text(value)),
            findsOneWidget,
          );
        }
        expect(
          find.descendant(of: history, matching: find.text('accepted')),
          findsNWidgets(2),
        );
        expect(
          find.descendant(
            of: find.byWidgetPredicate(
              (widget) =>
                  widget is AdminRecordFactsTable || widget is AdminDataTable,
            ),
            matching: find.byType(ListTile),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        result.dispose();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('compact source queue keeps receipt metadata in columns', (
    tester,
  ) async {
    final result = await pump(
      tester,
      width: 320,
      textScale: 2,
      reduceMotion: true,
      sourceJobs: [sourceJob()],
    );
    try {
      await openUnresolvedSource(tester, open: false);
      final sources = find.byWidgetPredicate(
        (widget) =>
            widget is AdminDataTable &&
            widget.tableLabel == 'MoMo source messages',
      );
      expect(sources, findsOneWidget);
      for (final value in [
        'Source message',
        'Status',
        'Received at',
        'Processing issue',
        'SMS reference',
        'source_unresolved',
        '2026-10-18T08:01:00.000Z',
        'historical_source_unresolved',
        rawSmsId,
      ]) {
        expect(
          find.descendant(of: sources, matching: find.text(value)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: sources, matching: find.byType(ListTile)),
        findsNothing,
      );
      final source = find.text('Source message — receiving source unresolved');
      await tester.ensureVisible(source);
      await tester.pumpAndSettle();
      await tapVisibleSourceTitle(tester, source);
      final facts = find.byWidgetPredicate(
        (widget) =>
            widget is AdminRecordFactsTable &&
            widget.semanticLabel == 'Source message facts',
      );
      expect(
        find.descendant(of: facts, matching: find.text(rawSmsId)),
        findsOneWidget,
      );
      expect(find.text('Reveal original SMS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('metadata reader has no financial or raw-source action', (
    tester,
  ) async {
    final result = await pump(tester, permissions: ['payments.read']);
    expect(find.byTooltip('More MoMo tools'), findsNothing);
    await tester.ensureVisible(find.text('Synthetic payer · …007'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Synthetic payer · …007'));
    await tester.pumpAndSettle();
    expect(find.text('Assign for independent review'), findsNothing);
    expect(find.text('Original SMS'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'authorized filters share totals scope, reset pages, and serialize exact UTC dates',
    (tester) async {
      final queries = <Map<String, String>>[];
      final result = await pump(
        tester,
        transactionRecords: (request) {
          final query = request.url.queryParameters;
          queries.add(query);
          final filtered =
              query.containsKey('receiving_account_id') ||
              query.containsKey('group_id') ||
              query.containsKey('from');
          final offset = int.parse(query['offset']!);
          final total = filtered ? 1 : 26;
          final length = (total - offset).clamp(0, 25);
          return {
            ...page(),
            'offset': offset,
            'total': total,
            'rows': [
              for (var index = 0; index < length; index++)
                {
                  ...transaction(),
                  'id':
                      '66666666-6666-4666-8666-${(offset + index).toString().padLeft(12, '0')}',
                  if (query.containsKey('group_id')) 'group_id': groupId,
                },
            ],
            'totals': {
              'received_minor': total * 5000,
              'credited_minor': 0,
              'unallocated_minor': total * 5000,
            },
          };
        },
      );
      await tester.scrollUntilVisible(
        find.byTooltip('Next page'),
        600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(queries.last['offset'], '25');
      await tester.scrollUntilVisible(
        find.text('Date, account and group'),
        -600,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Date, account and group'));
      await tester.pumpAndSettle();
      expect(find.text('All transaction dates'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collect synthetic receiver · 123456').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('momo-group-filter-search')),
        'Synthetic',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply filters'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Synthetic savings group').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(queries.last['offset'], '0');
      expect(queries.last['receiving_account_id'], accountId);
      expect(queries.last['group_id'], groupId);
      expect(find.textContaining('Received 5,000 RWF'), findsOneWidget);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await capture(tester, result.key, 'admin-momo-filters-1400');
      final filters = MomoTransactionFilters(
        dates: DateTimeRange(
          start: DateTime(2026, 10, 18),
          end: DateTime(2026, 10, 18),
        ),
      );
      await MomoAdminApi(result.session).transactions(
        '',
        '',
        0,
        receivingAccount: accountId,
        group: groupId,
        from: filters.fromUtc,
        to: filters.toUtc,
      );
      expect(queries.last['from'], '2026-10-17T22:00:00.000Z');
      expect(queries.last['to'], '2026-10-18T21:59:59.999Z');
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(queries.last['offset'], '0');
      expect(queries.last.containsKey('receiving_account_id'), isFalse);
      expect(queries.last.containsKey('group_id'), isFalse);
      expect(queries.last.containsKey('from'), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('attention keeps the credited outcome alongside a review issue', (
    tester,
  ) async {
    final result = await pump(
      tester,
      width: 390,
      records: {
        ...page(),
        'rows': [
          {
            ...transaction(status: 'credited'),
            'payment_id': paymentId,
            'credited_amount_minor': 5000,
            'has_conflict': 1,
          },
        ],
      },
    );
    expect(find.text('Credited'), findsOneWidget);
    expect(find.text('5,000'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    await tester.tap(find.text('Needs attention'));
    await tester.pumpAndSettle();
    expect(find.text('Credited'), findsOneWidget);
    expect(find.text('5,000'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    result.dispose();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'unknown assignment outcome retries identical retained request and never credits',
    (tester) async {
      final requests = <http.Request>[];
      final result = await pump(
        tester,
        respond: (request) async {
          if (request.url.path.endsWith('/assign')) {
            requests.add(request);
            if (requests.length == 1) {
              throw http.ClientException('Synthetic response lost');
            }
            return jsonResponse({
              'transaction_id': txId,
              'payment_id': paymentId,
              'status': 'awaiting_review',
              'version': 2,
              'requires_independent_review': true,
            });
          }
          return http.Response('{}', 404);
        },
      );
      await tester.ensureVisible(find.text('Synthetic payer · …007'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic payer · …007'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign for independent review'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Assign for review'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Search eligible destinations'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic beneficiary · 123456'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence and reason'),
        'Verified beneficiary against retained identity evidence',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign for review'));
      await tester.pumpAndSettle();
      expect(find.text('Retry original request'), findsOneWidget);
      await tester.tap(find.text('Retry original request'));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(
        requests[0].headers['idempotency-key'],
        requests[1].headers['idempotency-key'],
      );
      expect(requests[0].body, requests[1].body);
      expect(
        find.textContaining('Financial posting still follows'),
        findsOneWidget,
      );
      expect(find.text('Credited'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'pairing requires a selected account and shows only short-lived pairing code',
    (tester) async {
      final result = await pump(
        tester,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/bindings')) {
            expect(jsonDecode(request.body)['subscription_id'], 2);
            return jsonResponse({
              'binding_id': txId,
              'version': 1,
              'pairing_code': 'SYNTHETIC-ONE-TIME-PAIRING-CODE',
              'expires_in_seconds': 600,
            });
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create phone pairing code'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Collect synthetic receiver · 123456 · unverified').last,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Account ownership and pairing reason'),
        'Verified dedicated receiving account and operator',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Receiving SIM subscription ID (optional)',
        ),
        '2', // Synthetic observed Android diagnostic value, never a default.
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create phone pairing code'));
      await tester.pumpAndSettle();
      expect(find.text('SYNTHETIC-ONE-TIME-PAIRING-CODE'), findsOneWidget);
      expect(find.textContaining('expires in 10 minutes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
      await tester.pumpAndSettle();
    },
  );
}
