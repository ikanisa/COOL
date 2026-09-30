import '../../shared/models/collect_models.dart';

/// A server recheck must describe the exact payment the member reviewed.
/// Historical intent reads can contain receivers that are no longer active;
/// callers must obtain [current] from the live create_contribution_intent RPC.
bool preparedMomoIntentStillActionable(
  PaymentIntentModel prepared,
  PaymentIntentModel current, {
  required DateTime now,
}) {
  final instant = now.toUtc();
  return prepared.isRwandaMomo &&
      current.isRwandaMomo &&
      prepared.status == 'pending' &&
      current.status == 'pending' &&
      prepared.expiresAt.toUtc().isAfter(instant) &&
      current.expiresAt.toUtc().isAfter(instant) &&
      prepared.id == current.id &&
      prepared.collectionId == current.collectionId &&
      prepared.expectedAmountRwf == current.expectedAmountRwf &&
      prepared.receiverMomoNumber.isNotEmpty &&
      prepared.receiverMomoNumber == current.receiverMomoNumber &&
      prepared.receiverMomoNumberHash == current.receiverMomoNumberHash &&
      prepared.receiverMomoLabel == current.receiverMomoLabel &&
      prepared.momoNetwork == current.momoNetwork &&
      prepared.senderPhoneHash == current.senderPhoneHash &&
      prepared.createdAt.isAtSameMomentAs(current.createdAt) &&
      prepared.expiresAt.isAtSameMomentAs(current.expiresAt);
}
