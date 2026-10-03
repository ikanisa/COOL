import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final collectThemeModeProvider =
    StateNotifierProvider<CollectThemeModeController, ThemeMode>(
      (ref) => CollectThemeModeController(),
    );

class CollectThemeModeController extends StateNotifier<ThemeMode> {
  CollectThemeModeController({
    SharedPreferencesAsync? preferences,
    ThemeMode initialMode = ThemeMode.dark,
    bool loadPersistedMode = true,
  }) : this._(preferences, initialMode, loadPersistedMode);

  CollectThemeModeController._(
    this._preferences,
    ThemeMode initialMode,
    bool loadPersistedMode,
  ) : super(initialMode) {
    if (loadPersistedMode) unawaited(_load());
  }

  static const storageKey = 'collect_theme_mode';
  SharedPreferencesAsync? _preferences;

  Future<void> setDarkMode(bool enabled) =>
      setMode(enabled ? ThemeMode.dark : ThemeMode.light);

  Future<void> toggle() => setDarkMode(state != ThemeMode.dark);

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      await _preferencesClient?.setString(storageKey, mode.name);
    } catch (_) {
      // Theme choice remains active in-memory if local preferences are unavailable.
    }
  }

  Future<void> _load() async {
    try {
      final preferences = _preferencesClient;
      if (preferences == null) return;
      final stored = await preferences.getString(storageKey);
      final mode = _decode(stored);
      if (mounted) state = mode;
    } catch (_) {
      // Dark mode keeps the first launch calm when persistence is unavailable.
    }
  }

  SharedPreferencesAsync? get _preferencesClient {
    final existing = _preferences;
    if (existing != null) return existing;
    try {
      final created = SharedPreferencesAsync();
      _preferences = created;
      return created;
    } catch (_) {
      return null;
    }
  }

  static ThemeMode _decode(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }
}
