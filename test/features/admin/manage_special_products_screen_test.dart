import 'package:cool_app/core/theme/app_theme.dart';
import 'package:cool_app/features/admin/models/special_product.dart';
import 'package:cool_app/features/admin/providers/special_products_provider.dart';
import 'package:cool_app/features/admin/screens/manage_special_products_screen.dart';
import 'package:cool_app/shared/widgets/cool_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakeSpecialProductsRepository extends SpecialProductsRepository {
  FakeSpecialProductsRepository() : super(MockSupabaseClient());

  final List<SpecialProduct> upsertedProducts = <SpecialProduct>[];
  final List<Map<String, dynamic>> toggles = <Map<String, dynamic>>[];

  @override
  Future<void> upsert(SpecialProduct product) async {
    upsertedProducts.add(product);
  }

  @override
  Future<void> toggleActive(String id, {required bool isActive}) async {
    toggles.add(<String, dynamic>{'id': id, 'isActive': isActive});
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

Widget _wrapAdminScreen(Widget child, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark,
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: widget!,
      ),
      home: child,
    ),
  );
}

void main() {
  testWidgets('renders product list and toggles active state', (tester) async {
    _configureTallViewport(tester);
    final repository = FakeSpecialProductsRepository();

    await tester.pumpWidget(
      _wrapAdminScreen(
        const ManageSpecialProductsScreen(),
        overrides: <Override>[
          adminSpecialProductsProvider.overrideWith(
            (ref) async => <SpecialProduct>[
              const SpecialProduct(
                id: 'product-1',
                slug: 'buri-munsi',
                title: 'Buri Munsi',
                amount: 1000,
                momoRecipient: '12345',
                targetAudience: 'Families',
                isActive: true,
              ),
            ],
          ),
          specialProductsRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Special Products'), findsOneWidget);
    expect(find.text('Buri Munsi'), findsOneWidget);

    await tester.tap(find.byTooltip('Disable'));
    await tester.pumpAndSettle();

    expect(repository.toggles, hasLength(1));
    expect(repository.toggles.single['id'], 'product-1');
    expect(repository.toggles.single['isActive'], isFalse);
  });

  testWidgets('creates a special product from the editor sheet', (
    tester,
  ) async {
    _configureTallViewport(tester);
    final repository = FakeSpecialProductsRepository();

    await tester.pumpWidget(
      _wrapAdminScreen(
        const ManageSpecialProductsScreen(),
        overrides: <Override>[
          adminSpecialProductsProvider.overrideWith(
            (ref) async => const <SpecialProduct>[],
          ),
          specialProductsRepositoryProvider.overrideWithValue(repository),
        ],
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(_textFieldWithLabel('Title'), 'Harvest Advance');
    await tester.enterText(_textFieldWithLabel('Amount'), '25000');
    await tester.enterText(
      _textFieldWithLabel('MoMo Recipient'),
      'merchant-200',
    );

    await tester.tap(find.byType(CoolButton).last);
    await tester.pumpAndSettle();

    expect(repository.upsertedProducts, hasLength(1));
    expect(repository.upsertedProducts.single.title, 'Harvest Advance');
    expect(repository.upsertedProducts.single.amount, 25000);
    expect(repository.upsertedProducts.single.momoRecipient, 'merchant-200');
  });
}
