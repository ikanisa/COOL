--- canonical/scripts/audits/collect_inactive_restore_overlay.rb
+++ proposed/scripts/audits/collect_inactive_restore_overlay.rb
@@ -0,0 +1,180 @@
+# Isolated restore target authority stop, after original comparisons only.
+# No credential lookup, hosted connection, public RPC, or privileged fallback.
+require 'open3'
+require 'timeout'
+require 'securerandom'
+require 'time'
+require 'rbconfig'
+require_relative 'collect_recovery_source'
+
+module CollectInactiveRestoreOverlay
+  FORMAT = 'collect-inactive-restore-input-v1'.freeze
+  SQL_PATH = File.expand_path('../sql/collect_inactive_restore_overlay.sql', __dir__).freeze
+  REQUIRED = %w[20260930150000 20260930211605 20260930230100 20261001000400 20261001110000
+    20261001130000 20261001150000 20261001180000 20261001233000 20261002030000 20261002040000
+    20261002042000 20261002043000 20261002044000 20261002070000 20261002080000].freeze
+  COMPARISONS = %w[data_comparison schema_comparison roles_comparison source_catalog_comparison worker_snapshot_comparison].freeze
+  HEX = /\A[0-9a-f]{64}\z/
+  UUID = /\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/
+  class Error < RuntimeError; end
+  module_function
+
+  def refuse!(message)
+    raise Error, message
+  end
+
+  def digest_file(path)
+    Digest::SHA256.hexdigest(CollectRecoverySource.read(path))
+  end
+
+  def preflight!(options, document)
+    return false unless options['--inactive-overlay']
+    refuse!('Inactive overlay requires worker snapshot and exact contract') unless options['--worker-snapshot'] && document
+    refuse!('Inactive overlay cannot rehearse historical migrations') if options['--rehearse-migrations']
+    reason = options['--inactive-reason']
+    refuse!('Inactive overlay reason required') unless reason.is_a?(String) && reason == reason.strip && reason.length.between?(8,500) && !reason.match?(/[\x00-\x1f\x7f]/)
+    refuse!('Inactive overlay guard versions missing') unless (REQUIRED-document.fetch('catalog').fetch('migrations')).empty?
+    true
+  rescue KeyError
+    refuse!('Inactive overlay contract incomplete')
+  end
+
+  def comparison_association!(report)
+    normalized = report.transform_keys(&:to_s)
+    values = COMPARISONS.to_h do |key|
+      value=normalized[key]
+      refuse!('Inactive overlay original comparisons incomplete') unless value.is_a?(Hash)
+      value=value.transform_keys(&:to_s)
+      checked = key == 'data_comparison' ? value['all_fingerprints_match'] == true : key == 'worker_snapshot_comparison' ? value['source_state_compared_before_overlay'] == true && value['durable_inactive_overlay'] == false : value['match'] == true
+      refuse!('Inactive overlay original comparisons incomplete') unless checked
+      [key,value]
+    end
+    source = values.fetch('source_catalog_comparison')
+    refuse!('Inactive overlay original catalog must precede business changes') unless source['compared_before_any_business_policy_changes']==true && source['business_policy_overlay_applied']==false
+    CollectRecoverySource.digest(values)
+  end
+
+  def source_query(root)
+    raw=File.binread(File.join(root,'scripts/sql/collect_recovery_source_catalog.sql'))
+    start=raw.index('WITH ns AS (')
+    refuse!('Inactive overlay source query invalid') unless start && raw.end_with?(";\nCOMMIT;\n")
+    query=raw[start...raw.rindex(";\nCOMMIT;")]
+    # This query belongs only to the overlay: retain unmodified original comparison.
+    query=query.sub("nspname <> 'information_schema'", "nspname <> 'information_schema' AND nspname <> 'collect_recovery_restore'")
+    query=query.sub("WHERE (a.schema IN", "WHERE a.schema IS DISTINCT FROM 'collect_recovery_restore' AND b.schema IS DISTINCT FROM 'collect_recovery_restore' AND (a.schema IN")
+    query
+  end
+
+  def literal(value)
+    "'" + value.gsub("'", "''") + "'"
+  end
+
+  def input!(target:, document:, contract_sha256:, archive_sha256:, comparison_sha256:, reason:, tools_sha256:, restore_id: SecureRandom.uuid)
+    refuse!('Inactive overlay target invalid') unless target.is_a?(String) && /\Acollect-recovery-[a-z0-9-]{8,80}\z/.match?(target)
+    refuse!('Inactive overlay request invalid') unless UUID.match?(restore_id)
+    [contract_sha256,archive_sha256,comparison_sha256,tools_sha256].each { |sha| refuse!('Inactive overlay digest invalid') unless sha.is_a?(String) && HEX.match?(sha) }
+    refuse!('Inactive overlay reason invalid') unless reason.is_a?(String) && reason == reason.strip && reason.length.between?(8,500) && !reason.match?(/[\x00-\x1f\x7f]/)
+    { 'format'=>FORMAT,'restore_id'=>restore_id,'target'=>target,'source_contract_sha256'=>contract_sha256,
+      'source_catalog_sha256'=>document.fetch('catalog_sha256'),'source_vector_sha256'=>CollectRecoverySource.digest(document.fetch('migration_files')),
+      'archive_sha256'=>archive_sha256,'comparison_sha256'=>comparison_sha256,'reason'=>reason,
+      'tools_sha256'=>tools_sha256,'sql_sha256'=>digest_file(SQL_PATH),'expires_at'=>(Time.now.utc+120).iso8601(6) }
+  end
+
+  def script(context, document, root:)
+    raw=CollectRecoverySource.read(SQL_PATH)
+    refuse!('Inactive overlay SQL changed') unless context['sql_sha256']==Digest::SHA256.hexdigest(raw)
+    guard=raw[/AS \$guard\$(.*?)\$guard\$/m,1]
+    refuse!('Inactive overlay guard absent') unless guard
+    replacements={'__CONTEXT__'=>literal(JSON.generate(context)),'__CATALOG__'=>literal(JSON.generate(document.fetch('catalog'))),
+      '__SOURCE_QUERY__'=>source_query(root),'__SOURCE_QUERY_FINAL__'=>source_query(root),'__GUARD_HASH__'=>Digest::SHA256.hexdigest(guard)}
+    replacements.each { |token,value| refuse!('Inactive overlay SQL token invalid') unless raw.scan(token).length==1; raw=raw.sub(token){value} }
+    refuse!('Inactive overlay SQL unresolved') if raw.match?(/__[A-Z_]+__/)
+    raw
+  end
+
+  def result!(raw)
+    value=CollectRecoverySource.parse(raw.strip)
+    expected=%w[format restore_id recorded_at delta_sha256 item_count resume_required financial_action send_action session_owner effective_owner]
+    valid=value.is_a?(Hash) && value.keys.sort==expected.sort && value['format']=='collect-inactive-restore-result-v1' &&
+      value['restore_id'].is_a?(String) && UUID.match?(value['restore_id']) && value['recorded_at'].is_a?(String) &&
+      value['recorded_at'].match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,6})?(?:Z|\+00:00)\z/) &&
+      value['resume_required']==true && value['financial_action']==false && value['send_action']==false &&
+      value['session_owner']=='postgres' && value['effective_owner']=='postgres' &&
+      value['item_count'].is_a?(Integer) && value['item_count'].between?(10,2013) &&
+      value['delta_sha256'].is_a?(String) && HEX.match?(value['delta_sha256'])
+    refuse!('Inactive overlay result invalid') unless valid
+    Time.iso8601(value['recorded_at'])
+    value
+  rescue ArgumentError,CollectRecoverySource::Error
+    refuse!('Inactive overlay result invalid')
+  end
+
+  def execute(argv, text, error_path:)
+    target=argv.is_a?(Array) ? argv[3] : nil
+    expected=['docker','exec','-i',target,'psql','-w','-XqAt','-h','/run/collect','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1']
+    refuse!('Inactive overlay owner invocation invalid') unless argv==expected && target.is_a?(String) && /\Acollect-recovery-[a-z0-9-]{8,80}\z/.match?(target)
+    out='';err='';status=nil
+    Open3.popen3(*argv, pgroup:true) do |stdin,stdout,stderr,wait|
+      readers=[Thread.new{stdout.read},Thread.new{stderr.read}]
+      begin
+        Timeout.timeout(45) do
+          stdin.write(text);stdin.close;status=wait.value
+          out=readers[0].value;err=readers[1].value
+        end
+      rescue Timeout::Error
+        Process.kill('TERM',-wait.pid) rescue nil
+        begin;Timeout.timeout(3){wait.value};rescue Timeout::Error;Process.kill('KILL',-wait.pid)rescue nil;wait.value;end
+        File.write(error_path,'Owner transaction response timed out; original input UUID must be reconciled before any new attempt. No completion is claimed.'+"\n",mode:'wb',perm:0600)
+        refuse!('Inactive overlay owner transaction timed out; inspect original restore UUID')
+      ensure
+        stdin.close rescue nil
+        readers.each{|t|t.join(1);t.kill if t.alive?}
+      end
+    end
+    File.write(error_path,err,mode:'wb',perm:0600)
+    refuse!('Inactive overlay owner transaction refused; private receipt retained') unless status.success?
+    result!(out)
+  rescue SystemCallError,CollectRecoverySource::Error
+    refuse!('Inactive overlay owner execution unavailable')
+  end
+
+  def tooling(root)
+    docker=ENV.fetch('PATH','').split(File::PATH_SEPARATOR).map{|part|File.expand_path('docker',part)}.find{|path|File.file?(path)&&File.executable?(path)}
+    refuse!('Inactive overlay Docker executable unavailable') unless docker
+    files={ 'helper'=>__FILE__, 'source_helper'=>File.expand_path('collect_recovery_source.rb',__dir__),
+      'source_query'=>File.join(root,'scripts/sql/collect_recovery_source_catalog.sql'),
+      'restore_caller'=>File.join(root,'scripts/tests/production_archive_restore.rb'),
+      'ruby'=>File.realpath(RbConfig.ruby), 'docker'=>File.realpath(docker) }
+    values=files.to_h do |kind,path|
+      before=File.lstat(path);refuse!('Inactive overlay tool/source must be a regular file') unless before.file?
+      digest=File.open(path,File::RDONLY|File::NOFOLLOW)do|f|
+        now=f.stat;refuse!('Inactive overlay tool/source changed during open') unless [before.dev,before.ino,before.size]==[now.dev,now.ino,now.size]
+        Digest::SHA256.file(f).hexdigest
+      end
+      after=File.lstat(path);refuse!('Inactive overlay tool/source changed during capture') unless [before.dev,before.ino,before.size,before.mtime]==[after.dev,after.ino,after.size,after.mtime]
+      [kind,{'path'=>path,'bytes'=>before.size,'sha256'=>digest}]
+    end
+    {'ruby_description'=>RUBY_DESCRIPTION,'files'=>values}
+  rescue SystemCallError
+    refuse!('Inactive overlay tool/source unavailable')
+  end
+
+  def apply(target:, options:, document:, report:, directory:, root:)
+    refuse!('Inactive overlay explicit opt-in required') unless preflight!(options,document)
+    comparison=comparison_association!(report)
+    tools=tooling(root)
+    tools_sha256=CollectRecoverySource.digest(tools)
+    context=input!(target:target,document:document,contract_sha256:options.fetch('--source-contract-sha256'),archive_sha256:report.fetch(:source_database_sha256),
+      comparison_sha256:comparison,reason:options.fetch('--inactive-reason'),tools_sha256:tools_sha256)
+    # Original comparison flags, archived inputs and expected catalog are bound before writing.
+    raw=script(context,document,root:root)
+    File.write(File.join(directory,'inactive-overlay-tooling.json'),JSON.generate(tools)+"\n",mode:'wb',perm:0600)
+    input_path=File.join(directory,'inactive-overlay-input.json');File.write(input_path,JSON.generate(context)+"\n",mode:'wb',perm:0600)
+    argv=['docker','exec','-i',target,'psql','-w','-XqAt','-h','/run/collect','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1']
+    value=execute(argv,raw,error_path:File.join(directory,'inactive-overlay-owner.log'))
+    refuse!('Inactive overlay original UUID result conflict') unless value['restore_id']==context['restore_id']
+    refuse!('Inactive overlay source/tool/SQL changed after execution') unless context['sql_sha256']==digest_file(SQL_PATH) && tools==tooling(root) && document==CollectRecoverySource.selected_contract(options,root:root)
+    value.merge('input_sha256'=>Digest::SHA256.file(input_path).hexdigest,'sql_sha256'=>context['sql_sha256'],
+      'source_contract_sha256'=>context['source_contract_sha256'],'comparison_sha256'=>comparison,'tools_sha256'=>tools_sha256,'same_target_restart_only'=>true,'target_cleanup_survival'=>false)
+  end
+end
