import 'package:collect_app/admin/core/admin_pending_attempt_store.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/admin/core/cloudflare_admin_operating_pages.dart';
import 'package:collect_app/admin/core/cloudflare_admin_repository.dart';
import 'package:collect_app/admin/core/cloudflare_admin_session.dart';
import 'package:collect_app/admin/shared/components/admin_data_table.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/cloudflare/cloudflare_module.dart'
    show collectBackendClientProvider;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cloudflare_core_fixtures.dart' show coreId, coreDate;
import 'cloudflare_operating_repository_test.dart'
    show operatingRepository, operatingResponse, otherId;

// Synthetic read-only presentation fixtures, not hosted/provider/Auth evidence.
const _description =
    'Synthetic description first line with its complete retained facts.\n'
    'Synthetic description second line with its complete review context.\n'
    'Synthetic description third line with its complete final observation.';
const _note =
    'Synthetic support note first line with its complete retained facts.\n'
    'Synthetic support note second line with its complete review context.\n'
    'Synthetic support note third line with its complete final observation.';

void main() {
  testWidgets('actual group detail keeps its multiline description at 2x', (
    tester,
  ) async {
    final requests = <String>[];
    final repo = await operatingRepository((request) async {
      expect(request.method, 'GET');
      requests.add(request.url.path);
      expect(request.url.path, '/api/admin/operations/groups/$coreId');
      return operatingResponse({
        'resource_type': 'groups',
        'resource': {
          'id': coreId,
          'version': 1,
          'title': 'Synthetic long-description group',
          'description': _description,
          'status': 'active',
        },
        'current_actor_id': coreId,
        'can_manage': false,
        'related': <String, dynamic>{},
        'related_truncated': false,
      });
    });
    final semantics = tester.ensureSemantics();
    try {
      await _host(
        tester,
        repo: repo,
        scale: 2,
        child: const CloudflareOperatingDetailPage(
          type: 'groups',
          id: coreId,
          backPath: '/admin/groups',
        ),
      );
      final facts = find.byWidgetPredicate(
        (widget) =>
            widget is AdminDataTable && widget.tableLabel == 'Record details',
      );
      expect(facts, findsOneWidget);
      final table = tester.widget<AdminDataTable>(facts);
      expect(table.columns!.map((column) => column.label), [
        'Title',
        'Description',
        'Status',
        'Record ID',
      ]);
      expect(
        table.columns!
            .where((column) => column.allowNaturalHeight)
            .single
            .label,
        'Description',
      );
      await _expectCompleteFact(tester, _description, 'Description');
      expect(requests, ['/api/admin/operations/groups/$coreId']);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await _unmount(tester, repo: repo);
    }
  });

  testWidgets(
    'actual detail keeps the empty optional description placeholder',
    (tester) async {
      final requests = <String>[];
      final repo = await operatingRepository((request) async {
        expect(request.method, 'GET');
        requests.add(request.url.path);
        expect(request.url.path, '/api/admin/operations/groups/$coreId');
        return operatingResponse({
          'resource_type': 'groups',
          'resource': {
            'id': coreId,
            'version': 1,
            'title': 'Synthetic empty-description group',
            'description': '',
            'status': 'active',
          },
          'current_actor_id': coreId,
          'can_manage': false,
          'related': <String, dynamic>{},
          'related_truncated': false,
        });
      });
      final semantics = tester.ensureSemantics();
      try {
        await _host(
          tester,
          repo: repo,
          scale: 2,
          child: const CloudflareOperatingDetailPage(
            type: 'groups',
            id: coreId,
            backPath: '/admin/groups',
          ),
        );
        final placeholder = find.widgetWithText(SelectableText, '—');
        expect(placeholder, findsOneWidget);
        expect(tester.widget<SelectableText>(placeholder).data, '—');
        await _expectNativeFactSemantics(
          tester,
          placeholder,
          '—',
          'Description',
        );
        expect(find.bySemanticsLabel('Description: '), findsNothing);
        expect(requests, ['/api/admin/operations/groups/$coreId']);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _unmount(tester, repo: repo);
      }
    },
  );

  testWidgets('actual support notes keep every multiline fact at 2x', (
    tester,
  ) async {
    final requests = <String>[];
    final repo = await operatingRepository((request) async {
      expect(request.method, 'GET');
      requests.add(request.url.path);
      expect(request.url.path, '/api/admin/operations/groups/$coreId/notes');
      expect(request.url.queryParameters, {'limit': '25', 'offset': '0'});
      return operatingResponse({
        'contract_version': 1,
        'entity_type': 'collection',
        'entity_id': coreId,
        'rows': [
          {
            'id': otherId,
            'body': _note,
            'created_by': coreId,
            'author_name': 'Synthetic operator',
            'created_at': coreDate,
          },
        ],
        'total': 1,
        'limit': 25,
        'offset': 0,
      });
    });
    final semantics = tester.ensureSemantics();
    try {
      await _host(
        tester,
        repo: repo,
        scale: 2,
        child: const CloudflareOperatorNotes(type: 'groups', id: coreId),
      );
      final notes = tester.widget<AdminDataTable>(find.byType(AdminDataTable));
      expect(notes.columns!.map((column) => column.label), [
        'Note',
        'Recorded by',
        'Recorded at',
      ]);
      expect(
        notes.columns!
            .where((column) => column.allowNaturalHeight)
            .single
            .label,
        'Note',
      );
      await _expectCompleteFact(tester, _note, 'Note');
      expect(find.text('1 support notes'), findsOneWidget);
      expect(requests, ['/api/admin/operations/groups/$coreId/notes']);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await _unmount(tester, repo: repo);
    }
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('ordinary rows keep their existing bounds at ${scale}x', (
      tester,
    ) async {
      try {
        await _host(
          tester,
          scale: scale,
          child: AdminDataTable(
            rows: const [
              AdminTableRowData(
                id: 'synthetic-ordinary',
                title: '940001',
                subtitle: '',
                status: '',
                amount: '',
              ),
            ],
            columns: [
              AdminTableColumn(
                label: 'User ID',
                selectable: true,
                value: (row) => row.title,
              ),
            ],
          ),
        );
        final table = tester.widget<DataTable>(find.byType(DataTable));
        expect(table.dataRowMinHeight, 56 + (scale - 1) * 40);
        expect(table.dataRowMaxHeight, 64 + (scale - 1) * 40);
        final fact = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(fact.data, '940001');
        expect(fact.maxLines, 1);
        expect(fact.enableInteractiveSelection, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
      }
    });
  }
}

Future<void> _expectCompleteFact(
  WidgetTester tester,
  String value,
  String label,
) async {
  final fact = find.widgetWithText(SelectableText, value);
  expect(fact, findsOneWidget);
  await tester.ensureVisible(fact);
  await tester.pumpAndSettle();
  final selectable = tester.widget<SelectableText>(fact);
  expect(selectable.maxLines, isNull);
  expect(selectable.enableInteractiveSelection, isTrue);
  final editableFinder = find.descendant(
    of: fact,
    matching: find.byType(EditableText),
  );
  final editable = tester.widget<EditableText>(editableFinder);
  expect(editable.controller.text, value);
  final RenderEditable render = tester
      .state<EditableTextState>(editableFinder)
      .renderEditable;
  final boxes = render.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: value.length),
  );
  expect(boxes.length, greaterThanOrEqualTo(3));
  // Finder/semantics presence alone would miss a clipped editable viewport.
  // Every rendered line must fit vertically, with no hidden internal scroll.
  expect(render.size.height, greaterThan(104));
  expect(render.offset.pixels, 0);
  for (final box in boxes) {
    expect(box.top, greaterThanOrEqualTo(-0.01));
    expect(box.bottom, lessThanOrEqualTo(render.size.height + 0.01));
  }
  await _expectNativeFactSemantics(tester, fact, value, label);
  final table = tester.widget<DataTable>(
    find.ancestor(of: fact, matching: find.byType(DataTable)).first,
  );
  expect(table.dataRowMaxHeight, double.infinity);
  expect(tester.takeException(), isNull);
}

