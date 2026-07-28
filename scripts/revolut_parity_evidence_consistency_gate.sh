#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${COLLECT_EVIDENCE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
output_format="text"
require_full=false
source_only=false

for argument in "$@"; do
  case "$argument" in
    --json) output_format="json" ;;
    --full) require_full=true ;;
    --source-only) source_only=true ;;
    *)
      printf 'usage: %s [--json] [--full|--source-only]\n' "$0" >&2
      exit 2
      ;;
  esac
done

if [[ "$require_full" == true && "$source_only" == true ]]; then
  printf '%s\n' '--full and --source-only cannot be combined' >&2
  exit 2
fi

ROOT_DIR="$ROOT_DIR" \
OUTPUT_FORMAT="$output_format" \
REQUIRE_FULL="$require_full" \
SOURCE_ONLY="$source_only" \
ruby -r digest -r json -r time <<'RUBY'
root_dir = File.expand_path(ENV.fetch("ROOT_DIR"))
output_format = ENV.fetch("OUTPUT_FORMAT")
require_full = ENV.fetch("REQUIRE_FULL") == "true"
source_only = ENV.fetch("SOURCE_ONLY") == "true"
mode = require_full ? "full" : (source_only ? "source-only" : "available")

goal_dir = File.join(root_dir, "docs/revolut-parity-goal")
required_documents = %w[
  EVIDENCE_REGISTER.md
  FINAL_COMPLETION_AUDIT.md
  ISSUE_LOG.md
  RELEASE_READINESS_MATRIX.md
  REMAINING_TASKS.md
  VALIDATION_MANIFEST.md
]

checks = {}
failures = []

def add_check(checks, failures, name, passed, details = {})
  checks[name] = { "status" => passed ? "pass" : "fail" }.merge(details)
  failures << { "check" => name }.merge(details) unless passed
end

def sequence_details(values)
  expected = values.empty? ? [] : (1..values.max).to_a
  {
    "expected_count" => expected.length,
    "observed_count" => values.length,
    "missing" => expected - values,
    "duplicates" =>
      values.group_by { |value| value }
        .select { |_value, matches| matches.length > 1 }
        .keys
  }
end

def terminal_line(path)
  File.readlines(path, chomp: true).last
end

def comma(value)
  value.to_s.reverse.scan(/.{1,3}/).join(",").reverse
end

missing_documents = required_documents.reject do |name|
  File.file?(File.join(goal_dir, name))
end
design_qa_path = File.join(root_dir, "design-qa.md")
missing_documents << "design-qa.md" unless File.file?(design_qa_path)
add_check(
  checks,
  failures,
  "required_documents",
  missing_documents.empty?,
  "missing" => missing_documents
)

unless missing_documents.empty?
  result = {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "mode" => mode,
    "root" => root_dir,
    "checks" => checks,
    "failures" => failures
  }
  if output_format == "json"
    puts JSON.pretty_generate(result)
  else
    puts "[revolut-parity-evidence] status=fail failures=#{failures.length}"
  end
  exit 1
end

evidence_path = File.join(goal_dir, "EVIDENCE_REGISTER.md")
remaining_path = File.join(goal_dir, "REMAINING_TASKS.md")
issue_path = File.join(goal_dir, "ISSUE_LOG.md")
audit_path = File.join(goal_dir, "FINAL_COMPLETION_AUDIT.md")
validation_path = File.join(goal_dir, "VALIDATION_MANIFEST.md")
readiness_path = File.join(goal_dir, "RELEASE_READINESS_MATRIX.md")

evidence_text = File.read(evidence_path)
remaining_text = File.read(remaining_path)
issue_text = File.read(issue_path)
audit_text = File.read(audit_path)
validation_text = File.read(validation_path)
readiness_text = File.read(readiness_path)
design_qa_text = File.read(design_qa_path)

id_sources = {
  "evidence_ids" => [
    evidence_text.scan(/^\| E-(\d{3}) \|/).flatten.map(&:to_i),
    "E"
  ],
  "issue_ids" => [
    issue_text.scan(/^\| I-(\d{3}) \|/).flatten.map(&:to_i),
    "I"
  ],
  "remaining_task_ids" => [
    remaining_text.scan(/^\| RT-(\d{3}) \|/).flatten.map(&:to_i),
    "RT"
  ]
}

id_sources.each do |name, (values, prefix)|
  details = sequence_details(values)
  passed =
    !values.empty? &&
    details.fetch("missing").empty? &&
    details.fetch("duplicates").empty? &&
    values == values.sort
  add_check(
    checks,
    failures,
    name,
    passed,
    details.merge(
      "prefix" => prefix,
      "first" => values.first,
      "last" => values.last
    )
  )
end

