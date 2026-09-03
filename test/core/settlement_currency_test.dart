import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settlement precision is RWF whole francs and EUR cents', () {
    expect(formatMoneyMinor(12345, currency: 'RWF'), 'RWF 12,345');
    expect(formatMoneyMinor(12345, currency: 'EUR'), 'EUR 123.45');
    expect(formatMoneyMinor(-12345, currency: 'EUR'), 'EUR -123.45');
    expect(formatMoneyMinor(5, currency: 'EUR'), 'EUR 0.05');
  });
  test('mixed-currency totals are never added or converted', () {
    expect(
      formatCurrencyTotals({'RWF': 1000, 'EUR': 12345}),
      'EUR 123.45 · RWF 1,000',
    );
    expect(formatCurrencyTotals({}, emptyCurrency: 'EUR'), 'EUR 0.00');
  });
  test('legacy Rwanda payloads default to RWF not EUR', () {
    final contribution = Contribution.fromJson(const {
      'id': 'contribution',
      'collection_id': 'group',
      'amount_rwf': 12345,
      'created_at': '2026-09-02T00:00:00Z',
    });
    expect(contribution.currency, 'RWF');
    expect(contribution.amountMinor, 12345);
    expect(
      CollectionSummary.fromJson(const {'amount_raised_rwf': 12345}).currency,
      'RWF',
    );
  });
  test('bank payloads preserve settlement currency and minor units', () {
    final contribution = Contribution.fromJson(const {
      'id': 'contribution',
      'collection_id': 'group',
      'amount_minor': 12345,
      'currency': 'EUR',
      'posted_at': '2026-09-02T00:00:00Z',
    });
    expect(contribution.currency, 'EUR');
    expect(contribution.amountMinor, 12345);
    final summary = CollectionSummary.fromJson(const {
      'amount_raised_minor': 12345,
      'currency': 'EUR',
    });
    expect(
      formatMoneyMinor(summary.amountRaisedMinor, currency: summary.currency),
      'EUR 123.45',
    );
  });
}
