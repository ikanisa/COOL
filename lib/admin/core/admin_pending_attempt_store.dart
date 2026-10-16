import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_account_api.dart';
import 'admin_pending_attempt_storage.dart';
import 'admin_pending_attempt_storage_stub.dart'
    if (dart.library.js_interop) 'admin_pending_attempt_storage_web.dart'
    as platform;
import 'cloudflare_admin_session.dart';

export 'admin_pending_attempt_storage.dart';

const _storageKey = 'collect.admin.pending-attempts.v1';
// Keep unresolved original keys through their live session. A shorter TTL can
// turn a committed lost response into a new-key duplicate after reload.
const _maximumAge = Duration(hours: 8);
const _maximumEntries = 20;
const _maximumBytes = 65536;
const _maximumIntentBytes = 16384;
final _identifier = RegExp(r'^[A-Za-z0-9._:-]{1,200}$');
final _family = RegExp(r'^[a-z][a-z0-9_.-]{1,63}$');
final _permission = RegExp(r'^[a-z][a-z0-9_.]{2,80}$');
final _secretKey = RegExp(
  r'password|passwd|secret|token|cookie|authorization|credential|session',
  caseSensitive: false,
);

/// Map paths use dots; maps in lists use `[]`, for example `entries[]`.
/// Domain factories must validate restored values before constructing attempts.
class AdminPendingAttemptSchema {
  const AdminPendingAttemptSchema({
    required this.fields,
    this.nestedFields = const {},
  });
  final Set<String> fields;
  final Map<String, Set<String>> nestedFields;

  Map<String, dynamic> canonical(Map<String, dynamic> intent) {
    final value = _canonical(intent, this, '', 0) as Map<String, dynamic>;
    if (utf8.encode(jsonEncode(value)).length > _maximumIntentBytes) {
      throw const FormatException('The confirmation intent is too large.');
    }
    return value;
  }
}

dynamic _canonical(
  dynamic value,
  AdminPendingAttemptSchema? schema,
  String path,
  int depth,
) {
  if (depth > 8) {
    throw const FormatException(
      'The confirmation intent is too deeply nested.',
    );
  }
  if (value == null || value is bool) return value;
  if (value is int && value.abs() <= 9007199254740991) return value;
  if (value is String && value.length <= 4000) return value;
  if (value is List && value.length <= 100) {
    return List<dynamic>.unmodifiable([
      for (final item in value) _canonical(item, schema, '$path[]', depth + 1),
    ]);
  }
  if (value is Map && value.keys.every((key) => key is String)) {
    final allowed = path.isEmpty ? schema?.fields : schema?.nestedFields[path];
    final keys = value.keys.cast<String>().toList()..sort();
    if (keys.length > 100 ||
        keys.any(
          (key) =>
              key.isEmpty ||
              key.length > 80 ||
              _secretKey.hasMatch(key) ||
              schema != null && allowed?.contains(key) != true,
        )) {
      throw const FormatException(
        'This confirmation intent cannot be retained.',
      );
    }
    return Map<String, dynamic>.unmodifiable({
      for (final key in keys)
        key: _canonical(
          value[key],
          schema,
          path.isEmpty ? key : '$path.$key',
          depth + 1,
        ),
    });
  }
  throw const FormatException('This confirmation intent cannot be retained.');
}

class AdminPendingAttemptCheckpoint {
  const AdminPendingAttemptCheckpoint._({
    required this.requestKey,
    required this.permission,
    required this.family,
    required this.resourceId,
    required this.intent,
    required this.createdAt,
    required this.expiresAt,
    required this.restored,
  });
  final String requestKey, permission, family, resourceId;
  final Map<String, dynamic> intent;
  final DateTime createdAt, expiresAt;
  final bool restored;

  Map<String, dynamic> get _json => {
    'family': family,
    'resource_id': resourceId,
    'request_key': requestKey,
    'permission': permission,
    'intent': intent,
    'created_at': createdAt.millisecondsSinceEpoch,
    'expires_at': expiresAt.millisecondsSinceEpoch,
  };
}

