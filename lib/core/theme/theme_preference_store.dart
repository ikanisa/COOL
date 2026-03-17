import '../services/hive_runtime.dart';
import 'theme_preference.dart';

abstract class ThemePreferenceStore {
  Future<({AppThemePreference preference, DateTime? updatedAt})> read();
  Future<void> write(AppThemePreference preference, {DateTime? updatedAt});
}

class HiveThemePreferenceStore implements ThemePreferenceStore {
  HiveThemePreferenceStore({
    required OpenHiveBox<String> openBox,
    this.boxName = 'theme_preferences',
    this.preferenceKey = 'theme_mode',
    this.timestampKey = 'theme_updated_at',
  }) : _openBox = openBox;

  final OpenHiveBox<String> _openBox;
  final String boxName;
  final String preferenceKey;
  final String timestampKey;

  @override
  Future<({AppThemePreference preference, DateTime? updatedAt})> read() async {
    try {
      final box = await _openBox(boxName);
      final value = box.get(preferenceKey);
      final rawTimestamp = box.get(timestampKey);
      final preference = appThemePreferenceFromStorage(value);
      final updatedAt = rawTimestamp != null
          ? DateTime.tryParse(rawTimestamp)
          : null;
      return (preference: preference, updatedAt: updatedAt);
    } catch (_) {
      return (preference: AppThemePreference.system, updatedAt: null);
    }
  }

  @override
  Future<void> write(
    AppThemePreference preference, {
    DateTime? updatedAt,
  }) async {
    try {
      final box = await _openBox(boxName);
      await box.put(preferenceKey, preference.storageValue);
      if (updatedAt != null) {
        await box.put(timestampKey, updatedAt.toIso8601String());
      } else {
        await box.put(timestampKey, DateTime.now().toIso8601String());
      }
    } catch (_) {
      // Theme persistence is best-effort.
    }
  }
}
