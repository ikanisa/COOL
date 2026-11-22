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
usage: scripts/android_accessibility_structural_evidence.sh [--json]

Captures Pixel Android accessibility node trees for representative Collect
production flows with TalkBack enabled, including a 200 percent font-scale
launch capture, then restores the original device accessibility settings. This
is structural evidence for Codex-owned native mobile accessibility
responsibility.

Environment:
  ADB
  ANDROID_ACCESSIBILITY_DEVICE_ID       default: 13111JEC215558
  ANDROID_ACCESSIBILITY_PACKAGE         default: app.cool.mobile
  ANDROID_ACCESSIBILITY_EVIDENCE_DIR    default: .cache/android_accessibility_pixel4a/<timestamp>
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
DEVICE_ID="${ANDROID_ACCESSIBILITY_DEVICE_ID:-13111JEC215558}"
PACKAGE="${ANDROID_ACCESSIBILITY_PACKAGE:-app.cool.mobile}"
CLEAR_APP_DATA="${ANDROID_ACCESSIBILITY_CLEAR_APP_DATA:-1}"
TALKBACK_SERVICE="com.google.android.marvin.talkback/.TalkBackService"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_ACCESSIBILITY_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_accessibility_pixel4a/$timestamp}"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"
DEVICE_FILE="$EVIDENCE_DIR/device.txt"
SETTINGS_BEFORE="$EVIDENCE_DIR/device_settings_before.txt"
SETTINGS_AFTER="$EVIDENCE_DIR/device_settings_after.txt"

if ! "$ADB_BIN" devices | awk 'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' id="$DEVICE_ID"; then
  printf '[android-accessibility-structural][FAIL] Android device %s is not connected and authorized over ADB.\n' "$DEVICE_ID" >&2
  exit 1
fi

mkdir -p "$EVIDENCE_DIR"

setting() {
  "$ADB_BIN" -s "$DEVICE_ID" shell settings get "$1" "$2" | tr -d '\r'
}

put_setting() {
  local namespace="$1"
  local key="$2"
  local value="$3"
  if [[ "$value" == "null" ]]; then
    "$ADB_BIN" -s "$DEVICE_ID" shell settings delete "$namespace" "$key" >/dev/null 2>&1 || true
  else
    "$ADB_BIN" -s "$DEVICE_ID" shell settings put "$namespace" "$key" "$value" >/dev/null
  fi
}

before_accessibility_enabled="$(setting secure accessibility_enabled)"
before_enabled_services="$(setting secure enabled_accessibility_services)"
before_font_scale="$(setting system font_scale)"

restore_settings() {
  put_setting secure enabled_accessibility_services "$before_enabled_services"
  put_setting secure accessibility_enabled "$before_accessibility_enabled"
  put_setting system font_scale "$before_font_scale"
}
trap restore_settings EXIT

{
  printf 'device_id=%s\n' "$DEVICE_ID"
  printf 'model=%s\n' "$("$ADB_BIN" -s "$DEVICE_ID" shell getprop ro.product.model | tr -d '\r')"
  printf 'android_release=%s\n' "$("$ADB_BIN" -s "$DEVICE_ID" shell getprop ro.build.version.release | tr -d '\r')"
  printf 'android_sdk=%s\n' "$("$ADB_BIN" -s "$DEVICE_ID" shell getprop ro.build.version.sdk | tr -d '\r')"
  printf 'package=%s\n' "$PACKAGE"
  printf 'talkback_service=%s\n' "$TALKBACK_SERVICE"
} >"$DEVICE_FILE"

{
  printf 'accessibility_enabled=%s\n' "$before_accessibility_enabled"
  printf 'enabled_accessibility_services=%s\n' "$before_enabled_services"
  printf 'font_scale=%s\n' "$before_font_scale"
} >"$SETTINGS_BEFORE"

if ! "$ADB_BIN" -s "$DEVICE_ID" shell pm list packages | grep -q 'com.google.android.marvin.talkback'; then
  printf '[android-accessibility-structural][FAIL] TalkBack package is not installed on %s.\n' "$DEVICE_ID" >&2
  exit 1
fi

if ! "$ADB_BIN" -s "$DEVICE_ID" shell pm path "$PACKAGE" >/dev/null 2>&1; then
  printf '[android-accessibility-structural][FAIL] Package %s is not installed on %s.\n' "$PACKAGE" "$DEVICE_ID" >&2
  exit 1
