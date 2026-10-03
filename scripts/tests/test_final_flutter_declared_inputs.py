#!/usr/bin/env python3
"""Regression for the full-suite export's demonstrated namespace over-copy."""
import unittest

from final_flutter_acceptance import release_fixture_patterns


class ReleaseFixturePatternTest(unittest.TestCase):
    def test_adjacent_literals_select_actual_receipt_namespace(self):
        source = """
const _fixtureRoot =
    'docs/release/collect-codex-goal-2026-09-30/'
    'receipt-exception-worker-20261001/accepted-sql-attempt8';
File('$_fixtureRoot/observed-worker-$name.json').readAsStringSync();
"""
        self.assertEqual(release_fixture_patterns(source), [
            'docs/release/collect-codex-goal-2026-09-30/receipt-exception-worker-20261001/'
            'accepted-sql-attempt8/observed-worker-*.json'])

    def test_direct_adjacent_literal_and_exact_input_survive(self):
        source = """
File('docs/release/collect-codex-goal-2026-09-30/'
     'receipt-operational-authority-20261001/accepted-sql-attempt7/'
     'observed-$name.json').readAsStringSync();
File('docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json').readAsStringSync();
"""
        self.assertEqual(release_fixture_patterns(source), [
            'docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json',
            'docs/release/collect-codex-goal-2026-09-30/receipt-operational-authority-20261001/'
            'accepted-sql-attempt7/observed-*.json'])

    def test_namespace_and_generated_capture_are_not_recursive_inputs(self):
        source = """
const root = 'docs/release/collect-codex-goal-2026-09-30/';
File('docs/release/admin-review/output-$name.png').writeAsBytesSync(bytes);
"""
        self.assertEqual(release_fixture_patterns(source), [])

    def test_traversal_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'escapes'):
            release_fixture_patterns("File('docs/release/../../private.json').readAsStringSync();")


if __name__ == '__main__':
    unittest.main()