task_ids = id_sources.fetch("remaining_task_ids").first
add_check(
  checks,
  failures,
  "complete_task_inventory",
  task_ids == (1..48).to_a,
  "expected_range" => "RT-001..RT-048",
  "observed_last" => task_ids.last
)

markdown_paths =
  Dir[File.join(goal_dir, "*.md")].sort + [design_qa_path]
registered_evidence_ids = id_sources.fetch("evidence_ids").first
registered_task_ids = task_ids
missing_evidence_references = []
missing_task_references = []

markdown_paths.each do |path|
  text = File.read(path)
  text.scan(/\bE-(\d{3})\b/).flatten.map(&:to_i).uniq.each do |id|
    unless registered_evidence_ids.include?(id)
      missing_evidence_references << {
        "path" => path.delete_prefix("#{root_dir}/"),
        "id" => format("E-%03d", id)
      }
    end
  end
  text.scan(/\bRT-(\d{3})\b/).flatten.map(&:to_i).uniq.each do |id|
    unless registered_task_ids.include?(id)
      missing_task_references << {
        "path" => path.delete_prefix("#{root_dir}/"),
        "id" => format("RT-%03d", id)
      }
    end
  end
end

add_check(
  checks,
  failures,
  "registered_cross_references",
  missing_evidence_references.empty? && missing_task_references.empty?,
  "missing_evidence_references" => missing_evidence_references,
  "missing_task_references" => missing_task_references
)

issue_rows = issue_text.lines.grep(/^\| I-\d{3} \|/)
incomplete_issue_rows = issue_rows.each_with_index.map do |line, index|
  cells = line.split("|").map(&:strip)
  next nil if cells.length >= 9 && cells[1..8].all? { |cell| !cell.empty? }

  index + 1
end.compact
add_check(
  checks,
  failures,
  "issue_dispositions_complete",
  incomplete_issue_rows.empty?,
  "row_indexes" => incomplete_issue_rows
)

unresolved_issues = []
unassigned_unresolved_issues = []
issue_rows.each do |line|
  cells = line.split("|").map(&:strip)
  issue = {
    "id" => cells[1],
    "recommendation" => cells[5],
    "owner" => cells[6],
    "status" => cells[7],
    "escalation" => cells[8]
  }
  next if issue.fetch("status").start_with?("Closed")

  unresolved_issues << issue.fetch("id")
  assigned =
    issue.fetch("recommendation").to_s.length > 10 &&
    issue.fetch("owner").to_s.length >= 2 &&
    !issue.fetch("owner").match?(/\A(?:TBD|Unknown|None)\z/i) &&
    issue.fetch("status").to_s.length > 2 &&
    issue.fetch("escalation").to_s.length > 1
  unassigned_unresolved_issues << issue unless assigned
end
add_check(
  checks,
  failures,
  "open_issue_assignment",
  unassigned_unresolved_issues.empty?,
  "unresolved_issue_ids" => unresolved_issues,
  "unassigned" => unassigned_unresolved_issues
)

workstream_ids = audit_text.scan(/^\| WS(\d+) /).flatten.map(&:to_i)
deliverable_ids = audit_text.scan(/^\| (\d+)\. [^|]+ \|/).flatten.map(&:to_i)
add_check(
  checks,
  failures,
  "completion_audit_inventory",
  workstream_ids == (1..10).to_a && deliverable_ids == (1..10).to_a,
  "workstreams" => workstream_ids,
  "deliverables" => deliverable_ids
)

unfinished_tasks = remaining_text.lines.grep(/^\| RT-\d{3} \|/).map do |line|
  cells = line.split("|").map(&:strip)
  status = cells[7]
  next nil if status&.start_with?("Completed")

  cells[1]
end.compact
audit_sentinel = terminal_line(audit_path)
design_sentinel = terminal_line(design_qa_path)
sentinels_pass =
  !unfinished_tasks.empty? &&
  audit_sentinel == "completion result: blocked" &&
  design_sentinel == "final result: blocked"
add_check(
  checks,
  failures,
  "fail_closed_sentinels",
  sentinels_pass,
  "unfinished_task_count" => unfinished_tasks.length,
  "audit_sentinel" => audit_sentinel,
  "design_qa_sentinel" => design_sentinel
)

readiness_boundary_pass =
  readiness_text.include?("engineering in progress") &&
  readiness_text.include?("remain open")
add_check(
  checks,
  failures,
  "release_readiness_truth_boundary",
  readiness_boundary_pass
)

coverage_path = File.join(root_dir, "coverage/lcov.info")
if source_only
  add_check(
    checks,
    failures,
    "coverage_evidence",
    true,
    "status" => "skipped",
    "reason" => "source-only mode"
  )
