import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/utils/date_format.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';

PaymentIntentModel intent({
  bool credited = false,
  bool providerTime = true,
  String status = 'pending',
  DateTime? expiresAt,
  String? confirmationStatus,
}) => PaymentIntentModel(
  id: 'synthetic-intent',
  collectionId: 'qa-private-group',
  expectedAmountRwf: 5000,
  receiverMomoNumber: '123456',
  receiverMomoNumberHash: 'synthetic-receiver',
  receiverMomoLabel: 'Collect synthetic receiver',
  status: status,
  createdAt: DateTime.utc(2026, 10, 18),
  expiresAt: expiresAt ?? DateTime.utc(2030),
  confirmationStatus:
      confirmationStatus ?? (credited ? 'credited' : 'awaiting_confirmation'),
  paymentId: credited ? 'synthetic-payment' : null,
  contributionEntryId: credited ? 'synthetic-entry' : null,
  creditedAmountRwf: credited ? 5000 : null,
  postedAt: credited ? DateTime.utc(2026, 10, 18, 10) : null,
  providerTransactionAt: credited && providerTime
      ? DateTime.utc(2026, 10, 18, 8, 15)
      : null,
  providerTransactionReference: credited ? 'MOMO-SYNTHETIC-001' : null,
  balanceAfterContributionRwf: credited ? 12500 : null,
);

class _Repository extends FixtureCollectRepository {
  _Repository({bool existing = false}) {
    state = state.copyWith(paymentIntents: existing ? [intent()] : []);
  }
  int creates = 0, checks = 0, loads = 0;
  PaymentIntentModel response = intent();
  bool fail = false;
  void publish(PaymentIntentModel updated) {
    state = state.copyWith(paymentIntents: [updated]);
  }

  @override
  Future<PaymentIntentModel> createPaymentIntent(
    PaymentIntentDraft draft,
  ) async {
    creates++;
    state = state.copyWith(paymentIntents: [intent()]);
    return intent();
  }

  @override
  Future<PaymentIntentModel> refreshPaymentIntent(String id) async {
    checks++;
    if (fail) throw StateError('Synthetic network interruption');
    state = state.copyWith(paymentIntents: [response]);
    return response;
  }

  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async => loads++;
}

