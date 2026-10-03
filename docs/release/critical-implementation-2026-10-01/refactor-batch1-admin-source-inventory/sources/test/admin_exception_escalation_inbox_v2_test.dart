import 'dart:async';

import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_exception_checkpoint.dart';
import 'package:collect_app/admin/core/admin_exception_escalation_inbox_v2_models.dart';
import 'package:collect_app/admin/core/admin_exception_models.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_exception_escalation_inbox_v2_models_test.dart' as delivery;
import 'admin_exception_history_v2_models_test.dart' as history;
import 'admin_exception_models_test.dart' as exceptions;
import 'admin_exception_workflow_test.dart' as workflow;

const _owner = AdminIdentity(
  userId: delivery.inboxRecipientId,
  displayName: 'Declared recipient reviewer',
  roles: ['platform_owner'],
  permissions: [
    'audit.read',
    'payments.read',
    'notifications.read',
    'system_health.read',
  ],
);
final _authority = StateProvider<Future<AdminIdentity?>>((_) async => _owner);

class _Sessions extends AdminSessionController {
  _Sessions() : super(null) {
    change('opening');
  }
  int generation = 0;
  void change(String session) => state = (
    key: (userId: _owner.userId, sessionId: session),
    generation: ++generation,
  );
}

class _Store implements AdminExceptionCheckpointStore {
  final values = <String, String>{};
  @override
  String? read(String owner) => values[owner];
  @override
  void write(String owner, String encoded) => values[owner] = encoded;
  @override
  void clear(String owner) => values.remove(owner);
}

class _Repo extends AdminEvidenceRepository {
  Map<String, dynamic> raw = delivery.inboxFixture();
  DateTime now = DateTime.parse(delivery.inboxChecked);
  final queries = <AdminExceptionEscalationInboxQuery>[];
  final openingIds = <String>[];
  final workflowIds = <String>[];
  final historyQueries = <AdminEntityAuditQuery>[];
  int legacyReads = 0, legacyOpenings = 0, actions = 0;
  Object? error;
  bool invalidOpening = false, loseOpening = false;
  Completer<Map<String, dynamic>>? inboxGate, openingGate;
  @override
  Future<AdminIdentity?> currentIdentity() async => _owner;
  @override
  Future<Map<String, dynamic>> exceptionEscalationInboxPage(
    AdminExceptionEscalationInboxQuery query,
  ) async {
    queries.add(query);
    if (error != null) {
      throw error!;
    }
    return inboxGate?.future ?? delivery.inboxWindow(raw, query);
  }

  @override
  Future<Map<String, dynamic>> exceptionEscalationInbox() async {
    legacyReads++;
    throw StateError('Unexpected legacy inbox read');
  }

  @override
  Future<Map<String, dynamic>> readExceptionEscalation(String id) async {
    legacyOpenings++;
    throw StateError('Unexpected legacy opening');
  }

  @override
  Future<Map<String, dynamic>> readExceptionEscalationCurrent(String id) async {
    openingIds.add(id);
    if (openingGate != null) {
      return openingGate!.future;
    }
    final read = delivery.inboxWire(now.subtract(const Duration(minutes: 30)));
    // Explicit presentation double: persist the original read before simulating
    // a lost transport reply, so refresh investigates durable evidence.
    for (final row in raw['rows'] as List) {
      if ((row as Map)['escalation_id'] == id) {
        row['read_at'] = read;
      }
    }
    if (loseOpening) {
      throw TimeoutException('PRIVATE_OUTCOME_CANARY');
    }
    return {
      'contract_version': 2,
      'escalation_id': invalidOpening ? delivery.inboxExceptionId : id,
      'read_at': read,
      'source_resolved': false,
    };
  }

  @override
  Future<Map<String, dynamic>> exceptionWorkflow(String id) async {
    workflowIds.add(id);
    // Existing actual retained evidence is rebound only for this declared
    // presentation clock and target; it grants no mutation authority.
    return workflow.observed('workflow')
      ..['exception_id'] = id
      ..['checked_at'] = delivery.inboxWire(now)
      ..['sample_valid_until'] = delivery.inboxWire(
        now.add(const Duration(seconds: 60)),
      );
  }

