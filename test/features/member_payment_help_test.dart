import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:collect_app/features/payments/contribution_flow_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/member_data_authority_test.dart' as authority;
import '../shared/member_signed_history_test.dart' as history;
import '../shared/payment_support_review_test.dart' as support;

const paymentId = '80000000-0000-4000-8000-000000000001';
PaymentIntentModel intent({bool committed = false}) => PaymentIntentModel(
  id: support.intentId,
  collectionId: authority.group,
  expectedAmountRwf: 5000,
  receiverMomoNumber: '123456',
  receiverMomoLabel: 'Synthetic receiving account',
  status: committed ? 'matched' : 'pending',
  createdAt: DateTime.utc(2026),
  expiresAt: DateTime.utc(2030),
  confirmationStatus: committed ? 'reversed' : 'awaiting_confirmation',
  paymentId: committed ? paymentId : null,
  contributionEntryId: committed ? history.uuid(1) : null,
  creditedAmountRwf: committed ? 5000 : null,
  postedAt: committed ? DateTime.utc(2026, 10, 18, 10) : null,
  providerTransactionAt: committed ? DateTime.utc(2026, 10, 18, 8, 15) : null,
  balanceAfterContributionRwf: committed ? 12500 : null,
);

class _Repository extends authority.Repository {
  _Repository(super.client, {bool committed = false}) {
    state = state.copyWith(
      collections: [
        state.collections.single.copyWith(
          isCurrentUserMember: true,
          receiverMomoNumber: '123456',
          receiverDisplayLabel: 'Synthetic receiving account',
          receiverNetwork: 'mtn_momo',
          primaryPaymentRail: 'rwanda_momo',
        ),
      ],
      paymentIntents: [intent(committed: committed)],
    );
  }
  final queries = <MemberHistoryQuery>[];
  @override
  Future<void> loadInitial({bool syncPendingSms = false}) async {}
  @override
  Future<PaymentIntentModel> refreshPaymentIntent(String id) async =>
      intentById(id);
  @override
  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  }) async {
    queries.add(query);
    return history.decode(
      history.wire([
        {
          ...history.event(2, amount: -5000, kind: 'reversal', reverses: 1),
          'collection_id': authority.group,
          'payment_id': paymentId,
        },
        {
          ...history.event(1, amount: 5000),
          'collection_id': authority.group,
          'payment_id': paymentId,
        },
      ]),
    );
  }
}

