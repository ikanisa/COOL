import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collection creation defaults to private', () async {
    final repo = CollectRepository();
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Wedding support',
      description: 'Family collection',
      category: 'Wedding',
      targetAmountRwf: 100000,
      receiverMomoNumber: '+250788123456',
    );

    expect(collection.visibility, 'private');
    expect(collection.publicStatus, 'private');
  });

  test(
    'profile and collection media URLs are stored safely in local mode',
    () async {
      final repo = CollectRepository();
      await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
      await repo.updateProfile(
        displayName: 'Jane',
        momoNumber: '+250788123456',
        anonymityDefault: 'display_name',
        avatarUrl: 'https://example.com/avatar.jpg',
      );
      final collection = await repo.createCollection(
        title: 'Medical support',
        description: 'Help with treatment',
        category: 'Medical support',
        targetAmountRwf: 500000,
        receiverMomoNumber: '+250788123456',
        coverImageUrl: 'https://example.com/cover.jpg',
        isRecurring: true,
      );

      expect(
        repo.state.currentProfile?.avatarUrl,
        'https://example.com/avatar.jpg',
      );
      expect(collection.coverImageUrl, 'https://example.com/cover.jpg');
      expect(collection.isRecurring, isTrue);
      expect(collection.recurringRule?['frequency'], 'monthly');
    },
  );

  test('public collection request does not publish in the main app', () async {
    final repo = CollectRepository.seeded();
    final privateCollection = repo.state.collections.firstWhere(
      (item) => item.publicStatus == 'private',
    );

    expect(
      repo.publicCollections.any((item) => item.id == privateCollection.id),
      isFalse,
    );
    await repo.requestPublic(privateCollection.id);
    expect(
      repo.publicCollections.any((item) => item.id == privateCollection.id),
      isFalse,
    );
    expect(
      repo.collectionById(privateCollection.id).publicStatus,
      'public_requested',
    );
  });

  test(
    'payment intent and confirmation create anonymized contribution',
    () async {
      final repo = CollectRepository.seeded();
      final collection = repo.state.collections.first;
      final intent = await repo.createPaymentIntent(
        PaymentIntentDraft(
          collectionId: collection.id,
          amountRwf: 5000,
          anonymityChoice: 'anonymous',
        ),
      );

      expect(intent.status, 'pending');
      expect(intent.contributionCode, hasLength(6));
      final contribution = await repo.markIntentPaid(
        intent.id,
        transactionId: 'TX-100',
      );
      expect(contribution?.supporterLabel, 'Anonymous supporter');
      expect(repo.intentById(intent.id).status, 'matched');
    },
  );

  test('payment intent exposes configurable instruction copy', () async {
    final repo = CollectRepository.seeded();
    final intent = await repo.createPaymentIntent(
      const PaymentIntentDraft(
        collectionId: 'col-church',
        amountRwf: 7500,
        anonymityChoice: 'public_id',
      ),
    );

    expect(intent.instructionBody, contains(intent.contributionCode));
    expect(intent.instructionBody, contains(intent.receiverMomoNumber));
    expect(intent.receiverLabel, 'St Michel treasury');
  });

  test(
    'collection invite accepts Collect public IDs and returns private token',
    () async {
      final repo = CollectRepository.seeded();
      final invite = await repo.createInvite(
        collectionId: 'col-church',
        target: '038491',
        role: 'member',
      );

      expect(invite.invitedTarget, 'User #038491');
      expect(invite.inviteToken, isNotEmpty);
      expect(invite.role, 'member');
    },
  );

  test('manual SMS without deterministic match goes to review', () async {
    final repo = CollectRepository.seeded();
    final event = await repo.ingestManualSms(
      'You have received 10,000 RWF from Jane. TxId ABC123. Balance is 500000 RWF.',
    );

    expect(event.amountRwf, 10000);
    expect(event.transactionId, 'ABC123');
    expect(event.allocationStatus, 'needs_review');
  });
}
