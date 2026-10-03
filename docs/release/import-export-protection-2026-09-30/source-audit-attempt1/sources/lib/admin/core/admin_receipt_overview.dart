/// Redacted, server-derived Overview measurements. Monetary totals remain
/// decimal strings so the web client never rounds a bigint/numeric through JS.
class AdminReceiptOverview {
  const AdminReceiptOverview._({
    required this.checkedAt,
    required this.validUntil,
    required this.dayStart,
    required this.dayEnd,
    required this.postedCount,
    required this.postedValueRwf,
    required this.receipts,
  });

  final DateTime checkedAt, validUntil, dayStart, dayEnd;
  final int postedCount;
  final String postedValueRwf;
  final AdminReceiptOverviewQueue? receipts;

  bool isFresh(DateTime now) =>
      !checkedAt.isAfter(now.toUtc().add(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(validUntil);

  static Never _invalid() =>
      throw const FormatException('Overview measurements could not be validated.');

  static Map<String, dynamic> _object(Object? raw, Set<String> keys) {
    if (raw is! Map ||
        raw.length != keys.length ||
        raw.keys.any((key) => key is! String || !keys.contains(key))) {
      _invalid();
    }
    return Map<String, dynamic>.from(raw);
  }

  static int _count(Object? raw) {
    if (raw is! int || raw < 0 || raw > 9007199254740991) _invalid();
    return raw;
  }

  static DateTime _date(Object? raw) {
    if (raw is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$')
            .hasMatch(raw)) {
      _invalid();
    }
    final date = DateTime.tryParse(raw);
    if (date == null ||
        date.toUtc().toIso8601String().substring(0, 19) != raw.substring(0, 19)) {
      _invalid();
    }
    return date.toUtc();
  }

  factory AdminReceiptOverview.parse(Map<String, dynamic> raw) {
    final data = _object(raw, {
      'contract_version', 'scope', 'country_code', 'timezone', 'checked_at',
      'sample_valid_until', 'day_start', 'day_end', 'posted', 'receipts_state',
      'receipts',
    });
    if (data['contract_version'] is! int || data['contract_version'] != 1 ||
        data['scope'] != 'rwanda_momo' || data['country_code'] != 'RW' ||
        data['timezone'] != 'Africa/Kigali') _invalid();
    final checked = _date(data['checked_at']);
    final expires = _date(data['sample_valid_until']);
    final start = _date(data['day_start']);
    final end = _date(data['day_end']);
    final local = checked.add(const Duration(hours: 2));
    final expectedStart = DateTime.utc(local.year, local.month, local.day)
        .subtract(const Duration(hours: 2));
    if (expires.difference(checked) != const Duration(seconds: 60) ||
        start != expectedStart || end.difference(start) != const Duration(days: 1)) {
      _invalid();
    }
    final posted = _object(data['posted'], {'count', 'value_rwf'});
    final count = _count(posted['count']);
    final amount = posted['value_rwf'];
    if (amount is! String || !RegExp(r'^(?:0|[1-9][0-9]{0,77})$').hasMatch(amount) ||
        (count == 0) != (amount == '0') || BigInt.parse(amount) < BigInt.from(count)) {
      _invalid();
    }
    AdminReceiptOverviewQueue? receipts;
    if (data['receipts_state'] == 'available') {
      final queue = _object(data['receipts'], {
        'queued', 'awaiting_confirmation', 'oldest_pending_at',
        'failed_no_send', 'uncertain', 'send_started',
      });
      final queued = _count(queue['queued']);
      final awaiting = _count(queue['awaiting_confirmation']);
      final oldest = queue['oldest_pending_at'] == null
          ? null : _date(queue['oldest_pending_at']);
      if (((queued + awaiting) == 0) != (oldest == null) ||
          (oldest != null && oldest.isAfter(checked))) _invalid();
      receipts = AdminReceiptOverviewQueue(
        queued: queued,
        awaitingConfirmation: awaiting,
        oldestPendingAt: oldest,
        failedNoSend: _count(queue['failed_no_send']),
        uncertain: _count(queue['uncertain']),
        sendStarted: _count(queue['send_started']),
      );
    } else if (data['receipts_state'] != 'denied' || data['receipts'] != null) {
      _invalid();
    }
    return AdminReceiptOverview._(
      checkedAt: checked, validUntil: expires, dayStart: start, dayEnd: end,
      postedCount: count, postedValueRwf: amount, receipts: receipts,
    );
  }
}

class AdminReceiptOverviewQueue {
  const AdminReceiptOverviewQueue({
    required this.queued, required this.awaitingConfirmation,
    required this.oldestPendingAt, required this.failedNoSend,
    required this.uncertain, required this.sendStarted,
  });
  final int queued, awaitingConfirmation, failedNoSend, uncertain, sendStarted;
  final DateTime? oldestPendingAt;
  int get pending => queued + awaitingConfirmation;
}
