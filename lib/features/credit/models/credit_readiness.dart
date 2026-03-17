import '../../auth/models/user_profile.dart';
import 'credit_dashboard.dart';

enum CreditReadinessState { ready, nearlyReady, building, actionNeeded }

class CreditReadinessCheck {
  const CreditReadinessCheck({
    required this.id,
    required this.label,
    required this.detail,
    required this.isComplete,
    this.isBlocking = false,
  });

  final String id;
  final String label;
  final String detail;
  final bool isComplete;
  final bool isBlocking;
}

class CreditReadinessJourney {
  const CreditReadinessJourney({
    required this.title,
    required this.state,
    required this.summary,
    required this.nextStep,
  });

  final String title;
  final CreditReadinessState state;
  final String summary;
  final String nextStep;
}

class CreditReadinessReport {
  const CreditReadinessReport({
    required this.accountOpening,
    required this.loanApplication,
    required this.checks,
  });

  final CreditReadinessJourney accountOpening;
  final CreditReadinessJourney loanApplication;
  final List<CreditReadinessCheck> checks;

  int get completedChecks => checks.where((check) => check.isComplete).length;

  int get totalChecks => checks.length;

  int get blockingIssues =>
      checks.where((check) => check.isBlocking && !check.isComplete).length;
}

CreditReadinessReport buildCreditReadinessReport({
  required UserProfile user,
  required CreditDashboard? dashboard,
}) {
  final officialName = _effectiveOfficialName(user);
  final officialPhone = _effectiveOfficialPhone(user);
  final kycStatus = user.kycStatus.trim();
  final hasScore = dashboard?.hasReport == true;
  final scoreBand = dashboard?.scoreBand ?? 'limited_history';
  final statementCount = dashboard?.statementCount ?? 0;
  final activeMonthCount = dashboard?.activeMonthCount ?? 0;
  final groupContributionCount = dashboard?.groupContributionCount ?? 0;
  final groupTotal = dashboard?.groupTotal ?? 0;

  final hasOfficialName = officialName.isNotEmpty;
  final hasOfficialPhone = officialPhone.isNotEmpty;
  final kycReviewStarted =
      kycStatus == 'pending_review' || kycStatus == 'verified';
  final kycVerified = kycStatus == 'verified';
  final enoughWalletHistory = statementCount >= 12;
  final enoughActiveMonths = activeMonthCount >= 3;
  final hasSavingsEvidence = groupContributionCount >= 3 || groupTotal > 0;
  final scoreStrong = scoreBand == 'good' || scoreBand == 'excellent';

  final checks = <CreditReadinessCheck>[
    CreditReadinessCheck(
      id: 'official_name',
      label: 'Official Name On File',
      detail: hasOfficialName
          ? officialName
          : 'Add legal name',
      isComplete: hasOfficialName,
      isBlocking: true,
    ),
    CreditReadinessCheck(
      id: 'official_phone',
      label: 'Official phone confirmed',
      detail: hasOfficialPhone
          ? officialPhone
          : 'Add official phone',
      isComplete: hasOfficialPhone,
      isBlocking: true,
    ),
    CreditReadinessCheck(
      id: 'kyc_started',
      label: 'KYC review started',
      detail: _kycReviewDetail(kycStatus),
      isComplete: kycReviewStarted,
      isBlocking: true,
    ),
    CreditReadinessCheck(
      id: 'kyc_verified',
      label: 'KYC fully verified',
      detail: _kycVerifiedDetail(kycStatus),
      isComplete: kycVerified,
      isBlocking: true,
    ),
    CreditReadinessCheck(
      id: 'credit_score',
      label: 'Credit report generated',
      detail: hasScore
          ? 'Current score ${dashboard!.score} with ${scoreBand.replaceAll('_', ' ')} standing.'
          : 'Build more activity',
      isComplete: hasScore,
      isBlocking: true,
    ),
    CreditReadinessCheck(
      id: 'wallet_history',
      label: 'Wallet history depth',
      detail: enoughWalletHistory
          ? '$statementCount posted wallet entries are available for review.'
          : '$statementCount posted wallet entries are available. Aim for at least 12.',
      isComplete: enoughWalletHistory,
    ),
    CreditReadinessCheck(
      id: 'activity_window',
      label: 'Active months',
      detail: enoughActiveMonths
          ? '$activeMonthCount active months are covered in the score window.'
          : '$activeMonthCount active months are covered. Aim for at least 3.',
      isComplete: enoughActiveMonths,
    ),
    CreditReadinessCheck(
      id: 'savings_signal',
      label: 'Savings and group evidence',
      detail: hasSavingsEvidence
          ? '$groupContributionCount confirmed savings contributions were detected.'
          : 'No savings pattern yet',
      isComplete: hasSavingsEvidence,
    ),
  ];

  final accountOpening = _buildAccountOpeningJourney(
    hasOfficialName: hasOfficialName,
    hasOfficialPhone: hasOfficialPhone,
    kycStatus: kycStatus,
  );

  final loanApplication = _buildLoanApplicationJourney(
    hasOfficialName: hasOfficialName,
    hasOfficialPhone: hasOfficialPhone,
    hasScore: hasScore,
    scoreStrong: scoreStrong,
    scoreBand: scoreBand,
    kycStatus: kycStatus,
    enoughWalletHistory: enoughWalletHistory,
    enoughActiveMonths: enoughActiveMonths,
    hasSavingsEvidence: hasSavingsEvidence,
  );

  return CreditReadinessReport(
    accountOpening: accountOpening,
    loanApplication: loanApplication,
    checks: checks,
  );
}

