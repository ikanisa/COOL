#!/usr/bin/env python3
"""Source-wiring checks only. These do not compile Dart or exercise Dart behavior."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODELS = ROOT / 'lib/shared/models'

class PaymentDecodingSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = (MODELS / 'collect_models.dart').read_text()
        cls.payments = (MODELS / 'collect_payment_models.dart').read_text()
        cls.helper = (MODELS / 'collect_payment_json.dart').read_text()
        cls.shared = (ROOT / 'lib/core/data/exact_json_values.dart').read_text()
        cls.intent = cls.payments.split('factory PaymentIntentModel.fromJson', 1)[1].split('\n}\n', 1)[0]
        cls.contribution = cls.payments.split('factory Contribution.fromJson', 1)[1].split('\n}\n', 1)[0]
        cls.scope = json.loads((ROOT / 'scripts/qa/candidate_check_scope.json').read_text())

    def test_helper_is_in_same_library(self):
        self.assertEqual(self.models.count("part 'collect_payment_json.dart';"), 1)
        self.assertTrue(self.helper.startswith("part of 'collect_models.dart';"))
        self.assertIn("import '../../core/data/exact_json_values.dart';", self.models)

    def test_both_decoders_use_amount_validator(self):
        for factory in (self.intent, self.contribution):
            self.assertIn('_paymentAmount(', factory)
            self.assertNotIn('.toInt()', factory)
            self.assertNotIn('?? 0', factory)

    def test_amount_helper_has_exact_finite_positive_guards(self):
        for guard in ('!value.isFinite', 'value <= 0', 'value > _paymentMaxExactInteger', 'value.remainder(1) != 0'):
            self.assertIn(guard, self.helper)
        self.assertIn('const _paymentMaxExactInteger = maxExactJsonInteger;', self.helper)
        self.assertIn('const maxExactJsonInteger = 9007199254740991;', self.shared)

    def test_aliases_cannot_disagree(self):
        self.assertIn('current != legacy', self.helper)
        self.assertIn('_paymentPositiveInteger(currentValue', self.helper)
        self.assertIn('_paymentPositiveInteger(legacyValue', self.helper)

    def test_decoders_do_not_use_fallback_clock(self):
        for factory in (self.intent, self.contribution):
            self.assertNotIn('_dateTime(', factory)
            self.assertNotIn('DateTime.now()', factory)
            self.assertIn('_paymentTimestamp(', factory)
        self.assertNotIn('DateTime.now()', self.helper)

    def test_calendar_and_timezone_validated(self):
        self.assertIn('exactJsonTimestamp(value, field: field)', self.helper)
        for check in ('calendar.year != year', 'calendar.month != month', 'calendar.day != day', '!parsed.isUtc', 'offsetMinute > 59', 'match.end != value.length'):
            self.assertIn(check, self.shared)

    def test_missing_status_not_pending(self):
        self.assertIn("status: _paymentIdentifier(json['status'], 'status')", self.intent)
        self.assertNotIn("?? 'pending'", self.intent)

    def test_intent_lifetime_ordered(self):
        self.assertIn('!expiresAt.isAfter(createdAt)', self.intent)

    def test_timestamp_error_does_not_embed_payload(self):
        self.assertNotIn('$value', self.helper)
        self.assertNotRegex(self.helper + self.shared, r'FormatException\([^;]+,\s*value\s*\)')
        self.assertNotIn('$value', self.shared)

    def test_const_constructor_compatibility_preserved(self):
        for name in ('PaymentIntentDraft', 'PaymentIntentModel', 'Contribution', 'ParsedPaymentEvent'):
            self.assertIn('const ' + name + '(', self.payments)

    def test_record_precedence_retained(self):
        self.assertIn("json['payment_id'] ?? json['id']", self.contribution)
        self.assertIn("json['posted_at'] ?? json['created_at']", self.contribution)

    def test_ci_retains_tooling_checks_and_full_application_suite(self):
        ci = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('run: make qa-tooling-test', ci)
        self.assertIn('flutter test --concurrency=4', ci)

    def test_validation_scope_includes_suites(self):
        encoded = json.dumps(self.scope)
        for path in ('lib/shared/models/collect_payment_json.dart', 'lib/shared/models/collect_payment_models.dart', 'test/payment_json_integrity_test.dart', 'test/payment_cache_integrity_test.dart'):
            self.assertIn(path, encoded)

if __name__ == '__main__':
    unittest.main()
