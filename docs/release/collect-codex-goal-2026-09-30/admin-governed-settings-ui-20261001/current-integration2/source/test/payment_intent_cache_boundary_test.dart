import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CollectOfflineSnapshot _snapshot() => CollectOfflineSnapshot(
  savedAt: DateTime.utc(2026, 1, 1, 12),
  currentProfile: null,
  collections: const [],
  paymentIntents: [
    PaymentIntentModel(
      id: 'synthetic-intent',
      collectionId: 'synthetic-group',
      expectedAmountMinor: 1000,
      status: 'expired',
      createdAt: DateTime.utc(2026, 1, 1, 10),
      expiresAt: DateTime.utc(2026, 1, 1, 11),
    ),
  ],
  contributions: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('existing v4 UTC intent serialization round-trips', () {
    final payload = _snapshot().toJson();
    final before = jsonEncode(payload);
    final restored = CollectOfflineSnapshot.fromJson(payload);
    final intent = restored.paymentIntents.single;
    expect(intent.expectedAmountMinor, 1000);
    expect(intent.status, 'expired');
    expect(intent.createdAt, DateTime.utc(2026, 1, 1, 10));
    expect(intent.expiresAt, DateTime.utc(2026, 1, 1, 11));
    expect(jsonEncode(payload), before);
  });
  test('legacy amount alias in cached intents remains supported', () {
    final payload = _snapshot().toJson();
    final intent = (payload['payment_intents'] as List).single as Map;
    intent['expected_amount_rwf'] = intent.remove('amount_minor');
    expect(
      CollectOfflineSnapshot.fromJson(
        payload,
      ).paymentIntents.single.expectedAmountMinor,
      1000,
    );
  });
  test('legacy transfer destination is not inferred as Rwanda MoMo', () {
    final payload = _snapshot().toJson();
    final intent = (payload['payment_intents'] as List).single as Map;
    intent.remove('rail');
    intent.remove('currency');
    intent['destination_snapshot'] = {'masked_account': 'synthetic'};
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsFormatException,
    );
  });
  test('a missing cached status is rejected, not inferred pending', () {
    final payload = _snapshot().toJson();
    ((payload['payment_intents'] as List).single as Map).remove('status');
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsFormatException,
    );
  });
  test('a missing cached amount is rejected, not inferred zero', () {
    final payload = _snapshot().toJson();
    ((payload['payment_intents'] as List).single as Map).remove('amount_minor');
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsFormatException,
    );
  });
  test('valid intent survives mocked preferences save and read', () async {
    const key = 'synthetic.intent-decoding.valid';
    SharedPreferences.setMockInitialValues({'unrelated-setting': 'keep'});
    const cache = CollectOfflineCache(preferencesKey: key);
    await cache.save(_snapshot());
    final restored = await cache.read();
    expect(restored, isNotNull);
    expect(restored!.paymentIntents.single.expectedAmountMinor, 1000);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('unrelated-setting'), 'keep');
  });
  test(
    'invalid intent retains the existing whole-snapshot rejection policy',
    () async {
      const key = 'synthetic.intent-decoding.invalid';
      final payload = _snapshot().toJson();
      ((payload['payment_intents'] as List).single as Map)['amount_minor'] =
          1.5;
      SharedPreferences.setMockInitialValues({
        key: jsonEncode(payload),
        'unrelated-setting': 'keep',
      });
      const cache = CollectOfflineCache(preferencesKey: key);
      expect(await cache.read(), isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(key), isFalse);
      expect(preferences.getString('unrelated-setting'), 'keep');
    },
  );
}