fi

put_setting secure enabled_accessibility_services "$TALKBACK_SERVICE"
put_setting secure accessibility_enabled 1
put_setting system font_scale 1.0
sleep 2

capture() {
  local name="$1"
  shift
  local remote_xml="/sdcard/collect_${name}.xml"
  local remote_png="/sdcard/collect_${name}.png"
  local local_xml="$EVIDENCE_DIR/${name}.xml"
  local local_png="$EVIDENCE_DIR/${name}.png"
  local launch_log="$EVIDENCE_DIR/${name}_launch.txt"

  "$ADB_BIN" -s "$DEVICE_ID" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  if [[ "$CLEAR_APP_DATA" == "1" ]]; then
    "$ADB_BIN" -s "$DEVICE_ID" shell pm clear "$PACKAGE" >/dev/null 2>&1 || true
  fi
  "$@" >"$launch_log" 2>&1 || true
  sleep 4
  "$ADB_BIN" -s "$DEVICE_ID" shell dumpsys window >"$EVIDENCE_DIR/${name}_window.txt" 2>&1 || true
  "$ADB_BIN" -s "$DEVICE_ID" shell uiautomator dump "$remote_xml" >"$EVIDENCE_DIR/${name}_uiautomator.txt" 2>&1
  "$ADB_BIN" -s "$DEVICE_ID" shell screencap -p "$remote_png" >/dev/null
  "$ADB_BIN" -s "$DEVICE_ID" pull "$remote_xml" "$local_xml" >/dev/null
  "$ADB_BIN" -s "$DEVICE_ID" pull "$remote_png" "$local_png" >/dev/null
  "$ADB_BIN" -s "$DEVICE_ID" shell rm -f "$remote_xml" "$remote_png" >/dev/null 2>&1 || true
}

capture launch_onboarding \
  "$ADB_BIN" -s "$DEVICE_ID" shell am start -W -n "$PACKAGE/.MainActivity"
capture deeplink_onboarding_guard \
  "$ADB_BIN" -s "$DEVICE_ID" shell am start -W -a android.intent.action.VIEW -d "https://collect.ikanisa.com/c/qa-private-group" "$PACKAGE"
put_setting system font_scale 2.0
sleep 1
capture launch_onboarding_200_text \
  "$ADB_BIN" -s "$DEVICE_ID" shell am start -W -n "$PACKAGE/.MainActivity"

restore_settings
trap - EXIT

after_accessibility_enabled="$(setting secure accessibility_enabled)"
after_enabled_services="$(setting secure enabled_accessibility_services)"
after_font_scale="$(setting system font_scale)"
{
  printf 'accessibility_enabled=%s\n' "$after_accessibility_enabled"
  printf 'enabled_accessibility_services=%s\n' "$after_enabled_services"
  printf 'font_scale=%s\n' "$after_font_scale"
} >"$SETTINGS_AFTER"

ANDROID_ACCESSIBILITY_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
ANDROID_ACCESSIBILITY_PACKAGE="$PACKAGE" \
ANDROID_ACCESSIBILITY_DEVICE="$DEVICE_FILE" \
ANDROID_ACCESSIBILITY_SETTINGS_BEFORE="$SETTINGS_BEFORE" \
ANDROID_ACCESSIBILITY_SETTINGS_AFTER="$SETTINGS_AFTER" \
ANDROID_ACCESSIBILITY_EVIDENCE_DIR="$EVIDENCE_DIR" \
ANDROID_ACCESSIBILITY_BEFORE_ENABLED="$before_accessibility_enabled" \
ANDROID_ACCESSIBILITY_BEFORE_SERVICES="$before_enabled_services" \
ANDROID_ACCESSIBILITY_BEFORE_FONT_SCALE="$before_font_scale" \
ANDROID_ACCESSIBILITY_AFTER_ENABLED="$after_accessibility_enabled" \
ANDROID_ACCESSIBILITY_AFTER_SERVICES="$after_enabled_services" \
ANDROID_ACCESSIBILITY_AFTER_FONT_SCALE="$after_font_scale" \
ruby -r json -r rexml/document <<'RUBY' >"$SUMMARY_FILE"
include REXML

