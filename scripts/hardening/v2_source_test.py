#!/usr/bin/env python3
"""Source wiring invariants only: NOT Flutter, Android, iOS or SQL runtime tests."""
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def source(path):return (ROOT/path).read_text()
class V2Integration(unittest.TestCase):
 def test_live_repository_requires_protected_cache(self):
  text=source('lib/shared/repositories/collect_repository.dart').split('CollectRepository.fixture',1)[0]
  self.assertIn('CollectOfflineCache.protected()',text)
 def test_cache_owner_bound_read(self):
  self.assertIn('_offlineCache.read(ownerUserId: initialUserId)',source('lib/shared/repositories/collect_repository_offline_snapshot.dart'))
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
  android='android/app/src/main/kotlin/app/cool/mobile/'
  self.assertIn('storage.register(messenger)',source(android+'MainActivity.kt'))
  self.assertIn('"collect/secure_snapshot"',source(android+'MemberProtectedChannels.kt'))
  self.assertIn('protectedChannels.register(with: messenger)',source('ios/Runner/AppDelegate.swift'))
  self.assertIn('"collect/secure_snapshot"',source('ios/Runner/MemberProtectedChannels.swift'))
 def test_android_not_backed_up(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/security/ProtectedSnapshotStore.kt');self.assertIn('context.noBackupFilesDir',t);self.assertIn('AtomicFile',t)
 def test_android_missing_key_preserves_file(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/security/ProtectedSnapshotStore.kt').split('fun read',1)[1].split('fun write',1)[0];self.assertNotIn('delete()',t)
 def test_aad_owner_schema(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/security/SnapshotCipher.kt');self.assertEqual(t.count('cipher.updateAAD(binding(owner))'),2)
 def test_ios_keychain_protection(self):
  t=source('ios/Runner/CollectProtectedSnapshotStore.swift');self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly',t);self.assertIn('resources.isExcludedFromBackup = true',t)
 def test_ios_no_unprotected_fallback(self):
  t=source('ios/Runner/CollectProtectedSnapshotStore.swift');self.assertIn('AES.GCM.seal',t);self.assertIn('AES.GCM.open',t);self.assertNotIn('UserDefaults',t)
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
class SourceInventory(unittest.TestCase):
    def test_default_and_release_scopes_partition_the_full_checkout(self):
        with tempfile.TemporaryDirectory() as scratch:
            fixture = pathlib.Path(scratch) / "repo"
            tool = fixture / "scripts/hardening/source_inventory.py"
            tool.parent.mkdir(parents=True)
            shutil.copyfile(ROOT / "scripts/hardening/source_inventory.py", tool)
            inputs = {
                "lib/app.dart": b"tracked source\n",
                "docs/release/checkpoint/receipt.json": b"{}\n",
                "docs/release-notes/current.md": b"current release notes\n",
                ".env.local": b"fixture-private-value\n",
                "asset.p12": b"fixture-key\n",
            }
            for name, data in inputs.items():
                path = fixture / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
            (fixture / "linked.dart").symlink_to("lib/app.dart")
            def git(*args):
                subprocess.run(["git", *args], cwd=fixture, check=True, stdout=subprocess.DEVNULL)
            git("init", "-q")
            git("add", "-f", "--", *inputs, "linked.dart")
            git("-c", "user.name=Inventory fixture", "-c", "user.email=inventory@localhost",
                "-c", "commit.gpgsign=false", "commit", "-qm", "inventory fixture")
            (fixture / "lib/app.dart").write_bytes(b"working copy\n")
            (fixture / "untracked.dart").write_text("local")

            def inventory(scope=None):
                output = pathlib.Path(scratch) / "inventory.json"
                command = [sys.executable, str(tool), "--output", str(output)]
                if scope:
                    command.extend(["--scope", scope])
                subprocess.run(command, cwd=fixture, check=True)
                report = json.loads(output.read_text())
                self.assertEqual(report["scope"], scope or "source")
                self.assertFalse(report["private_values_exported"])
                self.assertFalse(report["reachability_proven"])
                return {row["path"]: row for row in report["files"]}

            source, evidence, full = inventory(), inventory("release-evidence"), inventory("checkout")
            self.assertEqual(set(evidence), {"docs/release/checkpoint/receipt.json"})
            self.assertEqual(set(source), set(inputs) - set(evidence))
            self.assertEqual({**evidence, **source}, full)
            self.assertEqual(source["lib/app.dart"]["sha256"], hashlib.sha256(b"working copy\n").hexdigest())
            for name in (".env.local", "asset.p12"):
                self.assertEqual(source[name], {"path": name, "bytes": len(inputs[name]),
                                                "classification": "private-review-required"})


if __name__=='__main__':unittest.main(verbosity=2)
