import 'admin_governed_settings_models.dart';
import 'admin_governed_settings_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_governed_settings_checkpoint_web.dart'
    as platform;

String adminSettingsOwnerDigest(String userId) => settingsHash(
  'collect.settings.v2:lhbowpbcpwoiparwnwgt:${settingsUuid(userId)}',
);

class AdminSettingsPendingOriginal implements Exception {
  const AdminSettingsPendingOriginal();
}

abstract interface class AdminSettingsCheckpointStore {
  List<String> read(String ownerDigest);
  Future<void> write(AdminSettingsBookmark bookmark);
  Future<void> resolve(AdminSettingsBookmark bookmark, String resolution);
}

AdminSettingsCheckpointStore? browserAdminSettingsCheckpointStore() =>
    platform.createSettingsCheckpointStore();
