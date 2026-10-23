import 'package:collect_app/core/payments/momo_ussd_intent_guard.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 9, 28, 12);

PaymentIntentModel _intent({
  String id = 'intent-one',
  String collectionId = 'group-one',
  int amount = 6000,
  String receiver = '0788123456',
  String receiverHash = 'receiver-hash',
  String label = 'Group receiver',
  String network = 'mtn_momo',
  String senderHash = 'sender-hash',
  String status = 'pending',
  DateTime? expiresAt,
}) => PaymentIntentModel(
  id: id,
  collectionId: collectionId,
  expectedAmountRwf: amount,
  receiverMomoNumber: receiver,
  receiverMomoNumberHash: receiverHash,
  receiverMomoLabel: label,
  momoNetwork: network,
  senderPhoneHash: senderHash,
  status: status,
  createdAt: _now.subtract(const Duration(minutes: 5)),
  expiresAt: expiresAt ?? _now.add(const Duration(hours: 1)),
);

void main() {
  test('unchanged server-confirmed MoMo intent can open USSD', () {
    expect(
      preparedMomoIntentStillActionable(_intent(), _intent(), now: _now),
      isTrue,
    );
  });

  test('changed account or route cannot reuse a prepared USSD prompt', () {
    final prepared = _intent();
    for (final current in [
      _intent(id: 'intent-for-another-account'),
      _intent(collectionId: 'another-group'),
      _intent(receiver: '0788999999'),
      _intent(receiverHash: 'new-receiver-hash'),
      _intent(label: 'New receiver'),
      _intent(network: 'airtel_money'),
      _intent(senderHash: 'new-sender-hash'),
    ]) {
      expect(
        preparedMomoIntentStillActionable(prepared, current, now: _now),
        isFalse,
      );
    }
  });

  test('changed amount, final status or expiry cannot open USSD', () {
    final prepared = _intent();
    for (final current in [
      _intent(amount: 6500),
      _intent(status: 'posted'),
      _intent(expiresAt: _now),
      _intent(expiresAt: _now.add(const Duration(hours: 2))),
      _intent(receiver: ''),
    ]) {
      expect(
        preparedMomoIntentStillActionable(prepared, current, now: _now),
        isFalse,
      );
    }
    expect(
      preparedMomoIntentStillActionable(
        _intent(expiresAt: _now),
        _intent(expiresAt: _now),
        now: _now,
      ),
      isFalse,
    );
  });
}
