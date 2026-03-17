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

    test('rejected KYC blocks both account opening and loan', () {
      final report = buildCreditReadinessReport(
        user: _user(kycStatus: 'rejected'),
        dashboard: _dashboard(
          score: 650,
          scoreBand: 'good',
          statementCount: 20,
          activeMonthCount: 6,
          groupContributionCount: 10,
          groupTotal: 200000,
        ),
      );

      expect(report.accountOpening.state, CreditReadinessState.actionNeeded);
      expect(report.loanApplication.state, CreditReadinessState.actionNeeded);
    });

    test('building state for thin wallet history with score', () {
      final report = buildCreditReadinessReport(
        user: _user(kycStatus: 'pending_review'),
        dashboard: _dashboard(
          score: 580,
          scoreBand: 'building',
          statementCount: 5,
          activeMonthCount: 2,
          groupContributionCount: 1,
          groupTotal: 5000,
        ),
      );

      expect(report.loanApplication.state, CreditReadinessState.building);
    });

    test('12 statements meets wallet history threshold', () {
      final report = buildCreditReadinessReport(
        user: _user(kycStatus: 'verified'),
        dashboard: _dashboard(
          score: 710,
          scoreBand: 'good',
          statementCount: 12,
          activeMonthCount: 3,
          groupContributionCount: 3,
          groupTotal: 50000,
        ),
      );

      final walletCheck = report.checks.firstWhere(
        (check) => check.id == 'wallet_history',
      );
      expect(walletCheck.isComplete, isTrue);
    });

    test('11 statements does NOT meet wallet history threshold', () {
      final report = buildCreditReadinessReport(
        user: _user(kycStatus: 'verified'),
        dashboard: _dashboard(
          score: 710,
          scoreBand: 'good',
          statementCount: 11,
          activeMonthCount: 3,
          groupContributionCount: 3,
          groupTotal: 50000,
        ),
      );

      final walletCheck = report.checks.firstWhere(
        (check) => check.id == 'wallet_history',
      );
      expect(walletCheck.isComplete, isFalse);
    });

    test('report counts completed checks and blocking issues correctly', () {
      final report = buildCreditReadinessReport(
        user: _user(kycStatus: 'verified'),
        dashboard: null,
      );

      // With verified KYC but no dashboard: 4 blocking issues
      // (credit_score is blocking and incomplete)
      expect(report.totalChecks, 8);
      expect(report.completedChecks, lessThan(report.totalChecks));
      expect(report.blockingIssues, greaterThanOrEqualTo(1));
    });
  });

  group('CreditDashboard', () {
    test('hasReport returns true when score is present', () {
      const dashboard = CreditDashboard(statementCount: 10, score: 600);
      expect(dashboard.hasReport, isTrue);
    });

    test('hasReport returns false when score is null', () {
      const dashboard = CreditDashboard(statementCount: 10);
      expect(dashboard.hasReport, isFalse);
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