root = ENV.fetch("ANDROID_ACCESSIBILITY_EVIDENCE_DIR")
captures = %w[
  launch_onboarding
  deeplink_onboarding_guard
  launch_onboarding_200_text
].map do |name|
  xml_path = File.join(root, "#{name}.xml")
  labels = []
  if File.exist?(xml_path)
    document = Document.new(File.read(xml_path))
    XPath.each(document, "//node") do |node|
      text = node.attributes["text"].to_s.strip
      description = node.attributes["content-desc"].to_s.strip
      label = [description, text].reject(&:empty?).join("\n").strip
      labels << label unless label.empty?
    end
  end
  {
    "name" => name,
    "screenshot" => "#{xml_path.delete_suffix(".xml")}.png",
    "xml" => xml_path,
    "window" => File.join(root, "#{name}_window.txt"),
    "active_package_match" => File.file?(File.join(root, "#{name}_window.txt")) &&
      File.read(File.join(root, "#{name}_window.txt")).include?(ENV.fetch("ANDROID_ACCESSIBILITY_PACKAGE")),
    "node_label_count" => labels.length,
    "sample_labels" => labels.take(10)
  }
end

failures = []
captures.each do |capture|
  min_labels = 5
  failures << "#{capture.fetch("name")} did not keep #{ENV.fetch("ANDROID_ACCESSIBILITY_PACKAGE")} focused for capture." unless capture.fetch("active_package_match")
  failures << "#{capture.fetch("name")} must expose at least #{min_labels} accessibility labels." if capture.fetch("node_label_count") < min_labels
end
failures << "Accessibility enabled setting was not restored." unless ENV.fetch("ANDROID_ACCESSIBILITY_AFTER_ENABLED") == ENV.fetch("ANDROID_ACCESSIBILITY_BEFORE_ENABLED")
failures << "Enabled accessibility services setting was not restored." unless ENV.fetch("ANDROID_ACCESSIBILITY_AFTER_SERVICES") == ENV.fetch("ANDROID_ACCESSIBILITY_BEFORE_SERVICES")
failures << "Font scale setting was not restored." unless ENV.fetch("ANDROID_ACCESSIBILITY_AFTER_FONT_SCALE") == ENV.fetch("ANDROID_ACCESSIBILITY_BEFORE_FONT_SCALE")

summary = {
  "generated_at" => ENV.fetch("ANDROID_ACCESSIBILITY_GENERATED_AT"),
  "status" => failures.empty? ? "pass" : "fail",
  "package" => ENV.fetch("ANDROID_ACCESSIBILITY_PACKAGE"),
  "talkback_service" => "com.google.android.marvin.talkback/.TalkBackService",
  "captures" => captures.map do |capture|
    capture.merge(
      "screenshot" => capture.fetch("screenshot").delete_prefix("#{Dir.pwd}/"),
      "xml" => capture.fetch("xml").delete_prefix("#{Dir.pwd}/"),
      "window" => capture.fetch("window").delete_prefix("#{Dir.pwd}/")
    )
  end,
  "device" => ENV.fetch("ANDROID_ACCESSIBILITY_DEVICE").delete_prefix("#{Dir.pwd}/"),
  "settings_before" => ENV.fetch("ANDROID_ACCESSIBILITY_SETTINGS_BEFORE").delete_prefix("#{Dir.pwd}/"),
  "settings_after" => ENV.fetch("ANDROID_ACCESSIBILITY_SETTINGS_AFTER").delete_prefix("#{Dir.pwd}/"),
  "device_settings_restored" => failures.none? { |failure| failure.include?("restored") },
  "failures" => failures,
  "codex_accessibility_responsibility" => "This structural capture verifies exposed Android accessibility labels with TalkBack enabled as part of Codex-owned structural accessibility responsibility.",
  "secret_handling" => "Captured node labels and screenshots are local evidence and must not include raw SMS bodies, OTPs, phone/MoMo numbers, signing keys, provider tokens, or production customer data."
}

puts JSON.pretty_generate(summary)
exit(failures.empty? ? 0 : 1)
RUBY
rc=$?

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  cat "$SUMMARY_FILE"
else
  status="$(ruby -r json -e 'puts JSON.parse(File.read(ARGV[0])).fetch("status")' "$SUMMARY_FILE")"
  printf '[android-accessibility-structural] status=%s evidence=%s\n' "$status" "${SUMMARY_FILE#$ROOT_DIR/}"
fi

exit "$rc"
