import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef PendingIntentClock = DateTime Function();

abstract interface class PendingSharedGroupIntentPreferences {
  Future<String?> getString(String key);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesPendingSharedGroupIntentPreferences
    implements PendingSharedGroupIntentPreferences {
  SharedPreferencesPendingSharedGroupIntentPreferences([this._preferences]);

  SharedPreferencesAsync? _preferences;

  SharedPreferencesAsync get _client =>
      _preferences ??= SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) => _client.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _client.setString(key, value);

  @override
  Future<void> remove(String key) => _client.remove(key);
}

class PendingSharedGroupIntentStore {
  PendingSharedGroupIntentStore({
    PendingSharedGroupIntentPreferences? preferences,
    PendingIntentClock? clock,
    this.preferencesKey = defaultPreferencesKey,
    this.maxAge = const Duration(hours: 24),
  }) : _preferences =
           preferences ??
           SharedPreferencesPendingSharedGroupIntentPreferences(),
       _clock = clock ?? DateTime.now;

  static const defaultPreferencesKey = 'collect.pending_shared_group_intent.v1';
  static const schemaVersion = 1;
  static const maxSlugLength = 240;

  final PendingSharedGroupIntentPreferences _preferences;
  final PendingIntentClock _clock;
  final String preferencesKey;
  final Duration maxAge;

  Future<String?> readSlug() async {
    final raw = await _preferences.getString(preferencesKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != schemaVersion ||
          decoded['slug'] is! String ||
          decoded['captured_at'] is! String) {
        await clear();
        return null;
      }

      final slug = normalizePendingSharedGroupSlug(decoded['slug'] as String);
      final capturedAt = DateTime.tryParse(decoded['captured_at'] as String);
      if (slug == null || capturedAt == null) {
        await clear();
        return null;
      }

      final now = _clock().toUtc();
      final age = now.difference(capturedAt.toUtc());
      if (age.isNegative || age > maxAge) {
        await clear();
        return null;
      }
      return slug;
    } on FormatException {
      await clear();
      return null;
    }
  }

  Future<String> saveSlug(String rawSlug) async {
    final slug = normalizePendingSharedGroupSlug(rawSlug);
    if (slug == null) {
      throw const FormatException('Group link is invalid');
    }
    await _preferences.setString(
      preferencesKey,
      jsonEncode({
        'version': schemaVersion,
        'slug': slug,
        'captured_at': _clock().toUtc().toIso8601String(),
      }),
    );
    return slug;
  }

  Future<void> clear() => _preferences.remove(preferencesKey);
}

String? normalizePendingSharedGroupSlug(String rawSlug) {
  final slug = rawSlug.trim().toLowerCase();
  if (slug.isEmpty ||
      slug.length > PendingSharedGroupIntentStore.maxSlugLength) {
    return null;
  }
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
    return null;
  }
  return slug;
}

String? pendingSharedGroupSlugFromAppLink(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.toLowerCase() != 'collect.ikanisa.com' ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments.first.toLowerCase() != 'c') {
    return null;
  }
  return normalizePendingSharedGroupSlug(uri.pathSegments[1]);
}
