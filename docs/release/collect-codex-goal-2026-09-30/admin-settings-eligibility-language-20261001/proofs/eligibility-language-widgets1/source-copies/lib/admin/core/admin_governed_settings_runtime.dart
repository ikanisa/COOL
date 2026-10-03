part of 'admin_runtime.dart';

class AdminSettingsDenied implements Exception {
  const AdminSettingsDenied();
}

typedef AdminSettingsCatalogQuery = ({String family, String? after});
typedef AdminSettingsControlQuery = ({String family, String identity});
typedef AdminSettingsHistoryQuery = ({
  String family,
  String identity,
  String? beforeAt,
  String? beforeId,
});
final adminSettingsCheckpointStoreProvider =
    Provider<AdminSettingsCheckpointStore?>(
      (ref) => browserAdminSettingsCheckpointStore(),
    );
Future<T> _settingsRead<T>(
  Ref ref,
  AdminSettingsFamily family,
  bool audit,
  Future<T> Function(AdminGovernedSettingsApi) read,
) async {
  final scope = ref.watch(adminAuthSessionScopeProvider);
  final version = ref.watch(_adminIdentityRevisionProvider);
  final repository = ref.watch(adminRepositoryProvider);
  var current = true;
  ref.onDispose(() => current = false);
  final identity = await ref.watch(adminIdentityProvider.future);
  bool owned() =>
      current &&
      ref.read(adminAuthSessionScopeProvider) == scope &&
      ref.read(_adminIdentityRevisionProvider) == version;
  if (!owned()) throw const AdminSessionChanged();
  if (scope == null ||
      identity?.userId != scope.key.userId ||
      !(audit ? family.canAudit(identity) : family.canRead(identity))) {
    throw const AdminSettingsDenied();
  }
  try {
    final result = await read(repository.governedSettings);
    if (!owned()) throw const AdminSessionChanged();
    return result;
  } catch (_) {
    if (!owned()) throw const AdminSessionChanged();
    rethrow;
  }
}

final adminSettingsCatalogProvider = FutureProvider.autoDispose
    .family<AdminSettingsCatalog, AdminSettingsCatalogQuery>((ref, q) {
      final family = AdminSettingsFamily.parse(q.family);
      return _settingsRead(
        ref,
        family,
        false,
        (api) => api.catalog(
          family,
          after: q.after == null ? null : family.identity(jsonDecode(q.after!)),
        ),
      );
    });
final adminSettingsControlProvider = FutureProvider.autoDispose
    .family<AdminSettingsControl, AdminSettingsControlQuery>((ref, q) {
      final family = AdminSettingsFamily.parse(q.family);
      return _settingsRead(
        ref,
        family,
        false,
        (api) => api.control(family, family.identity(jsonDecode(q.identity))),
      );
    });
typedef AdminSettingsEligibilityQuery = ({
  String family,
  String identity,
  int revision,
  String patch,
});
final adminSettingsEligibilityProvider = FutureProvider.autoDispose
    .family<AdminSettingsEligibility, AdminSettingsEligibilityQuery>((ref, q) {
      final family = AdminSettingsFamily.parse(q.family);
      return _settingsRead(ref, family, false, (api) async {
        final control = await api.control(
          family,
          family.identity(jsonDecode(q.identity)),
        );
        if (control.revision != q.revision)
          governedSettingsInvalid('current eligibility revision');
        return api.eligibility(control, q.patch);
      });
    });
final adminSettingsHistoryProvider = FutureProvider.autoDispose
    .family<AdminSettingsHistory, AdminSettingsHistoryQuery>((ref, q) {
      final family = AdminSettingsFamily.parse(q.family);
      if ((q.beforeAt == null) != (q.beforeId == null)) {
        governedSettingsInvalid('history cursor');
      }
      return _settingsRead(
        ref,
        family,
        true,
        (api) => api.history(
          family,
          family.identity(jsonDecode(q.identity)),
          before: q.beforeAt == null
              ? null
              : AdminSettingsHistoryCursor(
                  settingsInstant(q.beforeAt),
                  settingsUuid(q.beforeId),
                ),
        ),
      );
    });
final adminSettingsControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminSettingsActionController,
      AdminSettingsActionState
    >((ref) {
      final scope = ref.watch(adminAuthSessionScopeProvider),
          identity = _adminResolvedIdentity(ref.watch(adminIdentityProvider));
      final version = ref.watch(_adminIdentityRevisionProvider),
          repository = ref.watch(adminRepositoryProvider);
      final store = ref.watch(adminSettingsCheckpointStoreProvider),
          clock = ref.watch(adminClockProvider);
      var current = true;
      ref.onDispose(() => current = false);
      final enabled =
          scope != null &&
          identity?.userId == scope.key.userId &&
          identity!.roles.contains('platform_owner');
      return AdminSettingsActionController(
        ownerDigest: enabled ? adminSettingsOwnerDigest(scope.key.userId) : '',
        store: enabled ? store : null,
        api: repository.governedSettings,
        now: clock,
        scope: () => ref.read(adminAuthSessionScopeProvider),
        canManage: (family) => family.canManage(
          _adminResolvedIdentity(ref.read(adminIdentityProvider)),
        ),
        isCurrent: () =>
            enabled &&
            current &&
            ref.read(adminAuthSessionScopeProvider) == scope &&
            ref.read(_adminIdentityRevisionProvider) == version,
      );
    });
