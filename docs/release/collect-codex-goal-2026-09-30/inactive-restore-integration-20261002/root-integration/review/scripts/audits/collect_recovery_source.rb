--- canonical/scripts/audits/collect_recovery_source.rb
+++ proposed/scripts/audits/collect_recovery_source.rb
@@ -185,9 +185,9 @@
   def options(argv, kind)
     args = argv.dup
     result = {}
-    flags = kind == :backup ? %w[--roles-only --worker-snapshot] : %w[--rehearse-migrations --worker-snapshot]
+    flags = kind == :backup ? %w[--roles-only --worker-snapshot] : %w[--rehearse-migrations --worker-snapshot --inactive-overlay]
     values = %w[--source-contract --source-contract-sha256]
-    values += %w[--database-report --roles-report --extension-metadata] if kind == :restore
+    values += %w[--database-report --roles-report --extension-metadata --inactive-reason] if kind == :restore
     positions = []
     until args.empty?
       item = args.shift
@@ -218,6 +218,12 @@
       raise Error, 'Worker snapshot cannot capture global roles' if result['--roles-only']
       raise Error, 'Worker snapshot cannot rehearse historical migrations' if result['--rehearse-migrations']
     end
+    if result['--inactive-overlay']
+      raise Error, 'Inactive overlay requires explicit worker snapshot' unless kind == :restore && result['--worker-snapshot']
+      raise Error, 'Inactive overlay requires a stop reason' unless result.key?('--inactive-reason')
+    elsif result.key?('--inactive-reason')
+      raise Error, 'Inactive stop reason requires explicit overlay'
+    end
     result['output'] = positions.last
     result
   end
