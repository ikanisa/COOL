--- canonical/scripts/tests/production_archive_restore.rb
+++ proposed/scripts/tests/production_archive_restore.rb
@@ -2,6 +2,7 @@
 # network-disabled local cluster. Never run providers. Candidate migration
 # rehearsal requires its explicit local-only flag and exact reviewed hashes.
 require_relative '../audits/collect_encrypted_database_backup'
+require_relative '../audits/collect_inactive_restore_overlay'
 
 ROOT = File.expand_path('../..', __dir__)
 DB_REPORT = File.join(ROOT, 'docs/release/ENCRYPTED_PRODUCTION_DATABASE_BACKUP_V2_2026-09-03.json')
@@ -133,6 +134,7 @@
     source_contract = CollectRecoverySource.selected_contract(options)
     source_query = source_contract && CollectRecoverySource.query(source_contract)
     worker_snapshot = options['--worker-snapshot'] == true
+    inactive_overlay = CollectInactiveRestoreOverlay.preflight!(options, source_contract)
     database_path = options.fetch('--database-report', DB_REPORT)
     roles_path = options.fetch('--roles-report', ROLE_REPORT)
     metadata_path = options.fetch('--extension-metadata', GRAPHQL_REPORT)
@@ -154,7 +156,7 @@
     end
     raise CollectReceiptWorkerSnapshot::Error, 'Worker snapshot input cannot be ignored' if database_input.key?('worker_snapshot') && !worker_snapshot
     raise CollectReceiptWorkerSnapshot::Error, 'Global-role snapshot association invalid' if roles_input.key?('worker_snapshot')
-  rescue CollectRecoverySource::Error, CollectReceiptWorkerSnapshot::Error, SystemCallError, KeyError
+  rescue CollectRecoverySource::Error, CollectReceiptWorkerSnapshot::Error, CollectInactiveRestoreOverlay::Error, SystemCallError, KeyError
     abort('Restore source preflight refused; verify all explicit inputs and the current contract before vault actions.')
   end
   rehearse = options['--rehearse-migrations'] == true
@@ -331,6 +333,11 @@
         error_path: File.join(log_dir, 'worker-restored-reader.log'))
       raise 'Restored physical worker guards changed' unless sql.call("select current_setting('cron.launch_active_jobs')='off' and current_setting('listen_addresses')='' and current_setting('pg_net.database_name')='template1' and current_setting('pg_net.batch_size')='0';") == 't'
     end
+    if inactive_overlay
+      report[:inactive_overlay] = CollectInactiveRestoreOverlay.apply(target: target, options: options, document: source_contract,
+        report: report, directory: log_dir, root: ROOT)
+      raise 'Restored physical worker guards changed' unless sql.call("select current_setting('cron.launch_active_jobs')='off' and current_setting('listen_addresses')='' and current_setting('pg_net.database_name')='template1' and current_setting('pg_net.batch_size')='0';") == 't'
+    end
     report[:result] = 'DATABASE_RESTORE_AND_DATA_COMPARISON_PASS_NOT_FULL_RECOVERY_ACCEPTANCE'
     puts 'Table data, sequences, schema/ACLs and global role definitions match.'
     if rehearse