  @override
  Future<Map<String, dynamic>> exceptionEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    historyQueries.add(query);
    return history.historyWindow(history.historyFixture(), query);
  }

  @override
  Future<Map<String, dynamic>> exceptionInbox({
    bool active = true,
    int limit = 20,
    AdminExceptionSource? source,
    DateTime? beforeChangedAt,
    String? beforeId,
  }) async {
    // Route background list is deliberately empty; escalation deliveries are
    // independent retained evidence and do not fabricate source rows.
    return exceptions.exceptionFixture('empty')
      ..['active'] = active
      ..['limit'] = limit
      ..['source_kind'] = source?.wire
      ..['checked_at'] = delivery.inboxWire(now)
      ..['sample_valid_until'] = delivery.inboxWire(
        now.add(const Duration(seconds: 60)),
      );
  }

  @override
  Future<Map<String, dynamic>> action(
    String name,
    Map<String, dynamic> args,
  ) async {
    actions++;
    throw StateError('Unexpected action');
  }
}

class _Harness {
  final repo = _Repo(), sessions = _Sessions(), store = _Store();
  late ProviderContainer container;
  GoRouter? router;
  bool closed = false;
  Future<void> mount(
    WidgetTester tester, {
    AdminIdentity? identity = _owner,
    bool actualRouter = false,
    double width = 900,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(null),
        adminRepositoryProvider.overrideWithValue(repo),
        adminIdentityProvider.overrideWith((ref) => ref.watch(_authority)),
        adminAuthSessionScopeProvider.overrideWith((_) => sessions),
        adminClockProvider.overrideWithValue(() => repo.now),
        adminExceptionCheckpointStoreProvider.overrideWithValue(store),
        adminAuthGuardProvider.overrideWithValue(
          const AdminAuthGuard(isAuthorized: true),
        ),
      ],
    );
    container.read(_authority.notifier).state = Future.value(identity);
    final Widget app;
    if (actualRouter) {
      router = container.read(adminRouterProvider);
      router!.go('/admin/exceptions');
      app = MaterialApp.router(
        theme: CollectTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      );
    } else {
      app = MaterialApp(
        theme: CollectTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(
          body: SingleChildScrollView(child: AdminExceptionEscalationInbox()),
        ),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: app),
    );
    await _settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    if (closed) {
      return;
    }
    await tester.pumpWidget(const SizedBox.shrink());
    router?.dispose();
    container.dispose();
    closed = true;
    await tester.pump(Duration.zero);
    await tester.binding.setSurfaceSize(null);
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await _settle(tester);
}

Future<void> _with(
  WidgetTester tester,
  Future<void> Function(_Harness) body, {
  _Harness? fixture,
  AdminIdentity? identity = _owner,
  bool actualRouter = false,
  double width = 900,
  double scale = 1,
}) async {
  final h = fixture ?? _Harness();
  try {
    await h.mount(
      tester,
      identity: identity,
      actualRouter: actualRouter,
      width: width,
      scale: scale,
    );
    await body(h);
  } finally {
    await h.close(tester);
  }
}

Future<void> _expand(WidgetTester tester) =>
    _tap(tester, find.text('Your escalation inbox'));
Finder _firstOpen(_Harness h) => find.byKey(
  ValueKey(
    'exception-followup-${(h.repo.raw['rows'] as List).first['escalation_id']}',
  ),
);

String _topPath(GoRouter router) {
  final configuration = router.routerDelegate.currentConfiguration;
  final leaf = configuration.last;
  // go_router retains its declarative base URI when push adds an imperative
  // match. Inspect the actual top page's exported match, including shells.
  return leaf is ImperativeRouteMatch
      ? leaf.matches.uri.path
      : configuration.uri.path;
}

