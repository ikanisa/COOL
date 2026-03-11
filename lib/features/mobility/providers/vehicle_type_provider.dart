import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/vehicle_type.dart';
import '../repositories/vehicle_type_repository.dart';

/// Provides a singleton [VehicleTypeRepository].
final vehicleTypeRepositoryProvider = Provider<VehicleTypeRepository>(
  (ref) => VehicleTypeRepository(),
);

/// Fetches all active vehicle types, optionally filtered by country.
final vehicleTypesProvider =
    FutureProvider.family<List<VehicleType>, String?>((ref, country) {
  final repo = ref.read(vehicleTypeRepositoryProvider);
  return repo.fetchAll(country: country);
});
