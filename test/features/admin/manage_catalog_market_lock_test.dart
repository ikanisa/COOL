import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_content_repository.dart';
import 'package:cool_app/features/admin/screens/manage_partners_screen.dart';
import 'package:cool_app/features/admin/screens/manage_quick_actions_screen.dart';
import 'package:cool_app/features/admin/screens/manage_services_screen.dart';
import 'package:cool_app/shared/widgets/cool_admin_inline_field.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeCatalogAdminRepository extends AdminContentRepository {
  FakeCatalogAdminRepository({
    List<Map<String, dynamic>> partners = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> services = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> quickActions = const <Map<String, dynamic>>[],
  }) : _partners = partners.map(Map<String, dynamic>.from).toList(),
       _services = services.map(Map<String, dynamic>.from).toList(),
       _quickActions = quickActions.map(Map<String, dynamic>.from).toList(),
       super(client: MockSupabaseClient());

  final List<Map<String, dynamic>> _partners;
  final List<Map<String, dynamic>> _services;
  final List<Map<String, dynamic>> _quickActions;

  final List<Map<String, dynamic>> partnerUpserts = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> serviceUpserts = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> quickActionUpserts =
      <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchPartners({String? country}) async {
    return _partners.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<void> upsertPartner(Map<String, dynamic> partner) async {
    partnerUpserts.add(Map<String, dynamic>.from(partner));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPartnerServices({
    String? partnerId,
    String? country,
  }) async {
    return _services.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<void> upsertPartnerService(Map<String, dynamic> service) async {
    serviceUpserts.add(Map<String, dynamic>.from(service));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchQuickActions({
    String? country,
  }) async {
    return _quickActions.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<void> upsertQuickAction(Map<String, dynamic> action) async {
    quickActionUpserts.add(Map<String, dynamic>.from(action));
  }
}

Finder _textFieldWithLabel(String label) {
  final inlineField = find.byWidgetPredicate(
    (widget) => widget is CoolAdminInlineField && widget.label == label,
    description: 'CoolAdminInlineField(label: $label)',
  );
  if (inlineField.evaluate().isNotEmpty) {
    return find.descendant(of: inlineField, matching: find.byType(TextField));
  }

  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField(labelText: $label)',
  );
}

Finder _inputDecoratorWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is InputDecorator && widget.decoration.labelText == label,
    description: 'InputDecorator(labelText: $label)',
  );
}

Finder _dropdownFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField &&
        widget.decoration.labelText == label,
    description: 'DropdownButtonFormField(labelText: $label)',
  );
}

void _configureTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 4800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _tapAddAction(WidgetTester tester) async {
  final fab = find.byType(FloatingActionButton);
  if (fab.evaluate().isNotEmpty) {
    await tester.tap(fab);
    return;
  }

  final addButton = find.byIcon(Icons.add_rounded);
  expect(addButton, findsWidgets);
  await tester.tap(addButton.first);
}

Widget _buildTestApp(Widget child) {
  return MaterialApp(
    builder: (context, appChild) {
      final mediaQuery = MediaQuery.of(context);
      return MediaQuery(
        data: mediaQuery.copyWith(disableAnimations: true),
        child: appChild ?? const SizedBox.shrink(),
      );
    },
    home: child,
  );
}

void main() {
  testWidgets('partners screen locks the market to Rwanda', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeCatalogAdminRepository(
      partners: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'partner-1',
          'name': 'Urwego',
          'slug': 'urwego',
          'category': 'bank',
          'country': null,
          'emoji': '🏦',
          'is_active': true,
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminContentRepositoryProvider.overrideWithValue(repository),
        ],
        child: _buildTestApp(const ManagePartnersScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('urwego · bank'), findsOneWidget);

    await _tapAddAction(tester);
    await tester.pumpAndSettle();

    expect(_dropdownFieldWithLabel('Market'), findsNothing);
    expect(find.text('New Partner'), findsOneWidget);
    expect(_textFieldWithLabel('Name *'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('Name *'), 'Rayon Tickets');
    await tester.enterText(_textFieldWithLabel('Slug *'), 'rayon-tickets');
    await tester.enterText(_textFieldWithLabel('Emoji'), '🎟️');
    await tester.enterText(_textFieldWithLabel('Subtitle'), 'Local ticketing');
    // Category is a dropdown, not a text field
    await tester.enterText(
      _textFieldWithLabel('WhatsApp Number'),
      '+250788123456',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.partnerUpserts, hasLength(1));
    expect(repository.partnerUpserts.single, containsPair('country', 'RW'));
  });

  testWidgets('quick actions screen locks the market to Rwanda', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = FakeCatalogAdminRepository(
      quickActions: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'action-1',
          'title': 'Tickets',
          'route': '/tickets',
          'country': null,
          'emoji': '🎟️',
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminContentRepositoryProvider.overrideWithValue(repository),
        ],
        child: _buildTestApp(const ManageQuickActionsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('/tickets · Rwanda'), findsOneWidget);

    await _tapAddAction(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(_dropdownFieldWithLabel('Market scope'), findsNothing);
    expect(_inputDecoratorWithLabel('Market'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('Title'), 'Ride');
    await tester.enterText(_textFieldWithLabel('Subtitle'), 'Join a group');
    await tester.enterText(_textFieldWithLabel('Emoji'), '🤝');
    await tester.enterText(_textFieldWithLabel('Route'), '/groups');
    final saveButton = tester.widget<CoolButton>(find.byType(CoolButton).last);
    saveButton.onTap?.call();
    await tester.pump(const Duration(milliseconds: 500));

    expect(repository.quickActionUpserts, hasLength(1));
    expect(repository.quickActionUpserts.single, containsPair('country', 'RW'));
  });

  testWidgets('services screen locks the market to Rwanda', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeCatalogAdminRepository(
      partners: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'partner-1',
          'name': 'Urwego',
          'slug': 'urwego',
          'country': null,
        },
      ],
      services: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'service-1',
          'title': 'Savings',
          'subtitle': 'Open an account',
          'emoji': '💰',
          'category': 'banking',
          'partner_id': 'partner-1',
          'country': null,
          'partners': <String, dynamic>{'name': 'Urwego'},
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminContentRepositoryProvider.overrideWithValue(repository),
        ],
        child: _buildTestApp(const ManageServicesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Services under Urwego'), findsOneWidget);

    await _tapAddAction(tester);
    await tester.pumpAndSettle();

    expect(_inputDecoratorWithLabel('Market'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('Title'), 'Collections');
    await tester.enterText(_textFieldWithLabel('Subtitle'), 'Collect dues');
    await tester.enterText(_textFieldWithLabel('Emoji'), '📥');
    // Category is a dropdown
    await tester.enterText(_textFieldWithLabel('CTA Label'), 'Open');
    await tester.enterText(_textFieldWithLabel('CTA Action'), '/collections');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.serviceUpserts, hasLength(1));
    expect(repository.serviceUpserts.single, containsPair('country', 'RW'));
  });
}
