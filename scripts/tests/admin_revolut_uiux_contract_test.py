#!/usr/bin/env python3
"""Source-level regression contracts for Collect Admin B01-B04.

These assertions are deliberately narrow. They guard the code contracts that
were changed in this implementation; Flutter widget tests, hosted authorization,
accessibility and installed-PWA acceptance are separate execution gates.
"""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def source(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def check(name: str, condition: bool) -> None:
    if not condition:
        raise AssertionError(name)
    print(f"PASS {name}")


def main() -> None:
    sms = source("lib/admin/core/cloudflare_admin_sms_pages.dart")
    sms_ui = source("lib/admin/core/cloudflare_admin_sms_ui.dart")
    table = source("lib/admin/shared/components/admin_data_table.dart")
    facts = source("lib/admin/shared/components/admin_record_facts_panel.dart")
    empty = source("lib/admin/shared/components/admin_empty_state.dart")
    shell = source("lib/admin/admin_shell.dart")
    nav = source("lib/admin/admin_shell_navigation.dart")
    overview = source("lib/admin/core/admin_overview_runtime.dart")
    pwa = source("scripts/admin_pwa_release_build.sh")
    widget_test = source("test/admin/admin_revolut_receipts_uiux_test.dart")
    original_sms_test = source("test/admin/cloudflare_admin_sms_test.dart")

    check("SMS UI part is linked", "part 'cloudflare_admin_sms_ui.dart';" in sms
          and "part of 'cloudflare_admin_sms_pages.dart';" in sms_ui)
    check("SMS default list is operationally focused",
          sms_ui.count("List<AdminTableColumn> get _receiptListColumns") == 1
          and "_column('Masked contact', 'payer_masked_phone')" in sms_ui
          and "_column('Amount (RWF)', 'amount_rwf'" in sms_ui
          and "_column('Conflicts', 'conflicting_reference_count'" in sms_ui)
    list_def = sms_ui.split("List<AdminTableColumn> get _receiptListColumns => [", 1)[1].split("\n];", 1)[0]
    check("default list does not show a raw phone or hash",
          "'payer_phone'" not in list_def
          and "'payee_momo_number'" not in list_def
          and "'source_sha256'" not in list_def)
    check("full source schema remains accessible in detail",
          "List<AdminTableColumn> get _receiptDetailColumns" in sms_ui
          and "..._sourceColumns" in sms_ui
          and "_column('Payload SHA-256', 'source_payload_sha256')" in sms_ui)
    check("sensitive detail values receive a masking transform",
          "column.label == 'Payer phone'" in sms_ui
          and "column.label == 'Payee MoMo number'" in sms_ui
          and "_maskReceiptContact(sourceValue)" in sms_ui)
    check("detail uses readable facts instead of a single 36-column table",
          "_receiptFacts(detail.source)" in sms
          and "tableLabel: 'SMS source facts'" not in sms
          and "Technical source provenance" in facts)
    check("data table tools explicitly support paginated mode",
          "this.localToolsEnabled = true" in table
          and "widget.localToolsEnabled &&" in table
          and sms.count("localToolsEnabled: false") == 2
          and sms.count("columns: _receiptListColumns") == 2)
    check("search explicitly applies to all server records",
          "Searches all matching records, not just this page." in sms
          and "_receiptsProvider(_query)" in sms
          and "sms-receipt-apply-search" in sms_ui
          and "sms-receipt-clear-search" in sms_ui)
    check("empty queue differs from filtered no-results state",
          "No SMS receipts yet" in sms
          and "No matching receipts" in sms
          and "Clear search and filters" in sms
          and "final Widget? action;" in empty)
    check("fetch success timestamp is response-bound",
          "DateTime receivedAt" in sms
          and "receivedAt: DateTime.now()" in sms
          and "adminKigaliDateTime(result.receivedAt)" in sms)
    check("existing URL validation and audited financial workflows survive",
          "smsReturnLocation(String? location)" in sms
          and "Uri.tryParse" in sms
          and "int.tryParse" in sms
          and "_attempt ?? api.extract" in sms
          and "_recover()" in sms
          and "_reveal(detail.source)" in sms)
    check("responsive SMS cards activate below 720 logical pixels",
          "constraints.maxWidth < 720" in sms
          and "_mobileReceiptCard(source)" in sms
          and "sms-receipt-${source.id}" in sms_ui)
    check("advanced filters remain available when reopened from a deep link",
          "_advancedFiltersOpen = _extraction.isNotEmpty || _duplicates.isNotEmpty" in sms
          and "sms-receipt-advanced-filter-toggle" in sms)
    check("section navigation has Communications section",
          "communications, control" in nav
          and "'/admin/sms-gateway'" in nav
          and "return _AdminNavSection.communications;" in nav)
    check("ambiguous section search cannot silently navigate",
          "matches.length == 1" in nav
          and "More than one admin section matches" in nav
          and "Autocomplete<_AdminNavDestination>" in shell)
    check("overview reconciliation links are accurately labelled",
          "actionLabel: 'View reconciliations'" in overview
          and "tooltip: 'Open reconciliations'" in overview
          and "actionLabel: 'View all exceptions'" not in overview)
    check("installed PWA has role-gated shortcut entrypoints",
          'manifest["shortcuts"]' in pwa
          and '"./#/admin/sms-receipts"' in pwa
          and '"./#/admin/reconciliations"' in pwa
          and 'manifest["start_url"] = "."' in pwa)
    check("widget regression coverage is included",
          "testWidgets('server-paginated table does not imply page-local searching'" in widget_test
          and "detail facts reflow at 320px" in widget_test
          and "320px listing shows a privacy-safe card" in original_sms_test)
    check("operating source files are below the 1200-line hard limit",
          all(len(source(path).splitlines()) <= 1200 for path in [
              "lib/admin/core/cloudflare_admin_sms_pages.dart",
              "lib/admin/core/cloudflare_admin_sms_ui.dart",
              "lib/admin/admin_shell.dart",
              "lib/admin/admin_shell_navigation.dart",
              "lib/admin/core/admin_overview_runtime.dart",
              "lib/admin/shared/components/admin_data_table.dart",
              "lib/admin/shared/components/admin_record_facts_panel.dart",
          ]))
    check("PWA shell script parses in bash",
          subprocess.run(["bash", "-n", str(ROOT / "scripts/admin_pwa_release_build.sh")],
                         capture_output=True, check=False).returncode == 0)
    print("PASS 20/20 Admin UI/UX source contracts")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError) as exc:
        print(f"FAIL {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
