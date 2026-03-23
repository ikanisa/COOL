import '../../../core/utils/json_helpers.dart' as jh;
import 'biopay_profile.dart';

class BiopayMatchResult {
  const BiopayMatchResult({
    required this.match,
    required this.score,
    this.profile,
    this.cached = false,
  });

  final bool match;
  final double score;
  final BiopayProfile? profile;
  final bool cached;

  factory BiopayMatchResult.fromApiResponse(Map<String, dynamic> json) {
    final match = jh.asBool(json['match']);
    final score = jh.asDouble(json['score']) ?? 0;
    if (!match) {
      return BiopayMatchResult(match: false, score: score);
    }

    return BiopayMatchResult(
      match: true,
      score: score,
      profile: BiopayProfile.fromJson(<String, dynamic>{
        'id': json['profile_id'],
        'public_id': json['public_id'],
        'user_id': json['user_id'],
        'display_name': json['display_name'],
        'route_type': json['route_type'],
        'recipient_value': json['recipient_value'],
        'country_code': json['country_code'],
        'active': true,
        'consent_version': json['consent_version'] ?? 'biopay-v1',
        'consent_at': json['consent_at'],
        'created_at': json['created_at'],
        'updated_at': json['updated_at'],
      }),
    );
  }

  factory BiopayMatchResult.fromCacheJson(Map<String, dynamic> json) {
    return BiopayMatchResult(
      match: jh.asBool(json['match']),
      score: jh.asDouble(json['score']) ?? 0,
      cached: jh.asBool(json['cached']),
      profile: jh.asMapOrNull(json['profile']) == null
          ? null
          : BiopayProfile.fromJson(jh.asMap(json['profile'])),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'match': match,
      'score': score,
      'cached': cached,
      'profile': profile?.toJson(),
    };
  }

  BiopayMatchResult copyWith({bool? cached}) {
    return BiopayMatchResult(
      match: match,
      score: score,
      profile: profile,
      cached: cached ?? this.cached,
    );
  }
}
