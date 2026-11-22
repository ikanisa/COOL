"""Source-content regression checks, not a Dart compiler or Flutter execution."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]

class GroupSummarySourceTests(unittest.TestCase):
    def setUp(self):
        self.cards = (ROOT / 'lib/shared/widgets/collect_group_cards.dart').read_text()
        self.screen = (ROOT / 'lib/features/payments/contribute_entry_screen.dart').read_text()
    def test_eager_and_lazy_rows_keep_absent_summary(self):
        self.assertIn('summary: summaries[collections[index].id],', self.cards)
        self.assertIn('summary: summaries[collection.id],', self.cards)
        self.assertNotIn('const CollectionSummary(', self.cards)
    def test_list_and_card_accept_absence_without_changing_required_summary(self):
        self.assertEqual(self.cards.count('final CollectionSummary? summary;'), 2)
        self.assertEqual(self.cards.count('final CollectionSummary summary;'), 1)
    def test_amount_and_count_have_truthful_unavailable_semantics(self):
        self.assertIn("? 'Not available'", self.cards)
        self.assertIn("? 'Group total unavailable'", self.cards)
        self.assertIn("'Contributor count unavailable'", self.cards)
    def test_known_total_still_uses_existing_formatter(self):
        self.assertIn('formatCurrencyTotals(', self.cards)
        self.assertIn('currentSummary.totalsByCurrency,', self.cards)
        self.assertIn("separator: '\\n',", self.cards)
        self.assertIn('currentSummary?.supporterCountLabel', self.cards)
    def test_selection_uses_loaded_aggregate_not_partial_history(self):
        self.assertIn('final summaries = state.collectionSummaries;', self.screen)
        self.assertNotIn('ref.watch(collectionSummariesProvider)', self.screen)
        self.assertNotIn('summaryFor(', self.screen)
    def test_routes_membership_and_lazy_sections_preserved(self):
        self.assertIn('collection.creatorUserId == profile.id ||', self.screen)
        self.assertIn('collection.isCurrentUserMember', self.screen)
        self.assertEqual(self.screen.count('GroupListSliver('), 2)
        self.assertEqual(self.screen.count('..sort(_compareCollections)'), 2)
    def test_new_suite_is_in_candidate_scope(self):
        s = json.loads((ROOT / 'scripts/qa/candidate_check_scope.json').read_text())
        for key in ['widget_tests', 'format_targets']:
            self.assertIn('test/group_summary_integrity_test.dart', s[key])
    def test_ci_retains_full_suite_and_tooling_checks(self):
        t = (ROOT / '.github/workflows/ci.yml').read_text()
        self.assertIn('run: make qa-tooling-test', t)
        self.assertIn('flutter test --concurrency=4 --exclude-tags=integration', t)

if __name__ == '__main__':
    unittest.main(verbosity=2)
