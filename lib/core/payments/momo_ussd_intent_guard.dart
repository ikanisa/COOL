import '../../shared/models/collect_models.dart';
import 'contribution_command.dart';

/// A server recheck must describe the exact payment the member reviewed.
/// Historical intent reads can contain receivers that are no longer active;
/// the field comparator alone grants no launch authority. The member flow must
/// use [reviewedMomoIntentStillActionable] with a current-review response.
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
      RegExp(r'^[a-f0-9]{64}$').hasMatch(prepared.senderPhoneHash) &&
      prepared.senderPhoneHash == current.senderPhoneHash &&
      prepared.createdAt.isAtSameMomentAs(current.createdAt) &&
      prepared.expiresAt.isAtSameMomentAs(current.expiresAt);
}

/// Historical creation receipts cannot satisfy this typed current-review guard.
bool reviewedMomoIntentStillActionable(
  PaymentIntentModel prepared,
  ContributionIntentReview review, {
  required DateTime now,
}) => preparedMomoIntentStillActionable(prepared, review.intent, now: now);
