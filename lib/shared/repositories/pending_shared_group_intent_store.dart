import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
  static const schemaVersion = 2;
  // Must match join_group_by_share_code's server-side p_group_code bound.
  static const maxSlugLength = 140;

  final PendingSharedGroupIntentPreferences _preferences;
  final PendingIntentClock _clock;
  final String preferencesKey;
  final Duration maxAge;

  Future<PendingSharedGroupIntent?> read() async {
    final raw = await _preferences.getString(preferencesKey);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != schemaVersion ||
          decoded['slug'] is! String ||
          decoded['captured_at'] is! String ||
          decoded['intent_id'] is! String) {
        await clear();
        return null;
      }

      final slug = normalizePendingSharedGroupSlug(decoded['slug'] as String);
      final capturedAt = DateTime.tryParse(decoded['captured_at'] as String);
      final intentId = decoded['intent_id'] as String;
      final owner = decoded['owner_user_id'];
      if (slug == null ||
          capturedAt == null ||
          !_uuidPattern.hasMatch(intentId) ||
          (owner != null &&
              (owner is! String || !_uuidPattern.hasMatch(owner)))) {
        await clear();
        return null;
      }

      final now = _clock().toUtc();
      final age = now.difference(capturedAt.toUtc());
      if (age.isNegative || age > maxAge) {
        await clear();
        return null;
      }
      return PendingSharedGroupIntent(
        slug: slug,
        intentId: intentId.toLowerCase(),
        ownerUserId: (owner as String?)?.toLowerCase(),
        capturedAt: capturedAt.toUtc(),
      );
    } on FormatException {
      await clear();
      return null;
    }
  }

  static const _uuid = Uuid();
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  Future<String?> readSlug() async => (await read())?.slug;

  Future<PendingSharedGroupIntent> save(
    String rawSlug, {
    String? ownerUserId,
  }) async {
    final slug = normalizePendingSharedGroupSlug(rawSlug);
    if (slug == null) {
      throw const FormatException('Group link is invalid');
    }
    final owner = ownerUserId == null
        ? null
        : normalizePendingSharedGroupOwnerUserId(ownerUserId);
    final intent = PendingSharedGroupIntent(
      slug: slug,
      intentId: _uuid.v4(),
      ownerUserId: owner,
      capturedAt: _clock().toUtc(),
    );
    await write(intent);
    return intent;
  }

  Future<String> saveSlug(String rawSlug) async => (await save(rawSlug)).slug;

  Future<void> write(PendingSharedGroupIntent intent) async {
    if (normalizePendingSharedGroupSlug(intent.slug) != intent.slug ||
        !_uuidPattern.hasMatch(intent.intentId)) {
      throw const FormatException('Group invitation is invalid');
    }
    if (intent.ownerUserId != null) {
      if (intent.ownerUserId !=
          normalizePendingSharedGroupOwnerUserId(intent.ownerUserId!)) {
        throw const FormatException('Group invitation account is invalid');
      }
    }
    await _preferences.setString(
      preferencesKey,
      jsonEncode({
        'version': schemaVersion,
        'slug': intent.slug,
        'intent_id': intent.intentId,
        'owner_user_id': intent.ownerUserId,
        'captured_at': intent.capturedAt.toIso8601String(),
      }),
    );
  }

  Future<void> clear() => _preferences.remove(preferencesKey);
}

class PendingSharedGroupIntent {
  const PendingSharedGroupIntent({
    required this.slug,
    required this.intentId,
    required this.ownerUserId,
    required this.capturedAt,
  });

  final String slug;
  final String intentId;
  final String? ownerUserId;
  final DateTime capturedAt;

  PendingSharedGroupIntent bindTo(String userId) => PendingSharedGroupIntent(
    slug: slug,
    intentId: intentId,
    ownerUserId: normalizePendingSharedGroupOwnerUserId(userId),
    capturedAt: capturedAt,
  );
}

String normalizePendingSharedGroupOwnerUserId(String userId) {
  final normalized = userId.trim().toLowerCase();
  if (!PendingSharedGroupIntentStore._uuidPattern.hasMatch(normalized)) {
    throw const FormatException('Group invitation account is invalid');
  }
  return normalized;
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
  final target = collectAppLinkTargetFromUri(uri);
  return target?.kind == CollectAppLinkKind.group ? target?.value : null;
}

enum CollectAppLinkKind { group, app, invite }

class CollectAppLinkTarget {
  const CollectAppLinkTarget(this.kind, {this.value});

  final CollectAppLinkKind kind;
  final String? value;
}

CollectAppLinkTarget? collectAppLinkTargetFromUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'https' &&
      uri.host.toLowerCase() == 'collect.ikanisa.com' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443)) {
    final target = _collectHttpsAppLinkTarget(uri.pathSegments);
    if (target?.kind == CollectAppLinkKind.group &&
        collectGroupLinkHasAlternateTarget(uri)) {
      return null;
    }
    return target;
  }
  if (scheme == 'collect') {
    final target = _collectCustomSchemeTarget(
      uri.host.toLowerCase(),
      uri.pathSegments,
    );
    if (target?.kind == CollectAppLinkKind.group &&
        collectGroupLinkHasAlternateTarget(uri)) {
      return null;
    }
    return target;
  }
  return null;
}

bool collectGroupLinkHasAlternateTarget(Uri uri) {
  return uri.hasFragment ||
      uri.queryParameters.keys.any(
        (key) => const {'code', 'slug', 'group'}.contains(key.toLowerCase()),
      );
}

CollectAppLinkTarget? _collectHttpsAppLinkTarget(List<String> segments) {
  if (segments.length == 1 && segments.first.toLowerCase() == 'app') {
    return const CollectAppLinkTarget(CollectAppLinkKind.app);
  }
  if (segments.length != 2) return null;
  final route = segments.first.toLowerCase();
  if (route == 'c') {
    final slug = normalizePendingSharedGroupSlug(segments[1]);
    return slug == null
        ? null
        : CollectAppLinkTarget(CollectAppLinkKind.group, value: slug);
  }
  if (route == 'invite') {
    final publicId = _normalizeInviterPublicId(segments[1]);
    return publicId == null
        ? null
        : CollectAppLinkTarget(CollectAppLinkKind.invite, value: publicId);
  }
  return null;
}

CollectAppLinkTarget? _collectCustomSchemeTarget(
  String host,
  List<String> segments,
) {
  if (host == 'app' && segments.isEmpty) {
    return const CollectAppLinkTarget(CollectAppLinkKind.app);
  }
  if (segments.length != 1) return null;
  if (host == 'group') {
    final slug = normalizePendingSharedGroupSlug(segments.single);
    return slug == null
        ? null
        : CollectAppLinkTarget(CollectAppLinkKind.group, value: slug);
  }
  if (host == 'invite') {
    final publicId = _normalizeInviterPublicId(segments.single);
    return publicId == null
        ? null
        : CollectAppLinkTarget(CollectAppLinkKind.invite, value: publicId);
  }
  return null;
}

String? _normalizeInviterPublicId(String value) {
  final normalized = value.trim();
  if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(normalized)) return null;
  return normalized;
}
