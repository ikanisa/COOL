import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/supabase_client_provider.dart';
import '../models/vehicle_type.dart';
import '../repositories/vehicle_type_repository.dart';

/// Provides a singleton [VehicleTypeRepository].
final vehicleTypeRepositoryProvider = Provider<VehicleTypeRepository>(
  (ref) => VehicleTypeRepository(client: ref.read(supabaseClientProvider)),
);

/// Fetches all active vehicle types, optionally filtered by country.
final vehicleTypesProvider = FutureProvider.family<List<VehicleType>, String?>((
  ref,
  country,
) {
  final repo = ref.read(vehicleTypeRepositoryProvider);
  return repo.fetchAll(country: country);
});

final currentCountryVehicleTypesProvider = FutureProvider<List<VehicleType>>((
  ref,
) {
  final country = ref.watch(currentUserCountryCodeProvider);
  return ref.watch(vehicleTypesProvider(country).future);
});
