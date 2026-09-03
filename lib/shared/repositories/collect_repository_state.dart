part of 'collect_repository.dart';

const _unsetDateTimeField = Object();

class CollectState {
  const CollectState({
    required this.currentProfile,
    required this.collections,
    required this.paymentIntents,
    required this.contributions,
    this.collectionSummaries = const {},
    this.historyPage,
    this.pendingIntentCount,
    this.notificationEvents = const [],
    this.notificationPreferences = NotificationPreferences.defaults,
    this.smsAccessEnabled = false,
    this.smsAccessDenied = false,
    this.smsSyncNeedsAttention = false,
    this.smsQueueOverflowed = false,
    this.isLoading = false,
    this.usingStaleCache = false,
    this.lastSuccessfulSyncAt,
    this.lastError,
  });

  final CollectProfile? currentProfile;
  final List<CollectCollection> collections;
  final List<PaymentIntentModel> paymentIntents;
  final List<Contribution> contributions;
  final Map<String, CollectionSummary> collectionSummaries;
  final MemberHistoryPage? historyPage;
  final int? pendingIntentCount;
  final List<NotificationEvent> notificationEvents;
  final NotificationPreferences notificationPreferences;
  final bool smsAccessEnabled;
  final bool smsAccessDenied;
  final bool smsSyncNeedsAttention;
  final bool smsQueueOverflowed;
  final bool isLoading;
  final bool usingStaleCache;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastError;

  bool get hasInitialLoadFailure =>
      !isLoading &&
      lastError != null &&
      !usingStaleCache &&
      lastSuccessfulSyncAt == null &&
      collections.isEmpty &&
      contributions.isEmpty &&
      paymentIntents.isEmpty;

  bool get hasOfflineReadableData {
    return currentProfile != null ||
        collections.isNotEmpty ||
        paymentIntents.isNotEmpty ||
        contributions.isNotEmpty;
  }

  CollectState copyWith({
    Object? currentProfile = _unsetDateTimeField,
    List<CollectCollection>? collections,
    List<PaymentIntentModel>? paymentIntents,
    List<Contribution>? contributions,
    Map<String, CollectionSummary>? collectionSummaries,
    Object? historyPage = _unsetDateTimeField,
    int? pendingIntentCount,
    List<NotificationEvent>? notificationEvents,
    NotificationPreferences? notificationPreferences,
    bool? smsAccessEnabled,
    bool? smsAccessDenied,
    bool? smsSyncNeedsAttention,
    bool? smsQueueOverflowed,
    bool? isLoading,
    bool? usingStaleCache,
    Object? lastSuccessfulSyncAt = _unsetDateTimeField,
    String? lastError,
  }) {
    return CollectState(
      currentProfile: identical(currentProfile, _unsetDateTimeField)
          ? this.currentProfile
          : currentProfile as CollectProfile?,
      collections: collections ?? this.collections,
      paymentIntents: paymentIntents ?? this.paymentIntents,
      contributions: contributions ?? this.contributions,
      collectionSummaries: collectionSummaries ?? this.collectionSummaries,
      historyPage: identical(historyPage, _unsetDateTimeField)
          ? this.historyPage
          : historyPage as MemberHistoryPage?,
      pendingIntentCount: pendingIntentCount ?? this.pendingIntentCount,
      notificationEvents: notificationEvents ?? this.notificationEvents,
      notificationPreferences:
          notificationPreferences ?? this.notificationPreferences,
      smsAccessEnabled: smsAccessEnabled ?? this.smsAccessEnabled,
      smsAccessDenied: smsAccessDenied ?? this.smsAccessDenied,
      smsSyncNeedsAttention:
          smsSyncNeedsAttention ?? this.smsSyncNeedsAttention,
      smsQueueOverflowed: smsQueueOverflowed ?? this.smsQueueOverflowed,
      isLoading: isLoading ?? this.isLoading,
      usingStaleCache: usingStaleCache ?? this.usingStaleCache,
      lastSuccessfulSyncAt: identical(lastSuccessfulSyncAt, _unsetDateTimeField)
          ? this.lastSuccessfulSyncAt
          : lastSuccessfulSyncAt as DateTime?,
      lastError: lastError,
    );
  }
}
