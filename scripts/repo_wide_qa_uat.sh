#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
DART="${DART:-/Volumes/PRO-G40/flutter_3_44/bin/dart}"
ADB="${ADB:-adb}"
JAVA_HOME="${JAVA_HOME:-/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home}"
ANDROID_DEVICE_ID="${ANDROID_UAT_DEVICE_ID:-13111JEC215558}"

output_format="text"
if [[ "${1:-}" == "--json" ]]; then
  output_format="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
bundle_dir="${QA_UAT_BUNDLE_DIR:-$ROOT_DIR/.cache/repo_wide_qa_uat/$timestamp}"
mkdir -p "$bundle_dir"
commands_tsv="$bundle_dir/commands.tsv"
: > "$commands_tsv"

run_capture() {
  local name="$1"
  local outfile="$2"
  shift 2

  local started
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  set +e
  "$@" > "$bundle_dir/$outfile" 2>&1
  local rc=$?
  set -e
  local finished
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$outfile" "$rc" "$started" "$finished" >> "$commands_tsv"
  return 0
}

record_blocked() {
  local name="$1"
  local outfile="$2"
  local message="$3"

  if [[ "$outfile" == *.json ]]; then
    BLOCKER_KEY="$name" BLOCKER_MESSAGE="$message" ruby -r json <<'RUBY' > "$bundle_dir/$outfile"
puts JSON.pretty_generate(
  {
    "status" => "blocked",
    "blocker_keys" => [ENV.fetch("BLOCKER_KEY")],
    "blockers" => [ENV.fetch("BLOCKER_MESSAGE")],
    "manifest_written" => false,
    "skipped" => true
  }
)
RUBY
  else
    printf '[repo-wide-qa-uat][BLOCKED] %s\n' "$message" > "$bundle_dir/$outfile"
  fi
  printf '%s\t%s\t99\t%s\t%s\n' "$name" "$outfile" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$commands_tsv"
}

record_fixture() {
  local name="$1"
  local outfile="$2"
  local rc="$3"
  local message="$4"

  if [[ "$outfile" == *.json && "${message:0:1}" == "{" ]]; then
    printf '%s\n' "$message" > "$bundle_dir/$outfile"
  elif [[ "$outfile" == *.json ]]; then
    FIXTURE_NAME="$name" FIXTURE_STATUS="$([[ "$rc" == "0" ]] && printf pass || printf fail)" FIXTURE_MESSAGE="$message" ruby -r json <<'RUBY' > "$bundle_dir/$outfile"
puts JSON.pretty_generate(
  {
    "status" => ENV.fetch("FIXTURE_STATUS"),
    "fixture" => true,
    "name" => ENV.fetch("FIXTURE_NAME"),
    "message" => ENV.fetch("FIXTURE_MESSAGE")
  }
)
RUBY
  else
    printf '%s\n' "$message" > "$bundle_dir/$outfile"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$outfile" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$commands_tsv"
}

command_ok_recorded() {
  local name="$1"
  awk -F '\t' -v command_name="$name" '$1 == command_name { rc = $3; seen = 1 } END { exit(seen && rc == 0 ? 0 : 1) }' "$commands_tsv"
}

android_device_ready() {
  command -v "$ADB" >/dev/null 2>&1 &&
    "$ADB" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$ANDROID_DEVICE_ID"
}

