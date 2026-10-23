import 'admin_investigation.dart';

/// Selects an identifier from fresh joined evidence. The notice service still
/// verifies the canonical compensation and derives all recipient/content facts.
String? receiptNoticeReversalSnapshotId(
  AdminInvestigationSnapshot investigation, {
  required String outboxId,
  required DateTime now,
}) {
  final receipt = investigation.receipt;
  final payment = investigation.payment;
  if (!investigation.isFresh(now) ||
      investigation.scope != 'rwanda_momo' ||
      investigation.receiptState != 'available' ||
      investigation.paymentState != 'available' ||
      receipt == null ||
      payment == null ||
      receipt.id != outboxId ||
      payment.paymentId != receipt.paymentId ||
      payment.collectionId != receipt.collectionId ||
      payment.memberId != receipt.memberId) {
    return null;
  }
  final reversals = payment.journals.where(
    (journal) => journal.entryType == 'reversal',
  );
  if (reversals.length != 1) return null;
  final reversal = reversals.single;
  final snapshot = reversal.snapshot;
  if (reversal.amountRwf != receipt.amountRwf ||
      snapshot == null ||
      snapshot.deltaRwf != '-${receipt.amountRwf}' ||
      snapshot.id == receipt.snapshotId) {
    return null;
  }
  return snapshot.id;
}
