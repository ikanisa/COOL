import 'package:cool_app/features/auth/models/user_profile.dart';
import 'package:cool_app/features/credit/models/credit_dashboard.dart';
import 'package:cool_app/features/credit/models/credit_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildCreditReadinessReport', () {
    test('marks verified users with strong history as ready', () {
      final report = buildCreditReadinessReport(
        user: _user(kycStatus: 'verified'),
        dashboard: _dashboard(
          score: 708,
          scoreBand: 'good',
          statementCount: 18,
          activeMonthCount: 4,
          groupContributionCount: 5,
          groupTotal: 120000,
        ),
      );

      expect(report.accountOpening.state, CreditReadinessState.ready);
      expect(report.loanApplication.state, CreditReadinessState.ready);
      expect(report.blockingIssues, 0);
      expect(report.completedChecks, report.totalChecks);
    });

    test('treats pending review as nearly ready when score is strong', () {
      final report = buildCreditReadinessReport(
        user: _user(kycStatus: 'pending_review'),
        dashboard: _dashboard(
          score: 736,
          scoreBand: 'excellent',
          statementCount: 16,
          activeMonthCount: 5,
          groupContributionCount: 4,
          groupTotal: 98000,
        ),
      );

      expect(report.accountOpening.state, CreditReadinessState.nearlyReady);
      expect(report.loanApplication.state, CreditReadinessState.nearlyReady);
      expect(report.blockingIssues, 1);
    });

    test('requires identity completion and a score before handoff', () {
      final report = buildCreditReadinessReport(
        user: _user(officialPhone: '', phone: ''),
        dashboard: null,
      );

      expect(report.accountOpening.state, CreditReadinessState.actionNeeded);
      expect(report.loanApplication.state, CreditReadinessState.actionNeeded);
      expect(report.blockingIssues, greaterThanOrEqualTo(3));
      expect(
        report.checks
            .firstWhere((check) => check.id == 'official_phone')
            .isComplete,
        isFalse,
      );
      expect(
        report.checks
            .firstWhere((check) => check.id == 'credit_score')
            .isComplete,
        isFalse,
      );
    });
  });
}

UserProfile _user({
  String fullName = 'Aline Uwase',
  String officialName = 'Aline Uwase',
  String phone = '+250788123456',
  String officialPhone = '+250788123456',
  String kycStatus = 'unverified',
}) {
  return UserProfile(
    id: 'user-1',
    phone: phone,
    fullName: fullName,
    momoNumber: '+250788123456',
    momoProvider: 'mtn',
    country: 'RW',
    languageCode: 'en',
    isDriver: false,
    officialName: officialName,
    officialPhone: officialPhone,
    kycStatus: kycStatus,
  );
}

CreditDashboard _dashboard({
  required int score,
  required String scoreBand,
  required int statementCount,
  required int activeMonthCount,
  required int groupContributionCount,
  required int groupTotal,
}) {
  return CreditDashboard(
    statementCount: statementCount,
    groupContributionCount: groupContributionCount,
    activeMonthCount: activeMonthCount,
    score: score,
    scoreBand: scoreBand,
    groupTotal: groupTotal,
    averageGroupContribution: groupContributionCount == 0
        ? 0
        : (groupTotal / groupContributionCount).round(),
  );
}