Future<void> _expectNativeFactSemantics(
  WidgetTester tester,
  Finder fact,
  String value,
  String label,
) async {
  // Inspect the real merged SelectableText node, without replacing its native
  // focus, selection or copy callbacks with synthetic semantics actions.
  var node = tester.getSemantics(fact);
  var data = node.getSemanticsData();
  expect(data.label, '$label:');
  expect(data.value, value);
  expect(data.flagsCollection.isReadOnly, isTrue);
  expect(data.flagsCollection.isFocused.toBoolOrNull(), isNotNull);
  expect(data.hasAction(SemanticsAction.longPress), isTrue);
  final owner = node.owner!;
  owner.performAction(node.id, SemanticsAction.longPress);
  await tester.pumpAndSettle();
  node = tester.getSemantics(fact);
  data = node.getSemanticsData();
  expect(data.flagsCollection.isFocused.toBoolOrNull(), isTrue);
  expect(data.hasAction(SemanticsAction.setSelection), isTrue);
  final selection = TextSelection(baseOffset: 0, extentOffset: value.length);
  owner.performAction(node.id, SemanticsAction.setSelection, <String, dynamic>{
    'base': selection.baseOffset,
    'extent': selection.extentOffset,
  });
  await tester.pump();
  final editable = tester.widget<EditableText>(
    find.descendant(of: fact, matching: find.byType(EditableText)),
  );
  expect(editable.controller.text, value);
  expect(editable.controller.selection, selection);
  data = tester.getSemantics(fact).getSemanticsData();
  expect(data.label, '$label:');
  expect(data.value, value);
  expect(data.textSelection, selection);
  expect(data.hasAction(SemanticsAction.setSelection), isTrue);
  expect(data.hasAction(SemanticsAction.copy), isTrue);
  expect(data.hasAction(SemanticsAction.setText), isFalse);
}

Future<void> _host(
  WidgetTester tester, {
  required Widget child,
  CloudflareAdminRepository? repo,
  required double scale,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      collectBackendClientProvider.overrideWithValue(null),
      adminPendingAttemptStorageProvider.overrideWithValue(
        MemoryAdminPendingAttemptStorage(),
      ),
      if (repo != null) ...[
        adminRepositoryProvider.overrideWithValue(repo),
        cloudflareAdminSessionProvider.overrideWith((ref) => repo.session),
      ],
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: child is CloudflareOperatingDetailPage
              ? child
              : SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _unmount(
  WidgetTester tester, {
  CloudflareAdminRepository? repo,
}) async {
  if (repo != null && repo.session.mounted) repo.session.clear();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}
