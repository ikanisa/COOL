import 'package:cool_app/core/providers/supabase_client_provider.dart';
import 'package:cool_app/features/admin/screens/manage_ai_content_screen.dart';
import 'package:cool_app/features/home/models/nexus_recommendation.dart';
import 'package:cool_app/features/home/providers/nexus_provider.dart';
import 'package:cool_app/features/home/repositories/nexus_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeNexusRepository extends NexusRepository {
  FakeNexusRepository({
    List<NexusRecommendation> items = const <NexusRecommendation>[],
  }) : _items = List<NexusRecommendation>.from(items),
       super(client: MockSupabaseClient());

  final List<NexusRecommendation> _items;
  final List<String> approvedIds = <String>[];
  final List<String> rejectedIds = <String>[];
  final List<String> deletedIds = <String>[];
  final List<Map<String, dynamic>> toggledItems = <Map<String, dynamic>>[];
  final List<NexusRecommendation> upsertedItems = <NexusRecommendation>[];

  @override
  Future<List<NexusRecommendation>> fetchAll({
    AiContentStatus? statusFilter,
  }) async {
    return _items
        .where((item) => statusFilter == null || item.status == statusFilter)
        .toList(growable: false);
  }

  @override
  Future<void> approve(String id) async {
    approvedIds.add(id);
  }

  @override
  Future<void> reject(String id) async {
    rejectedIds.add(id);
  }

  @override
  Future<void> toggleActive(String id, {required bool isActive}) async {
    toggledItems.add(<String, dynamic>{'id': id, 'isActive': isActive});
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
  }

  @override
  Future<void> upsert(NexusRecommendation item) async {
    upsertedItems.add(item);
  }
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField(labelText: $label)',
  );
}

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('renders AI content and approves pending items', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeNexusRepository(
      items: <NexusRecommendation>[
        const NexusRecommendation(
          id: 'content-1',
          title: 'Smart Deposit',
          subtitle: 'Show a bank savings prompt',
          contentType: AiContentType.recommendation,
          status: AiContentStatus.pendingReview,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          nexusRepositoryProvider.overrideWithValue(repository),
          supabaseClientProvider.overrideWithValue(MockSupabaseClient()),
        ],
        child: const MaterialApp(home: ManageAiContentScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('AI Content'), findsOneWidget);
    expect(find.text('Smart Deposit'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(repository.approvedIds, contains('content-1'));
  });

  testWidgets('creates AI content from the editor sheet', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeNexusRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          nexusRepositoryProvider.overrideWithValue(repository),
          supabaseClientProvider.overrideWithValue(MockSupabaseClient()),
        ],
        child: const MaterialApp(home: ManageAiContentScreen()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Title *'), 'Market Prompt');
    await tester.enterText(
      _textFieldWithLabel('CTA Label (e.g. Open)'),
      'Open MoMo',
    );

    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();

    expect(repository.upsertedItems, hasLength(1));
    expect(repository.upsertedItems.single.title, 'Market Prompt');
    expect(repository.upsertedItems.single.ctaLabel, 'Open MoMo');
  });
}
