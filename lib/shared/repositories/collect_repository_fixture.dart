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
}) {
  final now = fixtureNow ?? DateTime.now();
  const user = CollectProfile(
    id: 'local-user',
    publicId: '038491',
    whatsappPhone: '+250788123456',
    momoNumber: '0788123456',
  );
  final church = CollectCollection(
    id: 'col-church',
    slug: 'st-michel-building-fund',
    creatorUserId: user.id,
    title: 'St Michel building fund',
    description:
        'Transparent support for materials, labor, and weekly updates from the building committee.',
    collectionType: CollectionType.church,
    categorySubtype: 'building_fund',
    purposeLabel: 'Building fund',
    receiverMomoNumber: '0788123456',
    receiverDisplayLabel: 'St Michel treasury',
    isPublic: true,
    createdAt: now.subtract(const Duration(days: 3)),
  );
  final team = CollectCollection(
    id: 'col-team',
    slug: 'kigali-lions-away-kit',
    creatorUserId: user.id,
    title: 'Kigali Lions away kit',
    description:
        'Fans are helping the team fund away jerseys and travel supplies for next month.',
    collectionType: CollectionType.sport,
    categorySubtype: 'fan_club',
    purposeLabel: 'Away kit support',
    receiverMomoNumber: '0788123456',
    isPublic: true,
    createdAt: now.subtract(const Duration(days: 1)),
  );
  final effectiveCollectionCount = max(2, collectionCount);
  final effectiveContributionCount = max(2, contributionCount);
  final denseCollections = List<CollectCollection>.generate(
    effectiveCollectionCount - 2,
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
        receiverDisplayLabel: 'Group $number treasury',
        isPublic: index.isEven,
        createdAt: now.subtract(Duration(days: number)),
      );
    },
    growable: false,
  );
  final collections = [church, team, ...denseCollections];
  final contributions = <Contribution>[
    Contribution(
      id: 'pay-1',
      collectionId: church.id,
      amountRwf: 25000,
      supporterLabel: 'Collect ID 038491',
      isCurrentUserContribution: true,
      createdAt: now.subtract(const Duration(hours: 5)),
      transactionId: 'MTN12345',
    ),
    Contribution(
      id: 'pay-2',
      collectionId: church.id,
      amountRwf: 10000,
      supporterLabel: 'Collect ID 038491',
      isCurrentUserContribution: true,
      createdAt: now.subtract(const Duration(hours: 2)),
      transactionId: 'MTN12346',
    ),
    for (var index = 0; index < effectiveContributionCount - 2; index++)
      Contribution(
        id: 'pay-fixture-${index + 3}',
        collectionId: collections[index % collections.length].id,
        amountRwf: 1000 * ((index % 25) + 1),
        supporterLabel:
            'Collect ID ${(100000 + index).toString().padLeft(6, '0')}',
        createdAt: now.subtract(Duration(minutes: (index + 1) * 7)),
        transactionId: 'FIXTURE${(index + 3).toString().padLeft(5, '0')}',
      ),
  ];
  return CollectState(
    currentProfile: user,
    collections: collections,
    paymentIntents: [
      PaymentIntentModel(
        id: 'intent-render',
        collectionId: church.id,
        expectedAmountRwf: 15000,
        receiverMomoNumber: church.receiverMomoNumber ?? user.momoNumber!,
        receiverLabel: church.receiverDisplayLabel,
        network: 'mtn',
        senderPhoneHash: HashUtils.phoneHash(user.momoNumber!),
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
        body: 'RWF 25,000 was recorded on the ledger.',
        status: 'read',
        createdAt: now.subtract(const Duration(hours: 5)),
        readAt: now.subtract(const Duration(hours: 4)),
      ),
      NotificationEvent(
        id: 'notif-app-update',
        userId: user.id,
        type: 'app_update',
        title: 'Collect updated',
        body: 'Group records refresh after confirmed MoMo SMS matching.',
        status: 'queued',
        createdAt: now.subtract(const Duration(minutes: 8)),
      ),
      NotificationEvent(
        id: 'notif-security',
        userId: user.id,
        type: 'security_notice',
        title: 'Security notice',
        body: 'Receiver details stay private.',
        status: 'sent',
        createdAt: now.subtract(const Duration(hours: 1)),
        sentAt: now.subtract(const Duration(hours: 1)),
      ),
    ],
  );
}
