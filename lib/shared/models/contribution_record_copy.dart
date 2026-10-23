import 'collect_models.dart';

/// Member-facing copy for the evidence the current contribution reader returns.
///
/// A Contribution is a posted Collect ledger record. Its wire contract does not
/// carry provider settlement or approved-finality-policy provenance. Preserve
/// the recorded amounts without presenting them as independently settled funds.
abstract final class ContributionRecordCopy {
  static const totalTitle = 'Recorded contributions';
  static const ownTotalTitle = 'Your recorded contributions';
  static const netTotalTitle = 'Net recorded activity';
  static const ownNetTotalTitle = 'Your net recorded activity';
  static const heroTotalLabel = 'Recorded total';
  static const recordLabel = 'Recorded';
  static const explanation =
      'These are Collect ledger records. A receipt SMS or a ledger entry alone does not verify provider settlement.';
  static const loadingMessage = 'Refreshing contribution records.';
  static const emptyMomoMessage = 'Recorded MoMo contributions appear here.';
  static const channelTitle = 'Contribution updates';
  static const channelDescription = 'Recorded contribution and ledger updates.';
  static const channelOverviewDescription =
      'Contribution updates, transfer reminders, group updates, and security notices.';
  static const recordHint =
      'View contribution records. A receipt SMS alone does not verify provider settlement.';
  static const handoffTitle = 'MoMo request opened';
  static const handoffMessage =
      'Opening MoMo does not confirm a transfer. Check the result with your provider, then refresh Activity to check for a recorded contribution. A receipt SMS alone does not verify settlement.';

  static String labelFor(Contribution row) => switch (row.entryKind) {
    ContributionEntryKind.reversal => 'Recorded reversal',
    ContributionEntryKind.correction => 'Recorded correction',
    ContributionEntryKind.contribution =>
      row.isHistoryEvent ? 'Recorded contribution' : recordLabel,
  };

  static String countLabel(int count, {bool signedHistory = false}) =>
      signedHistory
      ? '$count recorded ${count == 1 ? 'entry' : 'entries'}'
      : '$count recorded ${count == 1 ? 'contribution' : 'contributions'}';
}
