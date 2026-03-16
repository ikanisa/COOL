class CreditInsights {
  const CreditInsights({
    required this.creditReadiness,
    required this.estimatedScoreRange,
    required this.keyStrengths,
    required this.improvementAreas,
    required this.spendingAnalysis,
    required this.proactiveTips,
    required this.savingsDisciplineScore,
    required this.incomeStabilityScore,
  });

  factory CreditInsights.fromJson(Map<String, dynamic> json) {
    return CreditInsights(
      creditReadiness: json['credit_readiness'] as String,
      estimatedScoreRange: json['estimated_score_range'] as String,
      keyStrengths: List<String>.from(json['key_strengths'] as List),
      improvementAreas: List<String>.from(json['improvement_areas'] as List),
      spendingAnalysis: json['spending_analysis'] as String,
      proactiveTips: List<String>.from(json['proactive_tips'] as List),
      savingsDisciplineScore: (json['savings_discipline_score'] as num).toDouble(),
      incomeStabilityScore: (json['income_stability_score'] as num).toDouble(),
    );
  }

  final String creditReadiness;
  final String estimatedScoreRange;
  final List<String> keyStrengths;
  final List<String> improvementAreas;
  final String spendingAnalysis;
  final List<String> proactiveTips;
  final double savingsDisciplineScore;
  final double incomeStabilityScore;
}
