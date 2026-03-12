import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/country_catalog.dart';
import '../models/vehicle_type.dart';

/// Fetches vehicle types from the `vehicle_types` Supabase table.
class VehicleTypeRepository {
  VehicleTypeRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Fetch all active vehicle types, optionally filtered by country.
  Future<List<VehicleType>> fetchAll({String? country}) async {
    var query = _client.from('vehicle_types').select().eq('is_active', true);

    if (country != null && country.trim().isNotEmpty) {
      final normalizedCountry = CoolCountryCatalog.normalizeCountryCode(
        country,
      );
      query = query.or('country.is.null,country.eq.$normalizedCountry');
    }

    final rows = await query.order('sort_order');
    return rows.map((r) => VehicleType.fromJson(r)).toList();
  }
}
