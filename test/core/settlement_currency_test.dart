import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settlement precision is whole RWF', () {
    expect(formatMoneyMinor(12345, currency: 'RWF'), 'RWF 12,345');
    expect(formatCurrencyTotals({'RWF': 1000}), 'RWF 1,000');
    expect(formatCurrencyTotals({}), 'RWF 0');
  });

  test('Rwanda payloads default to RWF', () {
    final contribution = Contribution.fromJson(const {
      'id': 'contribution',
      'collection_id': 'group',
      'amount_rwf': 12345,
      'created_at': '2026-09-02T00:00:00Z',
    });
    expect(contribution.currency, 'RWF');
    expect(contribution.amountMinor, 12345);
    expect(
      CollectionSummary.fromJson(const {
        'amount_raised_rwf': 12345,
        'current_user_balance_rwf': 0,
      }).currency,
      'RWF',
    );
  });

  test('foreign contribution payloads are rejected', () {
    expect(
      () => Contribution.fromJson(const {
        'id': 'foreign-contribution',
        'collection_id': 'group',
        'amount_minor': 12345,
        'currency': 'EUR',
      }),
      throwsFormatException,
    );
  });
}