final adminPendingAttemptStorageProvider = Provider<AdminPendingAttemptStorage>(
  (_) => platform.createAdminPendingAttemptStorage(),
);

final adminPendingAttemptStoreProvider =
    ChangeNotifierProvider<AdminPendingAttemptStore>((ref) {
      final store = AdminPendingAttemptStore(
        storage: ref.watch(adminPendingAttemptStorageProvider),
      );
      void bind(AsyncValue<CloudflareAdminUser?> state) {
        // Cold cookie restoration must finish before a definitive logout clears
        // the previous same-tab checkpoint.
        if (state.isLoading || state.hasError) return;
        store.bind(state.asData?.value);
      }

      ref.listen(cloudflareAdminSessionProvider, (_, next) => bind(next));
      bind(ref.read(cloudflareAdminSessionProvider));
      return store;
    });

/// Per-tab, bounded recovery references. Restoration never performs transport.
class AdminPendingAttemptStore extends ChangeNotifier {
  AdminPendingAttemptStore({required this.storage, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AdminPendingAttemptStorage storage;
  final DateTime Function() _now;
  final _entries = <String, AdminPendingAttemptCheckpoint>{};
  CloudflareAdminUser? _user;
  String? _authority;
  Timer? _expiry;
  bool _storageAvailable = true;
  String _storageMessage = '';
  bool get storageAvailable => _storageAvailable;
  String get storageMessage => _storageMessage;

  static String _binding(CloudflareAdminUser user) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'actor': user.authorityKey.id,
            'session': user.authorityKey.sessionId,
            'email': user.authorityKey.email,
            'role': user.authorityKey.role.name,
            'permissions': user.authorityKey.permissions,
          }),
        ),
      )
      .toString();
  String _entryKey(String family, String resourceId) =>
      jsonEncode([family, resourceId]);

  void bind(CloudflareAdminUser? user) {
    final authority = user == null ? null : _binding(user);
    if (_authority != null && authority != _authority) {
      _entries.clear();
      _remove();
    }
    final firstBinding = _authority == null && authority != null;
    _user = user;
    _authority = authority;
    if (user == null || !user.expiresAt.isAfter(_now())) {
      _entries.clear();
      _remove();
      _expiry?.cancel();
    } else {
      if (firstBinding) _load();
      _prune();
      _schedule();
    }
  }

  CloudflareAdminUser _authorized(String permission) {
    final user = _user;
    if (user == null ||
        !user.expiresAt.isAfter(_now()) ||
        !user.permissions.contains(permission)) {
      _prune();
      throw const AdminAccountException(
        'Reopen the record with the original authorized session.',
      );
    }
    return user;
  }

  AdminPendingAttemptCheckpoint retain({
    required String family,
    required String resourceId,
    required String requestKey,
    required String permission,
    required Map<String, dynamic> intent,
    required AdminPendingAttemptSchema schema,
  }) {
    final user = _authorized(permission);
    if (!_family.hasMatch(family) ||
        !_identifier.hasMatch(resourceId) ||
        !_identifier.hasMatch(requestKey) ||
        requestKey.length < 8 ||
        !_permission.hasMatch(permission)) {
      throw const FormatException('Invalid pending request reference.');
    }
    _prune();
    final canonical = schema.canonical(intent),
        key = _entryKey(family, resourceId);
    final previous = _entries[key];
    if (previous != null &&
        (previous.requestKey != requestKey ||
            previous.permission != permission ||
            jsonEncode(previous.intent) != jsonEncode(canonical))) {
      throw const AdminAccountException(
        'Resolve the original request before starting a different confirmation.',
      );
    }
    final created = previous?.createdAt ?? _now().toUtc();
    final maximum = created.add(_maximumAge);
    final expires = user.expiresAt.isBefore(maximum) ? user.expiresAt : maximum;
    final checkpoint = AdminPendingAttemptCheckpoint._(
      requestKey: requestKey,
      permission: permission,
      family: family,
      resourceId: resourceId,
      intent: canonical,
      createdAt: created,
      expiresAt: expires,
      restored: previous?.restored ?? false,
    );
    final next = {..._entries, key: checkpoint};
    if (next.length > _maximumEntries ||
        utf8.encode(_encode(next)).length > _maximumBytes) {
      throw const AdminAccountException(
        'Resolve the existing pending requests before recording another one.',
      );
    }
    _entries[key] = checkpoint;
    _persist();
    _schedule();
    notifyListeners();
    return checkpoint;
  }

  AdminPendingAttemptCheckpoint? restore({
    required String family,
    required String resourceId,
    required AdminPendingAttemptSchema schema,
  }) {
    _prune();
    final key = _entryKey(family, resourceId), entry = _entries[key];
    if (entry == null) return null;
    _authorized(entry.permission);
    try {
      final intent = schema.canonical(entry.intent);
      return AdminPendingAttemptCheckpoint._(
        requestKey: entry.requestKey,
        permission: entry.permission,
        family: entry.family,
        resourceId: entry.resourceId,
        intent: intent,
        createdAt: entry.createdAt,
        expiresAt: entry.expiresAt,
        restored: true,
      );
    } on FormatException {
      clear(family: family, resourceId: resourceId);
      _storageAvailable = false;
      _storageMessage =
          'Recovery data could not be verified. Check the server record before starting a new request.';
      return null;
    }
  }

  /// Enumerate only a bounded, authorized family for record-scoped recovery.
  /// Consumers must validate compound resource identities before displaying them.
  List<AdminPendingAttemptCheckpoint> restoreFamily({
    required String family,
    required String permission,
    required AdminPendingAttemptSchema schema,
  }) {
    _authorized(permission);
    _prune();
    if (!_family.hasMatch(family) || !_permission.hasMatch(permission)) {
      throw const FormatException('Invalid pending request scope.');
    }
    final resources = [
      for (final entry in _entries.values)
        if (entry.family == family && entry.permission == permission)
          entry.resourceId,
    ];
    final restored = <AdminPendingAttemptCheckpoint>[];
    for (final resource in resources) {
      final checkpoint = restore(
        family: family,
        resourceId: resource,
        schema: schema,
      );
      if (checkpoint != null) {
        restored.add(checkpoint);
      }
    }
    return List<AdminPendingAttemptCheckpoint>.unmodifiable(restored);
  }

  void clear({required String family, required String resourceId}) {
    _entries.remove(_entryKey(family, resourceId));
    _persist();
    _schedule();
    notifyListeners();
  }

  String _encode(Map<String, AdminPendingAttemptCheckpoint> entries) =>
      jsonEncode({
        'version': 1,
        'authority': _authority,
        'entries': entries.values.map((entry) => entry._json).toList(),
      });

  void _persist() {
    try {
      if (_entries.isEmpty) {
        storage.remove(_storageKey);
      } else {
        final encoded = _encode(_entries);
        storage.write(_storageKey, encoded);
        if (storage.read(_storageKey) != encoded) throw StateError('read-back');
      }
    } catch (_) {
      _unavailable();
    }
  }

  void _remove() {
    try {
      storage.remove(_storageKey);
    } catch (_) {
      _unavailable();
    }
  }

  void _unavailable() {
    _storageAvailable = false;
    _storageMessage =
        'Per-tab recovery storage is unavailable. Keep the original request reference; a hard reload will lose local recovery. Check its server receipt before another submission.';
  }

  void _load() {
    try {
      final raw = storage.read(_storageKey);
      if (raw == null) return;
      if (utf8.encode(raw).length > _maximumBytes) {
        throw const FormatException();
      }
      final data = jsonDecode(raw);
      if (data is Map &&
          data['authority'] is String &&
          data['authority'] != _authority) {
        _remove();
        return;
      }
      if (data is! Map ||
          data.length != 3 ||
          data['version'] != 1 ||
          data['authority'] != _authority ||
          data['entries'] is! List ||
          (data['entries'] as List).length > _maximumEntries) {
        throw const FormatException();
      }
      final loaded = <String, AdminPendingAttemptCheckpoint>{};
      for (final value in data['entries'] as List) {
        if (value is! Map ||
            value.length != 7 ||
            value['family'] is! String ||
            !_family.hasMatch(value['family'] as String) ||
            value['resource_id'] is! String ||
            !_identifier.hasMatch(value['resource_id'] as String) ||
            value['request_key'] is! String ||
            !_identifier.hasMatch(value['request_key'] as String) ||
            (value['request_key'] as String).length < 8 ||
            value['permission'] is! String ||
            !_permission.hasMatch(value['permission'] as String) ||
            value['intent'] is! Map ||
            value['created_at'] is! int ||
            value['expires_at'] is! int ||
            (value['created_at'] as int) < 1 ||
            (value['expires_at'] as int) > 8640000000000000) {
          throw const FormatException();
        }
        final created = DateTime.fromMillisecondsSinceEpoch(
          value['created_at'] as int,
          isUtc: true,
        );
        final storedExpiry = DateTime.fromMillisecondsSinceEpoch(
          value['expires_at'] as int,
          isUtc: true,
        );
        if (created.isAfter(_now()) ||
            !storedExpiry.isAfter(created) ||
            storedExpiry.difference(created) > _maximumAge) {
          throw const FormatException();
        }
        final ageLimit = created.add(_maximumAge);
        final expires = _user!.expiresAt.isBefore(ageLimit)
            ? _user!.expiresAt
            : ageLimit;
        final intent =
            _canonical(value['intent'], null, '', 0) as Map<String, dynamic>;
        if (utf8.encode(jsonEncode(intent)).length > _maximumIntentBytes) {
          throw const FormatException();
        }
        if (!expires.isAfter(_now()) ||
            !_user!.permissions.contains(value['permission'])) {
          continue;
        }
        final key = _entryKey(
          value['family'] as String,
          value['resource_id'] as String,
        );
        if (loaded.containsKey(key)) throw const FormatException();
        loaded[key] = AdminPendingAttemptCheckpoint._(
          requestKey: value['request_key'] as String,
          permission: value['permission'] as String,
          family: value['family'] as String,
          resourceId: value['resource_id'] as String,
          intent: intent,
          createdAt: created,
          expiresAt: expires,
          restored: true,
        );
      }
      _entries.addAll(loaded);
      _persist();
    } on FormatException {
      _entries.clear();
      _remove();
      _storageAvailable = false;
      _storageMessage =
          'Recovery data could not be verified for this session. Check the server record before starting a new request.';
    } catch (_) {
      _entries.clear();
      _unavailable();
    }
  }

  void _prune() {
    final now = _now();
    final previous = _entries.length;
    _entries.removeWhere(
      (_, entry) =>
          !entry.createdAt.add(_maximumAge).isAfter(now) ||
          _user == null ||
          !_user!.expiresAt.isAfter(now) ||
          !_user!.permissions.contains(entry.permission),
    );
    var clamped = false;
    final user = _user;
    if (user != null) {
      for (final item in _entries.entries.toList()) {
        final entry = item.value;
        final ageLimit = entry.createdAt.add(_maximumAge);
        final expires = user.expiresAt.isBefore(ageLimit)
            ? user.expiresAt
            : ageLimit;
        if (entry.expiresAt != expires) {
          clamped = true;
          _entries[item.key] = AdminPendingAttemptCheckpoint._(
            requestKey: entry.requestKey,
            permission: entry.permission,
            family: entry.family,
            resourceId: entry.resourceId,
            intent: entry.intent,
            createdAt: entry.createdAt,
            expiresAt: expires,
            restored: entry.restored,
          );
        }
      }
    }
    if (_entries.length != previous || clamped) _persist();
  }

  void _schedule() {
    _expiry?.cancel();
    if (_entries.isEmpty) return;
    final expires = _entries.values
        .map((entry) => entry.expiresAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    _expiry = Timer(expires.difference(_now()), () {
      _prune();
      _schedule();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    // Disposal includes browser reload. Only logout/authority/expiry/success
    // clears durable references; never clear them merely because UI unmounts.
    super.dispose();
  }
}
