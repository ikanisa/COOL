part of 'collect_repository.dart';

CollectState _emptyCollectState() {
  return const CollectState(
    currentProfile: null,
    collections: [],
    paymentIntents: [],
    contributions: [],
  );
}

const _unsetDateTimeField = Object();

class CollectState {
  // Public named parameters are kept while masked backing fields stay private.
  const CollectState({
    required this.currentProfile,
    required List<CollectCollection> collections,
    required List<PaymentIntentModel> paymentIntents,
    required List<Contribution> contributions,
    Map<String, CollectionSummary> collectionSummaries = const {},
    MemberHistoryPage? historyPage,
    int? pendingIntentCount,
    this.notificationEvents = const [],
    this.notificationPreferences = NotificationPreferences.defaults,
    this.smsAccessEnabled = false,
    this.smsAccessDenied = false,
    this.smsSyncNeedsAttention = false,
    this.smsQueueOverflowed = false,
    this.isLoading = false,
    this.usingStaleCache = false,
    this.publicDiscoveryLoading = false,
    this.publicDiscoveryUnavailable = false,
    bool financialObservationUncertain = false,
    this.memberScopeUncertain = false,
    this.lastSuccessfulSyncAt,
    this.lastError,
  }) : _collections = collections, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _paymentIntents = paymentIntents,
       // ignore: prefer_initializing_formals
       _contributions = contributions,
       // ignore: prefer_initializing_formals
       _collectionSummaries = collectionSummaries,
       // ignore: prefer_initializing_formals
       _historyPage = historyPage,
       // ignore: prefer_initializing_formals
       _pendingIntentCount = pendingIntentCount,
       // ignore: prefer_initializing_formals
       _financialObservationUncertain = financialObservationUncertain;

  final CollectProfile? currentProfile;
  final List<CollectCollection> _collections;
  final List<PaymentIntentModel> _paymentIntents;
  final List<Contribution> _contributions;
  final Map<String, CollectionSummary> _collectionSummaries;
  final MemberHistoryPage? _historyPage;
  final int? _pendingIntentCount;

  // A history denial can reflect changed membership, but does not revoke the
  // account or its SMS consent. Hide the previous member snapshot until one
  // complete current-session read replaces it; never present it as zero.
  final bool memberScopeUncertain;
  List<CollectCollection> get collections =>
      memberScopeUncertain ? const [] : _collections;
  List<PaymentIntentModel> get paymentIntents =>
      memberScopeUncertain ? const [] : _paymentIntents;
  List<Contribution> get contributions =>
      memberScopeUncertain ? const [] : _contributions;
  Map<String, CollectionSummary> get collectionSummaries =>
      memberScopeUncertain ? const {} : _collectionSummaries;
  MemberHistoryPage? get historyPage =>
      memberScopeUncertain ? null : _historyPage;
  int? get pendingIntentCount =>
      memberScopeUncertain ? null : _pendingIntentCount;
  final List<NotificationEvent> notificationEvents;
  final NotificationPreferences notificationPreferences;
  final bool smsAccessEnabled;
  final bool smsAccessDenied;
  final bool smsSyncNeedsAttention;
  final bool smsQueueOverflowed;
  final bool isLoading;
  final bool usingStaleCache;
  final bool publicDiscoveryLoading;
  final bool publicDiscoveryUnavailable;
  final bool _financialObservationUncertain;
  bool get financialObservationUncertain =>
      memberScopeUncertain || _financialObservationUncertain;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastError;

  bool get hasInitialLoadFailure =>
      !isLoading &&
      (memberScopeUncertain ||
          (lastError != null &&
              !usingStaleCache &&
              lastSuccessfulSyncAt == null &&
              collections.isEmpty &&
              contributions.isEmpty &&
              paymentIntents.isEmpty));

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
    Object? pendingIntentCount = _unsetDateTimeField,
    List<NotificationEvent>? notificationEvents,
    NotificationPreferences? notificationPreferences,
    bool? smsAccessEnabled,
    bool? smsAccessDenied,
    bool? smsSyncNeedsAttention,
    bool? smsQueueOverflowed,
    bool? isLoading,
    bool? usingStaleCache,
    bool? publicDiscoveryLoading,
    bool? publicDiscoveryUnavailable,
    bool? financialObservationUncertain,
    bool? memberScopeUncertain,
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
      pendingIntentCount: identical(pendingIntentCount, _unsetDateTimeField)
          ? this.pendingIntentCount
          : pendingIntentCount as int?,
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
      publicDiscoveryLoading:
          publicDiscoveryLoading ?? this.publicDiscoveryLoading,
      publicDiscoveryUnavailable:
          publicDiscoveryUnavailable ?? this.publicDiscoveryUnavailable,
      financialObservationUncertain:
          financialObservationUncertain ?? this.financialObservationUncertain,
      memberScopeUncertain: memberScopeUncertain ?? this.memberScopeUncertain,
      lastSuccessfulSyncAt: identical(lastSuccessfulSyncAt, _unsetDateTimeField)
          ? this.lastSuccessfulSyncAt
          : lastSuccessfulSyncAt as DateTime?,
      lastError: lastError,
    );
  }
}
