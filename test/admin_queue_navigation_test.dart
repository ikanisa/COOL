import 'package:collect_app/admin/admin_app.dart';
import 'package:collect_app/admin/admin_router.dart';
import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_evidence_mode.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _QueueRepository extends AdminEvidenceRepository {
  final requests =
      <
        ({
          String rpc,
          String? search,
          String? status,
          String? sort,
          int? offset,
          String? country,
        })
      >[];

  @override
  Future<AdminRuntimeConfig?> runtimeConfig() async => null;

  @override
  Future<AdminListResult> list(
    String rpcName, {
    String? search,
    String? status,
    int? limit,
    int? offset,
    String? sortBy,
    String? countryCode,
  }) {
    requests.add((
      rpc: rpcName,
      search: search,
      status: status,
      sort: sortBy,
      offset: offset,
      country: countryCode,
    ));
    return super.list(
      rpcName,
      search: search,
      status: status,
      limit: limit,
      offset: offset,
      sortBy: sortBy,
      countryCode: countryCode,
    );
  }
}

final _activeIdentity = StateProvider<AdminIdentity?>((ref) => null);

Finder get _searchField => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == 'Search',
);

Future<ProviderContainer> _open(
  WidgetTester tester,
  _QueueRepository repository,
) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final identity = await repository.currentIdentity();
  final container = ProviderContainer(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      adminAuthGuardProvider.overrideWithValue(
        const AdminAuthGuard(isAuthorized: true),
      ),
      _activeIdentity.overrideWith((ref) => identity),
      adminIdentityProvider.overrideWith(
        (ref) async => ref.watch(_activeIdentity),
      ),
      adminRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  container.read(adminRouterProvider).go('/admin/groups');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const CollectAdminApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _searchAndOpen(WidgetTester tester) async {
  await tester.enterText(_searchField, 'Buri Munsi');
  await tester.tap(find.byTooltip('Refresh'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Open Buri Munsi'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Back to Groups'), findsOneWidget);
}

double _scrollOffset(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('admin-page-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position
    .pixels;

void _expectNamedSearch(WidgetTester tester, String value) {
  final fields = <SemanticsData>[];
  void visit(SemanticsNode node) {
    if (node.isMergedIntoParent) return;
    final data = node.getSemanticsData();
    if (data.flagsCollection.isTextField) fields.add(data);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  expect(
    fields,
    hasLength(2),
    reason: 'Global search and one editable queue search',
  );
  final queue = fields.singleWhere(
    (field) => field.label.contains('Search admin queue'),
  );
  expect(queue.hasAction(SemanticsAction.focus), isTrue);
  expect(queue.value, value);
}

void main() {
  testWidgets(
    'queue search has one editable accessible name before and after return',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _open(tester, _QueueRepository());
        _expectNamedSearch(tester, '');
        await _searchAndOpen(tester);
        await tester.tap(find.byTooltip('Back to Groups'));
        await tester.pumpAndSettle();
        _expectNamedSearch(tester, 'Buri Munsi');
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'returning from a record restores applied search filters and sort',
    (tester) async {
      final repository = _QueueRepository();
      await _open(tester, repository);
      await tester.tap(find.byTooltip('Filter: All'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is PopupMenuItem<String> &&
              widget.value == 'public_approved',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sort: Newest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest'));
      await tester.pumpAndSettle();
      await _searchAndOpen(tester);
      await tester.tap(find.byTooltip('Back to Groups'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_searchField).controller!.text,
        'Buri Munsi',
      );
      expect(find.byTooltip('Filter: Public'), findsOneWidget);
      expect(find.byTooltip('Sort: Oldest'), findsOneWidget);
      expect(repository.requests.last.search, 'Buri Munsi');
      expect(repository.requests.last.status, 'public_approved');
      expect(repository.requests.last.sort, 'created_at_asc');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('returning from a later-page record preserves page and scroll', (
    tester,
  ) async {
    final repository = _QueueRepository();
    await _open(tester, repository);
    tester.view.physicalSize = const Size(1440, 500);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 26-30 of 30'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Open Verified group 30'));
    await tester.pumpAndSettle();
    final offset = _scrollOffset(tester);
    expect(offset, greaterThan(0));
    await tester.tap(find.byTooltip('Open Verified group 30'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to Groups'));
    await tester.pumpAndSettle();
    expect(repository.requests.last.offset, 25);
    expect(find.text('Showing 26-30 of 30'), findsOneWidget);
    expect(_scrollOffset(tester), closeTo(offset, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('queue state does not carry across an Admin account switch', (
    tester,
  ) async {
    final repository = _QueueRepository();
    final container = await _open(tester, repository);
    await _searchAndOpen(tester);
    final original = container.read(_activeIdentity)!;
    container.read(_activeIdentity.notifier).state = AdminIdentity(
      userId: 'synthetic-other-admin',
      displayName: 'Other synthetic operator',
      roles: original.roles,
      permissions: original.permissions,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to Groups'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(_searchField).controller!.text, isEmpty);
    expect(repository.requests.last.search, isEmpty);
    expect(repository.requests.last.offset, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final leaveImmediately in [false, true]) {
    testWidgets('switching accounts on an open queue resets its state, '
        'immediate navigation: $leaveImmediately', (tester) async {
      final repository = _QueueRepository();
      final container = await _open(tester, repository);
      await tester.enterText(_searchField, 'Buri Munsi');
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      final original = container.read(_activeIdentity)!;
      container.read(_activeIdentity.notifier).state = AdminIdentity(
        userId: 'synthetic-other-admin',
        displayName: 'Other synthetic operator',
        roles: original.roles,
        permissions: original.permissions,
      );
      if (leaveImmediately) {
        await tester.pump();
        container.read(adminRouterProvider).go('/admin');
        await tester.pumpAndSettle();
        container.read(adminRouterProvider).go('/admin/groups');
      }
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(_searchField).controller!.text, isEmpty);
      expect(repository.requests.last.search, isEmpty);
      expect(repository.requests.last.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a country change away from a queue resets its page on return', (
    tester,
  ) async {
    final repository = _QueueRepository();
    final container = await _open(tester, repository);
    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    container.read(adminRouterProvider).go('/admin/groups/collection-26');
    await tester.pumpAndSettle();
    container.read(adminCountryScopeProvider.notifier).state =
        AdminCountryScope.malta;
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to Groups'));
    await tester.pumpAndSettle();
    expect(repository.requests.last.offset, 0);
    expect(repository.requests.last.country, 'MT');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
