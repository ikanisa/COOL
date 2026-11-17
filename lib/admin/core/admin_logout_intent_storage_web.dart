import 'package:web/web.dart' as web;

import 'admin_logout_intent_storage.dart';

const _prefix = 'collect.admin.logout-intent.v1.';
final _fingerprint = RegExp(r'^[0-9a-f]{64}$');

class _BrowserLogoutIntentStorage implements AdminLogoutIntentStorage {
  @override
  Set<String> readPending() {
    final storage = web.window.localStorage;
    final pending = <String>{};
    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i);
      if (key == null || !key.startsWith(_prefix)) continue;
      final fingerprint = key.substring(_prefix.length);
      if (!_fingerprint.hasMatch(fingerprint) || storage.getItem(key) != '1') {
        throw const FormatException('Invalid pending sign-out marker.');
      }
      pending.add(fingerprint);
    }
    return Set.unmodifiable(pending);
  }

  @override
  void add(String sessionFingerprint) {
    if (!_fingerprint.hasMatch(sessionFingerprint)) {
      throw const FormatException('Invalid sign-out session.');
    }
    final key = '$_prefix$sessionFingerprint';
    web.window.localStorage.setItem(key, '1');
    if (web.window.localStorage.getItem(key) != '1') {
      throw StateError('Sign-out intent could not be retained.');
    }
  }

  @override
  void remove(String sessionFingerprint) {
    if (!_fingerprint.hasMatch(sessionFingerprint)) {
      throw const FormatException('Invalid sign-out session.');
    }
    web.window.localStorage.removeItem('$_prefix$sessionFingerprint');
  }
}

AdminLogoutIntentStorage createAdminLogoutIntentStorage() =>
    _BrowserLogoutIntentStorage();
