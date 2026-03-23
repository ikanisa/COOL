import 'package:flutter/material.dart';

enum AppThemePreference { system, light, dark }

AppThemePreference appThemePreferenceFromStorage(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'system' => AppThemePreference.system,
    'light' => AppThemePreference.light,
    'dark' => AppThemePreference.dark,
    _ => AppThemePreference.dark,
  };
}

extension AppThemePreferenceThemeMode on AppThemePreference {
  ThemeMode get themeMode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  String get storageValue => name;
}
