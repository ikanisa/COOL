part of 'collect_repository.dart';

abstract interface class MemberPaymentState implements MemberGroupAccessState {
  Map<String, CollectionSummary> get collectionSummaries;
  List<PaymentIntentModel> get paymentIntents;
  bool get financialObservationUncertain;
}

abstract interface class MemberPaymentRepository {
  int get sessionGeneration;
  int get memberScopeGeneration;
  CollectCollection? maybeCollectionById(String id);
  PaymentIntentModel? maybeIntentById(String id);
  Future<void> loadInitial();

  Future<PaymentIntentModel> prepareContributionIntent(
    PaymentIntentDraft draft,
  );
  Future<ContributionCommandCheckpoint?> restoreContributionCommand(
    String collectionId,
  );
  Future<ContributionCommandCheckpoint> checkContributionCommand(
    String requestId,
  );
  Future<PaymentIntentModel> refreshPaymentIntent(String id);
  Future<ContributionIntentReview> reviewContributionIntent(
    PaymentIntentModel prepared,
  );
  Future<ContributionLaunchPermit> claimContributionHandoff(
    PaymentIntentModel prepared,
    ContributionIntentReview review,
  );
  Future<void> acknowledgeCommittedContribution(PaymentIntentModel intent);

  Future<PaymentHelpCheckpoint?> paymentHelpForIntent(String intentId);
  Future<PaymentHelpCheckpoint> requestPaymentHelp({
    required String intentId,
    String? providerReference,
    String? note,
  });
}

abstract interface class MemberHistoryRepository {
  int get sessionGeneration;
  MemberHistoryController openHistory(MemberHistoryQuery query);
  Future<MemberHistoryPage> fetchHistoryPage(
    MemberHistoryQuery query, {
    Map<String, dynamic>? cursor,
  });
}
