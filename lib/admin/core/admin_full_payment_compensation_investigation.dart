import 'admin_investigation.dart';

/// Selects immutable identifiers from a current joined investigation. The
/// compensation service independently checks financial proof and current access.
/// Keep the original source after reversal so a retained request can be recovered.
({
  String paymentId,
  String originalJournalEntryId,
  String originalSnapshotId,
  String collectionId,
  String? memberRecordId,
})?
fullPaymentCompensationInvestigationSource(
  AdminInvestigationSnapshot investigation, {
  required DateTime now,
}) {
  final payment = investigation.payment;
  if (!investigation.isFresh(now) ||
      investigation.scope != 'rwanda_momo' ||
      investigation.paymentState != 'available' ||
      payment == null ||
      payment.paymentId == null ||
      payment.collectionId == null) {
    return null;
  }
  final originals = payment.journals.where(
    (journal) => journal.entryType == 'receipt',
  );
  if (originals.length != 1) return null;
  final original = originals.single;
  final snapshot = original.snapshot;
  if (snapshot == null ||
      snapshot.deltaRwf != original.amountRwf ||
      (payment.memberId == null) != (snapshot.memberRwf == null)) {
    return null;
  }
  return (
    paymentId: payment.paymentId!,
    originalJournalEntryId: original.id,
    originalSnapshotId: snapshot.id,
    collectionId: payment.collectionId!,
    memberRecordId: payment.memberId,
  );
}
