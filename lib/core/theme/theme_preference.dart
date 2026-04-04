import 'package:flutter/material.dart';

/// Dark-only theme preference. The `system` value is kept for future
/// flexibility but resolves to dark in the current Mobi × Partner system.
enum AppThemePreference { system, dark }

AppThemePreference appThemePreferenceFromStorage(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'system' => AppThemePreference.system,
    // 'light' is legacy — map to dark for backward compat.
    'light' => AppThemePreference.dark,
    'dark' => AppThemePreference.dark,
    _ => AppThemePreference.dark,
  };
}

extension AppThemePreferenceThemeMode on AppThemePreference {
  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.dark,
    AppThemePreference.dark => ThemeMode.dark,
  };

  String get storageValue => name;
}