if [[ "${QA_UAT_FIXTURE:-0}" == "1" ]]; then
  for name in flutter_version dart_version format_check flutter_analyze flutter_test release_secret_scan admin_pwa_build admin_pwa_manifest_gate admin_pwa_hosting_gate admin_pwa_render_smoke mobile_route_render_smoke; do
    record_fixture "$name" "$name.txt" 0 "[repo-wide-qa-uat][fixture] $name passed"
  done
  record_fixture "collect_product_boundary_scan" "collect_product_boundary_scan.json" 0 "[repo-wide-qa-uat][fixture] collect_product_boundary_scan passed"
  cat > "$bundle_dir/admin_pwa_hosting_gate.json" <<'JSON'
{
  "status": "pass",
  "failure_keys": [],
  "files": {
    "_headers": {
      "exists": true
    },
    "robots.txt": {
      "exists": true
    }
  }
}
JSON
  mkdir -p "$bundle_dir/admin_pwa_render_smoke"
  cat > "$bundle_dir/admin_pwa_render_smoke/pwa-runtime.json" <<'JSON'
{
  "status": "pass",
  "runtime": {
    "activeScriptURL": "http://127.0.0.1/custom-sw.js?v=collect-admin-fixture",
    "cacheKeys": ["collect-admin-fixture"],
    "cached": {
      "./index.html": true,
      "./flutter_bootstrap.js": true,
      "./main.dart.js": true,
      "./manifest.json": true,
      "./icons/collect-admin.png": true
    }
  },
  "console": {
    "errors": [],
    "warnings": []
  }
}
JSON
  cat > "$bundle_dir/admin_pwa_render_smoke/desktop-1440x900.png.json" <<'JSON'
{
  "status": "pass",
  "path": "desktop-1440x900.png",
  "width": 1440,
  "height": 900,
  "bytes": 24000,
  "sampled_pixels": 20000,
  "distinct_rgb": 64,
  "non_background_pixels": 12000
}
JSON
  cat > "$bundle_dir/admin_pwa_render_smoke/mobile-390x844.png.json" <<'JSON'
{
  "status": "pass",
  "path": "mobile-390x844.png",
  "width": 390,
  "height": 844,
  "bytes": 18000,
  "sampled_pixels": 20000,
  "distinct_rgb": 48,
  "non_background_pixels": 9000
}
JSON
  ruby -e 'path, width, height, size = ARGV; bytes = Array.new(size.to_i, 0); bytes[0, 8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; bytes[8, 4] = [13].pack("N").bytes; bytes[12, 4] = "IHDR".bytes; bytes[16, 4] = [width.to_i].pack("N").bytes; bytes[20, 4] = [height.to_i].pack("N").bytes; bytes[24] = 8; bytes[25] = 2; File.binwrite(path, bytes.pack("C*"))' "$bundle_dir/admin_pwa_render_smoke/desktop-1440x900.png" 1440 900 24000
  ruby -e 'path, width, height, size = ARGV; bytes = Array.new(size.to_i, 0); bytes[0, 8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; bytes[8, 4] = [13].pack("N").bytes; bytes[12, 4] = "IHDR".bytes; bytes[16, 4] = [width.to_i].pack("N").bytes; bytes[20, 4] = [height.to_i].pack("N").bytes; bytes[24] = 8; bytes[25] = 2; File.binwrite(path, bytes.pack("C*"))' "$bundle_dir/admin_pwa_render_smoke/mobile-390x844.png" 390 844 18000
  cat > "$bundle_dir/admin_pwa_render_smoke/summary.json" <<'JSON'
{
  "status": "pass",
  "screenshots": [
    "desktop-1440x900.png",
    "mobile-390x844.png"
  ],
  "screenshot_checks": [
    "desktop-1440x900.png.json",
    "mobile-390x844.png.json"
  ],
  "runtime_evidence": "pwa-runtime.json"
}
JSON
  mkdir -p "$bundle_dir/mobile_route_render_smoke"
  mobile_routes=(
    "onboarding|/onboarding"
    "auth|/auth"
    "auth-success|/auth/success"
    "auth-failure|/auth/failure"
    "profile|/settings/profile"
    "profile-readiness|/settings/readiness"
    "sms-permission|/permissions/sms"
    "sms-denied|/permissions/sms-denied"
    "device-permission|/permissions/device"
    "home|/home"
    "groups|/groups"
    "group-create|/groups/create"
    "iphone-create-unavailable|/platform/iphone-create-unavailable"
    "group-detail|/groups/col-church"
    "group-created|/groups/col-church/created"
    "group-joined|/groups/col-church/joined"
    "join|/groups/join"
    "share|/groups/col-church/share"
    "share-invalid|/share/invalid"
    "share-expired|/share/expired"
    "contribution|/groups/col-church/contribute"
    "payment-waiting|/groups/col-church/pay/intent-render/waiting"
    "payment-pending|/groups/col-church/pay/intent-render/state/pending"
    "payment-confirmed|/groups/col-church/pay/intent-render/state/confirmed"
    "payment-expired|/groups/col-church/pay/intent-render/state/expired"
    "payment-needs-review|/groups/col-church/pay/intent-render/state/needs-review"
    "ledger|/groups/col-church/ledger"
    "manage|/groups/col-church/manage"
    "group-profile|/groups/col-church/profile"
    "members|/groups/col-church/members"
    "settings|/settings"
    "account|/settings/account"
    "account-delete|/settings/account/delete"
    "privacy|/settings/privacy"
    "legal-privacy|/settings/legal/privacy"
    "legal-terms|/settings/legal/terms"
    "help|/settings/help"
    "notifications|/notifications"
    "offline|/offline"
    "sync|/sync"
  )
  : > "$bundle_dir/mobile_route_render_smoke/captures.jsonl"
  for spec in "${mobile_routes[@]}"; do
    IFS='|' read -r route_name route_path <<< "$spec"
    png="$bundle_dir/mobile_route_render_smoke/${route_name}-390x844.png"
    ruby -e 'path, width, height, size = ARGV; bytes = Array.new(size.to_i, 0); bytes[0, 8] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; bytes[8, 4] = [13].pack("N").bytes; bytes[12, 4] = "IHDR".bytes; bytes[16, 4] = [width.to_i].pack("N").bytes; bytes[20, 4] = [height.to_i].pack("N").bytes; bytes[24] = 8; bytes[25] = 2; File.binwrite(path, bytes.pack("C*"))' "$png" 390 844 18000
    cat > "$png.json" <<JSON
{
  "status": "pass",
  "name": "$route_name",
  "route": "$route_path",
  "path": "$(basename "$png")",
  "width": 390,
  "height": 844,
  "bytes": 18000,
  "sampled_pixels": 20000,
  "distinct_rgb": 48,
  "non_background_pixels": 9000
}
JSON
    cat "$png.json" | tr -d '\n' >> "$bundle_dir/mobile_route_render_smoke/captures.jsonl"
    printf '\n' >> "$bundle_dir/mobile_route_render_smoke/captures.jsonl"
  done
  ruby -r json - "$bundle_dir/mobile_route_render_smoke" <<'RUBY'
