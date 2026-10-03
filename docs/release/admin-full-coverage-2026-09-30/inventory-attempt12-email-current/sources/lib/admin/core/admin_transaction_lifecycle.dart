/// Independent server observations. Allocation alone does not establish
/// verification, balanced posting, or notification delivery.
class AdminTransactionLifecycle {
  const AdminTransactionLifecycle._({
    required this.verification,
    required this.allocation,
    required this.ledger,
    required this.notification,
  });

  final String verification;
  final String allocation;
  final String ledger;
  final String notification;

  static const verificationStates = {
    'pending',
    'confirmation_recorded',
    'rejection_recorded',
    'evidence_conflict',
    'unavailable',
  };
  static const allocationStates = {
    'unallocated',
    'allocated',
    'ambiguous',
    'needs_review',
    'ignored',
    'pending_parse',
    'parse_failed',
    'unavailable',
  };
  static const ledgerStates = {
    'not_posted',
    'posted',
    'reversed',
    'evidence_missing',
    'unavailable',
  };
  static const notificationStates = {
    'queued',
    'awaiting_confirmation',
    'send_started',
    'observed_sent',
    'failed_no_send',
    'uncertain',
    'suppressed',
    'not_created',
    'access_required',
    'unavailable',
  };

  /// A genuinely older server may omit the whole versioned observation.
  /// A partial, unknown-version or malformed observation must fail validation.
  static AdminTransactionLifecycle? parse(Object? value) {
    if (value == null) return null;
    const keys = {
      'contract_version',
      'verification',
      'allocation',
      'ledger',
      'notification',
      'evidence_limit',
    };
    if (value is! Map ||
        value.length != keys.length ||
        !value.keys.every(keys.contains) ||
        value['contract_version'] != 1 ||
        value['contract_version'] is! int ||
        value['evidence_limit'] !=
            'confirmation_record_is_not_external_settlement_proof' ||
        !verificationStates.contains(value['verification']) ||
        !allocationStates.contains(value['allocation']) ||
        !ledgerStates.contains(value['ledger']) ||
        !notificationStates.contains(value['notification'])) {
      throw const FormatException('Invalid transaction lifecycle evidence.');
    }
    return AdminTransactionLifecycle._(
      verification: value['verification'] as String,
      allocation: value['allocation'] as String,
      ledger: value['ledger'] as String,
      notification: value['notification'] as String,
    );
  }

  static String label(String? state) => switch (state) {
    'confirmation_recorded' => 'Confirmation recorded',
    'rejection_recorded' => 'Rejection recorded',
    'evidence_conflict' => 'Evidence conflict',
    'pending' => 'Awaiting verification',
    'pending_parse' => 'Awaiting parsing',
    'parse_failed' => 'Parsing failed',
    'not_posted' => 'Not posted',
    'evidence_missing' => 'Evidence missing',
    'not_created' => 'No receipt evidence',
    'access_required' => 'Access required',
    'observed_sent' => 'Operator observed sent',
    'failed_no_send' => 'Definitely not sent',
    'send_started' => 'Send started',
    'awaiting_confirmation' => 'Awaiting approval',
    'needs_review' => 'Needs review',
    'unallocated' => 'Unallocated',
    'allocated' => 'Allocated',
    'ambiguous' => 'Ambiguous',
    'ignored' => 'Ignored',
    'posted' => 'Posted',
    'reversed' => 'Reversed',
    'queued' => 'Queued',
    'uncertain' => 'Unknown send outcome',
    'suppressed' => 'Suppressed',
    _ => 'Unavailable',
  };
}
