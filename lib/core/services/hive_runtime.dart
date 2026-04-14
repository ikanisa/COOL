import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

typedef OpenHiveBox<T> = Future<Box<T>> Function(String name);
typedef InitializeHive = Future<void> Function();

Future<void> initializeHiveRuntime() => Hive.initFlutter();

/// Current schema version for all Hive boxes.
///
/// Increment this whenever a breaking change is made to any Hive box
/// schema (e.g. renamed keys, changed value types, removed boxes).
///
/// All Hive data in this app is either regenerable from the backend or
/// best-effort caching, so a full wipe on schema mismatch is safe.
const int hiveSchemaVersion = 1;

/// Name of the internal box that tracks the persisted schema version.
const String _metaBoxName = '_cool_hive_meta';

/// Key inside the meta box that stores the version number.
const String _versionKey = 'schema_version';

/// Checks the stored Hive schema version against [hiveSchemaVersion].
///
/// If the versions differ (or no version has been stored yet), all known
/// Hive boxes are deleted and recreated fresh. This prevents hard crashes
/// from binary-incompatible data left over from a previous app version.
///
/// Call this **once** during app bootstrap, **after** [initializeHiveRuntime]
/// and **before** opening any other boxes.
Future<void> ensureHiveSchemaVersion() async {
  final metaBox = await Hive.openBox<dynamic>(_metaBoxName);

  final storedVersion = metaBox.get(_versionKey) as int?;
  if (storedVersion == hiveSchemaVersion) {
    await metaBox.close();
    return;
  }

  debugPrint(
    '[Hive] Schema version mismatch: stored=$storedVersion, '
    'current=$hiveSchemaVersion. Wiping all boxes.',
  );

  // Close the meta box before deleting everything.
  await metaBox.close();

  // Delete all boxes Hive knows about. This covers any box that has
  // been opened during a previous run on this device.
  try {
    await Hive.deleteFromDisk();
  } catch (error) {
    debugPrint('[Hive] deleteFromDisk failed: $error');
    // Non-fatal — individual box opens will self-heal via openHiveBox.
  }

  // Re-initialize Hive after the wipe (the directory may have been removed).
  await initializeHiveRuntime();

  // Persist the new schema version.
  final freshMetaBox = await Hive.openBox<dynamic>(_metaBoxName);
  await freshMetaBox.put(_versionKey, hiveSchemaVersion);
  await freshMetaBox.close();

  debugPrint('[Hive] Schema version set to $hiveSchemaVersion.');
}

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