dir = ARGV.fetch(0)
captures = File.readlines(File.join(dir, "captures.jsonl"), chomp: true).map { |line| JSON.parse(line) }
File.write(
  File.join(dir, "summary.json"),
  JSON.pretty_generate(
    {
      "status" => "pass",
      "viewport" => "390x844",
      "route_count" => captures.length,
      "routes" => captures.map { |item| item.fetch("route") },
      "screenshots" => captures.map { |item| item.fetch("path") },
      "screenshot_checks" => captures.map { |item| "#{item.fetch("path")}.json" },
      "captures" => captures,
      "secret_handling" => "Fixture mobile screenshots contain no production data."
    }
  ) + "\n"
)
RUBY
  cat > "$bundle_dir/worktree_review.json" <<'JSON'
{
  "status": "blocked",
  "blocker_keys": ["worktree_review"],
  "branch": "fixture",
  "upstream": "origin/fixture",
  "dirty": true,
  "changed_count": 1,
  "changed_paths": [
    {
      "status": "??",
      "path": "fixture"
    }
  ]
}
JSON
  record_fixture "release_worktree_review" "worktree_review.json" 99 "$(cat "$bundle_dir/worktree_review.json")"
  if [[ "${QA_UAT_ADMIN_LIVE_FIXTURE_PASS:-0}" == "1" ]]; then
    cat > "$bundle_dir/admin_pwa_live_gate.json" <<'JSON'
{
  "status": "pass",
  "fixture_mode": true,
  "failure_keys": [],
  "responses": {
    "/": {
      "status": 200
    }
  }
}
JSON
    record_fixture "admin_pwa_live_gate" "admin_pwa_live_gate.json" 0 "$(cat "$bundle_dir/admin_pwa_live_gate.json")"
  else
    cat > "$bundle_dir/admin_pwa_live_gate.json" <<'JSON'
{
  "status": "blocked",
  "blocker_keys": ["admin_pwa_live_url_missing"],
  "blockers": ["Fixture mode leaves deployed Admin PWA URL proof blocked."]
}
JSON
    record_fixture "admin_pwa_live_gate" "admin_pwa_live_gate.json" 99 "$(cat "$bundle_dir/admin_pwa_live_gate.json")"
  fi
  cat > "$bundle_dir/uat_signoff_gate.json" <<'JSON'
{
  "decision": "blocked",
  "status": "blocked",
  "signoff_approved": false,
  "blocker_keys": ["human_uat_signoff"],
  "blockers": ["Fixture mode leaves human UAT signoff blocked."]
}
JSON
  record_fixture "uat_signoff_gate" "uat_signoff_gate.json" 99 "$(cat "$bundle_dir/uat_signoff_gate.json")"
  record_blocked "android_apk_release_build" "android_apk_release_build.txt" "Fixture mode leaves release APK build blocked."
  record_blocked "android_aab_release_build" "android_aab_release_build.txt" "Fixture mode leaves release AAB build blocked."
  cat > "$bundle_dir/release_artifact_manifest.json" <<'JSON'
{
  "status": "blocked",
  "manifest_written": false,
  "missing_artifacts": ["fixture_release_artifacts"],
  "failures": []
}
JSON
  record_fixture "release_artifact_manifest" "release_artifact_manifest.json" 99 "$(cat "$bundle_dir/release_artifact_manifest.json")"
  cat > "$bundle_dir/mobile_release_gate.json" <<'JSON'
{
  "status": "blocked",
  "blocker_keys": ["android_release_signing_review", "ios_release_scope"],
  "checks": {
    "android_release_signing_review": {
      "status": "blocked",
      "message": "Fixture mode leaves Android signing review blocked."
    },
    "ios_release_scope": {
      "status": "blocked",
      "message": "Fixture mode leaves iOS release scope blocked."
    }
  }
}
JSON
  record_fixture "flutter_mobile_release_gate" "mobile_release_gate.json" 99 "$(cat "$bundle_dir/mobile_release_gate.json")"
  cat > "$bundle_dir/uat_evidence_gate.json" <<'JSON'
{
  "status": "blocked",
  "blocker_keys": ["uat_evidence_manifest_missing"],
  "blockers": ["Fixture mode leaves human UAT evidence manifest blocked."]
}
JSON
  record_fixture "uat_evidence_gate" "uat_evidence_gate.json" 99 "$(cat "$bundle_dir/uat_evidence_gate.json")"
  record_blocked "android_device_uat" "android_device_uat.txt" "Fixture mode leaves Android device UAT blocked."
  cat > "$bundle_dir/release_status.json" <<'JSON'
{
  "decision": "NO-GO",
  "supabase_strict": "fail",
  "blocker_keys": ["database_connectivity"]
}
JSON
  record_fixture "release_status_json" "release_status.json" 0 "$(cat "$bundle_dir/release_status.json")"
  cat > "$bundle_dir/go_live_gate.json" <<'JSON'
{
  "decision": "NO-GO",
  "approval_status": "blocked",
  "go_live_approved": false,
  "blocker_keys": ["database_connectivity"]
}
JSON
  record_fixture "supabase_go_live_gate_json" "go_live_gate.json" 1 "$(cat "$bundle_dir/go_live_gate.json")"
  record_blocked "supabase_go_live_evidence" "supabase_go_live_evidence.txt" "Fixture mode leaves Supabase evidence generation blocked."
  if [[ "${QA_UAT_CONTRADICTORY_FIXTURE:-0}" == "1" ]]; then
    cat > "$bundle_dir/release_status.json" <<'JSON'
{
  "decision": "GO",
  "status": "pass",
  "supabase_strict": "pass",
  "blocker_keys": []
}
JSON
    record_fixture "release_status_json" "release_status.json" 0 "$(cat "$bundle_dir/release_status.json")"
    cat > "$bundle_dir/go_live_gate.json" <<'JSON'
{
  "decision": "GO",
  "approval_status": "approved",
  "go_live_approved": true,
  "status": "blocked",
  "blocker_keys": ["android_sms_access_uat"]
}
JSON
    record_fixture "supabase_go_live_gate_json" "go_live_gate.json" 0 "$(cat "$bundle_dir/go_live_gate.json")"
    mkdir -p "$bundle_dir/supabase"
    cat > "$bundle_dir/supabase/summary.json" <<'JSON'
{
  "status": "blocked",
  "blocker_keys": ["android_sms_access_uat"],
  "blocked_reasons": ["acceptance_matrix_blocked"],
  "blocked_commands": ["acceptance_matrix_json"],
  "acceptance_matrix": {
    "overall_status": "blocked"
  }
}
JSON
    record_fixture "supabase_go_live_evidence" "supabase_go_live_evidence.txt" 0 "$(cat "$bundle_dir/supabase/summary.json")"
  fi
  if [[ "${QA_UAT_JSON_BLOCKED_PROBE:-0}" == "1" ]]; then
    record_blocked "json_blocked_probe" "json_blocked_probe.json" "Fixture mode probes blocked JSON evidence."
  fi
  run_capture "release_evidence_index" "evidence_index.json" env RELEASE_EVIDENCE_BUNDLE_DIR="$bundle_dir" "$ROOT_DIR/scripts/release_evidence_index.sh" --json
