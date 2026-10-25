#!/usr/bin/env python3
"""Source wiring invariants only: NOT Flutter, Android, iOS or SQL runtime tests."""
import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def source(path):return (ROOT/path).read_text()
class V2Integration(unittest.TestCase):
 def test_live_repository_requires_protected_cache(self):
  text=source('lib/shared/repositories/collect_repository.dart').split('CollectRepository.fixture',1)[0]
  self.assertIn('CollectOfflineCache.protected()',text)
 def test_cache_owner_bound_read(self):
  self.assertIn('_offlineCache.read(ownerUserId: initialUserId)',source('lib/shared/repositories/collect_repository.dart'))
 def test_bridge_does_not_fallback_to_preferences(self):
  text=source('lib/core/security/protected_snapshot_store.dart');self.assertNotIn('SharedPreferences',text);self.assertIn('on MissingPluginException',text)
 def test_cache_deletion_serialized(self):
  text=source('lib/shared/repositories/collect_offline_cache.dart');self.assertIn('return _serialize(_clear)',text);self.assertIn('epoch != _clearEpochs[preferencesKey]',text)
 def test_legacy_removed_not_migrated_into_trusted_cache(self):
  text=source('lib/shared/repositories/collect_offline_cache.dart').split('Future<CollectOfflineSnapshot?> _readProtected',1)[1].split('Future<void> _removeLegacyPlaintext',1)[0]
  self.assertIn('_removeLegacyPlaintext()',text);self.assertNotIn('getString(',text)
 def test_protected_read_checks_owner(self):
  self.assertIn('snapshot.currentProfile?.id.toLowerCase() != owner.toLowerCase()',source('lib/shared/repositories/collect_offline_cache.dart'))
 def test_native_channel_registered(self):
  self.assertIn('"collect/secure_snapshot"',source('android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt'))
 def test_android_not_backed_up(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/security/ProtectedSnapshotStore.kt');self.assertIn('context.noBackupFilesDir',t);self.assertIn('AtomicFile',t)
 def test_android_missing_key_preserves_file(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/security/ProtectedSnapshotStore.kt').split('fun read',1)[1].split('fun write',1)[0];self.assertNotIn('delete()',t)
 def test_aad_owner_schema(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/security/SnapshotCipher.kt');self.assertEqual(t.count('cipher.updateAAD(binding(owner))'),2)
 def test_ios_keychain_protection(self):
  t=source('ios/Runner/AppDelegate.swift');self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly',t);self.assertIn('resources.isExcludedFromBackup = true',t)
 def test_ios_no_unprotected_fallback(self):
  t=source('ios/Runner/AppDelegate.swift');self.assertIn('AES.GCM.seal',t);self.assertIn('AES.GCM.open',t);self.assertNotIn('UserDefaults',t)
 def test_missing_date_not_now(self):
  t=source('lib/shared/repositories/collect_offline_cache.dart')
  self.assertRegex(t,r"savedAt:\s*exactJsonTimestamp\(json\['saved_at'\],\s*field:\s*'snapshot.saved_at'\)")
  self.assertNotIn('DateTime.now',t)
  self.assertNotIn('DateTime.now',source('lib/core/data/exact_json_values.dart'))
 def test_home_does_not_sum_recent_history(self):
  t=source('lib/features/home/home_screen.dart');self.assertIn('state.historyPage?.ownTotals',t);self.assertNotIn('raisedTotalsByCurrencyProvider',t)
 def test_home_unavailable_not_zero(self):
  t=source('lib/features/home/home_screen.dart')
  self.assertRegex(t,r"raisedTotals\s*==\s*null\s*\?\s*'Not available'\s*:\s*formatCurrencyTotals\(\s*raisedTotals\b")
 def test_home_card_no_zero_fallback(self):
  t=source('lib/features/home/home_public_groups_section.dart');self.assertNotIn('CollectionSummary(',t)
 def test_nullable_card_is_wired(self):
  for name in ['collect_group_cards.dart','collect_group_card_editorial.dart','collect_group_card_metrics.dart']:
   self.assertIn('CollectionSummary? summary;',source('lib/shared/widgets/'+name))
 def test_summary_provider_no_derived_totals(self):
  t=source('lib/shared/repositories/collect_repository_providers.dart').split('final collectionSummariesProvider',1)[1].split('final activeCollectionsProvider',1)[0];self.assertNotIn('summaryFor(',t)
if __name__=='__main__':unittest.main(verbosity=2)
