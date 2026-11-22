import 'dart:convert';

import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CollectOfflineSnapshot _snapshot() => CollectOfflineSnapshot(
  savedAt: DateTime.utc(2026, 9, 27, 11),
  currentProfile: null,
  collections: const [],
  paymentIntents: [
    PaymentIntentModel(
      id: 'test-intent',
      collectionId: 'test-group',
      expectedAmountRwf: 2500,
      status: 'pending',
      createdAt: DateTime.utc(2000, 1, 1),
      expiresAt: DateTime.utc(2000, 1, 2),
    ),
  ],
  contributions: [
    Contribution(
      id: 'test-contribution',
      collectionId: 'test-group',
      amountRwf: 2500,
      supporterLabel: 'Collect member',
      createdAt: DateTime.utc(2026, 9, 26, 9),
      transactionId: 'redacted-in-cache',
      isCurrentUserContribution: true,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('existing v4 serializer round-trips money and original instants', () {
    final original = _snapshot();
    final wire = jsonDecode(jsonEncode(original.toJson())) as Map;
    final restored = CollectOfflineSnapshot.fromJson(
      Map<String, dynamic>.from(wire),
    );
    expect(restored.savedAt, original.savedAt);
    expect(restored.paymentIntents.single.expectedAmountMinor, 2500);
    expect(restored.paymentIntents.single.createdAt, DateTime.utc(2000, 1, 1));
    expect(restored.paymentIntents.single.expiresAt, DateTime.utc(2000, 1, 2));
    expect(restored.contributions.single.amountMinor, 2500);
    expect(
      restored.contributions.single.createdAt,
      DateTime.utc(2026, 9, 26, 9),
    );
    expect(restored.contributions.single.isCurrentUserContribution, isTrue);
    // Keep the existing cache's deliberate transaction-reference redaction.
    expect(restored.contributions.single.transactionId, isNull);
  });

  test('restored expired intent is not made actionable', () {
    final restored = CollectOfflineSnapshot.fromJson(_snapshot().toJson());
    expect(restored.paymentIntents.single.isAwaitingTransfer, isFalse);
  });

  test('invalid cached contribution is not silently dropped or zeroed', () {
    final payload = _snapshot().toJson();
    (payload['contributions'] as List).single.remove('amount_rwf');
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsFormatException,
    );
  });

  test('invalid cached intent does not become a pending zero intent', () {
    final payload = _snapshot().toJson();
    (payload['payment_intents'] as List).single['amount_minor'] = 0;
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsFormatException,
    );
  });

  test('cache cannot replace missing payment time with current time', () {
    final payload = _snapshot().toJson();
    (payload['payment_intents'] as List).single.remove('expires_at');
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsFormatException,
    );
  });

  test('cache cannot invent pending status', () {
    final payload = _snapshot().toJson();
    (payload['payment_intents'] as List).single.remove('status');
    expect(
      () => CollectOfflineSnapshot.fromJson(payload),
      throwsFormatException,
    );
  });

  test('valid serialized cache remains readable through preferences', () async {
    const key = 'test.payment-decoding.valid';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode(_snapshot().toJson()),
    });
    final restored = await const CollectOfflineCache(
      preferencesKey: key,
    ).read();
    expect(restored, isNotNull);
    expect(restored!.contributions.single.amountMinor, 2500);
    expect(restored.paymentIntents.single.isAwaitingTransfer, isFalse);
  });

  test(
    'existing fail-closed cache read rejects corrupted payment data',
    () async {
      const key = 'test.payment-decoding.invalid';
      final payload = _snapshot().toJson();
      (payload['contributions'] as List).single['amount_rwf'] = 2500.75;
      SharedPreferences.setMockInitialValues({key: jsonEncode(payload)});
      final restored = await const CollectOfflineCache(
        preferencesKey: key,
      ).read();
      expect(restored, isNull);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(key), isFalse);
    },
  );
}
