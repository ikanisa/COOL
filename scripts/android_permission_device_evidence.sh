#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

resolve_adb() {
  local candidate
  if [[ "${ADB:-}" != "" ]]; then
    printf '%s\n' "$ADB"
    return 0
  fi
  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return 0
  fi
  for candidate in \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$ROOT_DIR/../AppData/android/sdk/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'adb'
}

usage() {
  cat <<'USAGE'
usage: scripts/android_permission_device_evidence.sh [--json]

Environment:
  ADB
  ANDROID_PERMISSION_DEVICE_ID       default: 13111JEC215558
  ANDROID_PERMISSION_PACKAGE         default: app.cool.mobile
  ANDROID_PERMISSION_EVIDENCE_DIR    default: .cache/permission_device_evidence/<timestamp>
USAGE
}

OUTPUT_FORMAT="text"
case "${1:-}" in
  "")
    ;;
  --json)
    OUTPUT_FORMAT="json"
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

ADB_BIN="$(resolve_adb)"
DEVICE_ID="${ANDROID_PERMISSION_DEVICE_ID:-13111JEC215558}"
PACKAGE="${ANDROID_PERMISSION_PACKAGE:-app.cool.mobile}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_PERMISSION_EVIDENCE_DIR:-$ROOT_DIR/.cache/permission_device_evidence/$timestamp}"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
PACKAGE_DUMP="$EVIDENCE_DIR/android_package_permissions.txt"
APPOPS_DUMP="$EVIDENCE_DIR/android_appops_permissions.txt"
DEVICE_FILE="$EVIDENCE_DIR/device.txt"

if ! "$ADB_BIN" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  printf '[android-permission-evidence][FAIL] Android device %s is not connected and authorized over ADB.\n' "$DEVICE_ID" >&2
  exit 1
fi

mkdir -p "$EVIDENCE_DIR"

{
  printf 'device_id=%s\n' "$DEVICE_ID"
  printf 'model=%s\n' "$("$ADB_BIN" -s "$DEVICE_ID" shell getprop ro.product.model | tr -d '\r')"
  printf 'android_release=%s\n' "$("$ADB_BIN" -s "$DEVICE_ID" shell getprop ro.build.version.release | tr -d '\r')"
  printf 'android_sdk=%s\n' "$("$ADB_BIN" -s "$DEVICE_ID" shell getprop ro.build.version.sdk | tr -d '\r')"
  printf 'package=%s\n' "$PACKAGE"
} >"$DEVICE_FILE"

"$ADB_BIN" -s "$DEVICE_ID" shell dumpsys package "$PACKAGE" >"$PACKAGE_DUMP"
"$ADB_BIN" -s "$DEVICE_ID" shell cmd appops get "$PACKAGE" CAMERA POST_NOTIFICATION >"$APPOPS_DUMP" 2>&1 || true

ANDROID_PERMISSION_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
ANDROID_PERMISSION_PACKAGE="$PACKAGE" \
ANDROID_PERMISSION_DEVICE_FILE="${DEVICE_FILE#$ROOT_DIR/}" \
ANDROID_PERMISSION_PACKAGE_DUMP="${PACKAGE_DUMP#$ROOT_DIR/}" \
ANDROID_PERMISSION_APPOPS_DUMP="${APPOPS_DUMP#$ROOT_DIR/}" \
ruby -r json <<'RUBY' >"$SUMMARY_FILE"
package = ENV.fetch("ANDROID_PERMISSION_PACKAGE")
device_file = ENV.fetch("ANDROID_PERMISSION_DEVICE_FILE")
package_dump_path = ENV.fetch("ANDROID_PERMISSION_PACKAGE_DUMP")
appops_path = ENV.fetch("ANDROID_PERMISSION_APPOPS_DUMP")
dump = File.read(package_dump_path)

def permission_lines_after(lines, label)
  start = lines.index { |line| line.match?(/^\s*#{Regexp.escape(label)}:\s*$/) }
  return [] unless start

  values = []
  lines[(start + 1)..]&.each do |line|
    break if line.match?(/^\s*(declared permissions|requested permissions|install permissions|runtime permissions|User \d+|Queries|Dexopt state):/)
    text = line.strip
    next if text.empty?

    values << text
  end
  values
end

lines = dump.lines(chomp: true)
requested_lines = permission_lines_after(lines, "requested permissions")
install_lines = permission_lines_after(lines, "install permissions")
runtime_lines = permission_lines_after(lines, "runtime permissions")

requested = requested_lines.map { |line| line.split(/\s+/).first }.select { |line| line.match?(/permission/i) }
install = install_lines.map { |line| line.split(":").first }.select { |line| line.match?(/permission/i) }
runtime = runtime_lines.filter_map do |line|
  match = line.match(/^\s*([^:]+):\s+granted=(true|false)(?:,\s+flags=\[(.*)\])?/)
  next unless match

  {
    "permission" => match[1],
    "granted" => match[2] == "true",
    "flags" => (match[3] || "").split("|").map(&:strip).reject(&:empty?)
  }
end

runtime_by_permission = runtime.to_h { |entry| [entry.fetch("permission"), entry] }
restricted_sms = %w[
  android.permission.READ_SMS
  android.permission.RECEIVE_SMS
  android.permission.SEND_SMS
  android.permission.BROADCAST_SMS
]
expected_runtime = %w[
  android.permission.CAMERA
  android.permission.POST_NOTIFICATIONS
]

failures = []
failures << "Package #{package} is not installed or dumpsys package returned no package block." unless dump.include?("Package [#{package}]")
expected_runtime.each do |permission|
  failures << "Production package must request #{permission}." unless requested.include?(permission)
  failures << "Production runtime dump must include #{permission}." unless runtime_by_permission.key?(permission)
end

restricted_sms.each do |permission|
  failures << "Production package must not request restricted #{permission}." if requested.include?(permission)
  failures << "Production package must not install-grant restricted #{permission}." if install.include?(permission)
  failures << "Production package must not runtime-grant restricted #{permission}." if runtime_by_permission.key?(permission)
end

expected_runtime.each do |permission|
  next unless runtime_by_permission.key?(permission)

  failures << "#{permission} should be denied before action-triggered native prompt review." if runtime_by_permission.fetch(permission).fetch("granted")
end

summary = {
  "generated_at" => ENV.fetch("ANDROID_PERMISSION_GENERATED_AT"),
  "status" => failures.empty? ? "pass" : "fail",
  "package" => package,
  "requested_permissions" => requested,
  "install_permissions" => install,
  "runtime_permissions" => runtime,
  "restricted_sms_permissions_absent" => restricted_sms.none? { |permission|
    requested.include?(permission) || install.include?(permission) || runtime_by_permission.key?(permission)
  },
  "expected_runtime_permissions" => expected_runtime,
  "failures" => failures,
  "evidence" => {
    "device" => device_file,
    "package_dump" => package_dump_path,
    "appops" => appops_path
  },
  "secret_handling" => "Evidence is limited to Android package permission metadata and app-op state. It must not include raw SMS bodies, OTPs, phone/MoMo numbers, signing keys, provider tokens, or production customer data."
}

puts JSON.pretty_generate(summary)
exit(failures.empty? ? 0 : 1)
RUBY
rc=$?

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  cat "$SUMMARY_FILE"
else
  status="$(ruby -r json -e 'puts JSON.parse(File.read(ARGV[0])).fetch("status")' "$SUMMARY_FILE")"
  printf '[android-permission-evidence] status=%s evidence=%s\n' "$status" "${SUMMARY_FILE#$ROOT_DIR/}"
fi

exit "$rc"
