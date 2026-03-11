class HomeDashboardData {
  const HomeDashboardData({
    required this.totalBalance,
    required this.monthlyNetChange,
    this.memberCount = 0,
    this.recentTransactions = const <HomeDashboardTransaction>[],
  });

  final int totalBalance;
  final int monthlyNetChange;
  final int memberCount;
  final List<HomeDashboardTransaction> recentTransactions;
}

class HomeDashboardTransaction {
  const HomeDashboardTransaction({
    required this.title,
    required this.type,
    required this.amount,
    required this.currency,
    required this.recordedAt,
    this.groupName,
    this.status,
  });

  final String title;
  final String type;
  final int amount;
  final String currency;
  final DateTime recordedAt;
  final String? groupName;
  final String? status;

  bool get isPositive {
    final normalized = type.toLowerCase();
    return normalized.contains('deposit') ||
        normalized.contains('interest') ||
        normalized.contains('payout') ||
        normalized.contains('credit');
  }

  int get signedAmount => isPositive ? amount.abs() : -amount.abs();
}
