part of 'collect_repository.dart';

abstract interface class MemberGroupAccessState implements MemberAccountState {
  List<CollectCollection> get collections;
  bool get memberScopeUncertain;
  bool get usingStaleCache;
}

abstract interface class MemberGroupDirectoryState
    implements MemberGroupAccessState {
  bool get hasRecentMemberActivity;
  bool get hasMemberHistory;
  bool get hasInitialLoadFailure;
  bool get financialObservationUncertain;
  bool get publicDiscoveryLoading;
  bool get publicDiscoveryUnavailable;
  DateTime? get lastSuccessfulSyncAt;
  String? get lastError;
}

abstract interface class MemberGroupRepository {
  int get sessionGeneration;
  bool get isLive;
  CollectCollection? maybeCollectionById(String id);
  CollectionSummary? summaryFor(String collectionId);
  Future<void> loadInitial();
  Future<CollectCollection> joinPublicGroup(String collectionId);
  Future<CollectCollection> joinGroupBySlug(String slug);
}