void main() {
  final protectedValues = <String, String>{};
  var failProtectedWrite = false, failProtectedRead = false;
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
    protectedValues.clear();
    failProtectedWrite = false;
    failProtectedRead = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('collect/payment_help_pending'),
          (call) async {
            final args = call.arguments as Map;
            final owner = args['owner_id'] as String;
            switch (call.method) {
              case 'read':
                if (failProtectedRead) {
                  throw PlatformException(code: 'synthetic_read_failure');
                }
                return protectedValues[owner];
              case 'write':
                if (failProtectedWrite) return false;
                protectedValues[owner] = args['value'] as String;
                return true;
              case 'clear':
                protectedValues.remove(owner);
                return true;
            }
            throw StateError('Unexpected protected store operation');
          },
        );
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('collect/payment_help_pending'),
          null,
        ),
  );

  Future<
    ({
      GlobalKey key,
      _Repository repo,
      CollectCloudflareClient client,
      List<http.Request> requests,
    })
  >
  pump(
    WidgetTester tester, {
    bool loseFirst = false,
    bool committed = false,
    double width = 390,
    double scale = 1,
    bool actualRouter = false,
    String sessionId = authority.firstSession,
    String requestStatus = 'absent',
    bool statusUnavailable = false,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final client = CollectCloudflareClient(
      'https://api.example.test',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith(
          '/get_current_member_payment_review_request_v1',
        )) {
          if (statusUnavailable) return http.Response('{}', 503);
          final body = jsonDecode(request.body) as Map;
          return authority.jsonResponse({
            'id': body['p_request_id'],
            'status': requestStatus,
            'collection_id': body['p_collection_id'],
            'intent_id': body['p_intent_id'],
            'financial_effects': 0,
          });
        }
        if (request.url.path.endsWith('/create_mobile_support_request')) {
          requests.add(request);
          if (loseFirst && requests.length == 1) {
            throw http.ClientException('Synthetic lost response');
          }
          final body = jsonDecode(request.body) as Map;
          return authority.jsonResponse({
            'id': body['p_request_id'],
            'status': 'received',
            'collection_id': body['p_collection_id'],
            'intent_id': body['p_intent_id'],
            'financial_effects': 0,
          });
        }
        return http.Response('{}', 404);
      }),
    );
    await client.auth.recoverSession(
      authority.session(authority.actor, sessionId),
    );
    final repo = _Repository(client, committed: committed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await client.dispose();
    });
    final key = GlobalKey();
    final router = actualRouter
        ? createAppRouter(
            initialLocation: '/groups/${authority.group}/contribute',
          )
        : null;
    if (router != null) addTearDown(router.dispose);
    Widget app = router == null
        ? MaterialApp(
            theme: CollectTheme.dark(),
            home: const ContributionFlowScreen(collectionId: authority.group),
          )
        : MaterialApp.router(theme: CollectTheme.dark(), routerConfig: router);
    app = MediaQuery(
      data: MediaQueryData(
        size: Size(width, 844),
        textScaler: TextScaler.linear(scale),
      ),
      child: app,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            collectBackendClientProvider.overrideWithValue(client),
            collectRepositoryProvider.overrideWith((_) => repo),
          ],
          child: app,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Resume payment request'));
    await tester.tap(find.text('Resume payment request'));
    await tester.pumpAndSettle();
    return (key: key, repo: repo, client: client, requests: requests);
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final folder = Platform.environment['COLLECT_MOMO_CAPTURE_DIR'];
    if (folder == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$folder/resume-member-help-$name.png');
      if (file.existsSync()) {
        throw StateError('Refusing to replace existing capture');
      }
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'payment help submits real scoped request and never credits a balance',
    (tester) async {
      final h = await pump(tester);
      final before = h.repo.state.collectionSummaries;
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Reference'),
        'SYNTHETIC-007',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence note'),
        'Synthetic retained receipt evidence',
      );
      await tester.ensureVisible(find.text('Request check'));
      await tester.pumpAndSettle();
      await capture(tester, h.key, 'sheet-390');
      await tester.tap(find.text('Request check'));
      await tester.pumpAndSettle();
      expect(h.requests.length, 1);
      final body = jsonDecode(h.requests.single.body) as Map;
      expect(body['p_kind'], 'payment_review');
      expect(body['p_collection_id'], authority.group);
      expect(body['p_intent_id'], support.intentId);
      expect(body['p_provider_reference'], 'SYNTHETIC-007');
      expect(body['p_note'], 'Synthetic retained receipt evidence');
      expect(find.text('Request received'), findsOneWidget);
      expect(h.repo.state.collectionSummaries, before);
      expect(
        h.repo.state.paymentIntents.single.hasCommittedContribution,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await h.client.dispose();
    },
  );
  testWidgets(
    'unknown help reply retries identical request after sheet reopens',
    (tester) async {
      final h = await pump(tester, loseFirst: true);
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextField, 'Evidence note'),
        findsOneWidget,
        reason: tester.allWidgets
            .whereType<Text>()
            .map((text) => text.data)
            .join(' | '),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence note'),
        'Synthetic evidence for same request',
      );
      await tester.ensureVisible(find.text('Request check'));
      await tester.tap(find.text('Request check'));
      await tester.pumpAndSettle();
      expect(find.text('Request received'), findsNothing);
      expect(find.text('Retry request'), findsOneWidget);
      await tester.tap(find.byTooltip('Close payment help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      expect(h.requests.length, 1);
      expect(find.text('Retry request'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('Your original details are saved.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('You can add the provider reference'),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Retry request'));
      await capture(tester, h.key, 'recovery-pending-copy-final-390');
      await tester.tap(find.text('Retry request'));
      await tester.pumpAndSettle();
      expect(h.requests.length, 2);
      expect(h.requests[0].body, h.requests[1].body);
      expect(find.text('Request received'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await h.client.dispose();
    },
  );
  testWidgets('payment help remains reachable at 320 and 200 percent text', (
    tester,
  ) async {
    final h = await pump(tester, width: 320, scale: 2);
    await tester.ensureVisible(find.text('Payment help'));
    await tester.tap(find.text('Payment help'));
    await tester.pumpAndSettle();
    final submit = find.text('Request check');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit.hitTestable(), findsOneWidget);
    expect(MediaQuery.textScalerOf(tester.element(submit)).scale(10), 20);
    await capture(tester, h.key, 'sheet-320-text2');
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(h.requests.length, 1);
    expect(find.text('Request received'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await h.client.dispose();
  });
  testWidgets(
    'restart and replacement sign-in retry exact saved body, then retain Received',
    (tester) async {
      final first = await pump(tester, loseFirst: true);
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Reference'),
        'ORIGINAL-RESTART-007',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Evidence note'),
        'Original durable evidence note',
      );
      await tester.ensureVisible(find.text('Request check'));
      await tester.tap(find.text('Request check'));
      await tester.pumpAndSettle();
      expect(first.requests, hasLength(1));
      final exactBody = first.requests.single.body;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await first.client.dispose();

      final second = await pump(tester, sessionId: authority.nextSession);
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Original durable evidence note'), findsOneWidget);
      await tester.ensureVisible(find.text('Retry request'));
      await capture(tester, second.key, 'recovery-pending-390');
      await tester.tap(find.text('Retry request'));
      await tester.pumpAndSettle();
      expect(second.requests, hasLength(1));
      expect(second.requests.single.body, exactBody);
      expect(
        second.requests.single.headers['Authorization'],
        'Bearer ${authority.jwt(authority.actor, authority.nextSession)}',
      );
      expect(find.text('Request received'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await second.client.dispose();

      final third = await pump(tester, sessionId: authority.nextSession);
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      expect(find.text('Request received'), findsOneWidget);
      expect(find.text('Request check'), findsNothing);
      expect(third.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await capture(tester, third.key, 'recovery-received-390');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await third.client.dispose();
    },
  );
  testWidgets(
    'unknown old-session commit is recovered by read without another submission',
    (tester) async {
      final first = await pump(
        tester,
        loseFirst: true,
        statusUnavailable: true,
      );
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Request check'));
      await tester.tap(find.text('Request check'));
      await tester.pumpAndSettle();
      expect(first.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await first.client.dispose();
      final second = await pump(
        tester,
        sessionId: authority.nextSession,
        requestStatus: 'received',
      );
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Retry request'));
      await tester.tap(find.text('Retry request'));
      await tester.pumpAndSettle();
      expect(second.requests, isEmpty);
      expect(find.text('Request received'), findsOneWidget);
      expect(
        second.repo.state.paymentIntents.single.hasCommittedContribution,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await second.client.dispose();
    },
  );
  testWidgets(
    'unavailable protected write or unreadable recovery never sends a request',
    (tester) async {
      final h = await pump(tester);
      await tester.ensureVisible(find.text('Payment help'));
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      failProtectedWrite = true;
      await tester.ensureVisible(find.text('Request check'));
      await tester.tap(find.text('Request check'));
      await tester.pumpAndSettle();
      expect(h.requests, isEmpty);
      expect(
        find.text('Payment help could not be saved. Try again.'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close payment help'));
      await tester.pumpAndSettle();
      failProtectedRead = true;
      await tester.tap(find.text('Payment help'));
      await tester.pumpAndSettle();
      expect(find.text('Try recovery'), findsOneWidget);
      expect(find.text('Request check'), findsNothing);
      expect(h.requests, isEmpty);
      failProtectedRead = false;
      failProtectedWrite = false;
      await tester.ensureVisible(find.text('Try recovery'));
      await tester.tap(find.text('Try recovery'));
      await tester.pumpAndSettle();
      expect(find.text('Request check'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await h.client.dispose();
    },
  );
  testWidgets(
    'receipt opens its group and exact payment history including reversal',
    (tester) async {
      final h = await pump(tester, committed: true, actualRouter: true);
      expect(find.text('Reversed'), findsOneWidget);
      await tester.ensureVisible(find.text('View activity'));
      await tester.tap(find.text('View activity'));
      await tester.pumpAndSettle();
      expect(h.repo.queries.last.collectionId, authority.group);
      expect(h.repo.queries.last.search, paymentId);
      final rows = tester.widgetList<FinancialListRow>(
        find.byType(FinancialListRow),
      );
      expect(rows.map((row) => row.amountRwf), containsAll([5000, -5000]));
      expect(rows.map((row) => row.subtitle), contains('Recorded reversal'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await h.client.dispose();
    },
  );
}
