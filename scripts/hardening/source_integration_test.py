#!/usr/bin/env python3
"""Static integration checks; not Dart, Android or SQL runtime tests."""
import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def source(path):return (ROOT/path).read_text()
class IntegrationTests(unittest.TestCase):
 def test_ingest_has_no_legacy_fallback(self):
  t=source('supabase/functions/ingest-payment-sms/index.ts');self.assertIn('accept_attested_receipt_v2',t);self.assertNotIn('"ingest_raw_payment_sms"',t)
 def test_parser_never_self_confirms(self):
  t=source('supabase/functions/parse-payment-sms/index.ts');self.assertNotIn('finalize_attested_payment_sms',t);self.assertIn('awaiting_reconciliation',t)
 def test_sql_finality_is_contained(self):
  t=source('deploy/hardening/receipt_security_v2.sql').split('function public.finalize_attested_payment_sms',1)[1].split('end; $$;',1)[0];self.assertNotIn('payment.confirmed',t);self.assertIn('awaiting_reconciliation',t)
 def test_ack_body_hash_is_checked_in_sql(self):
  t=source('deploy/hardening/receipt_security_v2.sql');self.assertIn('r.body_hash is distinct from p_body_hash',t);self.assertIn('pg_advisory_xact_lock',t)
 def test_owner_rechecked_before_native_ack(self):
  t=source('lib/shared/repositories/collect_repository_contribution_actions.dart').split('Future<int> _syncPendingSmsAccessPass',1)[1]
  self.assertRegex(t,r'_requireSmsOwner\(owner, client\);\s*final acknowledged\s*=\s*await\s+_smsAccessChannel\.acknowledgeDurableReceipt\(\s*receipt,\s*\);\s*_requireSmsOwner\(owner, client\);')
 def test_mismatch_does_not_clear_queue(self):
  t=source('lib/shared/repositories/collect_repository_contribution_actions.dart').split('Future<int> _syncPendingSmsAccessPass',1)[1];self.assertNotIn('.setEnabled(false',t)
 def test_ciphertext_not_deleted_on_read_failure(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/receiver_sms/SmsQueueStore.kt').split('private fun readLocked()',1)[1].split('private fun writeLocked',1)[0];self.assertNotIn('.remove(',t);self.assertIn('throw IllegalStateException',t)
 def test_native_ack_is_owner_bound(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/MainActivity.kt');self.assertIn('acknowledgeDurable(owner, hashes)',t);self.assertIn('"contract_version") != 2',t)
 def test_phone_body_does_not_supply_sender(self):
  t=source('android/app/src/main/kotlin/app/cool/mobile/receiver_sms/CollectSmsReceiver.kt');self.assertNotIn('|| MOMO_CONTEXT_HINT.containsMatchIn(body)',t)
 def test_owner_not_display_label(self):
  t=source('lib/shared/repositories/collect_repository_providers.dart').split('bool _contributionBelongsToProfile',1)[1];self.assertNotIn('supporterLabel',t)
 def test_otp_no_static_secret(self):
  t=source('supabase/functions/auth-send-whatsapp-otp/index.ts');self.assertNotIn('x-hook-secret',t);self.assertIn('verifySmsHook',t)
 def test_integrity_oauth_contract(self):
  t=source('supabase/functions/verify-play-integrity/index.ts');self.assertIn('urn:ietf:params:oauth:grant-type:jwt-bearer',t);self.assertNotIn('account.token_uri ??',t)
 def test_privileged_readiness_not_pr_triggered(self):
  t=source('.github/workflows/supabase-readiness.yml');self.assertNotIn('pull_request:',t);self.assertIn('READONLY_DATABASE_URL',t);self.assertIn('production-readiness',t);self.assertIn('exit 1',t)
 def test_roster_preview_preserved(self):
  t=source('supabase/functions/prepare-roster-import/handler.ts');self.assertIn('create_roster_import_source',t);self.assertIn('complete_roster_import_preview',t);self.assertIn('r.can_submit !== false',t);self.assertIn('r.requires_human_review !== true',t);self.assertIn('validateRosterFile(bytes, mime)',source('supabase/functions/_shared/roster_provenance.ts'))
 def test_both_decoding_branches_keep_public_tests(self):
  for path in ['test/payment_intent_decoding_test.dart','test/payment_json_integrity_test.dart']:
   self.assertTrue((ROOT/path).is_file(),path)
  self.assertIn('flutter test --concurrency=4',source('.github/workflows/ci.yml'))
 def test_reconciliation_actor_not_caller_supplied(self):
  t=source('deploy/hardening/reconciliation_approval_v2.sql');self.assertIn('r.proposed_by=auth.uid()',t);self.assertIn("auth.jwt()->>'aal'",t);self.assertNotIn('p_reviewer_id',t)
if __name__=='__main__':unittest.main(verbosity=2)
