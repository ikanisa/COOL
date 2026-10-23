import 'dart:convert';

import 'package:collect_app/admin/core/admin_account_api.dart';
import 'package:collect_app/admin/core/admin_account_pages.dart';
import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'admin_invitation_recovery_test.dart' as v1;
import 'admin_invitation_v2_test.dart' as v2;

Future<void> mount(
  WidgetTester tester,
  v1.Harness h, {
  bool compact = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminAccountApiProvider.overrideWithValue(h.api),
        // Widget owns this separate store; transport harness retains its own store
        // solely for non-widget tests, preventing double-dispose of either owner.
        adminPendingAttemptStoreProvider.overrideWith(
          (ref) =>
              AdminPendingAttemptStore(storage: h.storage)
                ..bind(h.session.user),
        ),
      ],
      child: MaterialApp(
        theme: CollectTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(compact ? 1.3 : 1)),
          child: child!,
        ),
        home: const Scaffold(body: AdminAccountTeamPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> addTeammate(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Add teammate'));
  await tester.pumpAndSettle();
  expect(find.widgetWithText(FilledButton, 'Send access notice'), findsNothing);
  await tester.enterText(
    find.byKey(const Key('admin-account-email')),
    'synthetic@example.test',
  );
  await tester.enterText(
    find.byKey(const Key('admin-account-name')),
    'Synthetic Teammate',
  );
  final add = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, 'Add teammate'),
  );
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in ['auth_invite', 'access_notice']) {
    testWidgets(
      'ordinary Add Staff shows truthful $kind receipt with one actual HTTP mutation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(
          kind == 'access_notice' ? 320 : 1000,
          1000,
        );
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final storage = MemoryAdminPendingAttemptStorage(),
            calls = <http.Request>[];
        Map<String, dynamic>? latest;
        final h = (await tester.runAsync(
          () => v2.harness((request) async {
            calls.add(request);
            if (request.method == 'GET') {
              return v1.reply(
                latest == null
                    ? {...v2.team(), 'members': <Map<String, dynamic>>[]}
                    : v2.team(invitation: latest),
              );
            }
            expect(request.url.path.endsWith('/team/v2/invite'), isTrue);
            expect(jsonEncode(storage.values), contains('contract_version'));
            expect(jsonDecode(request.body), {
              'email': 'synthetic@example.test',
              'role': 'staff',
              'displayName': 'Synthetic Teammate',
            });
            latest = v2.receipt(kind: kind);
            return v1.reply({'ok': true, ...latest!, 'outcome': 'accepted'});
          }, storage: storage),
        ))!;
        await mount(tester, h, compact: kind == 'access_notice');
        expect(calls.where((r) => r.method == 'POST'), isEmpty);
        expect(
          find.widgetWithText(TextButton, 'Send access notice'),
          findsNothing,
        );
        await addTeammate(tester);
        expect(calls.where((r) => r.method == 'POST'), hasLength(1));
        expect(
          find.textContaining(
            kind == 'access_notice'
                ? 'Original access notice accepted for sending'
                : 'Original invitation accepted for sending',
          ),
          findsWidgets,
        );
        if (kind == 'access_notice') {
          expect(
            find.textContaining('Original invitation accepted for sending'),
            findsNothing,
          );
        }
        expect(find.textContaining('Inbox delivery'), findsWidgets);
        expect(find.textContaining('delivered to'), findsNothing);
        expect(
          find.widgetWithText(TextButton, 'Send access notice'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'historical already_registered repair is explicit and keeps original server lineage',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <http.Request>[];
      Map<String, dynamic> latest = v2.receipt(
        kind: 'auth_invite',
        status: 'already_registered',
      );
      final h = (await tester.runAsync(
        () => v2.harness((request) async {
          calls.add(request);
          if (request.method == 'GET') {
            return v1.reply(v2.team(invitation: latest));
          }
          expect(
            request.url.path.endsWith('/team/v2/${v2.staffId}/access-notice'),
            isTrue,
          );
          expect(jsonDecode(request.body), {
            'sourceRequestId': v2.serverRequest,
          });
          latest = v2.receipt(
            operation: 'notice_repair',
            requestId: v2.repairRequest,
            sourceRequestId: v2.serverRequest,
          );
          return v1.reply({'ok': true, ...latest, 'outcome': 'accepted'});
        }),
      ))!;
      await mount(tester, h);
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      final repair = find.widgetWithText(TextButton, 'Send access notice');
      await tester.ensureVisible(repair);
      await tester.tap(repair);
      await tester.pumpAndSettle();
      expect(find.text('Send an access notice?'), findsOneWidget);
      expect(find.textContaining(v2.serverRequest), findsOneWidget);
      expect(calls.where((r) => r.method == 'POST'), isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Send access notice'));
      await tester.pumpAndSettle();
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        find.textContaining('Original access notice accepted for sending'),
        findsWidgets,
      );
      expect(
        find.textContaining('Original invitation accepted for sending'),
        findsNothing,
      );
      expect(
        find.widgetWithText(TextButton, 'Send access notice'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'lost ordinary V2 request reload remains read-only and locks new Add Staff',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryAdminPendingAttemptStorage(),
          calls = <http.Request>[];
      final h = (await tester.runAsync(
        () => v2.harness((request) async {
          calls.add(request);
          if (request.url.path.endsWith('/team/v2/invitation-status')) {
            return v1.reply({
              'ok': true,
              'found': true,
              ...v2.receipt(status: 'unknown'),
            });
          }
          if (request.method == 'GET') {
            return v1.reply({
              ...v2.team(),
              'members': <Map<String, dynamic>>[],
            });
          }
          throw http.ClientException('synthetic lost response');
        }, storage: storage),
      ))!;
      await mount(tester, h);
      await addTeammate(tester);
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Close'));
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      final checkpoint = storage.values.values.single;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await mount(tester, h);
      expect(storage.values.values.single, checkpoint);
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Add teammate'),
            )
            .onPressed,
        isNull,
      );
      final check = find.widgetWithText(TextButton, 'Check original request');
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(
        calls.where((r) => r.url.path.endsWith('/team/v2/invitation-status')),
        hasLength(1),
      );
      expect(calls.where((r) => r.method == 'POST'), hasLength(1));
      expect(
        find.widgetWithText(FilledButton, 'Retry same request'),
        findsNothing,
      );
      expect(
        find.textContaining('Access notice sending is unconfirmed'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
