// Shared date formatting utilities for statement and ledger screens.
//
// Extracted from duplicated private helpers in momo_wallet_screen and
// group_statements_screen per Tactile Monolith audit.

/// Human-readable date with time for transaction tiles.
///
/// Example: `10 Apr 2026 • 14:30`
String formatTransactionDate(DateTime value) {
  final local = value.toLocal();
  final month = _monthAbbrev(local.month);
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day} $month ${local.year} • $hour:$minute';
}

/// Compact date label for export file names and period descriptions.
///
/// Example: `10 Apr 2026`
String formatExportDateLabel(DateTime value) {
  final local = value.toLocal();
  final month = _monthAbbrev(local.month);
  return '${local.day.toString().padLeft(2, '0')} $month ${local.year}';
}

String _monthAbbrev(int month) {
  return switch (month) {
    1 => 'Jan',
    2 => 'Feb',
    3 => 'Mar',
    4 => 'Apr',
    5 => 'May',
    6 => 'Jun',
    7 => 'Jul',
    8 => 'Aug',
    9 => 'Sep',
    10 => 'Oct',
    11 => 'Nov',
    _ => 'Dec',
  };
}
