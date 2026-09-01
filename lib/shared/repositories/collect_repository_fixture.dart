part of 'collect_repository.dart';

CollectState _emptyCollectState() {
  return const CollectState(
    currentProfile: null,
    collections: [],
    paymentIntents: [],
    contributions: [],
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
        displayName: 'Collect member',
        countryCode: 'RW',
        currencyCode: 'RWF',
        momoProvider: 'mtn_momo',
        momoNumber: '0788123456',
      );
  final church = CollectCollection(
    id: 'col-church',
    slug: 'st-michel-building-fund',
    creatorUserId: user.id,
    title: 'St Michel building fund',
    description: 'A member-created private group for parish support.',
    collectionType: CollectionType.church,
    categorySubtype: 'building_fund',
    purposeLabel: 'Community support',
    receiverMomoNumber: '0788123456',
    receiverDisplayLabel: 'St Michel MTN MoMo',
    receiverNetwork: 'mtn_momo',
    isPublic: false,
    isCurrentUserMember: true,
    createdAt: now.subtract(const Duration(days: 3)),
  );
  final team = CollectCollection(
    id: 'col-team',
    slug: 'gikundiro',
    creatorUserId: 'platform',
    title: 'Gikundiro',
    description:
        'A platform-sponsored public supporters group for transparent club contributions.',
    collectionType: CollectionType.sport,
    categorySubtype: 'fan_club',
    purposeLabel: 'Club support',
    receiverMomoNumber: '0788123456',
    receiverDisplayLabel: 'Gikundiro MTN MoMo',
    receiverNetwork: 'mtn_momo',
    isPublic: true,
    isCurrentUserMember: true,
    createdAt: now.subtract(const Duration(days: 1)),
  );
  final buriMunsi = CollectCollection(
    id: 'col-buri-munsi',
    slug: 'buri-munsi',
    creatorUserId: 'platform',
    title: 'Buri Munsi',
    description:
        'A platform-sponsored public group with transparent contribution updates.',
    collectionType: CollectionType.church,
    categorySubtype: 'building_fund',
    purposeLabel: 'Community support',
    receiverMomoNumber: '0788123456',
    receiverDisplayLabel: 'Buri Munsi MTN MoMo',
    receiverNetwork: 'mtn_momo',
    isPublic: true,
    isCurrentUserMember: true,
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
  final collections = [church, team, buriMunsi, ...denseCollections];
  final contributions = <Contribution>[
    Contribution(
      id: 'pay-1',
      collectionId: church.id,
      amountRwf: 25000,
      supporterLabel: 'Collect ID 038491',
      isCurrentUserContribution: true,
      createdAt: now.subtract(const Duration(hours: 5)),
      transactionId: 'MOMO-E2E-12345',
      currency: 'RWF',
    ),
    Contribution(
      id: 'pay-2',
      collectionId: church.id,
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
        collectionId: church.id,
        expectedAmountMinor: 15000,
        rail: 'rwanda_momo',
        receiverMomoNumber: '0788123456',
        receiverMomoNumberHash: 'fixture-receiver-hash',
        receiverMomoLabel: 'St Michel MTN MoMo',
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
        collectionId: church.id,
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
