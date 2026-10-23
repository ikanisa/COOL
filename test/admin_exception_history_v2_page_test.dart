import 'dart:async';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_entity_audit.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'admin_exception_history_v2_models_test.dart' as evidence;

const _owner = AdminIdentity(
  userId: evidence.historyActorId,
  displayName: 'Declared history reviewer',
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
  void change(String id) => state = (
    key: (userId: _owner.userId, sessionId: id),
    generation: ++generation,
  );
}

class _Repo extends AdminEvidenceRepository {
  Map<String, dynamic> raw = evidence.historyFixture();
  DateTime now = DateTime.parse(evidence.historyChecked);
  final queries = <AdminEntityAuditQuery>[];
  int legacyReads = 0, actions = 0;
  Object? error;
  Completer<Map<String, dynamic>>? gate;
  @override
  Future<AdminIdentity?> currentIdentity() async => _owner;
  @override
  Future<Map<String, dynamic>> exceptionEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    queries.add(query);
    if (error != null) {
      throw error!;
    }
    return gate?.future ?? evidence.historyWindow(raw, query);
  }

  @override
  Future<Map<String, dynamic>> operatorEntityAudit(
    AdminEntityAuditQuery query,
  ) async {
    legacyReads++;
    throw StateError('Unexpectedv1');
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
  final repo = _Repo(), sessions = _Sessions();
  late ProviderContainer container;
  bool closed = false;
  Future<void> mount(
    WidgetTester tester, {
    AdminIdentity? identity = _owner,
    int pageSize = 3,
    double width = 800,
    double scale = 1,
    String id = evidence.historyExceptionId,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1100));
    container = ProviderContainer(
      overrides: [
        collectBackendClientProvider.overrideWithValue(null),
        adminRepositoryProvider.overrideWithValue(repo),
        adminIdentityProvider.overrideWith((ref) => ref.watch(_authority)),
        adminAuthSessionScopeProvider.overrideWith((_) => sessions),
        adminClockProvider.overrideWithValue(() => repo.now),
      ],
    );
    container.read(_authority.notifier).state = Future.value(identity);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CollectTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: AdminEntityAuditPage(
              entityKind: 'exception',
              entityId: id,
              pageSize: pageSize,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    if (closed) {
      return;
    }
    await tester.pumpWidget(const SizedBox.shrink());
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

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _with(
  WidgetTester tester,
  Future<void> Function(_Harness) run, {
  _Harness? fixture,
  AdminIdentity? identity = _owner,
  int pageSize = 3,
  double width = 800,
  double scale = 1,
}) async {
  final h = fixture ?? _Harness();
  try {
    await h.mount(
      tester,
      identity: identity,
      pageSize: pageSize,
      width: width,
      scale: scale,
    );
    await run(h);
  } finally {
    await h.close(tester);
  }
}

void main() {
  testWidgets(
    'actual generic exception route renders v2 joined provenance with zero oldAPI or actions',
    (tester) async {
      await _with(tester, (h) async {
        expect(find.byType(AdminEntityAuditPage), findsOneWidget);
        expect(find.byType(AdminExceptionHistoryPage), findsOneWidget);
        expect(h.repo.queries, hasLength(1));
        expect(h.repo.legacyReads, 0);
        expect(h.repo.actions, 0);
        expect(find.text('History is incomplete'), findsOneWidget);
        expect(
          find.textContaining('Admin inbox delivery and opening are separate'),
          findsOneWidget,
        );
        final first =
            (evidence.historyWindow(h.repo.raw, h.repo.queries.single)['rows']
                        as List)
                    .first
                as Map;
        expect(find.text(first['event_id'] as String), findsOneWidget);
        expect(find.text('Recorded source revision: 1'), findsWidgets);
      }, pageSize: 20);
    },
  );
  testWidgets(
    'paired older newer history pages preserve exact target and reset manually',
    (tester) async {
      await _with(tester, (h) async {
        await _tap(tester, 'Older actions');
        expect(h.repo.queries, hasLength(2));
        expect(h.repo.queries.last.before, isNotNull);
        expect(h.repo.queries.last.id, evidence.historyExceptionId);
        expect(find.text('Newer actions'), findsOneWidget);
        await _tap(tester, 'Newer actions');
        expect(h.repo.queries.last.before, isNull);
        await _tap(tester, 'Older actions');
        await _tap(tester, 'Refresh evidence');
        expect(h.repo.queries.last.before, isNull);
        expect(find.text('Newer actions'), findsNothing);
        expect(h.repo.actions, 0);
      });
    },
  );
  for (final missing in [
    'role',
    'audit.read',
    'payments.read',
    'notifications.read',
    'system_health.read',
  ]) {
    testWidgets('v2 exception page missing $missing reads zero history', (
      tester,
    ) async {
      final actor = AdminIdentity(
        userId: _owner.userId,
        displayName: _owner.displayName,
        roles: missing == 'role' ? ['admin'] : _owner.roles,
        permissions: _owner.permissions.where((p) => p != missing).toList(),
      );
      await _with(tester, (h) async {
        expect(h.repo.queries, isEmpty);
        expect(find.text('Action history access denied'), findsOneWidget);
      }, identity: actor);
    });
  }
  for (final code in [
    '42501',
    '55P03',
    'operation_unavailable',
    '501',
    'XX000',
  ]) {
    testWidgets(
      'v2 $code read failure is redacted and never becomes empty history',
      (tester) async {
        final h = _Harness();
        h.repo.error = CollectApiException(
          message: 'PRIVATE_CANARY',
          code: code,
        );
        await _with(tester, (h) async {
          expect(h.repo.queries, hasLength(1));
          expect(find.textContaining('PRIVATE'), findsNothing);
          expect(
            find.text('No retained actions in this history window'),
            findsNothing,
          );
          expect(
            find.text(
              code == '42501'
                  ? 'Action history access denied'
                  : code == '55P03'
                  ? 'Action history authority unavailable'
                  : {'operation_unavailable', '501'}.contains(code)
                  ? 'Action history service unavailable'
                  : 'Action history read failed',
            ),
            findsOneWidget,
          );
          h.repo.error = null;
          await _tap(tester, 'Refresh evidence');
          expect(find.text('Older actions'), findsOneWidget);
        }, fixture: h);
      },
    );
  }
  testWidgets(
    'malformed successful private body stays hidden and manually recoverable',
    (tester) async {
      final h = _Harness();
      h.repo.raw['private'] = 'PRIVATE_CANARY';
      await _with(tester, (h) async {
        expect(find.text('Action history read failed'), findsOneWidget);
        expect(find.textContaining('PRIVATE'), findsNothing);
        expect(find.text('Older actions'), findsNothing);
      }, fixture: h);
    },
  );
  for (final unavailable in [false, true]) {
    testWidgets(
      'empty supported history unavailable=$unavailable preserves honest state',
      (tester) async {
        final h = _Harness();
        h.repo.raw['rows'] = [];
        h.repo.raw['status'] = unavailable ? 'unavailable' : 'available';
        await _with(tester, (h) async {
          expect(
            find.text(
              unavailable
                  ? 'Record unavailable in this scope'
                  : 'No retained actions in this history window',
            ),
            findsOneWidget,
          );
          expect(find.text('Older actions'), findsNothing);
        }, fixture: h);
      },
    );
  }
  testWidgets('expiry hides actions and paging until manual fresh read', (
    tester,
  ) async {
    await _with(tester, (h) async {
      h.repo.now = h.repo.now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Action history read expired'), findsOneWidget);
      expect(find.text('Older actions'), findsNothing);
      h.repo.raw['checked_at'] = evidence.historyWire(h.repo.now);
      h.repo.raw['sample_valid_until'] = evidence.historyWire(
        h.repo.now.add(const Duration(seconds: 60)),
      );
      await _tap(tester, 'Refresh evidence');
      expect(find.text('Older actions'), findsOneWidget);
    });
  });
  testWidgets(
    'permission departure suppresses held old projection and resets current query',
    (tester) async {
      final h = _Harness();
      h.repo.gate = Completer();
      await _with(tester, (h) async {
        final actor = AdminIdentity(
          userId: _owner.userId,
          displayName: _owner.displayName,
          roles: _owner.roles,
          permissions: [
            'payments.read',
            'notifications.read',
            'system_health.read',
          ],
        );
        h.container.read(_authority.notifier).state = Future.value(actor);
        await _settle(tester);
        h.repo.gate!.complete(
          evidence.historyWindow(h.repo.raw, h.repo.queries.first),
        );
        await _settle(tester);
        expect(find.text('Action history access denied'), findsOneWidget);
        expect(find.text('Older actions'), findsNothing);
        expect(h.repo.queries, hasLength(1));
      }, fixture: h);
    },
  );
  testWidgets(
    'A-B-A session reset loses prior cursor before reauthorized read',
    (tester) async {
      await _with(tester, (h) async {
        await _tap(tester, 'Older actions');
        h.sessions.change('replacement');
        await tester.pump();
        h.sessions.change('opening');
        await _settle(tester);
        expect(h.repo.queries.last.before, isNull);
        expect(find.text('Newer actions'), findsNothing);
        expect(h.repo.actions, 0);
      });
    },
  );
  testWidgets(
    'current identity loading hides retained rows and old pagination',
    (tester) async {
      await _with(tester, (h) async {
        final ready = Completer<AdminIdentity?>();
        h.container.read(_authority.notifier).state = ready.future;
        await _settle(tester);
        expect(find.text('Checking action history access'), findsOneWidget);
        expect(find.text('Older actions'), findsNothing);
        ready.complete(_owner);
        await _settle(tester);
        expect(h.repo.queries.last.before, isNull);
      });
    },
  );
  testWidgets(
    '320px2x provenance and dated assignment labels have no overflow',
    (tester) async {
      final assignment = _Harness();
      assignment.repo.raw['rows'] = (assignment.repo.raw['rows'] as List)
          .where((row) => (row as Map)['action'] == 'exception.workflow.assign')
          .toList();
      await _with(
        tester,
        (h) async {
          final semantics = tester.ensureSemantics();
          try {
            expect(h.repo.queries, hasLength(1));
            expect(tester.takeException(), isNull);
            final pageScroll = find
                .descendant(
                  of: find.byKey(const Key('admin-page-scroll-view')),
                  matching: find.byType(Scrollable),
                )
                .first;
            // At 320px with enlarged text, the lazy page header can fill the
            // viewport. Reach the evidence before asserting its contents.
            await tester.scrollUntilVisible(
              find.text('Recorded workflow revision: 1'),
              300,
              scrollable: pageScroll,
              maxScrolls: 30,
            );
            await tester.pumpAndSettle();
            expect(find.text('Recorded workflow revision: 1'), findsWidgets);
            expect(find.textContaining('Recorded deadline'), findsOneWidget);
            expect(find.text('Assigned operator ID'), findsOneWidget);
            final revision = tester.getRect(
              find.text('Recorded workflow revision: 1').first,
            );
            expect(revision.left, greaterThanOrEqualTo(0));
            expect(revision.right, lessThanOrEqualTo(320));
            expect(
              tester
                  .getSemantics(
                    find.text('Recorded workflow revision: 1').first,
                  )
                  .getSemanticsData()
                  .label,
              contains('Recorded workflow revision: 1'),
            );
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
              find.text('Refresh evidence'),
              -300,
              scrollable: pageScroll,
              maxScrolls: 30,
            );
            await _tap(tester, 'Refresh evidence');
            expect(h.repo.queries, hasLength(2));
            await tester.scrollUntilVisible(
              find.textContaining('Recorded deadline'),
              300,
              scrollable: pageScroll,
              maxScrolls: 30,
            );
            await tester.pumpAndSettle();
            expect(find.text('Recorded workflow revision: 1'), findsWidgets);
            expect(find.text('Assigned operator ID'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
        fixture: assignment,
        pageSize: 20,
        width: 320,
        scale: 2,
      );
    },
  );
}
