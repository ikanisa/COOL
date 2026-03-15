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
    StateNotifierProvider<ThemePreferenceNotifier, AppThemePreference>((ref) {
      return ThemePreferenceNotifier(
        ref: ref,
        store: ref.watch(themePreferenceStoreProvider),
        initialPreference: ref.watch(initialThemePreferenceProvider),
      );
    });

class ThemePreferenceNotifier extends StateNotifier<AppThemePreference> {
  ThemePreferenceNotifier({
    required Ref ref,
    required ThemePreferenceStore store,
    ({AppThemePreference preference, DateTime? updatedAt})? initialPreference,
  }) : _ref = ref,
       _store = store,
       _bootstrapped = initialPreference != null,
       _updatedAt = initialPreference?.updatedAt,
       super(initialPreference?.preference ?? AppThemePreference.system) {
    if (!_bootstrapped) {
      Future<void>.microtask(load);
    }

    _ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.user != null && previous?.user?.id != next.user!.id) {
        _syncWithRemote(next.user!);
      }
    });
  }

  final Ref _ref;
  final ThemePreferenceStore _store;
  final bool _bootstrapped;
  DateTime? _updatedAt;
  bool _isDisposed = false;
  bool _hasLoaded = false;

  Future<void> load() async {
    if (_bootstrapped || _hasLoaded) {
      return;
    }
    _hasLoaded = true;
    final result = await _store.read();
    if (_isDisposed) {
      return;
    }
    _updatedAt = result.updatedAt;
    state = result.preference;

    final user = _ref.read(authProvider).user;
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

    final user = _ref.read(authProvider).user;
    if (user != null) {
      await _ref.read(authProvider.notifier).updateProfile(
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
      await _ref.read(authProvider.notifier).updateProfile(
        user.copyWith(
          themePreference: state.storageValue,
          themePreferenceUpdatedAt: _updatedAt,
        ),
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
