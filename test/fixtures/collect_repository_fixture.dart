import 'dart:math';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';

/// Synthetic data for isolated tests and explicit preview targets only.
/// Never import this file from lib or use these records as a backend fallback.
class FixtureCollectRepository extends CollectRepository {
  FixtureCollectRepository({
    super.supabase,
    super.smsAccessChannel,
    bool seeded = true,
    DateTime? fixtureNow,
    int fixtureCollectionCount = 2,
    int fixtureContributionCount = 2,
    CollectProfile? profileOverride,
    super.fixtureAdditionalMembers,
    super.offlineCache,
  }) : super.fixture(
         initialState: seeded
             ? _fixtureCollectState(
                 fixtureNow: fixtureNow,
                 collectionCount: fixtureCollectionCount,
                 contributionCount: fixtureContributionCount,
                 profileOverride: profileOverride,
               )
             : const CollectState(
                 currentProfile: null,
                 collections: [],
                 paymentIntents: [],
                 contributions: [],
               ),
       );
}

CollectState _fixtureCollectState({
  DateTime? fixtureNow,
  int collectionCount = 2,
  int contributionCount = 2,
  CollectProfile? profileOverride,
}) {
  final now = fixtureNow ?? DateTime.now();
  final user =
      profileOverride ??
      const CollectProfile(
        id: 'local-user',
        publicId: '038491',
        whatsappPhone: '+250788123456',
        countryCode: 'RW',
        currencyCode: 'RWF',
        momoProvider: 'mtn_momo',
        momoNumber: '0788123456',
      );
  final ownedQaGroup = CollectCollection(
    id: 'qa-private-group',
    slug: 'qa-private-group',
    creatorUserId: user.id,
    title: 'QA private group',
    description: 'Synthetic private group for isolated automated tests only.',
    collectionType: CollectionType.church,
    categorySubtype: 'building_fund',
    purposeLabel: 'Community support',
    receiverMomoNumber: '0788123456',
    receiverDisplayLabel: 'QA MoMo receiver',
    receiverNetwork: 'mtn_momo',
    isPublic: false,
    isCurrentUserMember: true,
    createdAt: now.subtract(const Duration(days: 3)),
  );
  final publicSportFixture = CollectCollection(
    id: 'col-public-sport-fixture',
    slug: 'public-sport-fixture',
    creatorUserId: 'platform',
    title: 'Gikundiro',
    description: 'Official Rayon Sports supporter group open to everyone.',
    collectionType: CollectionType.sport,
    categorySubtype: 'fan_club',
    purposeLabel: 'Club support',
    receiverMomoNumber: '008000',
    receiverDisplayLabel: 'Rayon Sports FC',
    receiverNetwork: 'mtn_momo',
    isPublic: true,
    isPlatformSponsored: true,
    isCurrentUserMember: false,
    createdAt: now.subtract(const Duration(days: 1)),
  );
  final publicSavingsFixture = CollectCollection(
    id: 'col-public-savings-fixture',
    slug: 'public-savings-fixture',
    creatorUserId: 'platform',
    title: 'Buri Munsi',
    description: 'Platform-sponsored group savings open to everyone.',
    collectionType: CollectionType.ikimina,
    categorySubtype: 'group_savings',
    purposeLabel: 'Group savings',
    receiverMomoNumber: '41258',
    receiverDisplayLabel: 'IKANISA LTD',
    receiverNetwork: 'mtn_momo',
    isPublic: true,
    isPlatformSponsored: true,
    isCurrentUserMember: false,
    createdAt: now.subtract(const Duration(days: 2)),
  );
  final effectiveCollectionCount = max(3, collectionCount);
  final effectiveContributionCount = max(2, contributionCount);
  final denseCollections = List<CollectCollection>.generate(
    effectiveCollectionCount - 3,
    (index) {
      final number = index + 3;
      final type = CollectionType.values[index % CollectionType.values.length];
      return CollectCollection(
        id: 'col-fixture-$number',
        slug: 'fixture-group-$number',
        creatorUserId: user.id,
        title: 'Community group $number',
        description:
            'Representative local fixture data for scrolling and rendering checks.',
        collectionType: type,
        categorySubtype: type.storageValue,
        purposeLabel: type.shortPurpose,
        receiverMomoNumber: '0788123456',
        receiverDisplayLabel: 'MTN MoMo receiver',
        receiverNetwork: 'mtn_momo',
        isPublic: false,
        createdAt: now.subtract(Duration(days: number)),
      );
    },
    growable: false,
  );
  final collections = [
    ownedQaGroup,
    publicSportFixture,
    publicSavingsFixture,
    ...denseCollections,
  ];
  final contributions = <Contribution>[
    Contribution(
      id: 'pay-1',
      collectionId: ownedQaGroup.id,
      amountRwf: 25000,
      supporterLabel: 'Collect ID 038491',
      isCurrentUserContribution: true,
      createdAt: now.subtract(const Duration(hours: 5)),
      transactionId: 'MOMO-E2E-12345',
      currency: 'RWF',
    ),
    Contribution(
      id: 'pay-2',
      collectionId: ownedQaGroup.id,
      amountRwf: 10000,
      supporterLabel: 'Collect ID 038491',
      isCurrentUserContribution: true,
      createdAt: now.subtract(const Duration(hours: 2)),
      transactionId: 'MOMO-E2E-12346',
      currency: 'RWF',
    ),
    for (var index = 0; index < effectiveContributionCount - 2; index++)
      Contribution(
        id: 'pay-fixture-${index + 3}',
        collectionId: collections[index % collections.length].id,
        amountRwf: 1000 * ((index % 25) + 1),
        supporterLabel:
            'Collect ID ${(100000 + index).toString().padLeft(6, '0')}',
        createdAt: now.subtract(Duration(minutes: (index + 1) * 7)),
        transactionId: 'MOMO-FIXTURE-${(index + 3).toString().padLeft(5, '0')}',
        currency: 'RWF',
      ),
  ];
  return CollectState(
    currentProfile: user,
    collections: collections,
    paymentIntents: [
      PaymentIntentModel(
        id: 'intent-render',
        collectionId: ownedQaGroup.id,
        expectedAmountMinor: 15000,
        rail: 'rwanda_momo',
        receiverMomoNumber: '0788123456',
        receiverMomoNumberHash: 'fixture-receiver-hash',
        receiverMomoLabel: 'QA MoMo receiver',
        momoNetwork: 'mtn_momo',
        senderPhoneHash: 'fixture-sender-hash',
        currency: 'RWF',
        status: 'pending',
        createdAt: now.subtract(const Duration(minutes: 8)),
        expiresAt: now.add(const Duration(hours: 23)),
      ),
    ],
    contributions: contributions,
    notificationEvents: [
      NotificationEvent(
        id: 'notif-contribution-confirmed',
        userId: user.id,
        collectionId: ownedQaGroup.id,
        type: 'contribution_confirmed',
        title: 'Contribution confirmed',
        body: 'RWF 25,000 was reconciled and recorded on the ledger.',
        status: 'read',
        createdAt: now.subtract(const Duration(hours: 5)),
        readAt: now.subtract(const Duration(hours: 4)),
      ),
      NotificationEvent(
        id: 'notif-app-update',
        userId: user.id,
        type: 'app_update',
        title: 'Collect updated',
        body: 'Group records refresh after MoMo receipt reconciliation.',
        status: 'queued',
        createdAt: now.subtract(const Duration(minutes: 8)),
      ),
      NotificationEvent(
        id: 'notif-security',
        userId: user.id,
        type: 'security_notice',
        title: 'Security notice',
        body: 'Raw MoMo receipts and payer details stay private.',
        status: 'sent',
        createdAt: now.subtract(const Duration(hours: 1)),
        sentAt: now.subtract(const Duration(hours: 1)),
      ),
    ],
  );
}
