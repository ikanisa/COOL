import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/models/member_history_page.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final contribution = Contribution.fromJson(const {
    'id': 'momo-1',
    'collection_id': 'group-1',
    'amount_minor': 3000,
    'currency': 'RWF',
    'posted_at': '2026-09-02T10:00:00Z',
  });

  test('Rwanda MoMo history keeps whole-franc totals', () {
    final page = MemberHistoryPage.fromJson(
      const {
        'total_count': 1,
        'totals': {'RWF': 3000},
        'own_totals': {'RWF': 3000},
        'own_collection_ids': ['group-1'],
        'revision': '11111111111111111111111111111111',
        'next_cursor': null,
      },
      [contribution],
    );
    expect(page.items.single.currency, 'RWF');
    expect(page.totals, {'RWF': 3000});
    expect(page.ownTotals, {'RWF': 3000});
  });

  test('foreign currency history fails closed', () {
    expect(
      () => MemberHistoryPage.fromJson(
        const {
          'total_count': 1,
          'totals': {'RWF': 3000, 'EUR': 100},
          'own_totals': {'RWF': 3000},
          'own_collection_ids': ['group-1'],
          'revision': '11111111111111111111111111111111',
          'next_cursor': null,
        },
        [contribution],
      ),
      throwsFormatException,
    );
  });

  test('offline cache round trip retains Rwanda MoMo history', () async {
    const cache = CollectOfflineCache(
      preferencesKey: 'collect.rwanda.history.test',
    );
    final page = MemberHistoryPage.fromJson(
      const {
        'total_count': 1,
        'totals': {'RWF': 3000},
        'own_totals': {'RWF': 3000},
        'own_collection_ids': ['group-1'],
        'revision': '11111111111111111111111111111111',
        'next_cursor': null,
      },
      [contribution],
    );
    await cache.save(
      CollectOfflineSnapshot(
        savedAt: DateTime.utc(2026, 9, 2),
        currentProfile: null,
        collections: const [],
        paymentIntents: const [],
        contributions: [contribution],
        historyPage: page,
      ),
    );
    final restored = await cache.read();
    expect(restored!.historyPage!.totals, {'RWF': 3000});
    expect(restored.contributions.single.amountMinor, 3000);
  });
}
