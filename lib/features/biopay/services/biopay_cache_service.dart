import 'dart:math' show sqrt;

import '../../../core/config/country_catalog.dart';
import '../models/biopay_match_result.dart';

class BiopayCacheService {
  BiopayCacheService();

  static const boxName = 'biopay_match_cache_v1';
  final Map<String, _BiopayCacheEntry> _entries = <String, _BiopayCacheEntry>{};

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
    _entries[_cacheKey(ownerUserId, profileId)] = _BiopayCacheEntry(
      ownerUserId: ownerUserId,
      expiresAt: DateTime.now().add(ttl).toUtc(),
      embedding: List<double>.unmodifiable(embedding),
      payload: _buildCachePayload(result),
    );
  }

  Future<BiopayMatchResult?> findNearestMatch(
    List<double> embedding, {
    required String ownerUserId,
    double similarityThreshold = 0.96,
  }) async {
    final now = DateTime.now().toUtc();
    BiopayMatchResult? bestMatch;
    var bestScore = similarityThreshold;
    final expiredKeys = <String>[];

    for (final entry in _entries.entries) {
      final cached = entry.value;
      if (cached.ownerUserId != ownerUserId) {
        continue;
      }

      if (cached.expiresAt.isBefore(now)) {
        expiredKeys.add(entry.key);
        continue;
      }

      if (cached.embedding.length != embedding.length) {
        expiredKeys.add(entry.key);
        continue;
      }

      final score = _cosineSimilarity(embedding, cached.embedding);
      if (score >= bestScore) {
        bestScore = score;
        bestMatch = BiopayMatchResult.fromCacheJson(cached.payload);
      }
    }

    for (final key in expiredKeys) {
      _entries.remove(key);
    }
    return bestMatch;
  }

  Future<void> remove(String profileId, {String? ownerUserId}) async {
    if (ownerUserId != null && ownerUserId.trim().isNotEmpty) {
      _entries.remove(_cacheKey(ownerUserId, profileId));
      return;
    }
    _entries.removeWhere((_, entry) {
      final profile = entry.payload['profile'];
      return profile is Map && profile['id']?.toString() == profileId;
    });
  }

  Future<void> clear({String? ownerUserId}) async {
    if (ownerUserId != null && ownerUserId.trim().isNotEmpty) {
      _entries.removeWhere((_, entry) => entry.ownerUserId == ownerUserId);
      return;
    }
    _entries.clear();
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

class _BiopayCacheEntry {
  const _BiopayCacheEntry({
    required this.ownerUserId,
    required this.expiresAt,
    required this.embedding,
    required this.payload,
  });

  final String ownerUserId;
  final DateTime expiresAt;
  final List<double> embedding;
  final Map<String, Object?> payload;
}
