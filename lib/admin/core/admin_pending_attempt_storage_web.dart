import 'package:web/web.dart' as web;
import 'admin_pending_attempt_storage.dart';

class _SessionStorage implements AdminPendingAttemptStorage {
  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);
  @override
  void write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);
  @override
  void remove(String key) => web.window.sessionStorage.removeItem(key);
}

AdminPendingAttemptStorage createAdminPendingAttemptStorage() =>
    _SessionStorage();
