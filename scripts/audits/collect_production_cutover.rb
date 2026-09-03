# Approved 2026-09-03 cutover: exact rehearsed migration bytes, one atomic
# transaction, matching migration history, no provider sends or network edits.
require 'json'
require 'digest'
require 'net/http'
require 'io/console'
require 'time'
require_relative 'collect_hosted_preflight'
require_relative 'collect_index_inventory'

module CollectProductionCutover
  ROOT = File.expand_path('../..', __dir__)
  REF = 'lhbowpbcpwoiparwnwgt'.freeze
  SOURCE = 'docs/release/SUPABASE_PREFLIGHT_CURRENT_2026-09-02.json'.freeze
  REHEARSAL = 'docs/release/PRODUCTION_COPY_UPGRADE_REHEARSAL_V4_2026-09-03.json'.freeze
  PROTECTED = %w[profiles payments ledger_entries raw_payment_sms bank_transactions bank_ledger_entries].freeze

  def self.manifest
    source = JSON.parse(File.read(File.join(ROOT, SOURCE)))
    raise 'Unexpected source project' unless source.dig('project','id') == REF
    entries = source.dig('checks','migrations','pending')
    raise 'Exactly 14 reviewed migrations required' unless entries.length == 14
    entries.map do |entry|
      file = entry.fetch('file')
      raise 'Invalid manifest filename' unless file == "#{entry.fetch('version')}_#{entry.fetch('name')}.sql" && file.match?(/\A\d{14}_[a-z_]+\.sql\z/)
      content = File.read(File.join(ROOT,'supabase/migrations',file))
      raise 'Reviewed migration bytes changed' unless Digest::SHA256.hexdigest(content) == entry.fetch('sha256')
      entry.merge('content'=>content)
    end
  end

  def self.body(sql)
    raise 'Explicit outer transaction required' unless sql.match?(/\Abegin\s*;/i) && sql.match?(/commit\s*;\s*\z/i)
    result = sql.sub(/\Abegin\s*;\s*/i,'').sub(/\s*commit\s*;\s*\z/i,'')
    raise 'Nested SQL transaction not supported' if result.match?(/^\s*(?:begin|commit|rollback|start transaction)\s*;/i)
    result
  end

  def self.transaction(entries, remote)
    versions = remote.map { |row| row.fetch('version') }.sort
    raise 'Wrong production baseline' unless versions.length == 97 && versions.uniq == versions && versions.all? { |v| v.match?(/\A\d+\z/) }
    parts = [<<~SQL]
      BEGIN;
      SET LOCAL lock_timeout='5s';
      SET LOCAL statement_timeout='90s';
      DO $cutover_guard$ BEGIN
        IF NOT pg_try_advisory_xact_lock(20260903, 111) THEN RAISE EXCEPTION 'Another cutover is running'; END IF;
        IF (SELECT array_agg(version::text ORDER BY version) FROM supabase_migrations.schema_migrations)
          IS DISTINCT FROM ARRAY[#{versions.map { |v| "'#{v}'" }.join(',')}]::text[] THEN
          RAISE EXCEPTION 'Production migration history changed';
        END IF;
      END $cutover_guard$;
    SQL
    entries.each do |entry|
      content = entry.fetch('content')
      tag = '$collect_cutover_source$'
      raise 'SQL quoting collision' if content.include?(tag)
      parts << body(content) + "\n;\n"
      parts << "INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES ('#{entry.fetch('version')}','#{entry.fetch('name')}',ARRAY[#{tag}#{content}#{tag}]);"
    end
    parts << "NOTIFY pgrst,'reload schema';\nCOMMIT;"
    parts.join("\n")
  end

  def self.request(token, path, payload=nil)
    uri = URI("https://api.supabase.com/v1/projects/#{REF}#{path}")
    req = payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{token}"
    if payload
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(payload)
    end
    http = Net::HTTP.new(uri.host,443)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 110
    response = http.request(req)
    # Do not expose server error context containing private row data or SQL.
    raise "Management API HTTP #{response.code}; inspect history before any retry" unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body)
  end

  def self.query(token, sql, write: false)
    request(token,'/database/query',{query:sql,read_only:!write})
  end

  def self.history(token)
    query(token,'SELECT version,name FROM supabase_migrations.schema_migrations ORDER BY version;')
  end

  # The Management API read_only flag selects supabase_read_only_user. Its
  # information_schema views intentionally hide grants to other roles. Audit
  # ACLs as the authorized database owner, inside an SQL READ ONLY transaction.
  def self.catalog_query(token, sql)
    request(token,'/database/query',{
      query:"BEGIN READ ONLY; SET LOCAL statement_timeout='30s'; #{sql}\nROLLBACK;",
      read_only:false})
  end

  def self.projections(token)
    query(token,<<~SQL).to_h { |row| [row.fetch('table_name'),row.fetch('columns')] }
      SELECT table_name,jsonb_agg(column_name ORDER BY ordinal_position) AS columns
      FROM information_schema.columns WHERE table_schema='public'
        AND table_name IN (#{PROTECTED.map { |n| "'#{n}'" }.join(',')}) GROUP BY table_name;
    SQL
  end

  def self.fingerprint(token, projections)
    queries = projections.map do |table, columns|
      raise 'Unexpected protected table' unless PROTECTED.include?(table)
      raise 'Unexpected column identifier' unless columns.is_a?(Array) && columns.all? { |n| n.match?(/\A[a-z_][a-z0-9_]*\z/) }
      "SELECT '#{table}' AS table_name,count(*) AS rows,encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text),''),'sha256'),'hex') AS sha256 FROM (SELECT #{columns.map { |n| '"'+n+'"' }.join(',')} FROM public.#{table}) t"
    end
    query(token,queries.join(' UNION ALL ')+' ORDER BY table_name;')
  end

  def self.readback(token)
    context = query(token,"SELECT current_user, current_setting('transaction_read_only') AS transaction_read_only, has_function_privilege('authenticated','public.get_current_member_profile()','execute') AS member_rpc_granted;").first
    readiness = File.read(File.join(ROOT,'scripts/supabase_production_readiness.sh'))
    patterns = {privileges:/    with allowed_table_grants.*?    order by issue;/m,
      columns:/    with roles\(grantee\).*?    order by 1;/m,
      rails:/    with required_authenticated\(routine_name\).*?    order by issue;/m}
    results = patterns.to_h do |name,pattern|
      sql = readiness[pattern] or raise 'Readiness marker changed'
      rows = catalog_query(token,sql)
      raise "Permission readback failed: #{name}: #{JSON.generate(rows)}" unless rows.empty?
      [name,'pass']
    end
    indexes = CollectIndexInventory.expected(Dir[File.join(ROOT,'supabase/migrations/*.sql')].sort.map { |p|File.read(p) })
    raise 'Missing required index' unless query(token,CollectIndexInventory.query(indexes)).empty?
    results[:indexes] = 'pass'
    entries = manifest
    versions = entries.map { |e| "'#{e.fetch('version')}'" }.join(',')
    history_hashes = query(token,"SELECT version,encode(extensions.digest(statements[1],'sha256'),'hex') AS sha256 FROM supabase_migrations.schema_migrations WHERE version IN (#{versions}) ORDER BY version;")
    raise 'Deployed migration source hashes differ' unless history_hashes == entries.map { |e|e.slice('version','sha256') }
    results[:deployed_migration_sha256] = '14 exact source matches'
    results[:read_only_api_context] = context
    results[:catalog_audit_context] = catalog_query(token,"SELECT current_user,current_setting('transaction_read_only') AS transaction_read_only;").first
    results[:inventory] = query(token,<<~SQL).first
      SELECT (SELECT count(*) FROM supabase_migrations.schema_migrations) AS migrations,
        (SELECT count(*) FROM collect_hybrid.member_records) AS member_records,
        (SELECT count(*) FROM collect_admin_access.whatsapp_approvals) AS operator_approvals,
        (SELECT count(*) FROM storage.objects) AS storage_objects,
        (SELECT count(*) FROM storage.buckets) AS storage_buckets,
        NOT EXISTS(SELECT 1 FROM public.profiles p LEFT JOIN collect_hybrid.member_records m ON m.linked_user_id=p.id
          WHERE m.id IS NULL OR m.id<>p.id OR m.collect_id<>p.public_id OR m.origin<>'app') AS member_backfill_valid,
        NOT EXISTS(SELECT 1 FROM public.feature_flags WHERE key='hybrid_member_onboarding' AND enabled) AS hybrid_onboarding_remains_off;
    SQL
    raise 'Unexpected upgrade state' unless results[:inventory]['migrations'] == 111 && results[:inventory]['member_backfill_valid'] && results[:inventory]['hybrid_onboarding_remains_off']
    results
  end

  def self.run(mode, output)
    raise 'Invalid cutover mode' unless %w[plan apply readback].include?(mode)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    raise 'Linked project mismatch' unless File.read(File.join(ROOT,'supabase/.temp/project-ref')).strip == REF
    entries = manifest
    rehearsal = JSON.parse(File.read(File.join(ROOT,REHEARSAL)))
    raise 'Actual production-copy upgrade rehearsal required' unless rehearsal.dig('migration_rehearsal','status') == 'pass'
    STDOUT.sync = true
    puts 'Awaiting release credential on non-echoing stdin.'
    raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(raw.to_s)
    raw&.clear
    raise 'Wrong credential scope' unless credential.fetch('project_url') == "https://#{REF}.supabase.co"
    token = credential.fetch('access_token')
    raise 'Expected Management API credential' unless token.start_with?('sbp_')
    report = {started_at:Time.now.utc.iso8601,project:REF,mode:mode,result:'IN_PROGRESS',migration_commit_attempted:false,provider_sends:0,network_mutations:0}
    begin
      project = request(token,'')
      raise 'Wrong or unhealthy authenticated project' unless project['id']==REF && project['name']=='COOL' && project['status']=='ACTIVE_HEALTHY'
      remote = history(token)
      if mode == 'readback'
        report[:checks] = readback(token)
      else
        plan = CollectHostedPreflight.plan(remote,File.join(ROOT,'supabase/migrations'))
        raise 'Reviewed pending set changed' unless plan[:pending] == entries.map { |e|e.reject { |k,_| k=='content' } } && plan[:remote_only].empty? && plan[:history_holes].empty?
        sql = transaction(entries,remote)
        report[:migrations] = entries.map { |e|e.reject { |k,_|k=='content' } }
        report[:atomic_transaction_sha256] = Digest::SHA256.hexdigest(sql)
        report[:baseline_migrations] = remote.length
        puts 'Exact 14 migration hashes and 97-migration baseline verified.'
        if mode == 'apply'
          projection = projections(token)
          raise 'Missing financial/profile protection' unless %w[profiles payments ledger_entries raw_payment_sms bank_transactions].all? { |t|projection.key?(t) }
          before = fingerprint(token,projection)
          report[:migration_commit_attempted] = true
          query(token,sql,write:true)
          report[:committed_migrations] = history(token).length
          raise 'Unexpected committed history' unless report[:committed_migrations] == 111
          puts 'Atomic cutover committed; 111 migration records read back.'
          after = fingerprint(token,projection)
          report[:protected_data] = {before:before,after:after,unchanged:before==after}
          raise 'Protected data changed; investigate without automatic rollback' unless before == after
          report[:checks] = readback(token)
        end
      end
      report[:result] = mode == 'apply' ? 'MIGRATIONS_DEPLOYED_AND_VERIFIED_NOT_FULL_PRODUCTION_GO' : 'PASS'
    rescue StandardError => error
      report[:result] = 'FAILED_REQUIRES_READBACK_BEFORE_RETRY'
      report[:error] = error.message.gsub(token,'[redacted]')
      warn "Cutover stopped: #{report[:error]}"
    ensure
      report[:finished_at] = Time.now.utc.iso8601
      File.open(output,File::WRONLY|File::CREAT|File::EXCL,0600) { |f|f.write(JSON.pretty_generate(report)+"\n") }
      puts JSON.generate(report:output,result:report[:result])
    end
    report[:result] != 'FAILED_REQUIRES_READBACK_BEFORE_RETRY'
  ensure
    raw&.clear
    token&.clear
    credential&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_production_cutover.rb plan|apply|readback NEW_REPORT.json') unless ARGV.length==2
  exit(CollectProductionCutover.run(*ARGV) ? 0 : 1)
end
