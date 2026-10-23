#!/usr/bin/env python3
"""Source-wiring checks ONLY; no Dart/Flutter execution is performed."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODELS = (ROOT / 'lib/shared/models/collect_models.dart').read_text()
PAYMENT = (ROOT / 'lib/shared/models/collect_payment_models.dart').read_text()
HELPER = (ROOT / 'lib/shared/models/collect_payment_json.dart').read_text()
SHARED = (ROOT / 'lib/core/data/exact_json_values.dart').read_text()
FACTORY = PAYMENT.split('factory PaymentIntentModel.fromJson(', 1)[1].split('\n}\n', 1)[0]
SCOPE = json.loads((ROOT / 'scripts/qa/candidate_check_scope.json').read_text())

class PaymentIntentSourceTests(unittest.TestCase):
    def test_part_wiring(self):
        self.assertEqual(MODELS.count("part 'collect_payment_json.dart';"), 1)
        self.assertTrue(HELPER.startswith("part of 'collect_models.dart';"))
        self.assertIn("import '../../core/data/exact_json_values.dart';", MODELS)
    def test_no_clock_or_amount_default_in_factory(self):
        for fragment in ['DateTime.now', '_dateTime(', '?? 0', '.toInt()']:
            self.assertNotIn(fragment, FACTORY)
        self.assertNotIn('DateTime.now', HELPER)
    def test_status_and_ids_are_required(self):
        for name in ['id', 'collection_id', 'status']:
            self.assertIn(f"_paymentIdentifier(json['{name}'], '{name}')", FACTORY)
    def test_amount_aliases_validated_before_selection(self):
        self.assertIn('_paymentAmount(', FACTORY)
        self.assertIn("_paymentPositiveInteger(currentValue, currentKey)", HELPER)
        self.assertIn("_paymentPositiveInteger(legacyValue, legacyKey)", HELPER)
        self.assertLess(HELPER.index('current != legacy'), HELPER.index('return current ?? legacy!'))
    def test_exact_positive_amount_boundary(self):
        for fragment in ['!value.isFinite', 'value <= 0',
                         'value > _paymentMaxExactInteger', 'value.remainder(1) != 0']:
            self.assertIn(fragment, HELPER)
        self.assertIn('const _paymentMaxExactInteger = maxExactJsonInteger;', HELPER)
        self.assertIn('const maxExactJsonInteger = 9007199254740991;', SHARED)
    def test_dates_require_explicit_zone_and_real_calendar(self):
        self.assertIn('exactJsonTimestamp(value, field: field)', HELPER)
        self.assertIn('([Zz]|([+-])', SHARED)
        self.assertIn('match.end != value.length', SHARED)
        self.assertIn('calendar.day != day', SHARED)
        self.assertIn('offsetMinute > 59', SHARED)
        self.assertIn('expiresAt.isAfter(createdAt)', FACTORY)
    def test_no_external_calls_in_decoder(self):
        for fragment in ['.rpc(', '.invoke(', '.launch(', '.insert(', '.delete(', 'print(']:
            self.assertNotIn(fragment, FACTORY + HELPER + SHARED)
    def test_optional_defaults_are_explicitly_retained(self):
        self.assertIn("rail: 'rwanda_momo'", FACTORY)
        self.assertIn("currency: 'RWF'", FACTORY)
        self.assertIn("fallback: 'mtn_momo'", FACTORY)
    def test_helpers_never_attach_received_values_to_exception(self):
        self.assertNotIn('$value', HELPER + SHARED)
        self.assertNotIn(', value)', HELPER + SHARED)
    def test_new_suites_are_in_existing_validation_scope(self):
        for path in ['test/payment_intent_decoding_test.dart',
                     'test/payment_intent_cache_boundary_test.dart']:
            self.assertIn(path, SCOPE['format_targets'])
            self.assertIn(path, SCOPE['widget_tests'])
            self.assertTrue((ROOT / path).is_file())
    def test_factory_keeps_named_public_api(self):
        self.assertIn('factory PaymentIntentModel.fromJson(Map<String, dynamic> json)', PAYMENT)
        self.assertIn('const PaymentIntentModel({', PAYMENT)
        self.assertRegex(PAYMENT, r"isRwandaMomo\s*&&\s*status == 'pending'")

if __name__ == '__main__':
    unittest.main(verbosity=2)