CreditReadinessJourney _buildAccountOpeningJourney({
  required bool hasOfficialName,
  required bool hasOfficialPhone,
  required String kycStatus,
}) {
  if (!hasOfficialName || !hasOfficialPhone) {
    return const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.actionNeeded,
      summary:
          'Identity incomplete',
      nextStep:
          'Complete name and phone',
    );
  }

  return switch (kycStatus) {
    'verified' => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.ready,
      summary:
          'Identity verified',
      nextStep:
          'Proceed with partner',
    ),
    'pending_review' => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.nearlyReady,
      summary:
          'KYC pending approval',
      nextStep:
          'Finish after KYC approval',
    ),
    'rejected' => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.actionNeeded,
      summary:
          'KYC rejected',
      nextStep:
          'Correct identity data',
    ),
    _ => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.building,
      summary:
          'KYC not started',
      nextStep:
          'Start KYC first',
    ),
  };
}

CreditReadinessJourney _buildLoanApplicationJourney({
  required bool hasOfficialName,
  required bool hasOfficialPhone,
  required bool hasScore,
  required bool scoreStrong,
  required String scoreBand,
  required String kycStatus,
  required bool enoughWalletHistory,
  required bool enoughActiveMonths,
  required bool hasSavingsEvidence,
}) {
  if (!hasOfficialName || !hasOfficialPhone) {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.actionNeeded,
      summary:
          'Identity incomplete',
      nextStep:
          'Complete name and phone',
    );
  }

  if (kycStatus == 'rejected') {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.actionNeeded,
      summary:
          'KYC needs correction',
      nextStep:
          'Fix KYC first',
    );
  }

  if (!hasScore) {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.actionNeeded,
      summary:
          'No credit report yet',
      nextStep:
          'Build more activity',
    );
  }

  if (scoreStrong &&
      kycStatus == 'verified' &&
      enoughWalletHistory &&
      enoughActiveMonths &&
      hasSavingsEvidence) {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.ready,
      summary:
          'Strong profile ready',
      nextStep:
          'Review credit products',
    );
  }

  if (scoreStrong &&
      kycStatus == 'pending_review' &&
      enoughWalletHistory &&
      enoughActiveMonths) {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.nearlyReady,
      summary:
          'Pending KYC approval',
      nextStep:
          'Wait for KYC',
    );
  }

  if (scoreBand == 'building' ||
      enoughWalletHistory ||
      enoughActiveMonths ||
      hasSavingsEvidence ||
      kycStatus == 'pending_review') {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.building,
      summary:
          'File still thin',
      nextStep:
          'Build more history',
    );
  }

  return const CreditReadinessJourney(
    title: 'Loan Application',
    state: CreditReadinessState.actionNeeded,
    summary:
        'History too thin',
    nextStep:
        'Start with basics',
  );
}

String _effectiveOfficialName(UserProfile user) {
  final officialName = user.officialName?.trim() ?? '';
  if (officialName.isNotEmpty && officialName.toLowerCase() != 'user') {
    return officialName;
  }
  return user.fullName.trim();
}

String _effectiveOfficialPhone(UserProfile user) {
  final officialPhone = user.officialPhone?.trim() ?? '';
  if (officialPhone.isNotEmpty) {
    return officialPhone;
  }
  return user.phone.trim();
}

String _kycReviewDetail(String kycStatus) {
  return switch (kycStatus) {
    'verified' => 'KYC is already verified.',
    'pending_review' => 'KYC pending review',
    'rejected' => 'KYC rejected',
    _ => 'KYC has not been started yet.',
  };
}

String _kycVerifiedDetail(String kycStatus) {
  return switch (kycStatus) {
    'verified' => 'Identity verified',
    'pending_review' => 'Verification pending',
    'rejected' => 'Verification was rejected.',
    _ => 'Identity missing',
  };
}