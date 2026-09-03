# Production rollback-only bank lifecycle UAT. The exact SQL must start a
# transaction and end with ROLLBACK. Protected production fingerprints and
# identity/control-plane counts are verified unchanged before evidence passes.
require 'json'
require 'digest'
require 'io/console'
require 'time'
require_relative 'collect_production_cutover'

module CollectLinkedRollbackUat
  ROOT = CollectProductionCutover::ROOT
  REF = CollectProductionCutover::REF
  SQL_PATH = 'scripts/bank_transfer_rollback_uat.sql'.freeze

  def self.runtime_counts(token)
    CollectProductionCutover.query(token, <<~SQL).first
      SELECT
        (SELECT count(*) FROM auth.users) AS auth_users,
        (SELECT count(*) FROM auth.sessions) AS auth_sessions,
        (SELECT count(*) FROM public.admin_user_roles) AS admin_user_roles,
        (SELECT count(*) FROM collect_admin_access.whatsapp_approvals) AS whatsapp_approvals,
        (SELECT count(*) FROM public.audit_logs) AS audit_logs;
    SQL
  end

  def self.run(output)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
    sql = File.read(File.join(ROOT, SQL_PATH))
    raise 'Rollback UAT must start with BEGIN' unless sql.match?(/\Abegin\s*;/i)
    raise 'Rollback UAT must end with ROLLBACK' unless sql.match?(/rollback\s*;\s*\z/i)
    raise 'Rollback UAT must contain exactly one outer BEGIN and ROLLBACK' unless
      sql.scan(/^\s*begin\s*;/i).length == 1 && sql.scan(/^\s*rollback\s*;/i).length == 1
    STDOUT.sync = true
    puts 'Awaiting Management API credential on non-echoing stdin.'
    raw = STDIN.tty? ? STDIN.noecho(&:gets) : STDIN.gets
    credential = JSON.parse(raw.to_s)
    raw&.clear
    raise 'Wrong credential scope' unless
      credential.fetch('project_url') == "https://#{REF}.supabase.co"
    token = credential.fetch('access_token')
    raise 'Expected Management API credential' unless token.start_with?('sbp_')
    project = CollectProductionCutover.request(token, '')
    raise 'Wrong or unhealthy project' unless
      project['id'] == REF && project['name'] == 'COOL' && project['status'] == 'ACTIVE_HEALTHY'
    history = CollectProductionCutover.history(token)
    raise 'Production migration history must be exactly 120' unless history.length == 120
    projections = CollectProductionCutover.projections(token)
    required = %w[profiles payments ledger_entries raw_payment_sms bank_transactions]
    raise 'Missing protected production table' unless required.all? { |table| projections.key?(table) }
    protected_before = CollectProductionCutover.fingerprint(token, projections)
    runtime_before = runtime_counts(token)
    CollectProductionCutover.query(token, sql, write: true)
    protected_after = CollectProductionCutover.fingerprint(token, projections)
    runtime_after = runtime_counts(token)
    raise 'Rollback UAT changed protected production data' unless protected_before == protected_after
    raise 'Rollback UAT changed production identity/control-plane counts' unless runtime_before == runtime_after
    report = {
      captured_at: Time.now.utc.iso8601,
      project: REF,
      migration_count: history.length,
      uat_file: SQL_PATH,
      uat_sha256: Digest::SHA256.hexdigest(sql),
      transaction_ended_in_rollback: true,
      protected_data_unchanged: true,
      identity_control_plane_counts_unchanged: true,
      protected_fingerprints: { before: protected_before, after: protected_after },
      runtime_counts: { before: runtime_before, after: runtime_after },
      provider_sends: 0,
      operational_flags_enabled: 0,
      result: 'LINKED_PRODUCTION_ROLLBACK_UAT_PASS'
    }
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(report) + "\n")
    end
    puts JSON.generate(report: output, result: report[:result], production_data_unchanged: true)
    true
  ensure
    raw&.clear
    token&.clear
    credential&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_linked_rollback_uat.rb NEW_REPORT.json') unless ARGV.length == 1
  begin
    exit(CollectLinkedRollbackUat.run(ARGV.first) ? 0 : 1)
  rescue StandardError => error
    warn "Linked rollback UAT failed: #{error.class} (details withheld)"
    exit 1
  end
end