else
  run_capture "flutter_version" "flutter_version.txt" "$FLUTTER" --version
  run_capture "dart_version" "dart_version.txt" "$DART" --version
  run_capture "format_check" "format_check.txt" "$DART" format --set-exit-if-changed .
  run_capture "flutter_analyze" "flutter_analyze.txt" "$FLUTTER" analyze --no-pub
  run_capture "flutter_test" "flutter_test.txt" "$FLUTTER" test --no-pub --concurrency=1
  run_capture "release_secret_scan" "release_secret_scan.txt" "$ROOT_DIR/scripts/release_secret_scan.sh"
  run_capture "collect_product_boundary_scan" "collect_product_boundary_scan.json" "$ROOT_DIR/scripts/collect_product_boundary_scan.sh" --json
  run_capture "release_worktree_review" "worktree_review.json" "$ROOT_DIR/scripts/release_worktree_review_gate.sh" --json
  run_capture "admin_pwa_build" "admin_pwa_build.txt" "$ROOT_DIR/scripts/admin_pwa_release_build.sh"
  run_capture "admin_pwa_manifest_gate" "admin_pwa_manifest_gate.txt" "$ROOT_DIR/scripts/admin_pwa_manifest_gate.sh"
  run_capture "admin_pwa_hosting_gate" "admin_pwa_hosting_gate.json" "$ROOT_DIR/scripts/admin_pwa_hosting_gate.sh" --json
  run_capture "admin_pwa_live_gate" "admin_pwa_live_gate.json" "$ROOT_DIR/scripts/admin_pwa_live_gate.sh" --json
  run_capture "admin_pwa_render_smoke" "admin_pwa_render_smoke.txt" env ADMIN_PWA_RENDER_EVIDENCE_DIR="$bundle_dir/admin_pwa_render_smoke" "$ROOT_DIR/scripts/admin_pwa_render_smoke.sh"
  run_capture "mobile_route_render_smoke" "mobile_route_render_smoke.txt" env MOBILE_ROUTE_RENDER_EVIDENCE_DIR="$bundle_dir/mobile_route_render_smoke" "$ROOT_DIR/scripts/mobile_route_render_smoke.sh"
  run_capture "uat_evidence_gate" "uat_evidence_gate.json" "$ROOT_DIR/scripts/uat_evidence_gate.sh" --json
  run_capture "uat_signoff_gate" "uat_signoff_gate.json" "$ROOT_DIR/scripts/uat_signoff_gate.sh" --json

  if [[ "${QA_UAT_RELEASE_BUILDS:-1}" == "1" ]]; then
    run_capture "android_apk_release_build" "android_apk_release_build.txt" env JAVA_HOME="$JAVA_HOME" "$FLUTTER" build apk --release --flavor production --no-pub
    run_capture "android_aab_release_build" "android_aab_release_build.txt" env JAVA_HOME="$JAVA_HOME" "$FLUTTER" build appbundle --release --flavor production --no-pub
    if command_ok_recorded "admin_pwa_build" && command_ok_recorded "android_apk_release_build" && command_ok_recorded "android_aab_release_build"; then
      run_capture "release_artifact_manifest" "release_artifact_manifest.json" env RELEASE_ARTIFACT_MANIFEST_PATH="$bundle_dir/BUILD_ARTIFACT_CHECKSUMS.sha256" "$ROOT_DIR/scripts/release_artifact_manifest.sh" --json
    else
      record_blocked "release_artifact_manifest" "release_artifact_manifest.json" "Release artifact manifest skipped because Admin PWA and Android release builds did not all pass."
    fi
  else
    record_blocked "android_apk_release_build" "android_apk_release_build.txt" "Release APK build skipped because QA_UAT_RELEASE_BUILDS is not 1."
    record_blocked "android_aab_release_build" "android_aab_release_build.txt" "Release AAB build skipped because QA_UAT_RELEASE_BUILDS is not 1."
    record_blocked "release_artifact_manifest" "release_artifact_manifest.json" "Release artifact manifest skipped because QA_UAT_RELEASE_BUILDS is not 1."
  fi

  run_capture "flutter_mobile_release_gate" "mobile_release_gate.json" "$ROOT_DIR/scripts/flutter_mobile_release_gate.sh" --json

  if [[ "${QA_UAT_REQUIRE_ANDROID_DEVICE:-1}" == "1" ]]; then
    if android_device_ready; then
      run_capture "android_device_uat" "android_device_uat.txt" "$ROOT_DIR/scripts/android_device_uat.sh"
    else
      record_blocked "android_device_uat" "android_device_uat.txt" "Android UAT device $ANDROID_DEVICE_ID is not connected and authorized."
    fi
  else
    record_blocked "android_device_uat" "android_device_uat.txt" "Android device UAT skipped because QA_UAT_REQUIRE_ANDROID_DEVICE is not 1."
  fi

  run_capture "release_status_json" "release_status.json" "$ROOT_DIR/scripts/release_status.sh" --json
  run_capture "supabase_go_live_gate_json" "go_live_gate.json" "$ROOT_DIR/scripts/supabase_go_live_gate.sh" --json

  if [[ "${QA_UAT_SUPABASE_EVIDENCE:-1}" == "1" ]]; then
    run_capture "supabase_go_live_evidence" "supabase_go_live_evidence.txt" env SUPABASE_EVIDENCE_BUNDLE_DIR="$bundle_dir/supabase" "$ROOT_DIR/scripts/supabase_go_live_evidence_bundle.sh"
  else
    record_blocked "supabase_go_live_evidence" "supabase_go_live_evidence.txt" "Supabase evidence bundle skipped because QA_UAT_SUPABASE_EVIDENCE is not 1."
  fi

  run_capture "release_evidence_index" "evidence_index.json" env RELEASE_EVIDENCE_BUNDLE_DIR="$bundle_dir" "$ROOT_DIR/scripts/release_evidence_index.sh" --json
