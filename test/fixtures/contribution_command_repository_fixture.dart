import 'package:collect_app/core/payments/contribution_command.dart';
import 'package:collect_app/shared/models/collect_models.dart';

import 'collect_repository_fixture.dart';

const contributionFixtureOwner = '10000000-0000-0000-0000-000000000001';
const contributionFixtureGroup = '30000000-0000-0000-0000-000000000001';
const contributionFixtureIntent = '40000000-0000-0000-0000-000000000001';
const contributionFixtureSession = '20000000-0000-0000-0000-000000000001';

/// Explicit isolated payment-flow fixture. Production never falls back to this
/// fixture or converts creation/history into a review response.
class ContributionFixtureRepository extends FixtureCollectRepository {
  ContributionFixtureRepository()
    : super(
        profileOverride: const CollectProfile(
          id: contributionFixtureOwner,
          publicId: '038491',
          whatsappPhone: '+250788123456',
          countryCode: 'RW',
          currencyCode: 'RWF',
          momoProvider: 'mtn_momo',
          momoNumber: '0788123456',
        ),
      ) {
    state = state.copyWith(
      collections: [
        CollectCollection(
          id: contributionFixtureGroup,
          slug: 'contribution-fixture',
          creatorUserId: contributionFixtureOwner,
          title: 'Synthetic contribution group',
          description: '',
          receiverMomoNumber: '0788123456',
          receiverDisplayLabel: 'Synthetic recipient',
          receiverNetwork: 'mtn_momo',
          isCurrentUserMember: true,
          createdAt: DateTime.utc(2026),
        ),
        ...state.collections,
      ],
    );
  }
  int reviewCalls = 0, handoffCalls = 0;
  bool handoffPossible = false;
  @override
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  ) async => null;
  @override
  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  ) async {
    final intent = await createPaymentIntent(draft);
    // The legacy synthetic factory deliberately uses public preview IDs. This
    // explicit new payment fixture normalizes only its isolated test result.
    return PaymentIntentModel(
      id: contributionFixtureIntent,
      collectionId: contributionFixtureGroup,
      expectedAmountRwf: intent.expectedAmountRwf,
      receiverMomoNumber: intent.receiverMomoNumber,
      receiverMomoNumberHash: intent.receiverMomoNumberHash,
      receiverMomoLabel: intent.receiverMomoLabel,
      momoNetwork: intent.momoNetwork,
      senderPhoneHash: intent.senderPhoneHash,
      status: intent.status,
      createdAt: intent.createdAt,
      expiresAt: intent.expiresAt,
    );
  }

  Future<PaymentIntentModel> currentReviewIntent(
    PaymentIntentModel prepared,
  ) async => prepared;
  @override
  Future<ContributionIntentReview> reviewContributionIntent(
    PaymentIntentModel prepared,
  ) async {
    reviewCalls++;
    final intent = await currentReviewIntent(prepared);
    return contributionFixtureReview(intent);
  }

  @override
  Future<ContributionLaunchPermit> claimContributionHandoff(
    PaymentIntentModel prepared,
    ContributionIntentReview review,
  ) async {
    if (handoffPossible) {
      throw StateError('Synthetic handoff already possible.');
    }
    handoffCalls++;
    handoffPossible = true;
    return ContributionLaunchPermit(
      review: review,
      isCurrent: () => state.currentProfile?.id == contributionFixtureOwner,
    );
  }

  @override
  Future<void> acknowledgeCommittedContribution(
    PaymentIntentModel intent,
  ) async {}
}

ContributionIntentReview contributionFixtureReview(PaymentIntentModel intent) =>
    ContributionIntentReview.fromWire(
      {
        'contract_version': 1,
        'review_status': 'current',
        'collection_id': intent.collectionId,
        'intent_id': intent.id,
        'reviewed_session_id': contributionFixtureSession,
        'collection_revision': 1,
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'external_payment': 'unknown',
        'retry_authorized': false,
        'launch_authorized': true,
        'intent': {
          'id': intent.id,
          'collection_id': intent.collectionId,
          'amount_minor': intent.expectedAmountRwf,
          'currency': intent.currency,
          'rail': intent.rail,
          'status': intent.status,
          'receiver_momo_number': intent.receiverMomoNumber,
          'network': intent.momoNetwork,
          'receiver_label': intent.receiverMomoLabel,
          'receiver_momo_number_hash': intent.receiverMomoNumberHash,
          'sender_phone_hash': intent.senderPhoneHash,
          'originating_session_id': contributionFixtureSession,
          'created_at': intent.createdAt.toUtc().toIso8601String(),
          'expires_at': intent.expiresAt.toUtc().toIso8601String(),
        },
      },
      collectionId: intent.collectionId,
      intentId: intent.id,
      sessionId: contributionFixtureSession,
    );
