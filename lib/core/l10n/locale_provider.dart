import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive box + key used to persist the selected locale.
const _settingsBox = 'settings';
const _langKey = 'lang';

/// Provides the current app locale, backed by Hive persistence.
///
/// On first read the provider loads the stored language code from Hive
/// (defaulting to `'en'`). Updates are written through to Hive so the
/// choice survives app restarts.
final localeProvider =
    StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _loadFromHive();
  }

  Future<void> _loadFromHive() async {
    final box = await Hive.openBox<String>(_settingsBox);
    final code = box.get(_langKey, defaultValue: 'en')!;
    state = Locale(code);
  }

  /// Sets the app locale and persists the choice to Hive.
  Future<void> setLocale(String languageCode) async {
    state = Locale(languageCode);
    final box = await Hive.openBox<String>(_settingsBox);
    await box.put(_langKey, languageCode);
  }
}
