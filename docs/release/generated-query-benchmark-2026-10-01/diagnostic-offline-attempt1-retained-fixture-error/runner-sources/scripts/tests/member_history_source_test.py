#!/usr/bin/env python3
"""Static wiring checks; these do not execute Dart or Flutter."""
from pathlib import Path
import json
import unittest

ROOT = Path(__file__).resolve().parents[2]
PAGE = (ROOT / 'lib/shared/models/member_history_page.dart').read_text()
CONTROLLER = (ROOT / 'lib/shared/repositories/collect_repository_history.dart').read_text()
READER = (ROOT / 'lib/shared/repositories/collect_repository_live_reader.dart').read_text()
SCOPE = json.loads((ROOT / 'scripts/qa/candidate_check_scope.json').read_text())

class MemberHistorySourceChecks(unittest.TestCase):
    def test_live_reader_validates_request_before_return(self):
        method = READER.split('Future<MemberHistoryPage> fetchHistoryPage(', 1)[1].split('  List<Map<String, dynamic>> _pageRows', 1)[0]
        self.assertLess(method.index('page.validateRequest(query: query, cursor: cursor);'), method.index('return page;'))
    def test_wire_limit_and_rpc_preserved(self):
        self.assertIn("'list_current_member_history_page'", READER)
        self.assertIn("'p_limit': 50", READER)
    def test_no_payment_writes_introduced(self):
        for text in [PAGE, CONTROLLER]:
            for forbidden in ['createPaymentIntent(', '.launch(', 'syncPendingSms:', '.insert(', '.upsert(', '.delete(']:
                self.assertNotIn(forbidden, text)
    def test_append_checks_both_aggregate_maps(self):
        self.assertIn('_sameAmounts(totals, next.totals)', PAGE)
        self.assertIn('_sameAmounts(ownTotals, next.ownTotals)', PAGE)
        self.assertIn('ownCollectionIds.containsAll(next.ownCollectionIds)', PAGE)
    def test_cursor_is_canonical_and_unmodifiable(self):
        self.assertIn('Map<String, dynamic>.unmodifiable({', PAGE)
        self.assertIn("'after': value['after']", PAGE)
        self.assertNotIn('Map<String, dynamic>.from(cursor as Map)', PAGE)
    def test_precision_bounds_and_duplicates_are_checked(self):
        self.assertIn('9007199254740991', PAGE)
        self.assertIn('value.isFinite', PAGE)
        self.assertIn('!seen.add(row.id)', PAGE)
        self.assertIn('ids.toSet().length != ids.length', PAGE)
    def test_continuation_and_initial_completeness_are_checked(self):
        self.assertIn('(next.nextCursor == null) != complete', PAGE)
        self.assertIn('(nextCursor == null && items.length != totalCount)', PAGE)
    def test_selected_group_and_sort_are_checked(self):
        self.assertIn('row.collectionId != query.collectionId', PAGE)
        self.assertIn('result._validateOrder(query.sort)', PAGE)
        self.assertIn("{'newest', 'oldest', 'highest', 'lowest'}", PAGE)
    def test_provider_tracks_repository_replacement(self):
        self.assertIn('ref.watch(collectRepositoryProvider.notifier)', CONTROLLER)
    def test_callbacks_guard_owner_and_lifecycle(self):
        self.assertIn('repository.state.currentProfile?.id != _ownerProfileId', CONTROLLER)
        self.assertIn('repository._supabase?.auth.currentUser?.id != _ownerAuthId', CONTROLLER)
        self.assertIn('if (!mounted) return false;', CONTROLLER)
        self.assertIn('if (!_contextCurrent() || _refreshRequired) return;', CONTROLLER)
    def test_actual_dart_suites_are_in_existing_runner(self):
        for path in ['test/member_history_page_integrity_test.dart', 'test/member_history_controller_integrity_test.dart']:
            self.assertIn(path, SCOPE['format_targets'])
            self.assertIn(path, SCOPE['widget_tests'])
            self.assertTrue((ROOT / path).is_file())

if __name__ == '__main__':
    unittest.main(verbosity=2)
