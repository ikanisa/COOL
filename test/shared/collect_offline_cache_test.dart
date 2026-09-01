import 'dart:convert';

import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default cache discards the retired payment snapshot', () async {
    SharedPreferences.setMockInitialValues({
      'collect.offline_snapshot.v1': jsonEncode({
        'version': 1,
        'saved_at': '2026-08-20T10:00:00Z',
        'current_profile': {
          'id': 'legacy-user',
          'public_id': '123456',
          'whatsapp_phone': '+250788123456',
          'momo_number': '0788123456',
        },
      }),
    });

    const cache = CollectOfflineCache();
    expect(await cache.read(), isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('collect.offline_snapshot.v1'), isFalse);
  });

  test('Rwanda cache round trip preserves MoMo route and receiver', () async {
    SharedPreferences.setMockInitialValues({});
    const cache = CollectOfflineCache();
    final repository = CollectRepository.fixture(
      fixtureNow: DateTime.utc(2026, 8, 21, 10),
    );
    final intent = repository.state.paymentIntents.single;
    final snapshot = CollectOfflineSnapshot(
      savedAt: DateTime.utc(2026, 8, 21, 11),
      currentProfile: repository.state.currentProfile,
      collections: repository.state.collections,
      paymentIntents: [intent],
      contributions: repository.state.contributions,
    );

    await cache.save(snapshot);
    final restored = await cache.read();

    expect(restored, isNotNull);
    final restoredIntent = restored!.paymentIntents.single;
    expect(restoredIntent.rail, 'rwanda_momo');
    expect(restoredIntent.expectedAmountMinor, intent.expectedAmountMinor);
    expect(restoredIntent.currency, 'RWF');
    expect(restoredIntent.receiverMomoNumber, intent.receiverMomoNumber);
    expect(restoredIntent.momoNetwork, 'mtn_momo');

    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('collect.offline_snapshot.v2');
    expect(raw, isNotNull);
    final payload = Map<String, dynamic>.from(jsonDecode(raw!) as Map);
    expect(payload['version'], 2);
    expect(
      Map<String, dynamic>.from(payload['current_profile'] as Map).keys,
      containsAll(<String>[
        'id',
        'public_id',
        'whatsapp_phone',
        'display_name',
        'country_code',
        'currency_code',
        'momo_provider',
        'momo_number',
        'revolut_name',
        'revolut_link',
        'revolut_account',
      ]),
    );
    expect(restored.currentProfile?.countryCode, 'RW');
    expect(restored.currentProfile?.currencyCode, 'RWF');
    final cachedIntent = Map<String, dynamic>.from(
      (payload['payment_intents'] as List).single as Map,
    );
    expect(cachedIntent['amount_minor'], intent.expectedAmountMinor);
    expect(cachedIntent['rail'], 'rwanda_momo');
    expect(cachedIntent['receiver_momo_number'], intent.receiverMomoNumber);
  });
}
