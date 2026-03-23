import 'dart:math' show sqrt;

import '../../../core/config/country_catalog.dart';
import '../../../core/services/hive_runtime.dart';
import '../../../core/utils/json_helpers.dart' as jh;
import '../models/biopay_match_result.dart';

class BiopayCacheService {
  BiopayCacheService({required OpenHiveBox<dynamic> openBox})
    : _openBox = openBox;

  static const boxName = 'biopay_match_cache_v1';
  final OpenHiveBox<dynamic> _openBox;

  Future<void> storeMatch(
    String ownerUserId,
    List<double> embedding,
    BiopayMatchResult result, {
    Duration ttl = const Duration(hours: 24),
  }) async {
    final profileId = result.profile?.id;
    if (ownerUserId.trim().isEmpty || profileId == null || profileId.isEmpty) {
      return;
    }
    final box = await _openBox(boxName);
    await box.put(_cacheKey(ownerUserId, profileId), <String, Object?>{
      'owner_user_id': ownerUserId,
      'expires_at': DateTime.now().add(ttl).toUtc().toIso8601String(),
      'embedding': embedding,
      'payload': _buildCachePayload(result),
    });
  }

  Future<BiopayMatchResult?> findNearestMatch(
    List<double> embedding, {
    required String ownerUserId,
    double similarityThreshold = 0.96,
  }) async {
    final box = await _openBox(boxName);
    final now = DateTime.now().toUtc();
    BiopayMatchResult? bestMatch;
    var bestScore = similarityThreshold;

    for (final key in box.keys) {
      final raw = jh.asMapOrNull(box.get(key));
      if (raw == null) {
        continue;
      }

      if ((raw['owner_user_id']?.toString() ?? '') != ownerUserId) {
        continue;
      }

      final expiresAt = jh.parseDateTime(raw['expires_at']);
      if (expiresAt == null || expiresAt.isBefore(now)) {
        await box.delete(key);
        continue;
      }

      final cachedEmbedding = (raw['embedding'] as List?)
          ?.map((value) => jh.asDouble(value) ?? 0)
          .toList(growable: false);
      final payload = jh.asMapOrNull(raw['payload']);
      if (cachedEmbedding == null ||
          cachedEmbedding.length != embedding.length ||
          payload == null) {
        await box.delete(key);
        continue;
      }

      final score = _cosineSimilarity(embedding, cachedEmbedding);
      if (score >= bestScore) {
        bestScore = score;
        bestMatch = BiopayMatchResult.fromCacheJson(payload);
      }
    }

    return bestMatch;
  }

  Future<void> remove(String profileId, {String? ownerUserId}) async {
    final box = await _openBox(boxName);
    if (ownerUserId != null && ownerUserId.trim().isNotEmpty) {
      await box.delete(_cacheKey(ownerUserId, profileId));
      return;
    }
    await box.delete(profileId);
  }

  Future<void> clear({String? ownerUserId}) async {
    final box = await _openBox(boxName);
    if (ownerUserId != null && ownerUserId.trim().isNotEmpty) {
      final keysToDelete = box.keys
          .where(
            (key) =>
                jh.asMapOrNull(box.get(key))?['owner_user_id']?.toString() ==
                ownerUserId,
          )
          .toList(growable: false);
      await box.deleteAll(keysToDelete);
      return;
    }
    await box.clear();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var index = 0; index < a.length; index += 1) {
      dot += a[index] * b[index];
      normA += a[index] * a[index];
      normB += b[index] * b[index];
    }
    if (normA == 0 || normB == 0) {
      return 0;
    }
    return dot / (sqrt(normA) * sqrt(normB));
  }

  Map<String, Object?> _buildCachePayload(BiopayMatchResult result) {
    final profile = result.profile;
    return <String, Object?>{
      'match': result.match,
      'score': result.score,
      'cached': true,
      'profile': profile == null
          ? null
          : <String, Object?>{
              'id': profile.id,
              'public_id': profile.publicId,
              'user_id': profile.userId,
              'display_name': profile.displayName,
              'route_type': profile.routeType == MomoRecipientType.code
                  ? 'code'
                  : 'phone_number',
              'country_code': profile.countryCode,
              'active': profile.active,
              'consent_version': profile.consentVersion,
              'consent_at': profile.consentAt?.toIso8601String(),
              'created_at': profile.createdAt?.toIso8601String(),
              'updated_at': profile.updatedAt?.toIso8601String(),
              'revoked_at': profile.revokedAt?.toIso8601String(),
            },
    };
  }

  String _cacheKey(String ownerUserId, String profileId) {
    return '$ownerUserId:$profileId';
  }
}
