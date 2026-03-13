import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle_type.dart';

/// Fetches vehicle types from the `vehicle_types` Supabase table.
class VehicleTypeRepository {
  VehicleTypeRepository({required SupabaseClient client})
    : _client = client;

  final SupabaseClient _client;

  /// Fetch all active vehicle types for the fixed Rwanda app shell.
  Future<List<VehicleType>> fetchAll() async {
    final rows = await _client
        .from('vehicle_types')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return rows.map((r) => VehicleType.fromJson(r)).toList();
  }
}
