class FaceMatchResult {
  const FaceMatchResult({
    required this.isMatch,
    required this.confidence,
    required this.reason,
    required this.faciallyDetected,
    this.estimatedAgeId,
    this.estimatedAgeSelfie,
    required this.genderConsistent,
    required this.presentationAttackDetected,
  });

  factory FaceMatchResult.fromJson(Map<String, dynamic> json) {
    return FaceMatchResult(
      isMatch: json['is_match'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      reason: json['reason'] as String,
      faciallyDetected: json['facially_detected'] as bool,
      estimatedAgeId: (json['estimated_age_id'] as num?)?.toDouble(),
      estimatedAgeSelfie: (json['estimated_age_selfie'] as num?)?.toDouble(),
      genderConsistent: json['gender_consistent'] as bool,
      presentationAttackDetected: json['presentation_attack_detected'] as bool,
    );
  }

  final bool isMatch;
  final double confidence;
  final String reason;
  final bool faciallyDetected;
  final double? estimatedAgeId;
  final double? estimatedAgeSelfie;
  final bool genderConsistent;
  final bool presentationAttackDetected;
}
