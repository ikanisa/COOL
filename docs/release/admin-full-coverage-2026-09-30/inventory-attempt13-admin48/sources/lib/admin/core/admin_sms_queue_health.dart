import '../../core/data/exact_json_values.dart';

/// Aggregate evidence from the authenticated assisted-SMS operator service.
/// A heartbeat does not establish a completed supervisor run or SMS delivery.
class AdminSmsQueueHealth {
  const AdminSmsQueueHealth._({
    required this.enabled,
    required this.counts,
    required this.observedAt,
    required this.oldestQueuedAt,
  });

  final bool enabled;
  final Map<String, int> counts;
  final DateTime observedAt;
  final DateTime? oldestQueuedAt;

  static const countLabels = <String, String>{
    'queued': 'Queued receipts',
    'awaiting_confirmation': 'Awaiting operator confirmation',
    'send_started': 'Send started',
    'uncertain': 'Send outcome unknown',
    'suppressed': 'Suppressed receipts',
    'active_workers': 'Recent operator heartbeats',
  };

  static Never _invalid() =>
      throw const FormatException('SMS queue health could not be validated.');

  static DateTime _instant(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|\+00:00)$',
        ).hasMatch(value)) {
      _invalid();
    }
    try {
      return exactJsonTimestamp(value, field: 'SMS queue timestamp');
    } on FormatException {
      _invalid();
    }
  }

  factory AdminSmsQueueHealth.parse(Object? raw) {
    final keys = {
      ...countLabels.keys,
      'enabled',
      'observed_at',
      'oldest_queued_at',
    };
    if (raw is! Map ||
        raw.length != keys.length ||
        raw.keys.any((key) => key is! String || !keys.contains(key)) ||
        raw['enabled'] is! bool) {
      _invalid();
    }
    final counts = <String, int>{};
    for (final name in countLabels.keys) {
      final value = raw[name];
      if (value is! int || value < 0 || value > 9007199254740991) {
        _invalid();
      }
      counts[name] = value;
    }
    final observed = _instant(raw['observed_at']);
    final oldest = raw['oldest_queued_at'] == null
        ? null
        : _instant(raw['oldest_queued_at']);
    if ((counts['queued'] == 0) != (oldest == null) ||
        (oldest != null && oldest.isAfter(observed))) {
      _invalid();
    }
    return AdminSmsQueueHealth._(
      enabled: raw['enabled'] as bool,
      counts: Map.unmodifiable(counts),
      observedAt: observed,
      oldestQueuedAt: oldest,
    );
  }

  /// This is the Admin display policy, not a server-issued authorization TTL.
  bool isFresh(DateTime now) =>
      !now.toUtc().isBefore(observedAt.subtract(const Duration(seconds: 5))) &&
      now.toUtc().isBefore(observedAt.add(const Duration(seconds: 60)));
}
