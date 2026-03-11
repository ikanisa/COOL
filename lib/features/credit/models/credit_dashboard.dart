class CreditDashboard {
  const CreditDashboard({
    required this.statementCount,
    this.groupContributionCount = 0,
    this.activeMonthCount = 0,
    this.score,
    this.scoreVersion,
    this.scoreBand,
    this.summary,
    this.periodStart,
    this.periodEnd,
    this.lastUpdated,
    this.reasonCodes = const <String>[],
    this.creditEntryCount = 0,
    this.debitEntryCount = 0,
    this.creditTotal = 0,
    this.debitTotal = 0,
    this.groupTotal = 0,
    this.averageGroupContribution = 0,
    this.kycStatus,
    this.factors = const <CreditFactor>[],
    this.history = const <CreditHistoryPoint>[],
  });

  final int statementCount;
  final int groupContributionCount;
  final int activeMonthCount;
  final int? score;
  final String? scoreVersion;
  final String? scoreBand;
  final String? summary;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? lastUpdated;
  final List<String> reasonCodes;
  final int creditEntryCount;
  final int debitEntryCount;
  final int creditTotal;
  final int debitTotal;
  final int groupTotal;
  final int averageGroupContribution;
  final String? kycStatus;
  final List<CreditFactor> factors;
  final List<CreditHistoryPoint> history;

  bool get hasReport => score != null;
}

class CreditFactor {
  const CreditFactor({
    required this.key,
    required this.label,
    required this.emoji,
    required this.score,
  });

  final String key;
  final String label;
  final String emoji;
  final int score;
}

class CreditHistoryPoint {
  const CreditHistoryPoint({
    required this.label,
    required this.score,
    required this.recordedAt,
  });

  final String label;
  final int score;
  final DateTime recordedAt;
}
