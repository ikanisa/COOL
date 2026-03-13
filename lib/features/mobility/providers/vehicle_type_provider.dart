import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/supabase_client_provider.dart';
import '../models/vehicle_type.dart';
import '../repositories/vehicle_type_repository.dart';

/// Provides a singleton [VehicleTypeRepository].
final vehicleTypeRepositoryProvider = Provider<VehicleTypeRepository>(
  (ref) => VehicleTypeRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches all active vehicle types for the fixed Rwanda app shell.
final vehicleTypesProvider = FutureProvider<List<VehicleType>>((ref) {
  final repo = ref.read(vehicleTypeRepositoryProvider);
  return repo.fetchAll();
});

final currentCountryVehicleTypesProvider = vehicleTypesProvider;
