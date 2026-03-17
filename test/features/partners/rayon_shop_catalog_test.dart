import 'package:cool_app/features/partners/providers/rayon_sports_provider.dart';
import 'package:cool_app/features/partners/rayon/models/rs_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for [RayonShopCatalogData] business logic.
void main() {
  const productA = RsProduct(
    id: 'prod-a',
    partnerId: 'partner-1',
    name: 'Home Jersey 2026',
    category: ProductCategory.kits,
    price: 15000,
    imageEmoji: '👕',
    bgColor: Color(0xFF2196F3),
    stock: 50,
    isActive: true,
    isNew: true,
  );

  const productB = RsProduct(
    id: 'prod-b',
    partnerId: 'partner-1',
    name: 'Rayon Scarf',
    category: ProductCategory.scarves,
    price: 5000,
    imageEmoji: '🧣',
    bgColor: Color(0xFF4CAF50),
    stock: 100,
    isActive: true,
    isNew: false,
  );

  const productC = RsProduct(
    id: 'prod-c',
    partnerId: 'partner-1',
    name: 'Training Cap',
    category: ProductCategory.caps,
    price: 3000,
    imageEmoji: '🧢',
    bgColor: Color(0xFFF44336),
    stock: 25,
    isActive: true,
    isNew: false,
  );

  group('RayonShopCatalogData', () {
    test('empty cart returns no selected products', () {
      const catalog = RayonShopCatalogData(
        products: [productA, productB],
        membership: null,
        cart: <String, int>{},
      );

      expect(catalog.selectedProducts(), isEmpty);
      expect(catalog.hasItems, isFalse);
      expect(catalog.cartItemCount, 0);
    });

    test('selectedProducts returns only items in cart', () {
      const catalog = RayonShopCatalogData(
        products: [productA, productB, productC],
        membership: null,
        cart: <String, int>{'prod-a': 2, 'prod-c': 1},
      );

      final selected = catalog.selectedProducts();
      expect(selected.length, 2);
      expect(selected.map((p) => p.id).toList(), ['prod-a', 'prod-c']);
      expect(catalog.hasItems, isTrue);
      expect(catalog.cartItemCount, 3);
    });

    test('subtotalFor calculates total price * quantity', () {
      const catalog = RayonShopCatalogData(
        products: [productA, productB],
        membership: null,
        cart: <String, int>{'prod-a': 2, 'prod-b': 3},
      );

      final selected = catalog.selectedProducts();
      final subtotal = catalog.subtotalFor(selected);

      // 15000 * 2 + 5000 * 3 = 45000
      expect(subtotal, 45000);
    });

    test('quantityFor returns 0 for items not in cart', () {
      const catalog = RayonShopCatalogData(
        products: [productA],
        membership: null,
        cart: <String, int>{},
      );

      expect(catalog.quantityFor('prod-a'), 0);
      expect(catalog.quantityFor('nonexistent'), 0);
    });

    group('discounts', () {
      test('no discount without gold/platinum membership', () {
        const catalog = RayonShopCatalogData(
          products: [productA],
          membership: null,
          cart: <String, int>{'prod-a': 1},
        );

        expect(catalog.hasMemberDiscount, isFalse);
        expect(catalog.discountFor(15000), 0);
      });

      test('no discount for blue tier', () {
        final catalog = RayonShopCatalogData(
          products: [productA],
          membership: RsFanMembership(
            id: 'm-1',
            userId: 'u-1',
            partnerId: 'p-1',
            tier: FanTier.blue,
            points: 0,
            chapter: 'Kigali Central',
            membershipNumber: 'RS-001',
            joinedAt: DateTime(2026),
          ),
          cart: const <String, int>{'prod-a': 1},
        );

        expect(catalog.hasMemberDiscount, isFalse);
        expect(catalog.discountFor(15000), 0);
      });

      test('no discount for silver tier', () {
        final catalog = RayonShopCatalogData(
          products: [productA],
          membership: RsFanMembership(
            id: 'm-1',
            userId: 'u-1',
            partnerId: 'p-1',
            tier: FanTier.silver,
            points: 100,
            chapter: 'Kigali Central',
            membershipNumber: 'RS-002',
            joinedAt: DateTime(2026),
          ),
          cart: const <String, int>{'prod-a': 1},
        );

        expect(catalog.hasMemberDiscount, isFalse);
        expect(catalog.discountFor(15000), 0);
      });

      test('10% discount for gold tier', () {
        final catalog = RayonShopCatalogData(
          products: [productA],
          membership: RsFanMembership(
            id: 'm-1',
            userId: 'u-1',
            partnerId: 'p-1',
            tier: FanTier.gold,
            points: 500,
            chapter: 'Kigali Central',
            membershipNumber: 'RS-003',
            joinedAt: DateTime(2026),
          ),
          cart: const <String, int>{'prod-a': 2},
        );

        expect(catalog.hasMemberDiscount, isTrue);
        // subtotal 30000, 10% discount = 3000
        expect(catalog.discountFor(30000), 3000);
      });

      test('10% discount for platinum tier', () {
        final catalog = RayonShopCatalogData(
          products: [productA, productB],
          membership: RsFanMembership(
            id: 'm-1',
            userId: 'u-1',
            partnerId: 'p-1',
            tier: FanTier.platinum,
            points: 1000,
            chapter: 'Kigali Central',
            membershipNumber: 'RS-004',
            joinedAt: DateTime(2026),
          ),
          cart: const <String, int>{'prod-a': 1, 'prod-b': 2},
        );

        expect(catalog.hasMemberDiscount, isTrue);
        // subtotal: 15000 + 10000 = 25000, discount = 2500
        expect(catalog.discountFor(25000), 2500);
      });
    });

    test('cartTotal sums all products including those with 0 qty', () {
      const catalog = RayonShopCatalogData(
        products: [productA, productB, productC],
        membership: null,
        cart: <String, int>{'prod-a': 1, 'prod-c': 2},
      );

      // prod-a: 15000*1 + prod-b: 5000*0 + prod-c: 3000*2 = 21000
      expect(catalog.cartTotal, 21000);
    });
  });

  group('RayonCartController', () {
    test('addToCart increments quantity', () {
      final controller = RayonCartController();
      controller.addToCart('prod-a');
      expect(controller.debugState['prod-a'], 1);

      controller.addToCart('prod-a');
      expect(controller.debugState['prod-a'], 2);
    });

    test('addToCart adds new item with quantity 1', () {
      final controller = RayonCartController();
      controller.addToCart('prod-a');
      controller.addToCart('prod-b');

      expect(controller.debugState['prod-a'], 1);
      expect(controller.debugState['prod-b'], 1);
    });

    test('removeFromCart decrements quantity', () {
      final controller = RayonCartController();
      controller.addToCart('prod-a');
      controller.addToCart('prod-a');
      controller.addToCart('prod-a');
      controller.removeFromCart('prod-a');

      expect(controller.debugState['prod-a'], 2);
    });

    test('removeFromCart removes item when quantity reaches 0', () {
      final controller = RayonCartController();
      controller.addToCart('prod-a');
      controller.removeFromCart('prod-a');

      expect(controller.debugState.containsKey('prod-a'), isFalse);
    });

    test('removeFromCart is safe on empty cart', () {
      final controller = RayonCartController();
      controller.removeFromCart('nonexistent');

      expect(controller.debugState, isEmpty);
    });

    test('clearCart empties all items', () {
      final controller = RayonCartController();
      controller.addToCart('prod-a');
      controller.addToCart('prod-b');
      controller.addToCart('prod-c');
      controller.clearCart();

      expect(controller.debugState, isEmpty);
    });
  });

  group('RsProduct.discountedPrice', () {
    test('returns original price at 0% discount', () {
      expect(productA.discountedPrice(0), 15000);
    });

    test('returns 90% of price at 10% discount', () {
      expect(productA.discountedPrice(10), 13500);
    });

    test('returns 0 at 100% discount', () {
      expect(productA.discountedPrice(100), 0);
    });

    test('clamps negative discount to 0', () {
      expect(productA.discountedPrice(-10), 15000);
    });

    test('clamps above 100% discount to 100', () {
      expect(productA.discountedPrice(150), 0);
    });
  });

  group('RsShopOrder.fromJson', () {
    test('parses a valid JSON order', () {
      final json = <String, Object?>{
        'id': 'order-1',
        'user_id': 'user-1',
        'items': <Map<String, Object?>>[],
        'subtotal': 30000,
        'discount_amount': 3000,
        'delivery_fee': 0,
        'total': 27000,
        'delivery_address': 'Kigali Pele pickup',
        'momo_reference': 'MOMO-REF-123',
        'status': 'pending',
        'created_at': '2026-03-17T10:00:00.000Z',
      };

      final order = RsShopOrder.fromJson(json);

      expect(order.id, 'order-1');
      expect(order.userId, 'user-1');
      expect(order.subtotal, 30000);
      expect(order.discountAmount, 3000);
      expect(order.deliveryFee, 0);
      expect(order.total, 27000);
      expect(order.deliveryAddress, 'Kigali Pele pickup');
      expect(order.momoReference, 'MOMO-REF-123');
      expect(order.status, OrderStatus.pending);
    });

    test('computes total from subtotal - discount + delivery when missing', () {
      final json = <String, Object?>{
        'id': 'order-2',
        'user_id': 'user-1',
        'items': <Map<String, Object?>>[],
        'subtotal': 20000,
        'discount_amount': 2000,
        'delivery_fee': 1000,
        'delivery_address': 'Kigali',
        'momo_reference': '',
        'status': 'confirmed',
        'created_at': '2026-03-17T10:00:00.000Z',
      };

      final order = RsShopOrder.fromJson(json);

      // total should be: 20000 - 2000 + 1000 = 19000
      expect(order.total, 19000);
      expect(order.status, OrderStatus.confirmed);
    });
  });
}
