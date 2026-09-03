# One reviewed ACL migration only. Credentials arrive through non-echoing stdin
# and are never written to argv, dotenv, reports or shell history.
require 'json'
require 'digest'
require 'net/http'
require 'io/console'
require 'time'

module CollectMemberProfileWriteCutover
  ROOT = File.expand_path('../..', __dir__)
  REF = 'lhbowpbcpwoiparwnwgt'.freeze
  FILE = '20260903083947_member_profile_rpc_only_writes.sql'.freeze
  VERSION, NAME = File.basename(FILE, '.sql').split('_', 2)
  PROTECTED = %w[profiles payments ledger_entries raw_payment_sms bank_transactions].freeze

  def self.step(name)
    yield
  rescue RuntimeError => error
    raise "#{name}: #{error.message}"
  end

  def self.request(token, path, payload = nil)
    uri = URI("https://api.supabase.com/v1/projects/#{REF}#{path}")
    req = payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{token}"
    if payload
      req['Content-Type'] = 'application/json'
      req.body = JSON.generate(payload)
    end
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 90
    response = http.request(req)
    unless response.is_a?(Net::HTTPSuccess)
      api_message = begin
        parsed = JSON.parse(response.body)
        parsed['message'].to_s.gsub(/[\r\n]+/, ' ')[0, 400]
      rescue JSON::ParserError
        ''
      end
      suffix = api_message.empty? ? '' : ": #{api_message}"
      raise "Management API HTTP #{response.code}#{suffix}; read back before retrying"
    end
    JSON.parse(response.body)
  end

  def self.catalog(token, sql)
    statement = sql.rstrip.sub(/;\z/, '')
    request(token, '/database/query', {
      query: "BEGIN READ ONLY; SET LOCAL statement_timeout='30s'; #{statement};\nROLLBACK;",
      read_only: false
    })
  end

  def self.history(token)
    catalog(token, 'select version,name from supabase_migrations.schema_migrations order by version;')
  end

  def self.acl(token)
    catalog(token, <<~SQL).first
      select
        exists(select 1 from information_schema.table_privileges
          where table_schema='public' and table_name='profiles'
            and grantee='PUBLIC' and privilege_type='UPDATE') as public_table_update,
        exists(select 1 from information_schema.column_privileges
          where table_schema='public' and table_name='profiles'
            and grantee='PUBLIC' and privilege_type='UPDATE') as public_column_update,
        has_table_privilege('anon','public.profiles','UPDATE') as anon_table_update,
        has_any_column_privilege('anon','public.profiles','UPDATE') as anon_column_update,
        has_table_privilege('authenticated','public.profiles','UPDATE') as authenticated_table_update,
        has_any_column_privilege('authenticated','public.profiles','UPDATE') as authenticated_column_update,
        has_function_privilege('authenticated',
          'public.update_current_member_profile(text,text,text,text,text)','EXECUTE') as member_edit_rpc,
        has_function_privilege('authenticated',
          'public.update_current_profile(text,text,text,text,text,text,text)','EXECUTE') as legacy_profile_rpc,
        (select coalesce(jsonb_agg(column_name order by column_name),'[]')
          from information_schema.column_privileges
          where table_schema='public' and table_name='profiles'
            and grantee='authenticated' and privilege_type='UPDATE') as authenticated_update_columns
    SQL
  end

  def self.integrity(token)
    catalog(token, <<~SQL).first
      select
        count(*) filter (where momo_number_hash is not null) as hashed_profiles,
        count(*) filter (
          where momo_number_hash is not null
            and not (
              (momo_number ~ '^07[2389][0-9]{7}$'
                and momo_number_hash = encode(
                  extensions.digest('+250' || substr(momo_number, 2), 'sha256'), 'hex'))
              or (momo_number ~ '^\\+2507[2389][0-9]{7}$'
                and momo_number_hash = encode(
                  extensions.digest(momo_number, 'sha256'), 'hex'))
            )
        ) as inconsistent_hashes
      from public.profiles
    SQL
  end

  def self.fingerprints(token)
    union = PROTECTED.map do |table|
      <<~SQL.strip
        select '#{table}' as table_name,count(*) as row_count,
          encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(row_value) order by row_value.id)::text,'[]'),'sha256'),'hex') as sha256
        from public.#{table} row_value
      SQL
    end.join(' union all ')
    catalog(token, "select * from (#{union}) fingerprints order by table_name;")
  end

  def self.plan(token, source)
    remote = step('migration history') { history(token) }
    remote_versions = remote.map { |row| row.fetch('version').to_s }
    local_versions = Dir[File.join(ROOT, 'supabase/migrations/*.sql')].sort.map do |path|
      File.basename(path).split('_', 2).first
    end
    raise 'Migration history is not unique' unless remote_versions.uniq == remote_versions
    raise 'Local migration versions are not unique' unless local_versions.uniq == local_versions
    raise 'Unexpected migration baseline' unless remote_versions.length == 111
    reviewed_baseline = local_versions.take_while { |version| version < VERSION }
    raise 'Production does not exactly match the reviewed local baseline' unless remote_versions == reviewed_baseline
    raise 'Follow-up migration is already recorded' if remote_versions.include?(VERSION)
    current_acl = step('profile ACL inventory') { acl(token) }
    expected_columns = %w[momo_number momo_number_hash momo_pay_code updated_at].sort
    raise 'Unexpected existing profile table grant' if current_acl['authenticated_table_update']
    raise 'Unexpected anonymous profile write grant' if current_acl['public_column_update'] || current_acl['anon_column_update']
    raise 'Legacy profile column grants changed' unless current_acl['authenticated_update_columns'] == expected_columns
    raise 'Validated member edit RPC is unavailable' unless current_acl['member_edit_rpc'] && !current_acl['legacy_profile_rpc']
    current_integrity = step('profile hash integrity inventory') { integrity(token) }
    raise 'Existing profile hash integrity check failed' unless current_integrity['inconsistent_hashes'].to_i.zero?
    {
      source: { file: FILE, sha256: Digest::SHA256.hexdigest(source) },
      remote_migrations_before: remote_versions.length,
      pending: [FILE],
      acl_before: current_acl,
      integrity_before: current_integrity,
      fingerprints_before: step('protected data fingerprints') { fingerprints(token) }
    }
  end

  def self.apply(token, source, reviewed)
    body = source.sub(/\Abegin;\s*/i, '').sub(/\s*commit;\s*\z/i, '')
    raise 'Migration transaction wrapper changed' if body == source
    tag = '$collect_profile_acl_source$'
    raise 'Migration quoting collision' if source.include?(tag)
    expected_versions = history(token).map { |row| row.fetch('version').to_s }
    quoted_versions = expected_versions.map { |version| "'#{version}'" }.join(',')
    sql = <<~SQL
      BEGIN;
      SET LOCAL lock_timeout='5s';
      SET LOCAL statement_timeout='60s';
      DO $guard$ BEGIN
        IF NOT pg_try_advisory_xact_lock(20260903, 84310) THEN
          RAISE EXCEPTION 'Profile ACL cutover is already running';
        END IF;
        IF (SELECT array_agg(version::text ORDER BY version) FROM supabase_migrations.schema_migrations)
          IS DISTINCT FROM ARRAY[#{quoted_versions}]::text[] THEN
          RAISE EXCEPTION 'Production migration history changed';
        END IF;
        IF (SELECT coalesce(jsonb_agg(column_name ORDER BY column_name),'[]')
          FROM information_schema.column_privileges WHERE table_schema='public'
            AND table_name='profiles' AND grantee='authenticated' AND privilege_type='UPDATE')
          IS DISTINCT FROM '["momo_number","momo_number_hash","momo_pay_code","updated_at"]'::jsonb THEN
          RAISE EXCEPTION 'Profile ACL baseline changed';
        END IF;
      END $guard$;
      #{body};
      INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
      VALUES ('#{VERSION}','#{NAME}',ARRAY[#{tag}#{source}#{tag}]);
      NOTIFY pgrst,'reload schema';
      COMMIT;
    SQL
    request(token, '/database/query', { query: sql, read_only: false })
    after = fingerprints(token)
    raise 'Protected data changed during ACL migration' unless after == reviewed.fetch(:fingerprints_before)
    after
  end

  def self.readback(token, source_hash)
    rows = catalog(token, <<~SQL)
      select version,name,
        encode(extensions.digest(statements[1],'sha256'),'hex') as source_sha256
      from supabase_migrations.schema_migrations where version='#{VERSION}';
    SQL
    raise 'Migration history readback failed' unless rows == [{
      'version' => VERSION, 'name' => NAME, 'source_sha256' => source_hash
    }]
    result = acl(token)
    raise 'Browser profile write privilege remains' if %w[
      public_table_update public_column_update anon_table_update anon_column_update
      authenticated_table_update authenticated_column_update
    ].any? { |key| result[key] }
    raise 'Profile RPC boundary changed' unless result['member_edit_rpc'] && !result['legacy_profile_rpc']
    raise 'Direct authenticated update columns remain' unless result['authenticated_update_columns'] == []
    constraint = catalog(token, <<~SQL).first
      select convalidated as validated
      from pg_constraint
      where conrelid='public.profiles'::regclass
        and conname='profiles_momo_number_hash_matches'
    SQL
    raise 'Profile hash constraint readback failed' unless constraint == { 'validated' => true }
    current_integrity = integrity(token)
    raise 'Profile hash integrity readback failed' unless current_integrity['inconsistent_hashes'].to_i.zero?
    {
      migration: rows.first,
      migration_count: history(token).length,
      acl_after: result,
      hash_constraint: constraint,
      integrity_after: current_integrity
    }
  end

  def self.run(mode, output)
    raise 'Mode must be plan, apply or readback' unless %w[plan apply readback].include?(mode)
    raise 'Output must be a new JSON file' unless output.end_with?('.json') && !File.exist?(output)
    input = STDIN.tty? ? STDIN.raw(&:gets) : STDIN.gets
    credential = JSON.parse(input.to_s)
    input&.clear
    raise 'Credential source project mismatch' unless credential.fetch('project_url') == "https://#{REF}.supabase.co"
    token = credential.fetch('access_token')
    raise 'Invalid management credential' unless token.start_with?('sbp_')
    source = File.read(File.join(ROOT, 'supabase/migrations', FILE))
    project = step('project identity') { request(token, '') }
    raise 'Wrong production project' unless project['id'] == REF && project['name'] == 'COOL' && project['status'] == 'ACTIVE_HEALTHY'
    report = {
      captured_at: Time.now.utc.iso8601, mode: mode, project: project.slice('id', 'name', 'status'),
      credential_source: { title: 'Supabase', tab: 'Sheet1', saved: false },
      production_mutations: mode == 'apply' ? ['profile ACL migration and one migration history row'] : []
    }
    if mode == 'readback'
      report[:readback] = readback(token, Digest::SHA256.hexdigest(source))
      report[:result] = 'PROFILE_RPC_ONLY_WRITES_DEPLOYED'
    else
      report[:plan] = plan(token, source)
      if mode == 'apply'
        report[:fingerprints_after] = apply(token, source, report[:plan])
        report[:readback] = readback(token, report.dig(:plan, :source, :sha256))
        report[:result] = 'PROFILE_RPC_ONLY_WRITES_DEPLOYED'
      else
        report[:result] = 'PROFILE_RPC_ONLY_WRITES_PLAN_PASS'
      end
    end
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(report) + "\n")
    end
    puts JSON.generate(report: output, result: report[:result], production_mutations: report[:production_mutations].length)
  ensure
    token&.clear
    credential&.clear
    input&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: ruby scripts/audits/collect_member_profile_write_cutover.rb plan|apply|readback NEW_REPORT.json') unless ARGV.length == 2
  begin
    CollectMemberProfileWriteCutover.run(ARGV[0], File.expand_path(ARGV[1]))
  rescue StandardError => error
    detail = error.instance_of?(RuntimeError) ? error.message : 'private details withheld'
    warn "Profile ACL cutover failed: #{error.class} (#{detail}; read back before any retry)"
    exit 1
  end
end
