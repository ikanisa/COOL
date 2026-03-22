import 'dart:io';

import 'package:cool_app/core/theme/theme_preference.dart';
import 'package:cool_app/core/theme/theme_preference_provider.dart';
import 'package:cool_app/core/theme/theme_preference_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../helpers/test_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('appThemePreferenceFromStorage', () {
    test('defaults unknown values to dark', () {
      expect(
        appThemePreferenceFromStorage('unexpected'),
        AppThemePreference.dark,
      );
      expect(appThemePreferenceFromStorage(null), AppThemePreference.dark);
    });

    test('parses light and dark values', () {
      expect(appThemePreferenceFromStorage('light'), AppThemePreference.light);
      expect(appThemePreferenceFromStorage('dark'), AppThemePreference.dark);
    });
  });

  group('HiveThemePreferenceStore', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('cool_theme_pref');
      Hive.init(hiveDir.path);
    });

    tearDown(() async {
      if (Hive.isBoxOpen('theme_preferences')) {
        await Hive.box<String>('theme_preferences').clear();
        await Hive.box<String>('theme_preferences').close();
      }
      await Hive.deleteBoxFromDisk('theme_preferences');
      await hiveDir.delete(recursive: true);
    });

    test('defaults to dark when unset', () async {
      final store = HiveThemePreferenceStore(openBox: Hive.openBox<String>);

      final result = await store.read();
      expect(result.preference, AppThemePreference.dark);
      expect(result.updatedAt, isNull);
    });

    test('persists and restores theme preference', () async {
      final store = HiveThemePreferenceStore(openBox: Hive.openBox<String>);

      await store.write(AppThemePreference.dark);

      final result = await store.read();
      expect(result.preference, AppThemePreference.dark);
      expect(result.updatedAt, isA<DateTime>());
    });
  });

  group('ThemePreferenceNotifier', () {
    test('loads from store when not bootstrapped', () async {
      final container = createTestContainer(
        overrides: [
          themePreferenceStoreProvider.overrideWithValue(
            _FakeThemePreferenceStore(AppThemePreference.dark),
          ),
        ],
      );

      expect(
        container.read(themePreferenceProvider),
        AppThemePreference.dark,
      );

      await pumpEventQueue();

      expect(container.read(themePreferenceProvider), AppThemePreference.dark);
    });

    test('uses bootstrap value and persists updates', () async {
      final store = _FakeThemePreferenceStore(AppThemePreference.dark);
      final container = createTestContainer(
        overrides: [
          themePreferenceStoreProvider.overrideWithValue(store),
          initialThemePreferenceProvider.overrideWithValue(
            (preference: AppThemePreference.light, updatedAt: null),
          ),
        ],
      );

      expect(container.read(themePreferenceProvider), AppThemePreference.light);

      await container
          .read(themePreferenceProvider.notifier)
          .setPreference(AppThemePreference.dark);

      expect(container.read(themePreferenceProvider), AppThemePreference.dark);
      expect(store.writes, <AppThemePreference>[AppThemePreference.dark]);
    });
  });
}

class _FakeThemePreferenceStore implements ThemePreferenceStore {
  _FakeThemePreferenceStore(this.value);

  AppThemePreference value;
  final List<AppThemePreference> writes = <AppThemePreference>[];

  @override
  Future<({AppThemePreference preference, DateTime? updatedAt})> read() async {
    return (preference: value, updatedAt: null);
  }

  @override
  Future<void> write(AppThemePreference preference, {DateTime? updatedAt}) async {
    writes.add(preference);
    value = preference;
  }
}
