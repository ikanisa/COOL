# Read-only, credential-redacted Supabase advisor evidence. The report contains
# object names and advisor metadata only; it never stores credentials or row
# data and performs no production mutation.
require 'json'
require 'io/console'
require 'time'
require_relative 'collect_production_cutover'

module CollectAdvisorDetailAudit
  REF = CollectProductionCutover::REF

  def self.run(output)
    raise 'New JSON report required' unless output.end_with?('.json') && !File.exist?(output)
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
    checks = %w[security performance].to_h do |type|
      rows = CollectProductionCutover.request(token, "/advisors/#{type}").fetch('lints')
      safe = rows.map do |row|
        row.slice('level', 'name', 'title', 'description', 'detail', 'remediation', 'metadata')
      end
      [type, {
        count: safe.length,
        by_level: safe.group_by { |row| row.fetch('level') }.transform_values(&:length),
        by_name: safe.group_by { |row| row.fetch('name') }.transform_values(&:length),
        findings: safe
      }]
    end
    report = {
      captured_at: Time.now.utc.iso8601,
      project: REF,
      mode: 'read_only_no_production_mutations',
      checks: checks,
      credential_values_saved: false,
      result: 'ADVISOR_DETAIL_CAPTURED_FOR_REVIEW'
    }
    File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(JSON.pretty_generate(report) + "\n")
    end
    puts JSON.generate(
      report: output,
      security: checks.dig('security', :by_level),
      performance: checks.dig('performance', :by_level),
      production_mutations: 0
    )
    true
  ensure
    raw&.clear
    token&.clear
    credential&.clear
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: collect_advisor_detail_audit.rb NEW_REPORT.json') unless ARGV.length == 1
  begin
    exit(CollectAdvisorDetailAudit.run(ARGV.first) ? 0 : 1)
  rescue StandardError => error
    warn "Advisor audit failed: #{error.class} (details withheld)"
    exit 1
  end
end
