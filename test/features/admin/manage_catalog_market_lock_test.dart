import 'package:cool_app/features/admin/providers/admin_providers.dart';
import 'package:cool_app/features/admin/repositories/admin_repository.dart';
import 'package:cool_app/features/admin/screens/manage_partners_screen.dart';
import 'package:cool_app/features/admin/screens/manage_quick_actions_screen.dart';
import 'package:cool_app/features/admin/screens/manage_services_screen.dart';
import 'package:cool_app/features/admin/screens/manage_vehicle_types_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeCatalogAdminRepository extends AdminRepository {
  FakeCatalogAdminRepository({
    List<Map<String, dynamic>> partners = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> services = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> quickActions = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> vehicleTypes = const <Map<String, dynamic>>[],
  }) : _partners = partners.map(Map<String, dynamic>.from).toList(),
       _services = services.map(Map<String, dynamic>.from).toList(),
       _quickActions = quickActions.map(Map<String, dynamic>.from).toList(),
       _vehicleTypes = vehicleTypes.map(Map<String, dynamic>.from).toList(),
       super(client: MockSupabaseClient());

  final List<Map<String, dynamic>> _partners;
  final List<Map<String, dynamic>> _services;
  final List<Map<String, dynamic>> _quickActions;
  final List<Map<String, dynamic>> _vehicleTypes;

  final List<Map<String, dynamic>> partnerUpserts = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> serviceUpserts = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> quickActionUpserts =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> vehicleTypeUpserts =
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

  @override
  Future<List<Map<String, dynamic>>> fetchVehicleTypes({
    String? country,
  }) async {
    return _vehicleTypes.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<void> upsertVehicleType(Map<String, dynamic> type) async {
    vehicleTypeUpserts.add(Map<String, dynamic>.from(type));
  }
}

Finder _textFieldWithLabel(String label) {
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
  tester.view.physicalSize = const Size(1440, 2560);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
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
          adminRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManagePartnersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('urwego · bank'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(_dropdownFieldWithLabel('Market'), findsNothing);
    expect(_inputDecoratorWithLabel('Market (auto)'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('Name *'), 'Rayon Tickets');
    await tester.enterText(_textFieldWithLabel('Slug *'), 'rayon-tickets');
    await tester.enterText(_textFieldWithLabel('Emoji'), '🎟️');
    await tester.enterText(_textFieldWithLabel('Subtitle'), 'Local ticketing');
    // Category is a dropdown, not a text field
    await tester.enterText(_textFieldWithLabel('WhatsApp Number'), '+250788123456');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

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
          adminRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageQuickActionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('/tickets · Rwanda'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(_dropdownFieldWithLabel('Market scope'), findsNothing);
    expect(_inputDecoratorWithLabel('Market'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('Title'), 'Ride');
    await tester.enterText(_textFieldWithLabel('Subtitle'), 'Book a moto');
    await tester.enterText(_textFieldWithLabel('Emoji'), '🛵');
    await tester.enterText(_textFieldWithLabel('Route'), '/mobility');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.quickActionUpserts, hasLength(1));
    expect(
      repository.quickActionUpserts.single,
      containsPair('country', 'RW'),
    );
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
          adminRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageServicesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Urwego · banking · Rwanda'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(_inputDecoratorWithLabel('Market'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('Title'), 'Collections');
    await tester.enterText(_textFieldWithLabel('Subtitle'), 'Collect dues');
    await tester.enterText(_textFieldWithLabel('Emoji'), '📥');
    await tester.enterText(_textFieldWithLabel('Category'), 'payments');
    await tester.enterText(_textFieldWithLabel('CTA Label'), 'Open');
    await tester.enterText(_textFieldWithLabel('CTA Action'), '/collections');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.serviceUpserts, hasLength(1));
    expect(repository.serviceUpserts.single, containsPair('country', 'RW'));
  });

  testWidgets('vehicle types screen locks the market to Rwanda', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = FakeCatalogAdminRepository(
      vehicleTypes: const <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'vehicle-1',
          'label': 'Moto',
          'value': 'moto',
          'country': null,
          'emoji': '🛵',
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          adminRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: ManageVehicleTypesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('value: moto · Rwanda'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(_dropdownFieldWithLabel('Market scope'), findsNothing);
    expect(_inputDecoratorWithLabel('Market'), findsOneWidget);

    await tester.enterText(_textFieldWithLabel('Label (e.g. 🛺 Moto)'), 'Taxi');
    await tester.enterText(_textFieldWithLabel('Value (e.g. Moto)'), 'taxi');
    await tester.enterText(_textFieldWithLabel('Emoji'), '🚕');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.vehicleTypeUpserts, hasLength(1));
    expect(
      repository.vehicleTypeUpserts.single,
      containsPair('country', 'RW'),
    );
  });
}