void main() {
  testWidgets(
    'recipient inbox is lazy then reads actual20 paired-keyset pages without legacy APIs',
    (tester) async {
      await _with(tester, (h) async {
        expect(h.repo.queries, isEmpty);
        await _expand(tester);
        expect(h.repo.queries, hasLength(1));
        expect(find.text('Open exception follow-up'), findsNWidgets(20));
        await _tap(tester, find.text('Older escalations'));
        expect(h.repo.queries.last.before, isNotNull);
        expect(find.text('Open exception follow-up'), findsNWidgets(15));
        await _tap(tester, find.text('Newer escalations'));
        expect(h.repo.queries.last.before, isNull);
        await _tap(tester, find.text('Older escalations'));
        await _tap(tester, find.text('Refresh escalation inbox'));
        expect(h.repo.queries.last.before, isNull);
        expect(find.text('Newer escalations'), findsNothing);
        expect(h.repo.legacyReads, 0);
        expect(h.repo.legacyOpenings, 0);
        expect(h.repo.openingIds, isEmpty);
      });
    },
  );
  for (final missing in [
    'role',
    'payments.read',
    'notifications.read',
    'system_health.read',
  ]) {
    testWidgets(
      'recipient inbox missing $missing performs zero reads and zero openings',
      (tester) async {
        final actor = AdminIdentity(
          userId: _owner.userId,
          displayName: _owner.displayName,
          roles: missing == 'role' ? ['admin'] : _owner.roles,
          permissions: _owner.permissions.where((p) => p != missing).toList(),
        );
        await _with(tester, (h) async {
          expect(find.text('Your escalation inbox'), findsNothing);
          expect(h.repo.queries, isEmpty);
          expect(h.repo.openingIds, isEmpty);
        }, identity: actor);
      },
    );
  }
  testWidgets(
    'audit read remains independent from recipient opening authority',
    (tester) async {
      final actor = AdminIdentity(
        userId: _owner.userId,
        displayName: _owner.displayName,
        roles: _owner.roles,
        permissions: _owner.permissions
            .where((p) => p != 'audit.read')
            .toList(),
      );
      await _with(tester, (h) async {
        await _expand(tester);
        expect(find.text('Open exception follow-up'), findsWidgets);
        expect(find.text('View action history'), findsNothing);
        await _tap(tester, _firstOpen(h));
        expect(find.byType(Dialog), findsOneWidget);
        expect(h.repo.openingIds, hasLength(1));
        expect(find.text('View action history'), findsNothing);
        await _tap(tester, find.text('Close follow-up'));
      }, identity: actor);
    },
  );
  for (final code in ['42501', '42883', 'XX000']) {
    testWidgets(
      'recipient $code error cannot become empty healthy inbox or disclose private details',
      (tester) async {
        final h = _Harness();
        h.repo.error = PostgrestException(
          message: 'PRIVATE_CONTACT_CANARY',
          code: code,
        );
        await _with(tester, (h) async {
          await _expand(tester);
          expect(find.textContaining('could not be verified'), findsOneWidget);
          expect(find.textContaining('PRIVATE'), findsNothing);
          expect(
            find.text('No delivered escalations in this history window.'),
            findsNothing,
          );
          h.repo.error = null;
          await _tap(tester, find.text('Refresh escalation inbox'));
          expect(find.text('Older escalations'), findsOneWidget);
        }, fixture: h);
      },
    );
  }
  testWidgets(
    'successful private body is rejected rather than rendered or opened',
    (tester) async {
      final h = _Harness();
      h.repo.raw['phone'] = 'PRIVATE_CONTACT_CANARY';
      await _with(tester, (h) async {
        await _expand(tester);
        expect(find.textContaining('could not be verified'), findsOneWidget);
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.text('Open exception follow-up'), findsNothing);
        expect(h.repo.openingIds, isEmpty);
      }, fixture: h);
    },
  );
  testWidgets(
    'expiry removes row openings and pagination until manual fresh observation',
    (tester) async {
      await _with(tester, (h) async {
        await _expand(tester);
        final staleCallback = tester
            .widget<OutlinedButton>(_firstOpen(h))
            .onPressed!;
        h.repo.now = h.repo.now.add(const Duration(seconds: 60));
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining('observation expired'), findsOneWidget);
        expect(find.text('Open exception follow-up'), findsNothing);
        expect(find.text('Older escalations'), findsNothing);
        staleCallback();
        await _settle(tester);
        expect(h.repo.openingIds, isEmpty);
        h.repo.raw['checked_at'] = delivery.inboxWire(h.repo.now);
        h.repo.raw['sample_valid_until'] = delivery.inboxWire(
          h.repo.now.add(const Duration(seconds: 60)),
        );
        await _tap(tester, find.text('Refresh escalation inbox'));
        expect(find.text('Older escalations'), findsOneWidget);
      });
    },
  );
  testWidgets('wrong opening proof cannot open follow-up and never retries', (
    tester,
  ) async {
    final h = _Harness();
    h.repo.invalidOpening = true;
    await _with(tester, (h) async {
      await _expand(tester);
      await _tap(tester, _firstOpen(h));
      expect(h.repo.openingIds, hasLength(1));
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.textContaining('durable read acknowledgement'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(h.repo.openingIds, hasLength(1));
    }, fixture: h);
  });
  testWidgets(
    'lost opening reply is investigated by manual durable read refresh without replay',
    (tester) async {
      final h = _Harness();
      h.repo.loseOpening = true;
      await _with(tester, (h) async {
        await _expand(tester);
        await _tap(tester, _firstOpen(h));
        expect(find.byType(Dialog), findsNothing);
        expect(h.repo.openingIds, hasLength(1));
        await _tap(tester, find.text('Refresh escalation inbox'));
        expect(find.textContaining('Opened '), findsOneWidget);
        expect(h.repo.openingIds, hasLength(1));
        expect(h.repo.workflowIds, isEmpty);
        expect(find.textContaining('PRIVATE'), findsNothing);
      }, fixture: h);
    },
  );
  testWidgets(
    'opening records exact escalation id separately from target exception in a routerless modal',
    (tester) async {
      final h = _Harness();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(tester, (h) async {
        await _expand(tester);
        final row = (h.repo.raw['rows'] as List).single as Map;
        await _tap(tester, _firstOpen(h));
        expect(h.repo.openingIds.single, row['escalation_id']);
        expect(h.repo.workflowIds.single, row['exception_id']);
        expect(h.repo.openingIds.single, isNot(h.repo.workflowIds.single));
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('View action history'),
          ),
          findsNothing,
        );
        expect(h.repo.historyQueries, isEmpty);
        expect(h.repo.actions, 0);
        await _tap(tester, find.text('Close follow-up'));
      }, fixture: h);
    },
  );
  testWidgets(
    'actual router history-only link performs zero read acknowledgements and returns to inbox',
    (tester) async {
      final h = _Harness();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(
        tester,
        (h) async {
          await _expand(tester);
          await _tap(tester, find.text('View action history'));
          expect(
            _topPath(h.router!),
            '/admin/audit-logs/entity/exception/${delivery.inboxExceptionId}',
          );
          expect(find.byType(AdminExceptionHistoryPage), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          expect(h.repo.openingIds, isEmpty);
          expect(h.repo.workflowIds, isEmpty);
          expect(h.repo.historyQueries.single.id, delivery.inboxExceptionId);
          h.router!.pop();
          await _settle(tester);
          expect(_topPath(h.router!), '/admin/exceptions');
          expect(find.byType(Dialog), findsNothing);
        },
        fixture: h,
        actualRouter: true,
        width: 1440,
      );
    },
  );
  testWidgets(
    'actual modal closes before canonical exception history push and remains closed on return',
    (tester) async {
      final h = _Harness();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(
        tester,
        (h) async {
          await _expand(tester);
          await _tap(tester, _firstOpen(h));
          expect(find.byType(Dialog), findsOneWidget);
          final link = find.descendant(
            of: find.byType(Dialog),
            matching: find.text('View action history'),
          );
          await _tap(tester, link);
          expect(find.byType(Dialog), findsNothing);
          expect(
            _topPath(h.router!),
            '/admin/audit-logs/entity/exception/${delivery.inboxExceptionId}',
          );
          expect(
            h.repo.openingIds.single,
            delivery.inboxRow(1)['escalation_id'],
          );
          expect(h.repo.historyQueries.single.id, delivery.inboxExceptionId);
          expect(
            h.repo.openingIds.single,
            isNot(h.repo.historyQueries.single.id),
          );
          expect(h.repo.actions, 0);
          h.router!.pop();
          await _settle(tester);
          expect(find.byType(Dialog), findsNothing);
          expect(_topPath(h.router!), '/admin/exceptions');
        },
        fixture: h,
        actualRouter: true,
        width: 1440,
      );
    },
  );
  testWidgets(
    'opening-session A-B-A prevents a captured modal callback from navigating',
    (tester) async {
      final h = _Harness();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(
        tester,
        (h) async {
          await _expand(tester);
          await _tap(tester, _firstOpen(h));
          final button = tester.widget<OutlinedButton>(
            find.descendant(
              of: find.byType(Dialog),
              matching: find.byKey(
                const ValueKey(
                  'entity-audit-link-exception-${delivery.inboxExceptionId}',
                ),
              ),
            ),
          );
          final callback = button.onPressed!;
          h.sessions.change('replacement');
          await tester.pump();
          h.sessions.change('opening');
          await _settle(tester);
          callback();
          await _settle(tester);
          expect(_topPath(h.router!), '/admin/exceptions');
          expect(find.byType(Dialog), findsNothing);
          expect(h.repo.historyQueries, isEmpty);
          expect(h.repo.openingIds, hasLength(1));
        },
        fixture: h,
        actualRouter: true,
        width: 1440,
      );
    },
  );
  testWidgets(
    'late opening response after permission departure cannot publish modal or history',
    (tester) async {
      final h = _Harness();
      h.repo.openingGate = Completer();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(tester, (h) async {
        await _expand(tester);
        await _tap(tester, _firstOpen(h));
        h.container.read(_authority.notifier).state = Future.value(null);
        await _settle(tester);
        h.repo.openingGate!.complete({
          'contract_version': 2,
          'escalation_id': h.repo.openingIds.single,
          'read_at': '2026-10-01T19:30:00.000000Z',
          'source_resolved': false,
        });
        await _settle(tester);
        expect(find.byType(Dialog), findsNothing);
        expect(h.repo.workflowIds, isEmpty);
        expect(h.repo.historyQueries, isEmpty);
        expect(h.repo.openingIds, hasLength(1));
      }, fixture: h);
    },
  );
  for (final reopen in [false, true]) {
    testWidgets(
      'held opening ACK after inbox collapse reopen=$reopen cannot publish a modal',
      (tester) async {
        final h = _Harness();
        h.repo.openingGate = Completer();
        h.repo.raw = delivery.inboxFixture(count: 1);
        await _with(tester, (h) async {
          await _expand(tester);
          await _tap(tester, _firstOpen(h));
          expect(h.repo.openingIds, hasLength(1));
          await _expand(tester); // Actual expansion control closes the inbox.
          if (reopen) {
            await _expand(tester);
          }
          h.repo.openingGate!.complete({
            'contract_version': 2,
            'escalation_id': h.repo.openingIds.single,
            'read_at': '2026-10-01T19:30:00.000000Z',
            'source_resolved': false,
          });
          await _settle(tester);
          expect(find.byType(Dialog), findsNothing);
          expect(h.repo.workflowIds, isEmpty);
          expect(h.repo.historyQueries, isEmpty);
          expect(h.repo.openingIds, hasLength(1));
          expect(h.repo.actions, 0);
        }, fixture: h);
      },
    );
  }
  testWidgets(
    'history navigation is disabled during an original opening ACK and dispatches no competing read',
    (tester) async {
      final h = _Harness();
      h.repo.openingGate = Completer();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(
        tester,
        (h) async {
          await _expand(tester);
          await _tap(tester, _firstOpen(h));
          final target = find.byKey(
            const ValueKey(
              'entity-audit-link-exception-${delivery.inboxExceptionId}',
            ),
          );
          expect(tester.widget<OutlinedButton>(target).onPressed, isNull);
          await tester.tap(target, warnIfMissed: false);
          await _settle(tester);
          expect(_topPath(h.router!), '/admin/exceptions');
          expect(h.repo.historyQueries, isEmpty);
          expect(h.repo.workflowIds, isEmpty);
          expect(h.repo.openingIds, hasLength(1));
          h.repo.openingGate!.complete({
            'contract_version': 2,
            'escalation_id': h.repo.openingIds.single,
            'read_at': '2026-10-01T19:30:00.000000Z',
            'source_resolved': false,
          });
          await _settle(tester);
          expect(find.byType(Dialog), findsOneWidget);
          expect(h.repo.historyQueries, isEmpty);
          await _tap(tester, find.text('Close follow-up'));
        },
        fixture: h,
        actualRouter: true,
        width: 1440,
      );
    },
  );
  testWidgets(
    'actual router push away and return before opening ACK cannot resurrect the original modal',
    (tester) async {
      final h = _Harness();
      h.repo.openingGate = Completer();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(
        tester,
        (h) async {
          await _expand(tester);
          await _tap(tester, _firstOpen(h));
          unawaited(h.router!.push<void>('/admin/automations'));
          await _settle(tester);
          expect(_topPath(h.router!), '/admin/automations');
          h.router!.pop();
          await _settle(tester);
          expect(_topPath(h.router!), '/admin/exceptions');
          h.repo.openingGate!.complete({
            'contract_version': 2,
            'escalation_id': h.repo.openingIds.single,
            'read_at': '2026-10-01T19:30:00.000000Z',
            'source_resolved': false,
          });
          await _settle(tester);
          expect(find.byType(Dialog), findsNothing);
          expect(h.repo.workflowIds, isEmpty);
          expect(h.repo.historyQueries, isEmpty);
          expect(h.repo.openingIds, hasLength(1));
          expect(_topPath(h.router!), '/admin/exceptions');
        },
        fixture: h,
        actualRouter: true,
        width: 1440,
      );
    },
  );
  for (final returnBeforeClose in [false, true]) {
    testWidgets(
      'source route departure during history dialog closing return=$returnBeforeClose blocks the late canonical push',
      (tester) async {
        final h = _Harness();
        h.repo.raw = delivery.inboxFixture(count: 1);
        await _with(
          tester,
          (h) async {
            await _expand(tester);
            await _tap(tester, _firstOpen(h));
            final modal = find.byType(Dialog);
            final route = ModalRoute.of(tester.element(modal))!;
            var completed = false;
            unawaited(route.completed.then((_) => completed = true));
            final historyLink = find.descendant(
              of: modal,
              matching: find.text('View action history'),
            );
            await tester.ensureVisible(historyLink);
            await tester.pumpAndSettle();
            await tester.tap(historyLink);
            await tester.pump();
            // Keep the real reverse transition pending. A settled helper would
            // miss the guarded interval between pop and overlay completion.
            expect(completed, isFalse);
            unawaited(h.router!.push<void>('/admin/automations'));
            await tester.pump();
            if (returnBeforeClose) {
              expect(completed, isFalse);
              h.router!.pop();
              await tester.pump();
            }
            await _settle(tester);
            expect(completed, isTrue);
            expect(find.byType(Dialog), findsNothing);
            expect(
              _topPath(h.router!),
              returnBeforeClose ? '/admin/exceptions' : '/admin/automations',
            );
            expect(h.repo.historyQueries, isEmpty);
            expect(h.repo.openingIds, hasLength(1));
            expect(h.repo.actions, 0);
          },
          fixture: h,
          actualRouter: true,
          width: 1440,
        );
      },
    );
  }
  testWidgets(
    'late inbox observation after session replacement cannot restore old cursor or rows',
    (tester) async {
      final h = _Harness();
      h.repo.inboxGate = Completer();
      await _with(tester, (h) async {
        await _expand(tester);
        final original = h.repo.queries.single;
        h.container.read(_authority.notifier).state = Future.value(null);
        h.sessions.change('replacement');
        await _settle(tester);
        h.repo.inboxGate!.complete(delivery.inboxWindow(h.repo.raw, original));
        await _settle(tester);
        expect(find.text('Your escalation inbox'), findsNothing);
        expect(find.text('Open exception follow-up'), findsNothing);
        expect(h.repo.openingIds, isEmpty);
      }, fixture: h);
    },
  );
  testWidgets(
    'current session A-B-A resets inbox paging and rechecks original owner',
    (tester) async {
      await _with(tester, (h) async {
        await _expand(tester);
        await _tap(tester, find.text('Older escalations'));
        h.sessions.change('replacement');
        await tester.pump();
        h.sessions.change('opening');
        await _settle(tester);
        expect(h.repo.queries.last.before, isNull);
        expect(find.text('Newer escalations'), findsNothing);
        expect(h.repo.openingIds, isEmpty);
      });
    },
  );
  testWidgets(
    '320px enlarged inbox controls and dialog are named and have no overflow',
    (tester) async {
      final h = _Harness();
      h.repo.raw = delivery.inboxFixture(count: 1);
      await _with(
        tester,
        (h) async {
          final semantics = tester.ensureSemantics();
          try {
            await _expand(tester);
            expect(find.text('Refresh escalation inbox'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _tap(tester, _firstOpen(h));
            expect(find.text('Close follow-up'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await _tap(tester, find.text('Close follow-up'));
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
        fixture: h,
        width: 320,
        scale: 2,
      );
    },
  );
}
