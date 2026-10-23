import 'admin_sender_retention_models.dart';
import 'admin_sender_retention_checkpoint_stub.dart'
    if (dart.library.js_interop) 'admin_sender_retention_checkpoint_web.dart'
    as platform;

abstract interface class AdminRetentionStore {
  Future<AdminRetentionIntent?> read(String actor, String session);
  Future<void> write(AdminRetentionIntent intent);
  Future<void> clear(AdminRetentionIntent intent);
}

AdminRetentionStore? browserAdminRetentionStore() => platform.createStore();
