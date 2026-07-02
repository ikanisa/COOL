#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
if [[ "${1:-}" == "--json" ]]; then
  output_format="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

if [[ -z "${RELEASE_EVIDENCE_BUNDLE_DIR:-}" ]]; then
  latest_bundle="$(find "$ROOT_DIR/.cache/repo_wide_qa_uat" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1 || true)"
  RELEASE_EVIDENCE_BUNDLE_DIR="$latest_bundle"
fi

RELEASE_EVIDENCE_BUNDLE_DIR="${RELEASE_EVIDENCE_BUNDLE_DIR:-}" OUTPUT_FORMAT="$output_format" ROOT_DIR="$ROOT_DIR" ruby -r digest -r json -r time <<'RUBY'
root_dir = ENV.fetch("ROOT_DIR")
bundle_dir = ENV.fetch("RELEASE_EVIDENCE_BUNDLE_DIR", "")
output_format = ENV.fetch("OUTPUT_FORMAT")

def read_json(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError, Errno::ENOENT
  {}
end

def command_rows(commands_path)
  return [] unless File.exist?(commands_path)

  File.readlines(commands_path, chomp: true).map do |line|
    name, file, exit_code, started_at, finished_at = line.split("\t", 5)
    {
      "name" => name,
      "file" => file,
      "exit_code" => exit_code.to_i,
      "started_at" => started_at,
      "finished_at" => finished_at
    }
  end
end

def command(commands, name)
  commands.reverse.find { |row| row.fetch("name") == name }
end

def command_ok?(commands, name)
  row = command(commands, name)
  row && row.fetch("exit_code") == 0
end

def command_blocked?(commands, name)
  row = command(commands, name)
  row && row.fetch("exit_code") == 99
end

def go_live_gate_consistent?(gate)
  status = gate["status"].to_s
  gate["go_live_approved"] == true &&
    gate["decision"].to_s == "GO" &&
    gate["approval_status"].to_s == "approved" &&
    (status.empty? || status == "pass") &&
    Array(gate["blocker_keys"]).empty?
end

def command_evidence(row, bundle_dir)
  relative_file = row && row["file"].to_s
  bundle_root = File.expand_path(bundle_dir.to_s)
  path = File.expand_path(relative_file.to_s, bundle_root)
  inside_bundle = path == bundle_root || path.start_with?(bundle_root + File::SEPARATOR)
  exists = inside_bundle && File.file?(path)
  bytes = exists ? File.size(path) : nil
  {
    "file" => relative_file,
    "path" => inside_bundle ? path : nil,
    "inside_bundle" => inside_bundle,
    "exists" => exists,
    "bytes" => bytes,
    "nonempty" => exists && bytes.to_i.positive?
  }
end

def file_item(path, required: true)
  exists = File.file?(path)
  {
    "path" => path,
    "required" => required,
    "exists" => exists,
    "bytes" => exists ? File.size(path) : nil
  }
end

def png_header(path)
  return { "valid" => false } unless File.file?(path)

  data = File.binread(path, 33)
  signature = "\x89PNG\r\n\x1a\n".b
  valid =
    data.bytesize >= 33 &&
    data.start_with?(signature) &&
    data[8, 4].unpack1("N") == 13 &&
    data[12, 4] == "IHDR"
  {
    "valid" => valid,
    "width" => valid ? data[16, 4].unpack1("N") : nil,
    "height" => valid ? data[20, 4].unpack1("N") : nil
  }
end

def bundle_redaction_scan(bundle_dir)
  bundle_root = File.expand_path(bundle_dir.to_s)
  text_extensions = %w[.json .md .txt .log .csv .tsv .yaml .yml .html]
  forbidden_patterns = {
    "openai_api_key" => /sk-(?:proj-)?[A-Za-z0-9_\-]{20,}/,
    "supabase_access_token" => /sbp_[A-Za-z0-9]{20,}/,
    "jwt_like_token" => /eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+/,
    "postgres_password_url" => /postgresql:\/\/[A-Za-z0-9_.%+\-]+:[A-Za-z0-9_:%+\-.~!$&()*+,;=]+@/,
    "generic_secret_assignment" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9_\-]{12,}/i,
    "rwanda_phone_number" => /\+250\d{9}\b/,
    "raw_payment_or_sms" => /\b(?:momo|mobile money|transaction id|raw sms)\b.*\b(?:\+250\d{9}|\d{6,})/i
  }

  files = Dir.glob(File.join(bundle_root, "**", "*"), File::FNM_DOTMATCH).select do |path|
    File.file?(path) && text_extensions.include?(File.extname(path).downcase)
  end

  findings = files.flat_map do |path|
    relative_path = path.sub(%r{\A#{Regexp.escape(bundle_root)}/?}, "")
    text = File.binread(path).to_s
    forbidden_patterns.map do |key, pattern|
      next unless text.match?(pattern)

      {
        "path" => relative_path,
        "marker" => key
      }
    end.compact
  end

  {
    "status" => findings.empty? ? "pass" : "fail",
    "scanned_files" => files.count,
    "findings" => findings,
    "secret_handling" => "Only file paths and marker names are reported; matched secret or raw-data values are never printed."
  }
end

commands = command_rows(File.join(bundle_dir, "commands.tsv"))
release_status = read_json(File.join(bundle_dir, "release_status.json"))
go_live_gate = read_json(File.join(bundle_dir, "go_live_gate.json"))
uat_signoff = read_json(File.join(bundle_dir, "uat_signoff_gate.json"))
uat_evidence = read_json(File.join(bundle_dir, "uat_evidence_gate.json"))
worktree_review = read_json(File.join(bundle_dir, "worktree_review.json"))
mobile_release = read_json(File.join(bundle_dir, "mobile_release_gate.json"))
admin_runtime = read_json(File.join(bundle_dir, "admin_pwa_render_smoke", "pwa-runtime.json"))
admin_render_summary = read_json(File.join(bundle_dir, "admin_pwa_render_smoke", "summary.json"))
mobile_route_render_summary = read_json(File.join(bundle_dir, "mobile_route_render_smoke", "summary.json"))
admin_hosting = read_json(File.join(bundle_dir, "admin_pwa_hosting_gate.json"))
admin_live = read_json(File.join(bundle_dir, "admin_pwa_live_gate.json"))
admin_live_fixture = admin_live["fixture_mode"] == true
android_release_signing_preflight = read_json(File.join(bundle_dir, "android_release_signing_preflight.json"))
supabase_summary = read_json(File.join(bundle_dir, "supabase", "summary.json"))
bundle_redaction = bundle_redaction_scan(bundle_dir)

required_docs = {
  "fullstack_goal" => ["docs/release/FULLSTACK_UAT_GO_LIVE_GOAL.md", ["SMS-first", "GO Criteria"]],
  "production_readiness_checklist" => ["docs/release/PRODUCTION_READINESS_CHECKLIST.md", ["Current Readiness", "Production Blockers"]],
  "qa_test_report" => ["docs/release/QA_TEST_REPORT.md", ["Admin PWA", "linked Supabase"]],
  "uat_execution_report" => ["docs/release/UAT_EXECUTION_REPORT.md", ["UAT-01", "UAT-10"]],
  "uat_go_live_packet" => ["docs/release/UAT_GO_LIVE_PACKET_2026-05-24.md", ["Device And Browser Matrix", "Test Data Ledger", "Risk Register", "Final GO Criteria"]],
  "go_no_go_decision" => ["docs/release/GO_NO_GO_DECISION.md", ["NO-GO", "SMS-first"]],
  "release_blockers" => ["docs/release/RELEASE_BLOCKERS.md", ["P0-004", "SMS-first"]],
  "uat_signoff_checklist" => ["docs/release/UAT_SIGNOFF_CHECKLIST_2026-05-24.md", ["PENDING SIGNOFF", "Release Owner Decision"]],
  "completion_audit" => ["docs/release/GO_LIVE_COMPLETION_AUDIT_2026-05-24.md", ["Requirement Audit", "Current Blocking Keys"]],
  "google_play_optimization_goal" => ["docs/release/GOOGLE_PLAY_OPTIMIZATION_GOAL_2026-06-21.md", ["Official Source Map", "Current Blockers"]],
  "google_play_production_submission" => ["docs/release/GOOGLE_PLAY_PRODUCTION_SUBMISSION_2026-06-21.md", ["Target Release", "Blocked Upload Attempts"]],
  "google_play_optimization_surface_matrix" => ["docs/release/GOOGLE_PLAY_OPTIMIZATION_SURFACE_MATRIX_2026-06-21.md", ["Audit Matrix", "Immediate Submission Commands"]],
  "google_play_console_audit_packet" => ["docs/release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET_2026-06-21.json", ["store_listing", "app_content", "play_console_surfaces"]],
  "google_play_operational_readiness" => ["docs/release/GOOGLE_PLAY_OPERATIONAL_READINESS_2026-06-21.md", ["Play Integrity Strategy", "Vitals And Reporting Strategy", "Testing Tracks"]]
}

doc_items = required_docs.map do |name, (relative_path, markers)|
  path = File.join(root_dir, relative_path)
  text = File.file?(path) ? File.read(path) : ""
  missing_markers = markers.reject { |marker| text.include?(marker) }
  {
    "name" => name,
    "path" => relative_path,
    "exists" => File.file?(path),
    "missing_markers" => missing_markers,
    "status" => File.file?(path) && missing_markers.empty? ? "pass" : "fail"
  }
end

required_commands = %w[
  flutter_version
  dart_version
  format_check
  flutter_analyze
  flutter_test
  release_secret_scan
  collect_product_boundary_scan
  mobile_route_artifact_gate
  android_release_signing_preflight
  android_kotlin_plugin_compat
  admin_pwa_build
  admin_pwa_manifest_gate
  admin_pwa_hosting_gate
  admin_pwa_live_gate
  admin_pwa_render_smoke
  mobile_route_render_smoke
  uat_evidence_gate
  uat_signoff_gate
  android_apk_release_build
  android_aab_release_build
  release_artifact_manifest
  flutter_mobile_release_gate
  release_worktree_review
  android_device_uat
  release_status_json
  supabase_go_live_gate_json
  supabase_go_live_evidence
]

command_items = required_commands.map do |name|
  row = command(commands, name)
  evidence = command_evidence(row, bundle_dir)
  status = if row.nil?
    "fail"
  elsif !evidence.fetch("nonempty")
    "fail"
  elsif name == "admin_pwa_live_gate" && admin_live_fixture
    "fail"
  elsif name == "admin_pwa_live_gate" && admin_live["status"] == "blocked"
    "blocked"
  elsif name == "uat_evidence_gate" && uat_evidence["status"] == "blocked"
    "blocked"
  elsif name == "uat_signoff_gate" &&
      (uat_signoff["status"] == "blocked" ||
        uat_signoff["decision"] == "blocked" ||
        uat_signoff["blocker_keys"].to_a.include?("human_uat_signoff"))
    "blocked"
  elsif name == "flutter_mobile_release_gate" && mobile_release["status"] == "blocked"
    "blocked"
  elsif name == "release_worktree_review" && worktree_review["status"] == "blocked"
    "blocked"
  elsif name == "android_release_signing_preflight" &&
      android_release_signing_preflight["status"].to_s == "blocked"
    "blocked"
  elsif name == "supabase_go_live_gate_json" && go_live_gate_consistent?(go_live_gate)
    "pass"
  elsif name == "supabase_go_live_gate_json" &&
      (
        go_live_gate["go_live_approved"] == false ||
        Array(go_live_gate["blocker_keys"]).any? ||
        go_live_gate["status"].to_s == "blocked" ||
        go_live_gate["approval_status"].to_s == "blocked"
      )
    "blocked"
  elsif row.fetch("exit_code") == 0
    "pass"
  elsif row.fetch("exit_code") == 99 ||
      (name == "supabase_go_live_gate_json" && go_live_gate["go_live_approved"] == false) ||
      (name == "admin_pwa_live_gate" && admin_live["status"] == "blocked") ||
      (name == "android_release_signing_preflight" && android_release_signing_preflight["status"].to_s == "blocked") ||
      (name == "uat_evidence_gate" && uat_evidence["status"] == "blocked") ||
      (name == "uat_signoff_gate" && uat_signoff["blocker_keys"].to_a.include?("human_uat_signoff"))
    "blocked"
  else
    "fail"
  end

  {
    "name" => name,
    "present" => !row.nil?,
    "exit_code" => row && row.fetch("exit_code"),
    "evidence" => evidence,
    "status" => status
  }
end

artifact_paths = [
  "build/app/outputs/flutter-apk/app-production-release.apk",
  "build/app/outputs/bundle/productionRelease/app-production-release.aab",
  "build/web/index.html",
  "build/web/flutter_bootstrap.js",
  "build/web/main.dart.js",
  "build/web/manifest.json",
  "build/web/custom-sw.js",
  "build/web/icons/collect-admin.png",
  "build/web/_headers",
  "build/web/robots.txt"
]
bundle_checksum_manifest = File.join(bundle_dir, "BUILD_ARTIFACT_CHECKSUMS.sha256")
checksum_text = File.file?(bundle_checksum_manifest) ? File.read(bundle_checksum_manifest) : ""
checksum_entries = checksum_text.lines.each_with_object({}) do |line, entries|
  sha256, relative_path = line.strip.split(/\s+/, 2)
  next unless sha256&.match?(/\A[0-9a-f]{64}\z/) && relative_path && !relative_path.empty?

  entries[relative_path] = sha256
end
artifact_items = artifact_paths.map do |relative_path|
  path = File.join(root_dir, relative_path)
  exists = File.file?(path)
  recorded_sha256 = checksum_entries[relative_path]
  actual_sha256 = exists ? Digest::SHA256.file(path).hexdigest : nil
  checksum_recorded = !recorded_sha256.nil?
  checksum_matches = checksum_recorded && actual_sha256 == recorded_sha256
  {
    "path" => relative_path,
    "exists" => exists,
    "checksum_recorded" => checksum_recorded,
    "checksum_matches" => checksum_matches,
    "actual_sha256" => actual_sha256,
    "status" => exists && checksum_matches ? "pass" : "fail"
  }
end

artifact_status =
  if command_ok?(commands, "release_artifact_manifest") &&
      File.file?(bundle_checksum_manifest) &&
      artifact_items.all? { |item| item.fetch("status") == "pass" }
    "pass"
  elsif command_blocked?(commands, "release_artifact_manifest")
    "blocked"
  else
    "fail"
  end

admin_runtime_required_cache = [
  "./index.html",
  "./flutter_bootstrap.js",
  "./main.dart.js",
  "./manifest.json",
  "./icons/collect-admin.png"
]
admin_screenshot_specs = {
  "desktop-1440x900.png" => [1440, 900],
  "mobile-390x844.png" => [390, 844]
}
admin_screenshot_items = admin_screenshot_specs.map do |file_name, (expected_width, expected_height)|
  png_path = File.join(bundle_dir, "admin_pwa_render_smoke", file_name)
  check_path = "#{png_path}.json"
  check = read_json(check_path)
  exists = File.file?(png_path)
  check_exists = File.file?(check_path)
  actual_bytes = exists ? File.size(png_path) : nil
  png = png_header(png_path)
  declared_bytes = check["bytes"].to_i
  bytes_match = !actual_bytes.nil? && declared_bytes == actual_bytes
  status =
    if exists &&
        check_exists &&
        png["valid"] &&
        check["status"] == "pass" &&
        check["width"].to_i == expected_width &&
        check["height"].to_i == expected_height &&
        png["width"].to_i == expected_width &&
        png["height"].to_i == expected_height &&
        declared_bytes > 8_000 &&
        bytes_match &&
        check["distinct_rgb"].to_i >= 8 &&
        check["non_background_pixels"].to_i >= 100
      "pass"
    else
      "fail"
    end
  {
    "file" => file_name,
    "path" => png_path,
    "exists" => exists,
    "png_valid" => png["valid"],
    "check_path" => check_path,
    "check_exists" => check_exists,
    "width" => check["width"],
    "height" => check["height"],
    "actual_width" => png["width"],
    "actual_height" => png["height"],
    "bytes" => declared_bytes,
    "actual_bytes" => actual_bytes,
    "bytes_match" => bytes_match,
    "distinct_rgb" => check["distinct_rgb"],
    "non_background_pixels" => check["non_background_pixels"],
    "status" => status
  }
end
admin_screenshot_summary_ok =
  admin_render_summary["status"] == "pass" &&
  (admin_screenshot_specs.keys - Array(admin_render_summary["screenshots"])).empty? &&
  (admin_screenshot_specs.keys.map { |name| "#{name}.json" } - Array(admin_render_summary["screenshot_checks"])).empty?
admin_runtime_status =
  if command_blocked?(commands, "admin_pwa_render_smoke")
    "blocked"
  elsif command_ok?(commands, "admin_pwa_render_smoke") &&
      admin_runtime["status"] == "pass" &&
      admin_runtime.dig("runtime", "activeScriptURL").to_s.include?("/custom-sw.js") &&
      admin_runtime_required_cache.all? { |url| admin_runtime.dig("runtime", "cached", url) == true } &&
      Array(admin_runtime.dig("console", "errors")).empty? &&
      admin_screenshot_summary_ok &&
      admin_screenshot_items.all? { |item| item.fetch("status") == "pass" }
    "pass"
  else
    "fail"
  end

mobile_route_captures = Array(mobile_route_render_summary["captures"])
mobile_route_items = mobile_route_captures.map do |capture|
  file_name = capture["path"].to_s
  png_path = File.join(bundle_dir, "mobile_route_render_smoke", file_name)
  check_path = "#{png_path}.json"
  check = read_json(check_path)
  exists = File.file?(png_path)
  check_exists = File.file?(check_path)
  actual_bytes = exists ? File.size(png_path) : nil
  png = png_header(png_path)
  declared_bytes = check["bytes"].to_i
  bytes_match = !actual_bytes.nil? && declared_bytes == actual_bytes
  status =
    if exists &&
        check_exists &&
        png["valid"] &&
        check["status"] == "pass" &&
        check["width"].to_i == 390 &&
        check["height"].to_i == 844 &&
        png["width"].to_i == 390 &&
        png["height"].to_i == 844 &&
        declared_bytes > 8_000 &&
        bytes_match &&
        check["distinct_rgb"].to_i >= 8 &&
        check["non_background_pixels"].to_i >= 100
      "pass"
    else
      "fail"
    end
  {
    "name" => capture["name"],
    "route" => capture["route"],
    "file" => file_name,
    "path" => png_path,
    "exists" => exists,
    "png_valid" => png["valid"],
    "check_path" => check_path,
    "check_exists" => check_exists,
    "width" => check["width"],
    "height" => check["height"],
    "actual_width" => png["width"],
    "actual_height" => png["height"],
    "bytes" => declared_bytes,
    "actual_bytes" => actual_bytes,
    "bytes_match" => bytes_match,
    "distinct_rgb" => check["distinct_rgb"],
    "non_background_pixels" => check["non_background_pixels"],
    "status" => status
  }
end

required_mobile_routes = %w[
  /
  /auth
  /settings/profile
  /home
  /groups
  /groups/create
  /groups/scan
  /groups/col-church
  /groups/col-church/share
  /groups/col-church/invite
  /c/st-michel-building-fund
  /groups/col-church/contribute
  /groups/col-church/ledger
  /groups/col-church/manage
  /groups/col-church/profile
  /groups/col-church/members
  /settings
  /settings/account
  /settings/account/delete
  /settings/legal/privacy
  /settings/legal/terms
]
mobile_route_summary_ok =
  mobile_route_render_summary["status"] == "pass" &&
  mobile_route_render_summary["viewport"] == "390x844" &&
  mobile_route_render_summary["route_count"].to_i >= required_mobile_routes.length &&
  (required_mobile_routes - Array(mobile_route_render_summary["routes"])).empty? &&
  (Array(mobile_route_render_summary["screenshots"]) - mobile_route_items.map { |item| item.fetch("file") }).empty? &&
  (Array(mobile_route_render_summary["screenshot_checks"]) - mobile_route_items.map { |item| "#{item.fetch("file")}.json" }).empty?
mobile_route_render_status =
  if command_blocked?(commands, "mobile_route_render_smoke")
    "blocked"
  elsif command_ok?(commands, "mobile_route_render_smoke") &&
      mobile_route_summary_ok &&
      mobile_route_items.length >= required_mobile_routes.length &&
      mobile_route_items.all? { |item| item.fetch("status") == "pass" }
    "pass"
  else
    "fail"
  end

admin_hosting_status =
  if command_ok?(commands, "admin_pwa_hosting_gate") && admin_hosting["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "admin_pwa_hosting_gate") && admin_hosting["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

admin_live_status =
  if admin_live_fixture
    "fail"
  elsif command_ok?(commands, "admin_pwa_live_gate") && admin_live["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "admin_pwa_live_gate") && admin_live["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

signoff_status =
  if command_ok?(commands, "uat_signoff_gate") &&
      uat_signoff["status"] == "pass" &&
      uat_signoff["signoff_approved"] == true
    "pass"
  elsif (command_blocked?(commands, "uat_signoff_gate") ||
      command_ok?(commands, "uat_signoff_gate")) &&
      (uat_signoff["status"] == "blocked" ||
        uat_signoff["decision"] == "blocked" ||
        uat_signoff["blocker_keys"].to_a.include?("human_uat_signoff"))
    "blocked"
  else
    "fail"
  end

uat_evidence_status =
  if command_ok?(commands, "uat_evidence_gate") && uat_evidence["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "uat_evidence_gate") && uat_evidence["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

supabase_status =
  if command_ok?(commands, "supabase_go_live_gate_json") && go_live_gate_consistent?(go_live_gate)
    "pass"
  elsif !command_ok?(commands, "supabase_go_live_gate_json") &&
      go_live_gate["go_live_approved"] == false
    "blocked"
  elsif Array(go_live_gate["blocker_keys"]).any? ||
      go_live_gate["status"].to_s == "blocked" ||
      go_live_gate["approval_status"].to_s == "blocked"
    "blocked"
  else
    "fail"
  end

supabase_evidence_bundle_status =
  if command_ok?(commands, "supabase_go_live_evidence") && supabase_summary["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "supabase_go_live_evidence") ||
      supabase_summary["status"] == "blocked" ||
      Array(supabase_summary["blocker_keys"]).any? ||
      Array(supabase_summary["blocked_reasons"]).any? ||
      Array(supabase_summary["blocked_commands"]).any?
    "blocked"
  else
    "fail"
  end

worktree_status =
  if command_ok?(commands, "release_worktree_review") && worktree_review["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "release_worktree_review") && worktree_review["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

mobile_release_status =
  if command_ok?(commands, "flutter_mobile_release_gate") && mobile_release["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "flutter_mobile_release_gate") && mobile_release["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

bundle_files = [
  file_item(File.join(bundle_dir, "commands.tsv")),
  file_item(File.join(bundle_dir, "release_status.json")),
  file_item(File.join(bundle_dir, "go_live_gate.json")),
  file_item(File.join(bundle_dir, "worktree_review.json"), required: false),
  file_item(File.join(bundle_dir, "uat_evidence_gate.json"), required: false),
  file_item(File.join(bundle_dir, "uat_signoff_gate.json"), required: false),
  file_item(File.join(bundle_dir, "mobile_release_gate.json"), required: false),
  file_item(File.join(bundle_dir, "mobile_route_artifact_gate.json"), required: false),
  file_item(File.join(bundle_dir, "android_release_signing_preflight.json"), required: false),
  file_item(File.join(bundle_dir, "android_kotlin_plugin_compat.json"), required: false),
  file_item(File.join(bundle_dir, "admin_pwa_hosting_gate.json"), required: false),
  file_item(File.join(bundle_dir, "admin_pwa_live_gate.json"), required: false),
  file_item(File.join(bundle_dir, "BUILD_ARTIFACT_CHECKSUMS.sha256"), required: false),
  file_item(File.join(bundle_dir, "admin_pwa_render_smoke", "summary.json"), required: false),
  file_item(File.join(bundle_dir, "admin_pwa_render_smoke", "pwa-runtime.json"), required: false),
  file_item(File.join(bundle_dir, "mobile_route_render_smoke", "summary.json"), required: false),
  file_item(File.join(bundle_dir, "supabase", "summary.json"), required: false)
]

section_statuses = {
  "documents" => doc_items.any? { |item| item.fetch("status") == "fail" } ? "fail" : "pass",
  "commands" => if command_items.any? { |item| item.fetch("status") == "fail" }
    "fail"
  elsif command_items.any? { |item| item.fetch("status") == "blocked" }
    "blocked"
  else
    "pass"
  end,
  "bundle_redaction" => bundle_redaction.fetch("status"),
  "artifacts" => artifact_status,
  "flutter_mobile_release" => mobile_release_status,
  "admin_pwa_runtime" => admin_runtime_status,
  "mobile_route_render" => mobile_route_render_status,
  "admin_pwa_hosting" => admin_hosting_status,
  "admin_pwa_live_deployment" => admin_live_status,
  "worktree_review" => worktree_status,
  "human_uat_evidence" => uat_evidence_status,
  "human_uat_signoff" => signoff_status,
  "supabase_go_live" => supabase_status,
  "supabase_evidence_bundle" => supabase_evidence_bundle_status
}

failed_sections = section_statuses.select { |_name, status| status == "fail" }.keys
blocked_sections = section_statuses.select { |_name, status| status == "blocked" }.keys
index_status =
  if failed_sections.any?
    "fail"
  elsif blocked_sections.any?
    "blocked"
  else
    "pass"
  end

admin_live_failure_keys = Array(admin_live["failure_keys"])
admin_live_failure_keys << "admin_pwa_live_fixture_not_production" if admin_live_fixture

blocker_keys = (
  failed_sections +
  blocked_sections +
  Array(release_status["blocker_keys"]) +
  Array(go_live_gate["blocker_keys"]) +
  Array(supabase_summary["blocker_keys"]) +
  Array(mobile_release["blocker_keys"]) +
  Array(mobile_release["failure_keys"]) +
  Array(uat_evidence["blocker_keys"]) +
  Array(uat_evidence["failure_keys"]) +
  Array(uat_signoff["blocker_keys"]) +
  Array(admin_hosting["blocker_keys"]) +
  Array(admin_hosting["failure_keys"]) +
  Array(admin_live["blocker_keys"]) +
  admin_live_failure_keys +
  Array(worktree_review["blocker_keys"])
).compact.map(&:to_s).reject(&:empty?).uniq.sort

index = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => index_status,
  "bundle_dir" => bundle_dir,
  "go_live_decision" => go_live_gate["decision"] || release_status["decision"],
  "go_live_approved" => go_live_gate["go_live_approved"],
  "failed_sections" => failed_sections,
  "blocked_sections" => blocked_sections,
  "blocker_keys" => blocker_keys,
  "section_statuses" => section_statuses,
  "documents" => doc_items,
  "commands" => command_items,
  "bundle_redaction" => bundle_redaction,
  "artifacts" => {
    "checksum_manifest" => bundle_checksum_manifest,
    "checksum_manifest_present" => File.file?(bundle_checksum_manifest),
    "status" => artifact_status,
    "items" => artifact_items
  },
  "admin_pwa_runtime" => {
    "status" => admin_runtime_status,
    "evidence_path" => File.join(bundle_dir, "admin_pwa_render_smoke", "pwa-runtime.json"),
    "summary_path" => File.join(bundle_dir, "admin_pwa_render_smoke", "summary.json"),
    "active_script_url" => admin_runtime.dig("runtime", "activeScriptURL"),
    "cache_keys" => admin_runtime.dig("runtime", "cacheKeys") || [],
    "required_cached_urls" => admin_runtime_required_cache,
    "screenshot_summary_ok" => admin_screenshot_summary_ok,
    "screenshot_checks" => admin_screenshot_items
  },
  "mobile_route_render" => {
    "status" => mobile_route_render_status,
    "summary_path" => File.join(bundle_dir, "mobile_route_render_smoke", "summary.json"),
    "viewport" => mobile_route_render_summary["viewport"],
    "route_count" => mobile_route_render_summary["route_count"],
    "required_routes" => required_mobile_routes,
    "screenshot_summary_ok" => mobile_route_summary_ok,
    "screenshot_checks" => mobile_route_items
  },
  "admin_pwa_hosting" => {
    "status" => admin_hosting_status,
    "failure_keys" => admin_hosting["failure_keys"] || [],
    "files" => admin_hosting["files"] || {}
  },
  "admin_pwa_live_deployment" => {
    "status" => admin_live_status,
    "url" => admin_live["url"],
    "blocker_keys" => admin_live["blocker_keys"] || [],
    "failure_keys" => admin_live_failure_keys.uniq,
    "fixture_mode" => admin_live_fixture
  },
  "flutter_mobile_release" => {
    "status" => mobile_release_status,
    "blocker_keys" => mobile_release["blocker_keys"] || [],
    "failure_keys" => mobile_release["failure_keys"] || [],
    "android" => mobile_release["android"] || {},
    "ios" => mobile_release["ios"] || {}
  },
  "worktree_review" => {
    "status" => worktree_status,
    "branch" => worktree_review["branch"],
    "upstream" => worktree_review["upstream"],
    "dirty" => worktree_review["dirty"],
    "changed_count" => worktree_review["changed_count"],
    "blocker_keys" => worktree_review["blocker_keys"] || []
  },
  "human_uat_signoff" => {
    "status" => signoff_status,
    "blocker_keys" => uat_signoff["blocker_keys"] || ["human_uat_signoff"]
  },
  "human_uat_evidence" => {
    "status" => uat_evidence_status,
    "manifest" => uat_evidence["manifest"],
    "blocker_keys" => uat_evidence["blocker_keys"] || [],
    "personas_present" => uat_evidence["personas_present"] || [],
    "evidence_items" => uat_evidence["evidence_items"] || []
  },
  "supabase" => {
    "status" => supabase_status,
    "release_status_decision" => release_status["decision"],
    "go_live_gate_decision" => go_live_gate["decision"],
    "go_live_approved" => go_live_gate["go_live_approved"],
    "go_live_gate_status" => go_live_gate["status"],
    "blocker_keys" => go_live_gate["blocker_keys"] || []
  },
  "supabase_evidence_bundle" => {
    "status" => supabase_evidence_bundle_status,
    "summary_path" => File.join(bundle_dir, "supabase", "summary.json"),
    "bundle_status" => supabase_summary["status"],
    "blocker_keys" => supabase_summary["blocker_keys"] || [],
    "blocked_reasons" => supabase_summary["blocked_reasons"] || [],
    "blocked_commands" => supabase_summary["blocked_commands"] || []
  },
  "bundle_files" => bundle_files,
  "secret_handling" => "Evidence index stores paths, decisions, hashes, and blocker keys only; it must not print .env values or raw customer data."
}

if output_format == "json"
  puts JSON.pretty_generate(index)
else
  puts "[release-evidence-index] status=#{index.fetch("status")}"
  puts "[release-evidence-index] bundle=#{bundle_dir}"
  index.fetch("section_statuses").each do |name, status|
    puts "[release-evidence-index] #{name}=#{status}"
  end
end

exit(index_status == "pass" ? 0 : (index_status == "blocked" ? 99 : 1))
RUBY
