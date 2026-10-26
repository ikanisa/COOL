"""Static source invariants only. These do not execute Dart or render Flutter."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
def read(rel):
    return (ROOT / rel).read_text()

class RecoveryListSourceTests(unittest.TestCase):
    def test_new_viewport_is_prefixed(self):
        s = read('lib/features/payments/contribution_flow_screen.dart')
        self.assertIn("import '../../shared/widgets/collect_form_viewport.dart' as forms;", s)
        self.assertIn('forms.CollectFormViewport(', s)
        self.assertNotRegex(s, r'(?<![.\w])CollectFormViewport\(')
    def test_legacy_constructor_is_preserved(self):
        s = read('lib/shared/widgets/collect_foundation.dart')
        self.assertIn('const CollectFormViewport({required this.child, this.controller, super.key});', s)
    def test_recovery_uses_actual_snapshot_availability(self):
        s = read('lib/features/status/connection_recovery_screens.dart')
        self.assertIn('ref.watch(collectRepositoryProvider)', s)
        self.assertIn('state.collections.isNotEmpty', s)
        self.assertIn('state.usingStaleCache', s)
        self.assertNotIn('_RecoveryRow', s)
        self.assertNotIn("value: 'Protected'", s)
        self.assertNotIn("value: 'Masked'", s)
    def test_recovery_retains_both_destinations(self):
        s = read('lib/features/status/connection_recovery_screens.dart')
        self.assertIn("context.go('/groups')", s)
        self.assertIn("context.go('/settings/legal/privacy')", s)
        self.assertEqual(s.count('MinimalStatePanel('), 1)
    def test_recovery_refresh_is_data_only_and_ownership_checked(self):
        s = read('lib/features/status/connection_recovery_screens.dart')
        self.assertIn('await repository.loadInitial(syncPendingSms: false);', s)
        self.assertIn('if (!_ownsAttempt(repository, identity)) return;', s)
        self.assertIn('syncedAt.isAfter(before.lastSuccessfulSyncAt!)', s)
        self.assertNotIn('syncPendingSms: true', s)
        self.assertNotIn('createPaymentIntent(', s)
        self.assertNotIn("label: 'Retry'", s)
    def test_contribute_lists_use_slivers(self):
        s = read('lib/features/payments/contribute_entry_screen.dart')
        self.assertEqual(s.count('GroupListSliver('), 2)
        self.assertNotIn('GroupListPanel(', s)
        self.assertIn('SliverMainAxisGroup(', s)
        self.assertNotIn('shrinkWrap:', s)
    def test_membership_and_sorting_remain(self):
        s = read('lib/features/payments/contribute_entry_screen.dart')
        self.assertIn('collection.creatorUserId == profile.id ||', s)
        self.assertIn('collection.isCurrentUserMember', s)
        self.assertEqual(s.count('..sort(_compareCollections)'), 2)
    def test_group_list_retains_original_tokens(self):
        s = read('lib/shared/widgets/collect_group_cards.dart')
        self.assertIn('emphasis: CollectCardEmphasis.normal', s)
        self.assertIn('padding: EdgeInsets.zero', s)
        self.assertIn("ValueKey('group-list-${collection.id}')", s)
    def test_shared_list_is_lazy(self):
        s = read('lib/shared/widgets/collect_foundation.dart')
        s = s[s.index('class CollectSliverCardList '):]
        self.assertIn('SliverList.builder(', s)
        self.assertIn('this.emphasis = CollectCardEmphasis.flat', s)
        self.assertIn('this.padding = CollectSpacing.cardPadding', s)
        self.assertNotIn('BackdropFilter(', s)
    def test_typing_is_not_forcibly_unfocused(self):
        for rel in ['lib/features/payments/contribute_entry_screen.dart', 'lib/features/payments/contribution_flow_screen.dart']:
            self.assertNotIn('.unfocus(', read(rel))

if __name__ == '__main__':
    unittest.main(verbosity=2)
