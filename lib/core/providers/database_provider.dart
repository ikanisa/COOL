import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/cool_database.dart';

/// Singleton [CoolDatabase] instance for the entire app.
///
/// Uses `drift_flutter` for a production-ready SQLite connection
/// backed by `sqlite3_flutter_libs` on mobile and WASM on web.
final coolDatabaseProvider = Provider<CoolDatabase>((ref) {
  final db = CoolDatabase(
    driftDatabase(name: 'cool_v1'),
  );
  ref.onDispose(db.close);
  return db;
});
