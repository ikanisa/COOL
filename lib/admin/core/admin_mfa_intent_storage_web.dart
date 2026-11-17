import 'dart:convert';

import 'package:web/web.dart' as web;

import 'admin_mfa_intent_storage.dart';

const _key = 'collect.admin.mfa-intent.v1';

class _BrowserMfaIntentStorage implements AdminMfaIntentStorage {
  @override
  AdminMfaRecoveryIntent? read() {
    final value = web.window.sessionStorage.getItem(_key);
    return value == null
        ? null
        : AdminMfaRecoveryIntent.parse(jsonDecode(value));
  }

  @override
  void write(AdminMfaRecoveryIntent intent) {
    final value = jsonEncode(intent.toJson());
    web.window.sessionStorage.setItem(_key, value);
    if (web.window.sessionStorage.getItem(_key) != value) {
      throw StateError('Authenticator recovery could not be retained.');
    }
  }

  @override
  void clear() => web.window.sessionStorage.removeItem(_key);
}

AdminMfaIntentStorage createAdminMfaIntentStorage() =>
    _BrowserMfaIntentStorage();
