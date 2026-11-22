# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'tempfile'
require 'time'
require_relative 'external_evidence'

class PublicWebsiteCompletionGate
  COMPONENTS = {
    "static_quality_gate" => ["public_website_quality_gate.sh", "public-quality-gate.json", "--json"],
    "live_quality_gate" => ["public_website_live_gate.sh", "public-live-gate.json", "--json"],
    "live_audit_evidence" => ["public_website_audit_evidence.sh", "public-live-audit-evidence.json"],
  }.freeze

  def initialize(root:, evidence_dir:, results_dir: nil, expected_url:)
    @root = root
    @evidence_dir = evidence_dir
    @results_dir = results_dir
    @expected_url = expected_url
  end

  def run
    now = Time.now.utc
    reports = COMPONENTS.transform_values do |script, output, *arguments|
      report = component_report(script, arguments)
      write_report(File.join(@results_dir, output), report) if @results_dir
      report
    end
    code_checks = reports.transform_values { |report| report.fetch("status") == "pass" }
    external_checks = PublicWebsiteExternalEvidence.new(
      directory: @evidence_dir, expected_url: @expected_url, now: now
    ).checks
    missing = external_checks.reject { |_id, item| item.fetch("status") == "pass" }
    status = code_checks.values.all? && missing.empty? ? "pass" : "fail"
    result = {
      "checked_at_utc" => now.iso8601,
      "status" => status,
      "code_checks" => code_checks,
      "external_checks" => external_checks,
      "missing_external_count" => missing.length,
      "missing_external" => missing,
      "gate_summaries" => {
        "static" => reports.fetch("static_quality_gate")["summary"],
        "live" => reports.fetch("live_quality_gate")["summary"],
        "audit_metrics" => reports.fetch("live_audit_evidence")["metrics"],
      },
    }
    write_report(File.join(@evidence_dir, "completion_gate.json"), result)
    result
  end

  private

  def component_report(script, arguments)
    output, status = Open3.capture2("bash", File.join("scripts", script), *arguments, chdir: @root)
    result = JSON.parse(output)
    unless result.is_a?(Hash) && %w[pass fail].include?(result["status"])
      return component_failure(script, "Invalid component report", status)
    end
    if status.success? != (result.fetch("status") == "pass")
      return result.merge(component_failure(script, "Component exit status disagrees with its report", status))
    end

    result
  rescue JSON::ParserError
    component_failure(script, "Component did not emit valid JSON", status)
  end

  def component_failure(script, reason, status)
    {
      "status" => "fail",
      "component_error" => {
        "script" => script,
        "reason" => reason,
        "exit_status" => status.exitstatus,
        "term_signal" => status.termsig,
      },
    }
  end

  def write_report(path, report)
    parent = File.dirname(path)
    FileUtils.mkdir_p(parent)
    Tempfile.create(['.collect-public-website-', '.json'], parent) do |file|
      file.write(JSON.pretty_generate(report))
      file.close
      File.rename(file.path, path)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  mode = ARGV.fetch(0, "")
  unless ARGV.length <= 1 && ["", "--json", "--external-audit"].include?(mode)
    warn "Usage: scripts/public_website_completion_gate.sh [--json|--external-audit]"
    exit 64
  end
  result = PublicWebsiteCompletionGate.new(
    root: Dir.pwd,
    evidence_dir: ENV.fetch("PUBLIC_WEBSITE_EVIDENCE_DIR", "output/public_website_evidence"),
    results_dir: ENV["PUBLIC_WEBSITE_GATE_RESULTS_DIR"],
    expected_url: ENV.fetch("PUBLIC_WEBSITE_URL", "https://collect.ikanisa.com/")
  ).run
  code_checks = result.fetch("code_checks")
  missing = result.fetch("missing_external")
  status = result.fetch("status")

  case mode
  when "--json"
    puts JSON.pretty_generate(result)
  when "--external-audit"
    puts "Collect public website completion audit"
    puts "status: #{status}"
    puts "code checks: #{code_checks.values.count(true)}/#{code_checks.length}"
    puts "external missing or invalid: #{missing.length}"
    puts
    code_checks.each { |id, passed| puts "#{passed ? 'PASS' : 'FAIL'} code #{id}" }
    puts
    missing.each do |id, item|
      puts "MISSING_OR_INVALID #{id} (#{item.fetch('audit_id')})"
      puts "  #{item.fetch('description')}"
      puts "  accepted evidence:"
      item.fetch("paths").each { |accepted| puts "  - #{accepted}" }
      puts
    end
    if status == "pass"
      puts "All code-owned and external evidence requirements are satisfied."
    else
      puts "Resolve the reported checks and rerun scripts/public_website_completion_gate.sh --json."
    end
  else
    puts "#{status} code=#{code_checks.values.count(true)}/#{code_checks.length} external_missing=#{missing.length}"
    missing.each do |id, item|
      warn "MISSING #{id} (#{item.fetch('audit_id')}): #{item.fetch('description')}"
      warn "  accepted paths: #{item.fetch('paths').join(', ')}"
    end
  end
  exit status == "pass" ? 0 : 1
end
