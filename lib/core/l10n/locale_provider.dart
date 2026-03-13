import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'supported_locales.dart';

/// Hive box + key used to persist the selected locale.
const _settingsBox = 'settings';
const _langKey = 'lang';

abstract class LocaleStore {
  Future<String> readLanguageCode();
  Future<void> writeLanguageCode(String languageCode);
}

class HiveLocaleStore implements LocaleStore {
  const HiveLocaleStore();

  @override
  Future<String> readLanguageCode() async {
    try {
      final box = await Hive.openBox<String>(_settingsBox);
      return box.get(_langKey, defaultValue: 'en') ?? 'en';
    } catch (_) {
      // Tests and lightweight router boots can read locale before Hive is
      // initialized. Fall back to English instead of crashing those flows.
      return 'en';
    }
  }

  @override
  Future<void> writeLanguageCode(String languageCode) async {
    try {
      final box = await Hive.openBox<String>(_settingsBox);
      await box.put(_langKey, languageCode);
    } catch (_) {
      // Keep locale changes in-memory when persistence is unavailable.
    }
  }
}

final localeStoreProvider = Provider<LocaleStore>((ref) {
  return const HiveLocaleStore();
});

/// Provides the current app locale, backed by persistent locale storage.
///
/// On first read the provider loads the stored language code from the
/// configured store (defaulting to `'en'`). Updates are written back so the
/// choice survives app restarts.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier(store: ref.watch(localeStoreProvider));
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier({required LocaleStore store})
    : _store = store,
      super(const Locale('en')) {
    _loadFromStore();
  }

  final LocaleStore _store;

  Future<void> _loadFromStore() async {
    final code = normalizeSupportedLanguageCode(
      await _store.readLanguageCode(),
    );
    state = Locale(code);
  }

  /// Sets the app locale and persists the choice through the configured store.
  Future<void> setLocale(String languageCode) async {
    final normalized = normalizeSupportedLanguageCode(languageCode);
    state = Locale(normalized);
    await _store.writeLanguageCode(normalized);
  }
}
