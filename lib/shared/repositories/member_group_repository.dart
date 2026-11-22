import '../models/collect_models.dart';
import 'member_account_repository.dart';

abstract interface class MemberGroupAccessState implements MemberAccountState {
  List<CollectCollection> get collections;
  bool get memberScopeUncertain;
  bool get usingStaleCache;
}

abstract interface class MemberGroupDirectoryState
    implements MemberGroupAccessState {
  bool get hasRecordedContributions;
  bool get hasRecentMemberActivity;
  bool get hasMemberHistory;
  bool get hasInitialLoadFailure;
  bool get financialObservationUncertain;
  bool get publicDiscoveryLoading;
  bool get publicDiscoveryUnavailable;
  DateTime? get lastSuccessfulSyncAt;
  String? get lastError;
}

typedef MemberGroupSession = ({
  MemberGroupRepository repository,
  int generation,
  String? profileId,
});

abstract interface class MemberGroupRepository {
  int get sessionGeneration;
  bool get isLive;
  CollectCollection? maybeCollectionById(String id);
  CollectionSummary? summaryFor(String collectionId);
  Future<List<CollectMember>> membersForCollection(String collectionId);
  Future<void> loadInitial();
  Future<CollectCollection> joinPublicGroup(String collectionId);
  Future<CollectCollection> joinGroupBySlug(String slug);
}

abstract interface class MemberGroupManagementRepository {
  Future<CollectCollection> createCollection({
    required String title,
    required String description,
    CollectionType collectionType = CollectionType.ikimina,
    String? categorySubtype,
    String? purposeLabel,
    String? accentColorHex,
    String? imageUrl,
    bool isPublic = false,
    required String requestId,
  });

  Future<CollectCollection> updateCollectionProfile({
    required String collectionId,
    required String title,
    required String description,
    required String recurringCadence,
    CollectionType? collectionType,
    String? categorySubtype,
    String? purposeLabel,
    String? accentColorHex,
    String? imageUrl,
    required bool isPublic,
    bool isRecurring = true,
  });

  Future<void> inviteCollectionAdmin({
    required String collectionId,
    required String publicId,
  });

  Future<void> transferCollectionOwnership({
    required String collectionId,
    required String publicId,
  });

  Future<void> archiveCollection(String collectionId);
  Future<OwnerGroupHealth> ownerHealthFor(String collectionId);
}

abstract interface class MemberGroupInvitationRepository {
  CollectInvitationAuthority captureGroupInvitationAuthority(
    String collectionId, {
    bool requireOwner = false,
  });
  Future<String> getGroupShareCode(String collectionId);
  Future<String> rotateGroupShareCode(String collectionId);
}

/// Authority for one invitation operation. Once lost, it cannot be recovered
/// by returning to the same account or group.
abstract interface class CollectInvitationAuthority {
  bool get isCurrent;
  void check();
  void dispose();
}
