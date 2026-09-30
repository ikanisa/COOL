void _requireUuid(String value) {
  if (!RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$').hasMatch(value)) {
    throw const FormatException('Invalid reconciliation reference.');
  }
}

class AdminReconciliationFinalization {
  const AdminReconciliationFinalization._({
    required this.reviewId,
    required this.paymentId,
    required this.paymentStatus,
    required this.replayed,
  });
  final String reviewId;
  final String paymentId;
  final String paymentStatus;
  final bool replayed;
  factory AdminReconciliationFinalization.fromJson(
    Map<String, dynamic> json, {
    required String reviewId,
    required String paymentId,
  }) {
    _requireUuid(reviewId);
    _requireUuid(paymentId);
    if (json['review_id'] != reviewId ||
        json['payment_id'] != paymentId ||
        json['replayed'] is! bool ||
        json['evidence_level'] != 'independently_reconciled' ||
        !{'posted', 'reversed'}.contains(json['payment_status']) ||
        (json['payment_status'] == 'reversed' && json['replayed'] != true)) {
      throw const FormatException(
        'Reconciliation finalization returned an invalid acknowledgement.',
      );
    }
    return AdminReconciliationFinalization._(
      reviewId: reviewId,
      paymentId: paymentId,
      paymentStatus: json['payment_status'] as String,
      replayed: json['replayed'] as bool,
    );
  }
  String get message => paymentStatus == 'reversed'
      ? 'This reconciliation was already finalized and later reversed. No new ledger entry was created.'
      : replayed
      ? 'This reconciliation was already finalized. No duplicate ledger entry was created.'
      : 'Reconciled payment posted to the Collect ledger.';
}
