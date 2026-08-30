import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('fixture groups use the single governed EUR beneficiary', () {
    final repository = CollectRepository.fixture();

    expect(repository.state.collections, isNotEmpty);
    for (final group in repository.state.collections) {
      expect(group.receiverDisplayLabel, 'Collect EUR bank account');
    }
    expect(repository.state.currentProfile?.whatsappPhone, isNotEmpty);
  });

  test('fixture destination is active, routable, and EUR SEPA', () async {
    final repository = CollectRepository.fixture();

    final destination = await repository.getBankTransferDestination();

    expect(destination.enabled, isTrue);
    expect(destination.isPlaceholder, isFalse);
    expect(destination.currency, 'EUR');
    expect(destination.transferScheme, 'sepa_credit_transfer');
    expect(destination.iban, isNotEmpty);
    expect(destination.beneficiaryName, isNotEmpty);
  });

  test(
    'profile country and currency change without changing WhatsApp identity',
    () async {
      final repository = CollectRepository.fixture();
      final verifiedWhatsApp = repository.state.currentProfile!.whatsappPhone;

      final european = await repository.updateCurrentProfile(
        displayName: 'Jean Bosco',
        countryCode: 'GB',
        revolutName: 'Jean Bosco',
      );

      expect(european.whatsappPhone, verifiedWhatsApp);
      expect(european.countryCode, 'GB');
      expect(european.currencyCode, 'GBP');
      expect(european.revolutName, 'Jean Bosco');
      expect(european.isEuropean, isTrue);
      expect(european.isComplete, isTrue);

      final rwanda = await repository.updateCurrentProfile(
        displayName: 'Jean Bosco',
        countryCode: 'RW',
      );

      expect(rwanda.whatsappPhone, verifiedWhatsApp);
      expect(rwanda.countryCode, 'RW');
      expect(rwanda.currencyCode, 'RWF');
      expect(rwanda.revolutName, isEmpty);
      expect(rwanda.isEuropean, isFalse);
    },
  );

  test('European profiles require a Revolut name', () async {
    final repository = CollectRepository.fixture();

    await expectLater(
      repository.updateCurrentProfile(
        displayName: 'Jean Bosco',
        countryCode: 'DE',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'bank transfer request snapshots destination and exact reference',
    () async {
      final repository = CollectRepository.fixture(
        fixtureNow: DateTime.now().toUtc(),
      );

      final intent = await repository.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 12345),
      );

      expect(intent.expectedAmountMinor, 12345);
      expect(intent.currency, 'EUR');
      expect(intent.status, 'awaiting_transfer');
      expect(intent.transferReference, matches(RegExp(r'^COL-[A-Z0-9]{10}$')));
      expect(intent.destination.enabled, isTrue);
      expect(intent.destination.isPlaceholder, isFalse);
      expect(intent.destination.iban, isNotEmpty);
    },
  );

  test('active request with the same group and amount is reused', () async {
    final repository = CollectRepository.fixture(
      fixtureNow: DateTime.now().toUtc(),
    );
    const draft = PaymentIntentDraft(
      collectionId: 'col-church',
      amountRwf: 9876,
    );

    final first = await repository.createPaymentIntent(draft);
    final second = await repository.createPaymentIntent(draft);

    expect(second.id, first.id);
    expect(
      repository.state.paymentIntents.where((item) => item.id == first.id),
      hasLength(1),
    );
  });

  test(
    'Revolut handoff remains pending and does not create a contribution',
    () async {
      final repository = CollectRepository.fixture(
        fixtureNow: DateTime.now().toUtc(),
      );
      final contributionCount = repository.state.contributions.length;
      final intent = await repository.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 5050),
      );

      await repository.markBankTransferHandoffOpened(intent.id);
      final updated = repository.intentById(intent.id);

      expect(updated.status, 'handoff_opened');
      expect(updated.isAwaitingTransfer, isTrue);
      expect(repository.state.contributions, hasLength(contributionCount));
    },
  );

  test('group creation uses the governed bank destination', () async {
    final repository = CollectRepository.fixture();

    final group = await repository.createCollection(
      title: 'EUR savings circle',
      description: 'Bank-transfer-only group',
      isPublic: true,
    );

    expect(group.receiverDisplayLabel, 'Collect EUR bank account');
    expect(group.isPublic, isFalse);
    expect(group.visibilityStatus, 'public_requested');
  });

  test('bank models parse minor units and destination snapshot', () {
    final intent = PaymentIntentModel.fromJson(const {
      'id': 'intent-1',
      'collection_id': 'col-church',
      'amount_minor': 7500,
      'currency': 'EUR',
      'transfer_reference': 'COL-ABC1234567',
      'status': 'received_unreconciled',
      'created_at': '2026-08-20T10:00:00Z',
      'expires_at': '2026-08-22T10:00:00Z',
      'destination_snapshot': {
        'id': 'bank-1',
        'beneficiary_name': 'IKANISA Collect',
        'iban': 'DE89370400440532013000',
        'iban_masked': 'DE89••••3000',
        'bic': 'COBADEFFXXX',
        'bank_name': 'Collect Bank',
        'currency': 'EUR',
        'enabled': true,
      },
    });

    expect(intent.expectedAmountMinor, 7500);
    expect(intent.status, 'received_unreconciled');
    expect(intent.destination.beneficiaryName, 'IKANISA Collect');
    expect(intent.destination.enabled, isTrue);
  });

  test('contribution parser uses reconciled bank amount and currency', () {
    final contribution = Contribution.fromJson(const {
      'payment_id': 'bank-transaction-1',
      'collection_id': 'col-church',
      'amount_minor': 15000,
      'currency': 'EUR',
      'contributor_public_id': '038491',
      'posted_at': '2026-08-20T11:00:00Z',
      'transaction_id': 'BANK-E2E-1',
      'is_current_user_contribution': true,
    });

    expect(contribution.amountMinor, 15000);
    expect(contribution.currency, 'EUR');
    expect(contribution.supporterLabel, 'Collect ID 038491');
    expect(contribution.isCurrentUserContribution, isTrue);
  });
}
