#!/usr/bin/env python3
"""Non-Flutter, source-bound checks for Collect Admin UI/UX PR #51.

These checks are executable even when GitHub runners/Flutter SDK are unavailable.
They do not assert that Dart compiles or that hosted behavior is accepted.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]


def content(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def check_delimiters(relative: str) -> None:
    """Check balanced code delimiters, ignoring Dart strings and comments.

    This is a lexical sanity check, NOT a Dart parser or format/analyzer gate.
    """
    src = content(relative)
    pairs = {")": "(", "]": "[", "}": "{"}
    opened: list[tuple[str, int]] = []
    i = 0
    line = 1
    block_depth = 0
    while i < len(src):
        c = src[i]
        pair = src[i:i + 2]
        if c == "\n":
            line += 1
        if pair == "//":
            end = src.find("\n", i)
            if end < 0:
                break
            i = end
            continue
        if pair == "/*":
            block_depth = 1
            i += 2
            while i < len(src) and block_depth:
                if src[i:i + 2] == "/*":
                    block_depth += 1
                    i += 2
                elif src[i:i + 2] == "*/":
                    block_depth -= 1
                    i += 2
                else:
                    if src[i] == "\n":
                        line += 1
                    i += 1
            if block_depth:
                raise AssertionError(f"{relative}:{line}: unterminated comment")
            continue
        quote_start = i
        raw = c in "rR" and i + 1 < len(src) and src[i + 1] in "'\"" and (
            i == 0 or not (src[i - 1].isalnum() or src[i - 1] == "_")
        )
        if raw:
            quote_start += 1
        quote = src[quote_start]
        if quote in "'\"":
            triple = src[quote_start:quote_start + 3] == quote * 3
            i = quote_start + (3 if triple else 1)
            while i < len(src):
                if src[i] == "\n":
                    line += 1
                if src[i] == "\\" and not raw:
                    i += 2
                    continue
                if triple and src[i:i + 3] == quote * 3:
                    i += 3
                    break
                if not triple and src[i] == quote:
                    i += 1
                    break
                i += 1
            else:
                raise AssertionError(f"{relative}:{line}: unterminated string")
            continue
        if c in "([{":
            opened.append((c, line))
        elif c in ")]}":
            if not opened or opened[-1][0] != pairs[c]:
                raise AssertionError(f"{relative}:{line}: unexpected {c}")
            opened.pop()
        i += 1
    if opened:
        raise AssertionError(f"{relative}:{opened[-1][1]}: unclosed {opened[-1][0]}")


class SourceRegression(unittest.TestCase):
    def test_previous_twenty_source_contracts(self) -> None:
        p = subprocess.run(
            [sys.executable, str(ROOT / "scripts/tests/admin_revolut_uiux_contract_test.py")],
            cwd=ROOT, capture_output=True, text=True, check=False,
        )
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn("PASS 20/20", p.stdout)

    def test_native_selectable_semantics_not_suppressed(self) -> None:
        facts = content("lib/admin/shared/components/admin_record_facts_panel.dart")
        widget = content("test/admin/admin_revolut_receipts_uiux_test.dart")
        self.assertIn("child: SelectableText(", facts)
        self.assertNotIn("excludeSemantics: true", facts)
        self.assertIn("node.hasAction(SemanticsAction.longPress)", widget)
        self.assertIn(".hasAction(SemanticsAction.copy)", widget)

    def test_mobile_receipts_expose_operational_exceptions(self) -> None:
        sms = content("lib/admin/core/cloudflare_admin_sms_ui.dart")
        test = content("test/admin/cloudflare_admin_sms_test.dart")
        self.assertIn("'Status: $status'", sms)
        self.assertIn("'Extraction: $extraction'", sms)
        self.assertIn("'Conflicts: $conflicts'", sms)
        self.assertIn("if (conflicts > 0)", sms)
        self.assertIn("find.text('Status: Needs Review')", test)
        self.assertIn("find.text('Extraction: Parsed')", test)

    def test_keyboard_section_selection_is_visible_and_role_scoped(self) -> None:
        shell = content("lib/admin/admin_shell.dart")
        nav = content("lib/admin/admin_shell_navigation.dart")
        self.assertIn("AutocompleteHighlightedOption.of(", shell)
        self.assertIn("onFieldSubmitted();", shell)
        self.assertIn("onSelected: (option) => context.go(option.path)", shell)
        self.assertIn("_adminNavDestinationsFor(", shell)
        self.assertIn("adminCanOpenPath(", nav)

    def test_embedded_ruby_and_python_blocks_parse(self) -> None:
        script = content("scripts/admin_pwa_release_build.sh")
        self.assertEqual(
            subprocess.run(["bash", "-n"], input=script, capture_output=True,
                           text=True, check=False).returncode, 0,
            "shell failed syntax verification",
        )
        seen = set()
        for match in re.finditer(r"<<'([A-Z][A-Z0-9_]*)'", script):
            marker = match.group(1)
            end = re.search(rf"(?m)^{re.escape(marker)}$", script[match.end():])
            self.assertIsNotNone(end, f"unclosed {marker}")
            code = script[match.end(): match.end() + end.start()]
            code = code.lstrip("\n")
            if marker.startswith("RUBY") or marker == "RUBY":
                cp = subprocess.run(["ruby", "-c", "-"], input=code,
                                    text=True, capture_output=True, check=False)
                self.assertEqual(cp.returncode, 0, cp.stderr + cp.stdout)
                seen.add("ruby")
            elif marker.startswith("PY"):
                compile(code, f"{marker} heredoc", "exec")
                seen.add("python")
        self.assertEqual(seen, {"ruby", "python"})

    def test_manifest_shortcuts_do_not_leave_admin_origin(self) -> None:
        script = content("scripts/admin_pwa_release_build.sh")
        section = script.split('manifest["shortcuts"] = [', 1)[1].split("]\nmanifest[\"icons\"]", 1)[0]
        urls = re.findall(r'"url"\s*=>\s*"([^\"]+)"', section)
        self.assertEqual(urls, ["./#/admin", "./#/admin/sms-receipts", "./#/admin/reconciliations"])
        self.assertIn('manifest["start_url"] = "."', script)
        self.assertIn('manifest["name"] = "Collect Admin"', script)
        self.assertTrue(all(x.startswith("./#/admin") and "?" not in x for x in urls))
        self.assertFalse(any(x.startswith("http") for x in urls))

    def test_acceptance_runner_fails_closed_without_toolchain(self) -> None:
        runner = ROOT / "scripts/tests/admin_b01_b04_acceptance.sh"
        script = runner.read_text(encoding="utf-8")
        self.assertIn('exit 2', script)
        self.assertIn('flutter analyze --fatal-infos', script)
        self.assertIn('flutter test test/admin/cloudflare_admin_sms_test.dart', script)
        self.assertIn('admin_pwa_manifest_gate.sh', script)
        self.assertEqual(
            subprocess.run(["bash", "-n", str(runner)], capture_output=True,
                           text=True, check=False).returncode,
            0,
        )

    def test_source_delimiters_are_balanced(self) -> None:
        for path in [
            "lib/admin/admin_shell.dart",
            "lib/admin/admin_shell_navigation.dart",
            "lib/admin/core/cloudflare_admin_sms_pages.dart",
            "lib/admin/core/cloudflare_admin_sms_ui.dart",
            "lib/admin/shared/components/admin_record_facts_panel.dart",
            "lib/admin/shared/components/admin_data_table.dart",
            "test/admin/admin_revolut_receipts_uiux_test.dart",
            "test/admin/cloudflare_admin_sms_test.dart",
        ]:
            with self.subTest(path=path):
                check_delimiters(path)

    def test_no_raw_patch_markers_or_production_credentials(self) -> None:
        for path in ROOT.rglob("*.dart"):
            content_ = path.read_text(encoding="utf-8")
            self.assertNotIn("*** Begin Patch", content_)
            self.assertNotIn("Authorization: Bearer ", content_)


if __name__ == "__main__":
    unittest.main(verbosity=2)
