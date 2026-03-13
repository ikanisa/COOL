import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The COOL app is English-only. This provider always returns `Locale('en')`.
///
/// The locale store abstraction is kept so that callers that previously
/// injected a [LocaleStore] in tests continue to compile.

abstract class LocaleStore {
  Future<String> readLanguageCode();
  Future<void> writeLanguageCode(String languageCode);
}

/// A no-op locale store. The app is English-only.
class HiveLocaleStore implements LocaleStore {
  const HiveLocaleStore();

  @override
  Future<String> readLanguageCode() async => 'en';

  @override
  Future<void> writeLanguageCode(String languageCode) async {
    // No-op — language is fixed to English.
  }
}

final localeStoreProvider = Provider<LocaleStore>((ref) {
  return const HiveLocaleStore();
});

/// Provides the current app locale — always `Locale('en')`.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier(store: ref.watch(localeStoreProvider));
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier({required LocaleStore store})
    : _store = store,
      super(const Locale('en'));

  // ignore: unused_field
  final LocaleStore _store;

  /// No-op — the app is English-only. Kept for API compatibility.
  Future<void> setLocale(String languageCode) async {
    // Always English.
    state = const Locale('en');
  }
}