void main() {
  var opened = true;
  var launches = 0;
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    opened = true;
    launches = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('collect/momo_ussd'), (
          call,
        ) async {
          launches++;
          return opened;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('collect/momo_ussd'),
          null,
        );
  });

  Future<GlobalKey> pump(
    WidgetTester tester,
    _Repository repository, {
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((_) => repository)],
        child: MaterialApp(
          theme: CollectTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 844),
              textScaler: TextScaler.linear(scale),
            ),
            child: RepaintBoundary(
              key: key,
              child: const ContributionFlowScreen(
                collectionId: 'qa-private-group',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  Future<void> prepare(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '5000');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Continue to MoMo'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to MoMo'));
    await tester.pumpAndSettle();
  }

  Future<void> capture(
    WidgetTester tester,
    GlobalKey key,
    String name, {
    bool resetScroll = true,
  }) async {
    final directory = Platform.environment['COLLECT_MOMO_CAPTURE_DIR'];
    if (directory == null) return;
    if (resetScroll) {
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(0);
    }
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final snapshot = await boundary.toImage(pixelRatio: 1);
      final bytes = await snapshot.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      snapshot.dispose();
    });
  }

  testWidgets('dialer return and status checks do not credit a balance', (
    tester,
  ) async {
    final repository = _Repository();
    final balances = repository.state.collectionSummaries;
    final key = await pump(tester, repository);
    await prepare(tester);
    expect(find.text('Collect synthetic receiver'), findsOneWidget);
    expect(find.text('Copy payment code'), findsOneWidget);
    expect(find.text('Copy amount'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Open MoMo USSD'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Open MoMo USSD'));
    await tester.pumpAndSettle();
    expect(launches, 1);
    expect(find.text('MoMo request opened'), findsOneWidget);
    expect(find.text('Credited'), findsNothing);
    await tester.tap(find.text('Check payment'));
    await tester.pumpAndSettle();
    expect(repository.checks, 1);
    expect(
      repository.creates,
      2,
    ); // Preparation and live dialer preflight only.
    expect(repository.state.collectionSummaries, balances);
    expect(repository.loads, 0);
    expect(find.text('Awaiting confirmation'), findsOneWidget);
    expect(find.text('MoMo request opened'), findsNothing);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'member-awaiting-390');
  });

  testWidgets(
    'linked payment record without a ledger entry does not imply receipt or credit',
    (tester) async {
      // Match the accepted payment_received wire case: a linked payment row,
      // no contribution entry and no evidence object or provider reference.
      final linkedRecord = PaymentIntentModel.fromJson(const {
        'id': 'synthetic-intent',
        'collection_id': 'qa-private-group',
        'amount_minor': 5000,
        'status': 'pending',
        'created_at': '2026-10-18T08:00:00Z',
        'expires_at': '2030-01-01T00:00:00Z',
        'receiver_momo_number': '123456',
        'receiver_label': 'Collect synthetic receiver',
        'confirmation_status': 'payment_received',
        'payment_id': 'synthetic-payment',
        'contribution_entry_id': null,
        'credited_amount_rwf': null,
        'posted_at': null,
        'provider_transaction_reference': null,
        'provider_transaction_at': null,
      });
      expect(linkedRecord.hasCommittedContribution, isFalse);
      final repository = _Repository(existing: true)..response = linkedRecord;
      final balances = repository.state.collectionSummaries;
      final contributions = repository.state.contributions;
      await pump(tester, repository);
      await tester.tap(find.text('Resume payment request'));
      await tester.pumpAndSettle();

      expect(find.text('Payment record linked'), findsOneWidget);
      expect(
        find.textContaining('A payment record is linked to this request.'),
        findsOneWidget,
      );
      expect(find.textContaining('awaiting review'), findsNothing);
      expect(find.text('Payment received'), findsNothing);
      expect(find.textContaining('Your payment was received'), findsNothing);
      expect(find.text('Credited'), findsNothing);
      expect(find.text('Contribution credited'), findsNothing);
      expect(find.text('Balance after this contribution'), findsNothing);
      expect(find.textContaining('Provider transaction '), findsNothing);
      expect(find.text('Check payment'), findsOneWidget);
      expect(find.text('Payment help'), findsOneWidget);
      expect(repository.state.collectionSummaries, balances);
      expect(repository.state.contributions, contributions);
      expect(repository.loads, 0);
      expect(repository.creates, 0);
      expect(repository.checks, 1);
      expect(launches, 0);
      expect(tester.takeException(), isNull);

      // Only a subsequent authoritative contribution association may advance
      // this same request to the existing credited receipt and history reader.
      repository.response = intent(credited: true);
      await tester.tap(find.text('Check payment'));
      await tester.pumpAndSettle();
      expect(find.text('Credited'), findsOneWidget);
      expect(find.text('Balance after this contribution'), findsOneWidget);
      expect(find.text('Payment record linked'), findsNothing);
      expect(repository.loads, 1);
      expect(repository.checks, 2);
      expect(repository.creates, 0);
      expect(launches, 0);
      expect(repository.state.collectionSummaries, balances);
      expect(repository.state.contributions, contributions);
      expect(tester.takeException(), isNull);
    },
  );

  for (final update in [
    'expired',
    'unknown_state',
    'elapsed_lifetime',
    'needs_review',
  ]) {
    testWidgets('opened handoff yields to authoritative $update', (
      tester,
    ) async {
      final repository = _Repository();
      final balances = repository.state.collectionSummaries;
      await pump(tester, repository);
      await prepare(tester);
      await tester.scrollUntilVisible(
        find.text('Open MoMo USSD'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Open MoMo USSD'));
      await tester.pumpAndSettle();
      expect(find.text('MoMo request opened'), findsOneWidget);
      expect(launches, 1);

      repository.publish(switch (update) {
        'elapsed_lifetime' => intent(
          expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
        'needs_review' => intent(confirmationStatus: 'needs_review'),
        _ => intent(status: update),
      });
      await tester.pumpAndSettle();
      expect(find.text('MoMo request opened'), findsNothing);
      expect(find.text('Credited'), findsNothing);
      if (update == 'elapsed_lifetime') {
        expect(find.textContaining('This request expired'), findsOneWidget);
      }
      if (update == 'needs_review') {
        expect(find.text('Needs help'), findsOneWidget);
      }
      expect(repository.state.collectionSummaries, balances);
      expect(repository.loads, 0);
      expect(repository.creates, 2);
      expect(repository.checks, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'resume fetches existing intent without creating or opening payment',
    (tester) async {
      final repository = _Repository(existing: true);
      await pump(tester, repository);
      await tester.tap(find.text('Resume payment request'));
      await tester.pumpAndSettle();
      expect(repository.creates, 0);
      expect(repository.checks, 1);
      expect(launches, 0);
      expect(find.text('Check payment'), findsOneWidget);
      expect(find.text('Awaiting confirmation'), findsOneWidget);
      expect(find.text('MoMo request opened'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsupported dialer retains usable manual instructions at enlarged text',
    (tester) async {
      opened = false;
      final repository = _Repository();
      final key = await pump(tester, repository, width: 320, scale: 2);
      await prepare(tester);
      await tester.scrollUntilVisible(
        find.text('Open MoMo USSD'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open MoMo USSD'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Check payment'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Check payment'), findsOneWidget);
      expect(find.text('MoMo request opened'), findsNothing);
      expect(
        find.textContaining('Copy the code and amount above'),
        findsOneWidget,
      );
      expect(find.text('Credited'), findsNothing);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'member-manual-320-text2');
    },
  );

  testWidgets(
    'committed association shows receipt and refresh failure preserves it',
    (tester) async {
      final repository = _Repository(existing: true)
        ..response = intent(credited: true);
      final key = await pump(tester, repository);
      await tester.tap(find.text('Resume payment request'));
      await tester.pumpAndSettle();
      expect(find.text('Credited'), findsOneWidget);
      expect(find.text('Balance after this contribution'), findsOneWidget);
      expect(find.textContaining('MOMO-SYNTHETIC-001'), findsOneWidget);
      expect(
        find.textContaining(
          'Provider transaction ${formatCollectDateTime(repository.response.providerTransactionAt!)}',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Credited ${formatCollectDateTime(repository.response.postedAt!)}',
        ),
        findsOneWidget,
      );
      final providerText = tester.widget<Text>(
        find.textContaining('Provider transaction '),
      );
      expect(providerText.data, matches(RegExp(r'\(UTC[+-]\d{2}:\d{2}\)$')));
      expect(find.text('Copy payment code'), findsNothing);
      expect(repository.loads, 1);
      await capture(tester, key, 'member-credited-390');
      repository.fail = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Credited'), findsOneWidget);
      expect(find.text('Status could not refresh'), findsOneWidget);
      expect(repository.loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'legacy receipt omits absent provider time and keeps credited time',
    (tester) async {
      final repository = _Repository(existing: true)
        ..response = intent(credited: true, providerTime: false);
      await pump(tester, repository);
      await tester.tap(find.text('Resume payment request'));
      await tester.pumpAndSettle();
      expect(find.text('Credited'), findsOneWidget);
      expect(find.textContaining('Provider transaction '), findsNothing);
      expect(
        find.textContaining(
          'Credited ${formatCollectDateTime(repository.response.postedAt!)}',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('provider and credited times reflow at 320 with enlarged text', (
    tester,
  ) async {
    final repository = _Repository(existing: true)
      ..response = intent(credited: true);
    final key = await pump(tester, repository, width: 320, scale: 2);
    await tester.scrollUntilVisible(
      find.text('Resume payment request'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Resume payment request'));
    await tester.pumpAndSettle();
    final provider = find.textContaining('Provider transaction ');
    final credited = find.textContaining(
      'Credited ${formatCollectDateTime(repository.response.postedAt!)}',
    );
    await tester.scrollUntilVisible(
      provider,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    for (final finder in [provider, credited]) {
      expect(finder, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.size.width, lessThanOrEqualTo(320));
      expect(tester.widget<Text>(finder).maxLines, isNull);
    }
    expect(tester.takeException(), isNull);
    await capture(
      tester,
      key,
      'resume-receipt-times-320-text2',
      resetScroll: false,
    );
  });

  testWidgets(
    'existing repository invalidation advances an open screen without optimistic credit',
    (tester) async {
      final repository = _Repository();
      final balances = repository.state.collectionSummaries;
      await pump(tester, repository);
      await prepare(tester);
      repository.publish(intent(credited: true));
      await tester.pumpAndSettle();
      expect(find.text('Credited'), findsOneWidget);
      expect(find.text('Balance after this contribution'), findsOneWidget);
      expect(repository.checks, 0);
      expect(launches, 0);
      expect(repository.state.collectionSummaries, balances);
      repository.publish(intent());
      await tester.pumpAndSettle();
      expect(find.text('Credited'), findsOneWidget);
      expect(find.text('Awaiting confirmation'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
