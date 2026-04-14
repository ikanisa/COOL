import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

typedef OpenHiveBox<T> = Future<Box<T>> Function(String name);
typedef InitializeHive = Future<void> Function();

Future<void> initializeHiveRuntime() => Hive.initFlutter();

/// Opens a Hive box with corruption recovery.
///
/// If a box fails to open (e.g. due to corrupt data or a schema
/// mismatch from a version upgrade), the box file is deleted and
/// a fresh empty box is returned. This prevents hard crashes from
/// local storage corruption while accepting the tradeoff of losing
/// cached data (all Hive data in this app is either regenerable or
/// best-effort caching).
Future<Box<T>> openHiveBox<T>(String name) async {
  try {
    return await Hive.openBox<T>(name);
  } catch (error) {
    debugPrint('[Hive] Box "$name" failed to open: $error');
    debugPrint('[Hive] Deleting corrupt box "$name" and recreating…');

    try {
      await Hive.deleteBoxFromDisk(name);
    } catch (deleteError) {
      debugPrint('[Hive] Could not delete box "$name": $deleteError');
    }

    // Open a fresh box. If this also fails, let it propagate —
    // the bootstrap error handler will show a retry card.
    return Hive.openBox<T>(name);
  }
}
