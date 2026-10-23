import 'dart:async';
import 'dart:convert';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/features/settings/settings_subscreens.dart';
import 'package:collect_app/features/settings/receipt_sms_consent_section.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:collect_app/shared/models/receipt_sms_consent.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../support/receipt_sms_harness.dart';

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([inter.load(), icons.load()]);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<ReceiptSmsHarness> mount(
    WidgetTester tester, {
    double scale = 1,
    bool longTitle = false,
  }) async {
    final h = (await tester.runAsync(ReceiptSmsHarness.create))!;
    if (longTitle) {
      h.repo.replaceGroups([
        smsCollection(
          smsGroup,
          'Community contribution group with a complete long name that must remain readable',
        ),
        smsCollection(smsGroupB, 'Another group'),
      ]);
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(h.close);
    });
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [collectRepositoryProvider.overrideWith((ref) => h.repo)],
        child: MaterialApp(
          theme: CollectTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: NotificationSettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await reach(tester, find.byType(ReceiptSmsConsentSection));
    return h;
  }

  Future<void> button(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await reach(tester, target);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> choose(
    WidgetTester tester,
    ReceiptSmsHarness h,
    String title, {
    bool wait = true,
    String group = smsGroup,
  }) async {
    await button(tester, 'receipt-sms-group');
    await tester.pumpAndSettle();
    expect(find.text('Public group'), findsNothing);
    final row = find.widgetWithText(ListTile, title);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 250));
    if (wait) {
      await idle(tester, h, onlyGroup: group);
    } else {
      await tester.runAsync(() async {
        for (var i = 0; i < 8; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
    }
  }

  testWidgets(
    'existing settings exposes only actual memberships, with no default or write before explicit group selection',
    (tester) async {
      final h = await mount(tester);
      expect(h.reads, isEmpty);
      expect(h.writes, isEmpty);
      await choose(tester, h, 'Community group');
      expect(h.reads, [smsGroup]);
      expect(h.writes, isEmpty);
      expect(find.text('Saved choice: Off'), findsOneWidget);
    },
  );
  testWidgets(
    'unsupported backend is truthful and cannot expose an enabled opt-in',
    (tester) async {
      final h = await mount(tester);
      h.unsupported = true;
      await choose(tester, h, 'Community group');
      expect(
        find.textContaining('not available from this service yet'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('receipt-sms-opt-in')), findsNothing);
      expect(h.writes, isEmpty);
    },
  );
  testWidgets(
    'blocked saved opt-in is not shown as withdrawn; explicit withdrawal remains available without new phone proof',
    (tester) async {
      final h = await mount(tester);
      h.remote['$smsUser/$smsGroup'] = smsRead(
        smsGroup,
        optIn: true,
        revision: 1,
        status: 'blocked_phone_binding',
        binding: false,
        proof: false,
        available: false,
        reason: 'current_phone_verification_required',
      );
      await choose(tester, h, 'Community group');
      expect(find.text('Saved choice: On'), findsOneWidget);
      expect(find.textContaining('saved choice is still On'), findsOneWidget);
      expect(
        tester
            .widget<CollectButton>(
              find.byKey(const ValueKey('receipt-sms-opt-in')),
            )
            .onPressed,
        isNull,
      );
      await button(tester, 'receipt-sms-withdraw');
      await idle(tester, h);
      expect(h.writes.single['p_opt_in'], isFalse);
      expect(find.text('Last read choice: On'), findsOneWidget);
      expect(find.textContaining('Decision recorded.'), findsOneWidget);
    },
  );
  testWidgets(
    'Direct verification is pending and never inferred from push or MoMo',
    (tester) async {
      final h = await mount(tester);
      h.remote['$smsUser/$smsGroup'] = smsRead(
        smsGroup,
        proof: false,
        available: false,
        reason: 'direct_recipient_verification_required',
      );
      await choose(tester, h, 'Community group');
      expect(
        find.textContaining('Direct member phone verification is pending'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CollectButton>(
              find.byKey(const ValueKey('receipt-sms-opt-in')),
            )
            .onPressed,
        isNull,
      );
      expect(h.writes, isEmpty);
    },
  );
  testWidgets(
    'matching current status after an unknown save keeps original request recovery and forbids a new choice',
    (tester) async {
      final h = await mount(tester);
      await choose(tester, h, 'Community group');
      h.loseReply = true;
      await button(tester, 'receipt-sms-opt-in');
      await idle(tester, h);
      final original = h.writes.single['p_request_id'];
      expect(
        find.text('Unconfirmed choice: Allow receipt SMS'),
        findsOneWidget,
      );
      await button(tester, 'receipt-sms-refresh');
      await idle(tester, h);
      expect(h.writes, hasLength(1));
      expect(find.text('Saved choice: On'), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-sms-withdraw')), findsNothing);
      await button(tester, 'receipt-sms-retry');
      await idle(tester, h);
      expect(h.writes.last['p_request_id'], original);
      expect(h.writes, hasLength(2));
    },
  );
  testWidgets(
    'selected-group change while first status is delayed cannot display the old group response',
    (tester) async {
      final h = await mount(tester);
      h.readGates[smsGroup] = Completer<http.Response>();
      await choose(tester, h, 'Community group', wait: false);
      await choose(tester, h, 'Another group', group: smsGroupB);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('receipt-sms-group-title')))
            .data,
        'Another group',
      );
      h.readGates[smsGroup]!.complete(
        http.Response(
          jsonEncode(smsRead(smsGroup, optIn: true, revision: 1)),
          200,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(find.text('Saved choice: Off'), findsOneWidget);
      expect(find.text('Saved choice: On'), findsNothing);
      expect(h.writes, isEmpty);
    },
  );
  testWidgets(
    'an earlier sign-in retains its identity and exposes only explicit withdrawal recovery',
    (tester) async {
      final h = await mount(tester);
      await tester.runAsync(() async {
        await h.store.claim(
          const PendingReceiptSmsRequest(
            userId: smsUser,
            sessionId: smsSession,
            collectionId: smsGroup,
            requestId: 'd5000000-0000-4000-8000-000000000001',
            expectedRevision: 0,
            expectedDecisionRevision: 0,
            optIn: true,
          ),
        );
        await h.login(smsUser, smsNextSession);
      });
      await tester.pumpAndSettle();
      await choose(tester, h, 'Community group');
      expect(
        find.textContaining('Earlier sign-ins have unresolved requests'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('receipt-sms-retry')), findsNothing);
      expect(find.byKey(const ValueKey('receipt-sms-opt-in')), findsNothing);
      expect(find.byKey(const ValueKey('receipt-sms-withdraw')), findsNothing);
      expect(h.writes, isEmpty);
      final retained = await tester.runAsync(
        () => h.store.read(userId: smsUser, collectionId: smsGroup),
      );
      expect(retained!.pending.single.sessionId, smsSession);
    },
  );
  testWidgets(
    'cached-only groups allow a truthful read but no consent change',
    (tester) async {
      final h = await mount(tester);
      h.repo.offline();
      await tester.pump();
      await choose(tester, h, 'Community group');
      expect(find.textContaining('Cached groups are shown'), findsOneWidget);
      expect(
        tester
            .widget<CollectButton>(
              find.byKey(const ValueKey('receipt-sms-opt-in')),
            )
            .onPressed,
        isNull,
      );
      expect(h.writes, isEmpty);
    },
  );
  testWidgets(
    'no current memberships has an honest empty state without any read or default choice',
    (tester) async {
      final h = await mount(tester);
      h.repo.replaceGroups([
        smsCollection(smsForeign, 'Public group', member: false),
      ]);
      await tester.pump();
      expect(
        find.text('There are no current groups to manage here.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('receipt-sms-group')), findsNothing);
      expect(h.reads, isEmpty);
      expect(h.writes, isEmpty);
    },
  );
  testWidgets(
    'a pre-dispatch failure is visible and never invents a saved choice',
    (tester) async {
      final h = await mount(tester);
      h.repo.refuseNextConsentRead = true;
      await choose(tester, h, 'Community group');
      expect(
        find.textContaining('Receipt SMS could not be checked or changed'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('receipt-sms-saved-choice')),
        findsNothing,
      );
      expect(h.reads, isEmpty);
      expect(h.writes, isEmpty);
    },
  );
  testWidgets(
    'explicit recovery withdraws through the current session and retains the earlier unknown identity',
    (tester) async {
      final h = await mount(tester);
      const original = PendingReceiptSmsRequest(
        userId: smsUser,
        sessionId: smsSession,
        collectionId: smsGroup,
        requestId: 'd5000000-0000-4000-8000-000000000001',
        expectedRevision: 0,
        expectedDecisionRevision: 0,
        optIn: true,
      );
      await tester.runAsync(() async {
        await h.store.claim(original);
        await h.login(smsUser, smsNextSession);
      });
      await tester.pumpAndSettle();
      await choose(tester, h, 'Community group');
      expect(h.writes, isEmpty);
      await button(tester, 'receipt-sms-withdraw-recover');
      await idle(tester, h);
      expect(h.writes.single['p_opt_in'], isFalse);
      expect(h.writes.single['p_expected_revision'], 0);
      expect(h.writes.single['p_expected_decision_revision'], 0);
      expect(find.textContaining('Decision recorded.'), findsOneWidget);
      expect(
        find.textContaining('original outcomes remain unconfirmed'),
        findsOneWidget,
      );
      final retained = await tester.runAsync(
        () => h.store.read(userId: smsUser, collectionId: smsGroup),
      );
      expect(retained!.pending, isEmpty);
      expect(retained.superseded.single.request.toJson(), original.toJson());
      expect(h.reads, hasLength(1));
      await button(tester, 'receipt-sms-refresh');
      await idle(tester, h);
      expect(find.text('Saved choice: Off'), findsOneWidget);
    },
  );
  testWidgets(
    'lost recovery acknowledgement keeps both requests and offers exact retry without a new withdrawal',
    (tester) async {
      final h = await mount(tester);
      await tester.runAsync(() async {
        await h.store.claim(
          const PendingReceiptSmsRequest(
            userId: smsUser,
            sessionId: smsSession,
            collectionId: smsGroup,
            requestId: 'd5000000-0000-4000-8000-000000000001',
            expectedRevision: 0,
            expectedDecisionRevision: 0,
            optIn: true,
          ),
        );
        await h.login(smsUser, smsNextSession);
      });
      await tester.pumpAndSettle();
      await choose(tester, h, 'Community group');
      h.loseReply = true;
      await button(tester, 'receipt-sms-withdraw-recover');
      await idle(tester, h);
      final id = h.writes.single['p_request_id'];
      expect(
        find.text('2 unresolved request identities are retained.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('receipt-sms-withdraw-recover')),
        findsNothing,
      );
      await button(tester, 'receipt-sms-refresh');
      await idle(tester, h);
      expect(h.writes, hasLength(1));
      expect(find.text('Saved choice: Off'), findsOneWidget);
      await button(tester, 'receipt-sms-retry');
      await idle(tester, h);
      expect(h.writes.last['p_request_id'], id);
      expect(h.current(smsGroup)['decision_revision'], 1);
    },
  );
  testWidgets(
    '320dp2x unknown recovery keeps full status and reachable named retry without clipping',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await mount(tester, scale: 2, longTitle: true);
        await tester.runAsync(() async {
          await h.store.claim(
            const PendingReceiptSmsRequest(
              userId: smsUser,
              sessionId: smsSession,
              collectionId: smsGroup,
              requestId: 'd5000000-0000-4000-8000-000000000001',
              expectedRevision: 0,
              expectedDecisionRevision: 0,
              optIn: true,
            ),
          );
          await h.login(smsUser, smsNextSession);
        });
        await tester.pumpAndSettle();
        await choose(tester, h, 'Community group');
        h.loseReply = true;
        await button(tester, 'receipt-sms-withdraw-recover');
        await idle(tester, h);
        await button(tester, 'receipt-sms-refresh');
        await idle(tester, h);
        final retry = find.byKey(const ValueKey('receipt-sms-retry'));
        await reach(tester, retry);
        expect(retry.hitTestable(), findsOneWidget);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byType(ReceiptSmsConsentSection),
            matching: find.byType(RichText),
          ),
        )) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: paragraph.text.toPlainText(),
          );
        }
        expect(find.bySemanticsLabel('Retry original change'), findsWidgets);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    '320dp at2x retains full group/status/recovery text and reachable named actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final h = await mount(tester, scale: 2, longTitle: true);
        await choose(
          tester,
          h,
          'Community contribution group with a complete long name that must remain readable',
        );
        await reach(tester, find.byKey(const ValueKey('receipt-sms-opt-in')));
        expect(tester.takeException(), isNull);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(
            of: find.byType(ReceiptSmsConsentSection),
            matching: find.byType(RichText),
          ),
        )) {
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: paragraph.text.toPlainText(),
          );
        }
        expect(find.bySemanticsLabel('Allow receipt SMS'), findsWidgets);
        expect(
          find.byKey(const ValueKey('receipt-sms-opt-in')).hitTestable(),
          findsOneWidget,
        );
        expect(
          (Offset.zero & tester.view.physicalSize).contains(
            tester.getCenter(find.byKey(const ValueKey('receipt-sms-opt-in'))),
          ),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}

Future<void> reach(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 60,
    );
  }
  await tester.pump();
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> idle(
  WidgetTester tester,
  ReceiptSmsHarness h, {
  String? onlyGroup,
}) async {
  for (var i = 0; i < 200; i++) {
    // File IO and its continuations cross real and test microtask queues. Pump
    // between bounded real waits instead of starving the fake-async queue.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final busy = (onlyGroup == null ? [smsGroup, smsGroupB] : [onlyGroup]).any(
      (g) => h.repo.receiptSmsConsentFor(g).busy,
    );
    if (!busy) {
      await tester.pumpAndSettle();
      return;
    }
  }
  throw StateError('Synthetic receipt SMS UI did not settle.');
}
