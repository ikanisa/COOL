part of 'collect_financial_components.dart';

CollectStatusTone paymentStatusTone(String status) {
  return switch (status) {
    'reconciled' || 'confirmed' => CollectStatusTone.success,
    'received_unreconciled' ||
    'needs_review' ||
    'review' => CollectStatusTone.warning,
    'expired' || 'failed' || 'exception' => CollectStatusTone.danger,
    'pending' => CollectStatusTone.info,
    _ => CollectStatusTone.neutral,
  };
}

String paymentStatusLabel(String status) {
  return switch (status) {
    'reconciled' || 'confirmed' => 'Reconciled',
    'received_unreconciled' => 'Received — awaiting reconciliation',
    'needs_review' || 'review' => 'Needs review',
    'expired' => 'Expired',
    'pending' => 'Pending',
    _ => status.replaceAll('_', ' '),
  };
}

CollectStatusTone statusToneFromText(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('approved') ||
      normalized.contains('allocated') ||
      normalized.contains('reconciled') ||
      normalized.contains('confirmed')) {
    return CollectStatusTone.success;
  }
  if (normalized.contains('pending') ||
      normalized.contains('review') ||
      normalized.contains('requested') ||
      normalized.contains('unreconciled')) {
    return CollectStatusTone.warning;
  }
  if (normalized.contains('reject') ||
      normalized.contains('danger') ||
      normalized.contains('expired') ||
      normalized.contains('exception')) {
    return CollectStatusTone.danger;
  }
  if (normalized.contains('private')) {
    return CollectStatusTone.privacy;
  }
  return CollectStatusTone.neutral;
}
