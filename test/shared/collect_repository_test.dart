import 'package:collect_app/core/security/sms_access_channel.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('group creation stores receiver MoMo from profile flow', () async {
    final repo = CollectRepository();
    await repo.signInWithOtp(phone: '+250788123456', otp: '123456');
    final collection = await repo.createCollection(
      title: 'Family group',
      description: 'Family support',
      receiverMomoNumber: '+250788123456',
    );

    expect(collection.receiverMomoNumber, '+250788123456');
  });

  test('payment intent stays pending for automated SMS allocation', () async {
    final repo = CollectRepository.seeded();
    final collection = repo.state.collections.first;
    final intent = await repo.createPaymentIntent(
      PaymentIntentDraft(collectionId: collection.id, amountRwf: 5000),
    );

    expect(intent.status, 'pending');
    expect(intent.contributionCode, hasLength(6));
    expect(repo.contributionsFor(collection.id), hasLength(2));
  });

  test(
    'payment intent exposes receiver context without manual instructions',
    () async {
      final repo = CollectRepository.seeded();
      final intent = await repo.createPaymentIntent(
        const PaymentIntentDraft(collectionId: 'col-church', amountRwf: 7500),
      );

      expect(intent.contributionCode, hasLength(6));
      expect(intent.receiverMomoNumber, '+250788123456');
      expect(intent.receiverLabel, 'St Michel treasury');
    },
  );

  test('shared group link opens by slug', () async {
    final repo = CollectRepository.seeded();
    final collection = await repo.joinGroupBySlug('st-michel-building-fund');

    expect(collection.id, 'col-church');
    expect(collection.title, 'St Michel building fund');
  });

  test(
    'pending Android SMS sync drains only when SMS access is enabled',
    () async {
      final channel = _FakeSmsAccessChannel(
        pending: const [
          SmsAccessEnvelope(
            rawSender: 'MTN MOMO',
            rawBody: 'You have received 5,000 RWF. TxId ABCD1234.',
            receivedAtDevice: '1',
          ),
        ],
      );
      final repo = CollectRepository.seeded(smsAccessChannel: channel);

      expect(await repo.syncPendingSmsAccess(), 0);
      expect(channel.drainCalls, 0);

      await repo.setSmsAccess(true);

      expect(await repo.syncPendingSmsAccess(), 1);
      expect(channel.drainCalls, 1);
    },
  );

  test('SMS access denial keeps group receiver ingestion disabled', () async {
    final repo = CollectRepository.seeded(
      smsAccessChannel: _FakeSmsAccessChannel(pending: const [], grant: false),
    );

    expect(await repo.setSmsAccess(true), isFalse);
    expect(repo.state.smsAccessEnabled, isFalse);
  });
}

class _FakeSmsAccessChannel extends SmsAccessChannel {
  _FakeSmsAccessChannel({required this.pending, this.grant = true});

  final List<SmsAccessEnvelope> pending;
  final bool grant;
  var enabled = false;
  var drainCalls = 0;

  @override
  Future<bool> setEnabled(bool enabled) async {
    this.enabled = enabled && grant;
    return this.enabled;
  }

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<List<SmsAccessEnvelope>> drainPendingSms() async {
    drainCalls += 1;
    return pending;
  }
}
