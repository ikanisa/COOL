#!/usr/bin/env python3
"""Source-level B09–B12 checks; not Flutter or installed-PWA acceptance."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]

def source(path):
    return (ROOT / path).read_text(encoding='utf-8')

def main():
    helper = source('lib/admin/core/admin_receipt_presentation.dart')
    ui = source('lib/admin/core/cloudflare_admin_sms_ui.dart')
    pages = source('lib/admin/core/cloudflare_admin_sms_pages.dart')
    tests = source('test/admin/admin_revolut_receipts_uiux_test.dart')
    journey = source('test/admin/cloudflare_admin_sms_test.dart')
    sw_test = source('scripts/tests/admin_pwa_service_worker_isolated_test.mjs')
    qual = source('scripts/admin_revolut_qualification.py')
    ci = source('.github/workflows/ci.yml')
    checks = {
        'honest empty offset with nonempty filtered totals':
            'static String pageSummary(' in helper
            and 'No records on this page' in helper
            and 'static bool outOfRangePage(' in helper,
        'pagination labels use authoritative summary':
            'AdminReceiptPresentation.pageSummary(' in ui,
        'filtered out-of-range state offers a first-page path':
            "title: 'This page no longer has records'" in pages
            and "Key('sms-receipt-first-page')" in pages,
        'pagination recovery resets URL page without dropping filters':
            'setState(() => _offset = 0);' in pages
            and 'context.go(_location)' in pages,
        'existing no-result vs no-queue distinction remains':
            "'No matching receipts'" in pages
            and "'No SMS receipts yet'" in pages,
        'widget and page-boundary regressions included':
            "out-of-range receipt pages preserve truthful totals" in tests
            and "shrinking receipt queue recovers an out-of-range page" in journey,
        'existing privacy guard and extraction outcome recovery remain':
            'maskedContact' in helper
            and 'AdminReceiptPresentation.maskedContact(' in ui
            and '_recover()' in pages,
        'service-worker harness executes original template':
            "admin_pwa_service_worker.js'" in sw_test
            and 'new Script(source' in sw_test,
        'PWA test includes private response boundary and tamper cases':
            'private and unfamiliar assets never receive cached account content' in sw_test
            and 'tampered static asset blocks install' in sw_test,
        'PWA test includes offline and update integrity cases':
            'offline route navigation uses the verified shell only' in sw_test
            and 'failed reinstall preserves previously verified same-build cache' in sw_test,
        'qualification runner runs isolated PWA script when available':
            'isolated Admin PWA service-worker runtime checks' in qual
            and 'pwa_template.is_file()' in qual,
        'GitHub CI eventually runs the focused source and JS suites':
            'admin_revolut_b09_b12_contract_test.py' in ci
            and 'admin_pwa_service_worker_isolated_test.mjs' in ci,
        'production Dart changes remain below 1200-line hard limit':
            len(pages.splitlines()) <= 1200 and len(ui.splitlines()) <= 1200,
    }
    for label, passed in checks.items():
        print(f'{"PASS" if passed else "FAIL"} {label}')
    print(f'{sum(checks.values())}/{len(checks)} B09–B12 source contracts passed')
    return 0 if all(checks.values()) else 1

if __name__ == '__main__':
    sys.exit(main())
