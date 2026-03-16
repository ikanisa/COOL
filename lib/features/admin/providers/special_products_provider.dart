import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/special_product.dart';

/// All special products (active + inactive) for admin management.
final adminSpecialProductsProvider =
    FutureProvider.autoDispose<List<SpecialProduct>>((ref) async {
  final rows = await Supabase.instance.client
      .from('special_products')
      .select()
      .order('sort_order');
  return rows.map((r) => SpecialProduct.fromJson(r)).toList();
});

/// Active special products only (for customer home screen).
final activeSpecialProductsProvider =
    FutureProvider.autoDispose<List<SpecialProduct>>((ref) async {
  final rows = await Supabase.instance.client
      .from('special_products')
      .select()
      .eq('is_active', true)
      .order('sort_order');
  return rows.map((r) => SpecialProduct.fromJson(r)).toList();
});

/// CRUD operations for admin.
class SpecialProductsRepository {
  SpecialProductsRepository(this._client);

  final SupabaseClient _client;

  Future<void> upsert(SpecialProduct product) async {
    final data = product.toInsertJson();
    if (product.id.isEmpty) {
      await _client.from('special_products').insert(data);
    } else {
      await _client
          .from('special_products')
          .update(data)
          .eq('id', product.id);
    }
  }

  Future<void> toggleActive(String id, {required bool isActive}) async {
    await _client.from('special_products').update({
      'is_active': isActive,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  Future<void> delete(String id) async {
    await _client.from('special_products').delete().eq('id', id);
  }
}