elsif File.file?(coverage_path)
  total_lines = 0
  hit_lines = 0
  File.foreach(coverage_path) do |line|
    next unless line.start_with?("DA:")

    _line_number, count = line.delete_prefix("DA:").split(",", 2)
    total_lines += 1
    hit_lines += 1 if count.to_i.positive?
  end
  coverage_percent =
    total_lines.zero? ? "0.00" : format("%.2f", hit_lines * 100.0 / total_lines)
  coverage_sha256 = Digest::SHA256.file(coverage_path).hexdigest
  expected_markers = [
    "#{comma(hit_lines)} of #{comma(total_lines)} lines",
    "#{coverage_percent}%",
    coverage_sha256
  ]
  coverage_pass =
    total_lines.positive? &&
    expected_markers.all? { |marker| validation_text.include?(marker) }
  add_check(
    checks,
    failures,
    "coverage_evidence",
    coverage_pass,
    "lines_hit" => hit_lines,
    "lines_total" => total_lines,
    "percent" => coverage_percent,
    "sha256" => coverage_sha256,
    "missing_markers" =>
      expected_markers.reject { |marker| validation_text.include?(marker) }
  )
else
  add_check(
    checks,
    failures,
    "coverage_evidence",
    !require_full,
    "status" => require_full ? "fail" : "skipped",
    "reason" => "coverage/lcov.info is unavailable"
  )
end

artifact_manifests =
  Dir[File.join(root_dir, "output/release_artifacts/BUILD_ARTIFACT_CHECKSUMS_*.sha256")]
    .sort
artifact_manifest_path = artifact_manifests.last
if source_only
  add_check(
    checks,
    failures,
    "release_artifact_evidence",
    true,
    "status" => "skipped",
    "reason" => "source-only mode"
  )
elsif artifact_manifest_path
  manifest_entries = File.readlines(artifact_manifest_path, chomp: true).map do |line|
    match = line.match(/\A([0-9a-f]{64})  (.+)\z/)
    next nil unless match

    { "sha256" => match[1], "path" => match[2] }
  end.compact
  artifact_failures = manifest_entries.map do |entry|
    path = File.join(root_dir, entry.fetch("path"))
    actual_sha256 = Digest::SHA256.file(path).hexdigest if File.file?(path)
    next nil if actual_sha256 == entry.fetch("sha256")

    {
      "path" => entry.fetch("path"),
      "expected_sha256" => entry.fetch("sha256"),
      "actual_sha256" => actual_sha256
    }
  end.compact
  manifest_sha256 = Digest::SHA256.file(artifact_manifest_path).hexdigest
  primary_artifacts = %w[
    build/app/outputs/flutter-apk/app-production-release.apk
    build/app/outputs/bundle/productionRelease/app-production-release.aab
    build/web/main.dart.js
  ]
  evidence_marker_failures = primary_artifacts.map do |relative_path|
    absolute_path = File.join(root_dir, relative_path)
    next({ "path" => relative_path, "reason" => "missing" }) unless File.file?(absolute_path)

    sha256 = Digest::SHA256.file(absolute_path).hexdigest
    size = File.size(absolute_path)
    next nil if validation_text.include?(sha256) &&
      validation_text.include?("#{comma(size)} bytes")

    {
      "path" => relative_path,
      "reason" => "validation manifest lacks current size or hash",
      "bytes" => size,
      "sha256" => sha256
    }
  end.compact
  manifest_name = artifact_manifest_path.delete_prefix("#{root_dir}/")
  manifest_evidence_pass =
    validation_text.include?(manifest_name) &&
    validation_text.include?(manifest_sha256)
  artifacts_pass =
    manifest_entries.length == 9 &&
    artifact_failures.empty? &&
    evidence_marker_failures.empty? &&
    manifest_evidence_pass
  add_check(
    checks,
    failures,
    "release_artifact_evidence",
    artifacts_pass,
    "manifest" => manifest_name,
    "manifest_sha256" => manifest_sha256,
    "artifact_count" => manifest_entries.length,
    "artifact_failures" => artifact_failures,
    "evidence_marker_failures" => evidence_marker_failures,
    "manifest_recorded" => manifest_evidence_pass
  )
else
  add_check(
    checks,
    failures,
    "release_artifact_evidence",
    !require_full,
    "status" => require_full ? "fail" : "skipped",
    "reason" => "release artifact checksum manifest is unavailable"
  )
end

status = failures.empty? ? "pass" : "fail"
result = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "mode" => mode,
  "root" => root_dir,
  "checks" => checks,
  "failures" => failures
}

if output_format == "json"
  puts JSON.pretty_generate(result)
else
  puts "[revolut-parity-evidence] status=#{status} mode=#{result.fetch("mode")} failures=#{failures.length}"
  checks.each do |name, check|
    puts "[revolut-parity-evidence] #{name}=#{check.fetch("status")}"
  end
end

exit(status == "pass" ? 0 : 1)
RUBY
