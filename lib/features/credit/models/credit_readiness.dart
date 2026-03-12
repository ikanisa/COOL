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
      label: 'Official name on file',
      detail: hasOfficialName
          ? officialName
          : 'Add the user legal or official name used for lending and bank onboarding.',
      isComplete: hasOfficialName,
      isBlocking: true,
    ),
    CreditReadinessCheck(
      id: 'official_phone',
      label: 'Official phone confirmed',
      detail: hasOfficialPhone
          ? officialPhone
          : 'Capture the official phone number used for account opening and application follow-up.',
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
          : 'Build more verified wallet and savings activity to generate a score.',
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
          : 'No confirmed savings pattern is visible yet in the current window.',
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
          'Official identity details are still incomplete, so partner onboarding would stall.',
      nextStep:
          'Complete the official name and phone fields before starting a bank handoff.',
    );
  }

  return switch (kycStatus) {
    'verified' => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.ready,
      summary:
          'Official profile data and identity verification are in place for partner onboarding.',
      nextStep:
          'Open a partner page and proceed with account-opening or savings onboarding.',
    ),
    'pending_review' => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.nearlyReady,
      summary:
          'Official identity is captured and KYC is already in review, but final opening still depends on approval.',
      nextStep:
          'Shortlist a partner now and finish the handoff once KYC is verified.',
    ),
    'rejected' => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.actionNeeded,
      summary:
          'The current KYC result was rejected, so a partner would require corrected identity data first.',
      nextStep:
          'Correct the official identity data and restart KYC before opening an account.',
    ),
    _ => const CreditReadinessJourney(
      title: 'Bank Account Opening',
      state: CreditReadinessState.building,
      summary:
          'Official profile details are captured, but identity verification has not started yet.',
      nextStep:
          'Start KYC review before moving into partner account-opening flows.',
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
          'Loan preparation cannot start until the official identity profile is complete.',
      nextStep:
          'Complete the official name and phone fields used in formal applications.',
    );
  }

  if (kycStatus == 'rejected') {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.actionNeeded,
      summary:
          'Identity verification must be corrected before any lending handoff can be considered.',
      nextStep:
          'Resolve the rejected KYC result first, then refresh the credit report.',
    );
  }

  if (!hasScore) {
    return const CreditReadinessJourney(
      title: 'Loan Application',
      state: CreditReadinessState.actionNeeded,
      summary:
          'There is no current credit report yet, so the user is not ready for a formal lending handoff.',
      nextStep:
          'Keep wallet and savings activity flowing until a credit report is generated.',
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
          'The user has a strong report, verified identity, and enough transaction depth for a serious partner conversation.',
      nextStep:
          'Review partner credit products and prepare the formal application package.',
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
          'The score and transaction history are credible, but final lending readiness still depends on KYC approval.',
      nextStep:
          'Keep activity consistent and move forward once KYC changes to verified.',
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
          'The profile shows promising signals, but the file is still too thin or uneven for a strong lending handoff.',
      nextStep:
          'Build more active months, savings consistency, and posted wallet activity before applying.',
    );
  }

  return const CreditReadinessJourney(
    title: 'Loan Application',
    state: CreditReadinessState.actionNeeded,
    summary:
        'The user needs a stronger verified history before entering a partner loan flow.',
    nextStep:
        'Start with wallet activity, group savings, and KYC completion before pursuing credit.',
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
    'pending_review' => 'KYC has been submitted and is pending review.',
    'rejected' => 'KYC was rejected and needs correction.',
    _ => 'KYC has not been started yet.',
  };
}

String _kycVerifiedDetail(String kycStatus) {
  return switch (kycStatus) {
    'verified' => 'Identity verification is complete.',
    'pending_review' => 'Verification is underway but not approved yet.',
    'rejected' => 'Verification was rejected.',
    _ => 'Identity verification is still missing.',
  };
}
