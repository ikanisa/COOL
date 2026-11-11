#!/usr/bin/env python3
"""B05–B08 source contracts. This is not Flutter, browser or hosted acceptance."""
from __future__ import annotations
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[2]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")

def main():
    sms = read('lib/admin/core/cloudflare_admin_sms_pages.dart')
    ui = read('lib/admin/core/cloudflare_admin_sms_ui.dart')
    helper = read('lib/admin/core/admin_receipt_presentation.dart')
    tests = read('test/admin/admin_revolut_receipts_uiux_test.dart')
    checks = {
        'privacy: normal list values are masked even if the API field is not':
            "field == 'payer_masked_phone'" in sms
            and 'AdminReceiptPresentation.maskedContact(row.extra[field])' in sms,
        'privacy: ordinary mobile card masks contact independently':
            "AdminReceiptPresentation.maskedContact(\n      values['payer_masked_phone']" in ui,
        'privacy: standard detail masks every contact field':
            "column.label == 'Source masked phone'" in ui
            and '_maskReceiptContact(sourceValue)' in ui,
        'source: masking never trusts an already-masked label':
            "digits.substring(digits.length - 3)" in helper,
        'state: untrusted negative counts remain unknown':
            "if (count == null) return 'Conflict count unavailable';" in helper,
        'state: mobile card shows extraction and conflicts':
            "'Extraction: $extraction'" in ui and 'conflicts,' in ui,
        'recovery: receipt list offers an explicit retry':
            "Key('sms-receipt-retry-loading')" in sms,
        'recovery: receipt detail offers an explicit retry':
            "Key('sms-receipt-retry-detail')" in sms,
        'tests: contact and malformed conflict fixtures are supplied':
            "maskedContact('0788767816')" in tests
            and "conflicts('-1')" in tests,
        'safety: original request recovery remains':
            '_recover()' in sms and '_reviewRetry()' in sms,
    }
    for name, valid in checks.items():
        print(f'{"PASS" if valid else "FAIL"} {name}')
    if not all(checks.values()):
        return 1
    print(f'PASS {len(checks)}/{len(checks)} narrow source contracts')
    return 0
if __name__ == '__main__':
    sys.exit(main())