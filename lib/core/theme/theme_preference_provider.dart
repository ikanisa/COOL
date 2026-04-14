import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/models/user_profile.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../providers/hive_providers.dart';
import 'theme_preference.dart';
import 'theme_preference_store.dart';

final initialThemePreferenceProvider =
    Provider<({AppThemePreference preference, DateTime? updatedAt})?>((ref) {
      return null;
    });

final themePreferenceStoreProvider = Provider<ThemePreferenceStore>((ref) {
  return HiveThemePreferenceStore(openBox: ref.read(hiveStringBoxProvider));
});

final themePreferenceProvider =
    NotifierProvider<ThemePreferenceNotifier, AppThemePreference>(
      ThemePreferenceNotifier.new,
    );

class ThemePreferenceNotifier extends Notifier<AppThemePreference> {
  late final ThemePreferenceStore _store;
  late final bool _bootstrapped;
  DateTime? _updatedAt;
  bool _hasLoaded = false;

  @override
  AppThemePreference build() {
    _store = ref.watch(themePreferenceStoreProvider);
    final initial = ref.watch(initialThemePreferenceProvider);
    _bootstrapped = initial != null;
    _updatedAt = initial?.updatedAt;

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.user != null && previous?.user?.id != next.user!.id) {
        _syncWithRemote(next.user!);
      }
    });

    if (!_bootstrapped) {
      Future<void>.microtask(load);
    }

    return initial?.preference ?? AppThemePreference.dark;
  }

  Future<void> load() async {
    if (_bootstrapped || _hasLoaded) {
      return;
    }
    _hasLoaded = true;
    final result = await _store.read();
    _updatedAt = result.updatedAt;
    state = result.preference;

    final user = ref.read(authProvider).user;
    if (user != null) {
      await _syncWithRemote(user);
    }
  }

  Future<void> setPreference(AppThemePreference preference) async {
    if (state == preference) {
      return;
    }
    final now = DateTime.now();
    state = preference;
    _updatedAt = now;
    await _store.write(preference, updatedAt: now);

    final user = ref.read(authProvider).user;
    if (user != null) {
      await ref
          .read(authProvider.notifier)
          .updateProfile(
            user.copyWith(
              themePreference: preference.storageValue,
              themePreferenceUpdatedAt: now,
            ),
          );
    }
  }

  Future<void> _syncWithRemote(UserProfile user) async {
    final remotePreference = appThemePreferenceFromStorage(
      user.themePreference,
    );
    final remoteUpdatedAt = user.themePreferenceUpdatedAt;

    // Last-write-wins sync logic.
    if (remoteUpdatedAt != null &&
        (_updatedAt == null || remoteUpdatedAt.isAfter(_updatedAt!))) {
      // Remote is newer.
      if (state != remotePreference) {
        state = remotePreference;
        _updatedAt = remoteUpdatedAt;
        await _store.write(remotePreference, updatedAt: remoteUpdatedAt);
      }
    } else if (_updatedAt != null &&
        (remoteUpdatedAt == null || _updatedAt!.isAfter(remoteUpdatedAt))) {
      // Local is newer.
      await ref
          .read(authProvider.notifier)
          .updateProfile(
            user.copyWith(
              themePreference: state.storageValue,
              themePreferenceUpdatedAt: _updatedAt,
            ),
          );
    }
  }
}
