part of 'collect_repository.dart';

CollectState _emptyCollectState() {
  return const CollectState(
    currentProfile: null,
    collections: [],
    paymentIntents: [],
    contributions: [],
  );
}

CollectState _fixtureCollectState() {
  final now = DateTime.now();
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
    receiverMomoNumber: '+250788123456',
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
    receiverMomoNumber: '+250788123456',
    isPublic: true,
    createdAt: now.subtract(const Duration(days: 1)),
  );
  return CollectState(
    currentProfile: user,
    collections: [church, team],
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
    contributions: [
      Contribution(
        id: 'pay-1',
        collectionId: church.id,
        amountRwf: 25000,
        supporterLabel: 'Collect ID 038491',
        createdAt: now.subtract(const Duration(hours: 5)),
        transactionId: 'MTN12345',
      ),
      Contribution(
        id: 'pay-2',
        collectionId: church.id,
        amountRwf: 10000,
        supporterLabel: 'Collect ID 038491',
        createdAt: now.subtract(const Duration(hours: 2)),
        transactionId: 'MTN12346',
      ),
    ],
  );
}
