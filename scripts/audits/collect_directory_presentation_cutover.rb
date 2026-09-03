# Narrow, authorized display-only release. Uses the CLI's existing owner login;
# never reads its credential store or prints credentials/private database rows.
require 'json'
require 'digest'
require 'open3'
require 'tempfile'
require 'time'

module CollectDirectoryPresentationCutover
  ROOT = File.expand_path('../..', __dir__)
  REF = 'lhbowpbcpwoiparwnwgt'.freeze
  VERSION = '20260903200322'.freeze
  NAME = 'hybrid_directory_presentation'.freeze
  SHA = '2909300e938a4f09012e025c7d22136953ff53ffd9c4713662a9bc33ffc5c4c1'.freeze
  CLI = '/Users/jeanbosco/.npm/_npx/1517203cdeef2779/node_modules/@supabase/cli-darwin-arm64/bin/supabase'.freeze
  PROTECTED = %w[public.profiles public.payments public.ledger_entries public.raw_payment_sms public.bank_transactions public.bank_transaction_allocations public.journal_entries public.collection_members public.collections public.collection_receivers public.admin_user_roles public.feature_flags collect_admin_access.whatsapp_approvals collect_hybrid.member_records collect_hybrid.member_momo_identities].freeze

  def self.query(sql)
    Tempfile.create(['collect-directory-release-', '.sql']) do |file|
      file.chmod(0600)
      file.write(sql)
      file.flush
      out, _err, status = Open3.capture3(CLI, 'db', 'query', '--linked', '--project-ref', REF, '--file', file.path, '-o', 'json', '--agent=yes')
      raise 'Owner CLI query failed; inspect live history before retrying a write' unless status.success?
      JSON.parse(out).fetch('rows')
    end
  end

  def self.transaction(source, versions)
    raise 'Source hash mismatch' unless Digest::SHA256.hexdigest(source) == SHA
    raise 'Wrong baseline' unless versions.length == 120 && versions.last == '20260903092500' && versions.uniq == versions && versions.all? { |v| v.match?(/\A\d{12}(?:\d{2})?\z/) }
    raise 'Outer transaction missing' unless source.match?(/\Abegin\s*;/i) && source.match?(/commit\s*;\s*\z/i)
    body = source.sub(/\Abegin\s*;\s*/i, '').sub(/\s*commit\s*;\s*\z/i, '')
    raise 'Quoting collision' if source.include?('$directory_source$')
    checks = PROTECTED.map do |table|
      "SELECT '#{table}' AS relation, count(*) AS rows, md5(coalesce(string_agg(to_jsonb(t)::text, '' ORDER BY to_jsonb(t)::text), '')) AS fingerprint FROM #{table} t"
    end.join("\nUNION ALL\n")
    <<~SQL
      BEGIN ISOLATION LEVEL REPEATABLE READ;
      SET LOCAL lock_timeout='5s';
      SET LOCAL statement_timeout='90s';
      DO $guard$ BEGIN
        IF NOT pg_try_advisory_xact_lock(20260903, 121) THEN RAISE EXCEPTION 'Another directory cutover is running'; END IF;
        IF (SELECT array_agg(version::text ORDER BY version) FROM supabase_migrations.schema_migrations) IS DISTINCT FROM ARRAY[#{versions.map { |v| "'#{v}'" }.join(',')}]::text[] THEN RAISE EXCEPTION 'Migration history changed'; END IF;
      END $guard$;
      CREATE TEMP TABLE directory_data_before ON COMMIT DROP AS #{checks};
      CREATE TEMP TABLE directory_acl_before ON COMMIT DROP AS
        SELECT oid, proacl, proowner FROM pg_proc WHERE oid IN ('public.admin_list_members(text,text,integer,integer,text)'::regprocedure, 'public._admin_list_people_by_membership(boolean,text,text,integer,integer,text)'::regprocedure);
      #{body}
      CREATE TEMP TABLE directory_data_after ON COMMIT DROP AS #{checks};
      DO $verify$ BEGIN
        IF EXISTS ((SELECT * FROM directory_data_before EXCEPT SELECT * FROM directory_data_after) UNION ALL (SELECT * FROM directory_data_after EXCEPT SELECT * FROM directory_data_before)) THEN RAISE EXCEPTION 'Protected rows changed'; END IF;
        IF EXISTS (SELECT 1 FROM directory_acl_before old JOIN pg_proc live ON live.oid=old.oid WHERE old.proacl IS DISTINCT FROM live.proacl OR old.proowner<>live.proowner) THEN RAISE EXCEPTION 'Function privilege or owner drift'; END IF;
      END $verify$;
      INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES ('#{VERSION}','#{NAME}',ARRAY[$directory_source$#{source}$directory_source$]);
      NOTIFY pgrst,'reload schema';
      COMMIT;
      SELECT version,name,encode(extensions.digest(statements[1],'sha256'),'hex') AS sha256 FROM supabase_migrations.schema_migrations WHERE version='#{VERSION}';
    SQL
  end

  def self.run(mode, output)
    raise 'Use plan or apply' unless %w[plan apply].include?(mode)
    raise 'New JSON report path required' unless output.end_with?('.json') && !File.exist?(output)
    raise 'Linked project mismatch' unless File.read(File.join(ROOT,'supabase/.temp/project-ref')).strip == REF
    source = File.read(File.join(ROOT,"supabase/migrations/#{VERSION}_#{NAME}.sql"))
    versions = query('SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;').map { |r| r.fetch('version') }
    sql = transaction(source, versions)
    report = {at:Time.now.utc.iso8601,project:REF,mode:mode,baseline:versions.length,migration:VERSION,source_sha256:SHA,transaction_sha256:Digest::SHA256.hexdigest(sql),protected_relations:PROTECTED,provider_sends:0}
    if mode == 'apply'
      report[:commit_attempted] = true
      begin
        rows = query(sql)
        raise 'Migration source readback mismatch' unless rows == [{'version'=>VERSION,'name'=>NAME,'sha256'=>SHA}]
        report[:result] = 'DEPLOYED_AND_VERIFIED'
        report[:protected_data_and_acl] = 'UNCHANGED_IN_ATOMIC_TRANSACTION'
      rescue StandardError => error
        report[:result] = 'INSPECT_LIVE_HISTORY_BEFORE_RETRY'
        report[:error] = error.message
      end
    else
      report[:result] = 'PLAN_VERIFIED'
    end
    File.open(output,File::WRONLY|File::CREAT|File::EXCL,0600) { |f| f.write(JSON.pretty_generate(report)+"\n") }
    puts JSON.generate(report)
    report[:result] != 'INSPECT_LIVE_HISTORY_BEFORE_RETRY'
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_directory_presentation_cutover.rb plan|apply NEW_REPORT.json') unless ARGV.length == 2
  exit(CollectDirectoryPresentationCutover.run(*ARGV) ? 0 : 1)
end
