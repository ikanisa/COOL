part of 'rayon_sports_repository.dart';

extension RayonSportsShopRepository on RayonSportsRepository {
  Future<List<RsShopProduct>> getProducts(
    String partnerId,
    String? category,
  ) async {
    var query = _client
        .from('rs_shop_products')
        .select()
        .eq('partner_id', partnerId)
        .eq('is_active', true);

    if (category != null && category.isNotEmpty) {
      query = query.ilike('category', '%$category%');
    }

    return _asListOfMaps(
      await query.order('sort_order').order('price').order('name'),
    ).map(RsShopProduct.fromJson).toList(growable: false);
  }

  Future<String> placeOrder({
    required String userId,
    required List<RsShopProduct> products,
    required Map<String, int> quantities,
    required String deliveryAddress,
    String? referralInviteId,
    int discountAmount = 0,
  }) async {
    final subtotal = _sumProducts(products, quantities);
    if (subtotal <= 0) throw StateError('Your cart is empty.');

    final total = subtotal - discountAmount;
    return _checkoutService.openCheckout(
      component: 'rayon_shop',
      userId: userId,
      referencePrefix: 'RS-SHOP',
      amount: total,
      successMessage: 'Rayon shop checkout opened successfully.',
      failureMessage: 'Rayon shop checkout failed before payment sync.',
      failureMetadata: <String, Object?>{
        'discount_amount': discountAmount,
        'total': total,
      },
      prepare: (reference) async {
        final rows = _asListOfMaps(
          await _client
              .from('rs_shop_orders')
              .insert(<String, Object?>{
                'user_id': userId,
                'items': products
                    .map(
                      (p) => <String, Object?>{
                        'product': p.toJson(),
                        'product_id': p.id,
                        'name': p.name,
                        'category': p.category.value,
                        'image_emoji': p.imageEmoji,
                        'image_url': p.imageUrl,
                        'bg_color':
                            '#${p.bgColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                        'sizes': p.availableSizes,
                        'quantity': quantities[p.id] ?? 0,
                        'unit_price': p.price,
                      },
                    )
                    .where((item) => (item['quantity'] as int) > 0)
                    .toList(growable: false),
                'subtotal': subtotal,
                'discount_amount': discountAmount,
                'discount': discountAmount,
                'delivery_fee': 0,
                'total': total,
                'delivery_address': deliveryAddress,
                'momo_reference': reference,
                'referral_invite_id': referralInviteId,
                'status': 'pending',
              })
              .select('id'),
        );

        final orderId = rows.first['id']?.toString() ?? reference;
        return RayonCheckoutResult<String>(
          value: orderId,
          subjectType: 'rs_shop_orders',
          subjectId: orderId,
          successMetadata: <String, Object?>{
            'item_count': quantities.values.fold<int>(
              0,
              (sum, quantity) => sum + quantity,
            ),
            'discount_amount': discountAmount,
            'total': total,
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> getMyOrders(String userId) async {
    return _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    );
  }

  Future<List<RsShopOrder>> getMyShopOrders(String userId) async {
    return _asListOfMaps(
      await _client
          .from('rs_shop_orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false),
    ).map(RsShopOrder.fromJson).toList(growable: false);
  }

  Future<void> cancelOrder(String orderId) async {
    await _client
        .from('rs_shop_orders')
        .update(<String, Object?>{'status': 'cancelled'})
        .eq('id', orderId)
        .eq('status', 'pending');
  }
}