fi

set +e
BUNDLE_DIR="$bundle_dir" COMMANDS_TSV="$commands_tsv" ruby -r json -r time <<'RUBY'
bundle_dir = ENV.fetch("BUNDLE_DIR")
commands_path = ENV.fetch("COMMANDS_TSV")

commands = File.readlines(commands_path, chomp: true).map do |line|
  name, file, exit_code, started_at, finished_at = line.split("\t", 5)
  {
    "name" => name,
    "file" => file,
    "exit_code" => exit_code.to_i,
    "started_at" => started_at,
    "finished_at" => finished_at
  }
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

def command_exit_code(commands, name)
  row = command(commands, name)
  row && row.fetch("exit_code")
end

def go_live_gate_consistent?(gate)
  status = gate["status"].to_s
  gate["go_live_approved"] == true &&
    gate["decision"].to_s == "GO" &&
    gate["approval_status"].to_s == "approved" &&
    (status.empty? || status == "pass") &&
    Array(gate["blocker_keys"]).empty?
end

def read_json(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError, Errno::ENOENT
  {}
end

release_status = read_json(File.join(bundle_dir, "release_status.json"))
go_live_gate = read_json(File.join(bundle_dir, "go_live_gate.json"))
supabase_summary = read_json(File.join(bundle_dir, "supabase", "summary.json"))
admin_live_gate = read_json(File.join(bundle_dir, "admin_pwa_live_gate.json"))
uat_signoff = read_json(File.join(bundle_dir, "uat_signoff_gate.json"))
uat_evidence = read_json(File.join(bundle_dir, "uat_evidence_gate.json"))
mobile_release = read_json(File.join(bundle_dir, "mobile_release_gate.json"))
worktree_review = read_json(File.join(bundle_dir, "worktree_review.json"))
artifact_manifest = read_json(File.join(bundle_dir, "release_artifact_manifest.json"))
admin_hosting = read_json(File.join(bundle_dir, "admin_pwa_hosting_gate.json"))
evidence_index = read_json(File.join(bundle_dir, "evidence_index.json"))

admin_live_surface =
  if admin_live_gate["fixture_mode"] == true
    "fail"
  elsif command_ok?(commands, "admin_pwa_live_gate") && admin_live_gate["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "admin_pwa_live_gate") && admin_live_gate["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

human_signoff_surface =
  if command_ok?(commands, "uat_signoff_gate") &&
      uat_signoff["status"] == "pass" &&
      uat_signoff["signoff_approved"] == true
    "pass"
  elsif command_blocked?(commands, "uat_signoff_gate") &&
      (
        uat_signoff["status"] == "blocked" ||
        uat_signoff["decision"] == "blocked" ||
        uat_signoff["blocker_keys"].to_a.include?("human_uat_signoff")
      )
    "blocked"
  else
    "fail"
  end

supabase_release_surface =
  if command_ok?(commands, "supabase_go_live_gate_json") && go_live_gate_consistent?(go_live_gate)
    "pass"
  elsif (
      command_exit_code(commands, "supabase_go_live_gate_json") == 1 &&
      (go_live_gate["go_live_approved"] == false || go_live_gate["decision"] == "NO-GO")
    ) ||
      Array(go_live_gate["blocker_keys"]).any? ||
      go_live_gate["status"].to_s == "blocked" ||
      go_live_gate["approval_status"].to_s == "blocked"
    "blocked"
  else
    "fail"
  end

admin_pwa_surface =
  if %w[admin_pwa_build admin_pwa_manifest_gate admin_pwa_render_smoke].all? { |name| command_ok?(commands, name) } &&
      command_ok?(commands, "admin_pwa_hosting_gate") &&
      admin_hosting["status"] == "pass"
    "pass"
  else
    "fail"
  end

mobile_route_render_surface =
  if command_ok?(commands, "mobile_route_render_smoke")
    "pass"
  elsif command_blocked?(commands, "mobile_route_render_smoke")
    "blocked"
  else
    "fail"
  end

worktree_surface =
  if command_ok?(commands, "release_worktree_review") && worktree_review["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "release_worktree_review") && worktree_review["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

human_evidence_surface =
  if command_ok?(commands, "uat_evidence_gate") && uat_evidence["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "uat_evidence_gate") && uat_evidence["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

artifact_manifest_surface =
  if command_ok?(commands, "release_artifact_manifest") &&
      artifact_manifest["status"] == "pass" &&
      artifact_manifest["manifest_written"] == true
    "pass"
  elsif command_blocked?(commands, "release_artifact_manifest") && artifact_manifest["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

mobile_release_surface =
  if command_ok?(commands, "flutter_mobile_release_gate") && mobile_release["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "flutter_mobile_release_gate") && mobile_release["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

release_evidence_index_surface =
  if command_ok?(commands, "release_evidence_index") && evidence_index["status"] == "pass"
    "pass"
  elsif command_blocked?(commands, "release_evidence_index") && evidence_index["status"] == "blocked"
    "blocked"
  else
    "fail"
  end

supabase_evidence_bundle_surface =
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

surfaces = {
  "flutter_app" => %w[flutter_version dart_version format_check flutter_analyze flutter_test release_secret_scan collect_product_boundary_scan].all? { |name| command_ok?(commands, name) } ? "pass" : "fail",
  "admin_pwa" => admin_pwa_surface,
  "mobile_route_render" => mobile_route_render_surface,
  "admin_pwa_live_deployment" => admin_live_surface,
  "worktree_review" => worktree_surface,
  "human_uat_evidence" => human_evidence_surface,
  "human_uat_signoff" => human_signoff_surface,
  "android_release_artifacts" => %w[android_apk_release_build android_aab_release_build].all? { |name| command_ok?(commands, name) } ? "pass" : (%w[android_apk_release_build android_aab_release_build].any? { |name| command_blocked?(commands, name) } ? "blocked" : "fail"),
  "release_artifact_manifest" => artifact_manifest_surface,
  "flutter_mobile_release" => mobile_release_surface,
  "release_evidence_index" => release_evidence_index_surface,
  "android_device_uat" => command_ok?(commands, "android_device_uat") ? "pass" : (command_blocked?(commands, "android_device_uat") ? "blocked" : "fail"),
  "supabase_release_gate" => supabase_release_surface,
  "supabase_evidence_bundle" => supabase_evidence_bundle_surface
}

decision =
  if surfaces.value?("fail")
    "FAIL"
  elsif surfaces.value?("blocked")
    "NO-GO"
  else
    "GO"
  end

def collect_values_for_keys(value, keys)
  case value
  when Hash
    value.flat_map do |key, nested_value|
      keys.include?(key) ? Array(nested_value) : collect_values_for_keys(nested_value, keys)
    end
  when Array
    value.flat_map { |nested_value| collect_values_for_keys(nested_value, keys) }
  else
    []
  end
end

failed_surfaces = surfaces.select { |_name, status| status == "fail" }.keys
blocked_surfaces = surfaces.select { |_name, status| status == "blocked" }.keys
blocker_keys = (
  failed_surfaces +
  blocked_surfaces +
  collect_values_for_keys(
    [
      release_status,
      go_live_gate,
      supabase_summary,
      admin_live_gate,
      uat_signoff,
      uat_evidence,
      mobile_release,
      worktree_review,
      artifact_manifest,
      admin_hosting,
      evidence_index
    ],
    %w[blocker_keys failure_keys missing_artifacts]
  )
).compact.map(&:to_s).reject(&:empty?).uniq.sort

summary = {
  "generated_at" => Time.now.utc.iso8601,
  "bundle_dir" => bundle_dir,
  "decision" => decision,
  "surfaces" => surfaces,
  "failed_surfaces" => failed_surfaces,
  "blocked_surfaces" => blocked_surfaces,
  "blocker_keys" => blocker_keys,
  "release_status" => {
    "decision" => release_status["decision"],
    "supabase_strict" => release_status["supabase_strict"],
    "blocker_keys" => release_status["blocker_keys"] || []
  },
  "go_live_gate" => {
    "decision" => go_live_gate["decision"],
    "approval_status" => go_live_gate["approval_status"],
    "go_live_approved" => go_live_gate["go_live_approved"],
    "status" => go_live_gate["status"],
    "blocker_keys" => go_live_gate["blocker_keys"] || []
  },
  "supabase_evidence" => {
    "status" => supabase_summary["status"],
    "decision" => supabase_summary["decision"],
    "blocker_keys" => supabase_summary["blocker_keys"] || [],
    "blocked_reasons" => supabase_summary["blocked_reasons"] || [],
    "blocked_commands" => supabase_summary["blocked_commands"] || [],
    "acceptance_matrix" => supabase_summary["acceptance_matrix"] || {}
  },
  "release_evidence_index" => evidence_index,
  "commands" => commands,
  "secret_handling" => "Outputs are captured into local .cache evidence and release commands must not print raw .env values."
}

File.write(File.join(bundle_dir, "summary.json"), JSON.pretty_generate(summary) + "\n")
File.write(
  File.join(bundle_dir, "README.md"),
  <<~MARKDOWN
    # Repo-Wide QA/UAT Production Readiness Bundle

    Generated at: `#{summary.fetch("generated_at")}`
    Decision: `#{summary.fetch("decision")}`

    ## Surfaces

    #{surfaces.map { |name, status| "- `#{name}`: `#{status}`" }.join("\n")}

    Failed surfaces: #{failed_surfaces.empty? ? "`none`" : failed_surfaces.map { |name| "`#{name}`" }.join(", ")}
    Blocked surfaces: #{blocked_surfaces.empty? ? "`none`" : blocked_surfaces.map { |name| "`#{name}`" }.join(", ")}
    Blocker keys: #{blocker_keys.empty? ? "`none`" : blocker_keys.map { |key| "`#{key}`" }.join(", ")}

    ## Files

    - `summary.json`: machine-readable repo-wide decision
    - `commands.tsv`: command exit codes and timestamps
    - `release_status.json`: redacted strict release status
    - `go_live_gate.json`: final go-live approval gate
    - `admin_pwa_hosting_gate.json`: static hosting headers, cache, CSP, and robots gate
    - `admin_pwa_live_gate.json`: deployed Admin PWA URL headers and PWA file gate
    - `mobile_route_render_smoke/`: representative mobile route screenshots and nonblank PNG checks
    - `worktree_review.json`: release branch/worktree review gate
    - `collect_product_boundary_scan.json`: Collect app product-boundary scan for forbidden Buro/crypto/trading/legacy navigation concepts
    - `uat_evidence_gate.json`: sanitized human UAT evidence manifest gate
    - `uat_signoff_gate.json`: human UAT release-owner signoff gate
    - `mobile_release_gate.json`: Flutter mobile release metadata, signing-review, and iOS-scope gate
    - `BUILD_ARTIFACT_CHECKSUMS.sha256`: APK, AAB, and Admin PWA release artifact hashes when release builds run
    - `evidence_index.json`: release-owner-facing evidence index across docs, commands, artifacts, Admin PWA runtime, signoff, and Supabase gates
    - `supabase/`: nested Supabase evidence bundle when enabled

    #{summary.fetch("secret_handling")}
  MARKDOWN
)

exit(decision == "GO" ? 0 : 1)
RUBY

rc=$?
set -e
if [[ "$output_format" == "json" ]]; then
  cat "$bundle_dir/summary.json"
else
  ruby -r json - "$bundle_dir/summary.json" <<'RUBY'
data = JSON.parse(File.read(ARGV.fetch(0)))
puts "[repo-wide-qa-uat] decision=#{data.fetch("decision")}"
puts "[repo-wide-qa-uat] bundle=#{data.fetch("bundle_dir")}"
data.fetch("surfaces").each do |name, status|
  puts "[repo-wide-qa-uat] #{name}=#{status}"
end
puts "[repo-wide-qa-uat] failed_surfaces=#{Array(data.fetch("failed_surfaces")).join(",")}"
puts "[repo-wide-qa-uat] blocked_surfaces=#{Array(data.fetch("blocked_surfaces")).join(",")}"
puts "[repo-wide-qa-uat] blockers=#{Array(data.fetch("blocker_keys")).join(",")}"
RUBY
fi
exit "$rc"
