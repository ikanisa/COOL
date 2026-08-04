#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

resolve_adb() {
  local candidate
  for candidate in \
    "${ADB:-}" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'adb\n'
}

ADB_BIN="$(resolve_adb)"
DEVICE_ID="${ANDROID_ACCESSIBILITY_DEVICE_ID:-}"
ALLOW_PHYSICAL="${ANDROID_ACCESSIBILITY_ALLOW_PHYSICAL:-false}"
PACKAGE="${ANDROID_ACCESSIBILITY_PACKAGE:-app.cool.mobile.dev}"
ACTIVITY="${ANDROID_ACCESSIBILITY_ACTIVITY:-app.cool.mobile.MainActivity}"
MIN_TARGET_DP="${ANDROID_ACCESSIBILITY_MIN_TARGET_DP:-44}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
EVIDENCE_DIR="${ANDROID_ACCESSIBILITY_EVIDENCE_DIR:-$ROOT_DIR/.cache/android_native_accessibility_measurement/$timestamp}"
SCREENSHOT_DIR="$EVIDENCE_DIR/screenshots"
UI_DIR="$EVIDENCE_DIR/ui"
REPORT_DIR="$EVIDENCE_DIR/reports"
LOG_FILE="$EVIDENCE_DIR/android_native_accessibility_measurement.txt"
SUMMARY_FILE="$EVIDENCE_DIR/summary.json"

fail() {
  printf '[android-native-accessibility][FAIL] %s\n' "$*" >&2
  exit 1
}

if [[ -z "$DEVICE_ID" ]]; then
  fail "ANDROID_ACCESSIBILITY_DEVICE_ID is required."
fi
if [[ "$DEVICE_ID" != emulator-* && "$ALLOW_PHYSICAL" != "true" ]]; then
  fail "Physical-device interaction is disabled. Use a controlled emulator or explicitly opt in."
fi
if ! "$ADB_BIN" devices | awk \
  'NR > 1 && $1 == id && $2 == "device" { found = 1 } END { exit(found ? 0 : 1) }' \
  id="$DEVICE_ID"; then
  fail "Android target $DEVICE_ID is not connected and authorized."
fi
if ! "$ADB_BIN" -s "$DEVICE_ID" shell pm path "$PACKAGE" | grep -q '^package:'; then
  fail "Package $PACKAGE is not installed on $DEVICE_ID."
fi
if [[ "$PACKAGE" != *.dev ]]; then
  fail "The default harness is fixture-only and refuses a non-dev package."
fi
if ! [[ "$MIN_TARGET_DP" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  fail "ANDROID_ACCESSIBILITY_MIN_TARGET_DP must be numeric."
fi

mkdir -p "$SCREENSHOT_DIR" "$UI_DIR" "$REPORT_DIR"
: >"$LOG_FILE"

record() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

dump_remote_to_local() {
  local remote="$1"
  local local_path="$2"
  local attempt
  "$ADB_BIN" -s "$DEVICE_ID" shell rm -f "$remote" >/dev/null 2>&1 || true
  for attempt in 1 2 3; do
    if "$ADB_BIN" -s "$DEVICE_ID" shell timeout 15 \
      uiautomator dump --compressed "$remote" >>"$LOG_FILE" 2>&1; then
      if "$ADB_BIN" -s "$DEVICE_ID" exec-out cat "$remote" >"$local_path" &&
        [[ -s "$local_path" ]]; then
        "$ADB_BIN" -s "$DEVICE_ID" shell rm -f "$remote" >/dev/null 2>&1 || true
        return 0
      fi
    fi
    record "uiautomator_retry remote=$remote attempt=$attempt"
    "$ADB_BIN" -s "$DEVICE_ID" shell rm -f "$remote" >/dev/null 2>&1 || true
    sleep 1
  done
  return 1
}

screen_size="$("$ADB_BIN" -s "$DEVICE_ID" shell wm size | tr -d '\r')"
physical_width="$(printf '%s\n' "$screen_size" | sed -n 's/^Physical size: \([0-9][0-9]*\)x[0-9][0-9]*$/\1/p' | tail -1)"
physical_height="$(printf '%s\n' "$screen_size" | sed -n 's/^Physical size: [0-9][0-9]*x\([0-9][0-9]*\)$/\1/p' | tail -1)"
screen_width="$(printf '%s\n' "$screen_size" | sed -n 's/^Override size: \([0-9][0-9]*\)x[0-9][0-9]*$/\1/p' | tail -1)"
screen_height="$(printf '%s\n' "$screen_size" | sed -n 's/^Override size: [0-9][0-9]*x\([0-9][0-9]*\)$/\1/p' | tail -1)"
if [[ -z "$screen_width" || -z "$screen_height" ]]; then
  screen_width="$physical_width"
  screen_height="$physical_height"
fi
[[ -n "$screen_width" && -n "$screen_height" &&
  -n "$physical_width" && -n "$physical_height" ]] ||
  fail "Could not resolve the Android display size."

density_output="$("$ADB_BIN" -s "$DEVICE_ID" shell wm density | tr -d '\r')"
density_dpi="$(printf '%s\n' "$density_output" | sed -n 's/^Override density: \([0-9][0-9]*\)$/\1/p' | tail -1)"
if [[ -z "$density_dpi" ]]; then
  density_dpi="$(printf '%s\n' "$density_output" | sed -n 's/^Physical density: \([0-9][0-9]*\)$/\1/p' | tail -1)"
fi
[[ -n "$density_dpi" ]] || fail "Could not resolve Android display density."

dump_ui() {
  local name="$1"
  local remote="/data/local/tmp/collect-accessibility-$name.xml"
  dump_remote_to_local "$remote" "$UI_DIR/$name.xml" ||
    fail "Could not capture a fresh accessibility tree for $name."
  [[ -s "$UI_DIR/$name.xml" ]] || fail "Accessibility tree $name is empty."
}

capture() {
  local name="$1"
  dump_ui "$name"
  "$ADB_BIN" -s "$DEVICE_ID" exec-out screencap -p >"$SCREENSHOT_DIR/$name.png"
  [[ -s "$SCREENSHOT_DIR/$name.png" ]] || fail "Screenshot $name is empty."
}

tap_named() {
  local expected="$1"
  local occurrence="${2:-1}"
  local scratch="$EVIDENCE_DIR/current.xml"
  local remote="/data/local/tmp/collect-accessibility-current.xml"
  dump_remote_to_local "$remote" "$scratch" ||
    fail "Could not capture a fresh accessibility tree before selecting '$expected'."
  local coordinates
  coordinates="$(
    XML_PATH="$scratch" EXPECTED="$expected" OCCURRENCE="$occurrence" PACKAGE="$PACKAGE" ruby <<'RUBY'
require "rexml/document"

document = REXML::Document.new(File.read(ENV.fetch("XML_PATH")))
expected = ENV.fetch("EXPECTED")
occurrence = Integer(ENV.fetch("OCCURRENCE"))
package = ENV.fetch("PACKAGE")
matches = []
REXML::XPath.each(document, "//node") do |node|
  next unless node.attributes["package"] == package
  values = [
    node.attributes["content-desc"],
    node.attributes["text"],
    node.attributes["hint"]
  ].compact
  next unless values.include?(expected)
  next unless node.attributes["enabled"] == "true"
  control_class = node.attributes["class"].to_s
  actionable =
    node.attributes["clickable"] == "true" ||
    node.attributes["long-clickable"] == "true" ||
    (
      node.attributes["focusable"] == "true" &&
      [
        "android.widget.Button",
        "android.widget.CheckBox",
        "android.widget.EditText",
        "android.widget.ImageButton",
        "android.widget.RadioButton",
        "android.widget.Spinner",
        "android.widget.Switch",
        "android.widget.ToggleButton"
      ].include?(control_class)
    )
  next unless actionable
  bounds = node.attributes["bounds"].to_s.scan(/\d+/).map(&:to_i)
  next unless bounds.length == 4
  matches << [((bounds[0] + bounds[2]) / 2.0).round,
              ((bounds[1] + bounds[3]) / 2.0).round]
end
target = matches.fetch(occurrence - 1)
puts target.join(" ")
RUBY
  )" || fail "Could not find clickable enabled control named '$expected' occurrence $occurrence."
  local x y
  read -r x y <<<"$coordinates"
  local touch_x touch_y
  touch_x=$((x * physical_width / screen_width))
  touch_y=$((y * physical_height / screen_height))
  "$ADB_BIN" -s "$DEVICE_ID" shell input tap "$touch_x" "$touch_y"
  sleep 1
}

launch_app() {
  "$ADB_BIN" -s "$DEVICE_ID" shell am force-stop "$PACKAGE"
  "$ADB_BIN" -s "$DEVICE_ID" shell am start -W \
    -n "$PACKAGE/$ACTIVITY" >>"$LOG_FILE"
  sleep 2
}

record "device_id=$DEVICE_ID"
record "package=$PACKAGE"
record "activity=$ACTIVITY"
record "display=${screen_width}x${screen_height}"
record "physical_touch_display=${physical_width}x${physical_height}"
record "density_dpi=$density_dpi"
record "minimum_target_dp=$MIN_TARGET_DP"
record "scope=controlled Android target; installed dev fixture; no production mutation"

launch_app
tap_named "Home"
capture "01-home"

tap_named "Groups"
capture "02-groups"
tap_named "St Michel building fund, RWF 35,000, 2 members"
capture "03-group-detail"

# Group detail has both an in-flow contribution action and the persistent
# navigation destination. Use the latter so the group-selection state is
# measured independently before entering the amount flow.
tap_named "Contribute" 2
capture "04-contribute-group-selection"
tap_named "St Michel building fund, RWF 35,000, 2 members"
capture "05-contribution-amount"

launch_app
tap_named "Activity"
capture "06-activity"

tap_named "Profile"
capture "07-profile"
"$ADB_BIN" -s "$DEVICE_ID" shell input swipe \
  $((physical_width / 2)) $((physical_height * 72 / 100)) \
  $((physical_width / 2)) $((physical_height * 42 / 100)) 450
sleep 1
capture "07b-profile-scrolled"

launch_app
tap_named "Settings"
capture "08-settings"

PACKAGE="$PACKAGE" \
DENSITY_DPI="$density_dpi" \
MIN_TARGET_DP="$MIN_TARGET_DP" \
UI_DIR="$UI_DIR" \
REPORT_DIR="$REPORT_DIR" \
SUMMARY_FILE="$SUMMARY_FILE" \
EVIDENCE_DIR="$EVIDENCE_DIR" \
DEVICE_ID="$DEVICE_ID" \
ruby <<'RUBY'
require "digest"
require "json"
require "rexml/document"
require "time"

package = ENV.fetch("PACKAGE")
density_dpi = Float(ENV.fetch("DENSITY_DPI"))
density_scale = density_dpi / 160.0
minimum_dp = Float(ENV.fetch("MIN_TARGET_DP"))
ui_dir = ENV.fetch("UI_DIR")
report_dir = ENV.fetch("REPORT_DIR")
evidence_dir = ENV.fetch("EVIDENCE_DIR")

screen_reports = Dir[File.join(ui_dir, "*.xml")].sort.map do |path|
  document = REXML::Document.new(File.read(path))
  primary_navigation_top = nil
  scroll_view_top = nil
  scroll_view_bottom = nil
  REXML::XPath.each(document, "//node") do |node|
    next unless node.attributes["content-desc"] == "Primary navigation"
    bounds = node.attributes["bounds"].to_s.scan(/\d+/).map(&:to_i)
    primary_navigation_top = bounds[1] if bounds.length == 4
    break
  end
  REXML::XPath.each(document, "//node") do |node|
    next unless node.attributes["class"] == "android.widget.ScrollView"
    bounds = node.attributes["bounds"].to_s.scan(/\d+/).map(&:to_i)
    next unless bounds.length == 4
    scroll_view_top = bounds[1]
    scroll_view_bottom = bounds[3]
    break
  end
  targets = []
  REXML::XPath.each(document, "//node") do |node|
    next unless node.attributes["package"] == package
    next unless node.attributes["enabled"] == "true"
    control_class = node.attributes["class"].to_s
    actionable =
      node.attributes["clickable"] == "true" ||
      node.attributes["long-clickable"] == "true" ||
      (
        node.attributes["focusable"] == "true" &&
        [
          "android.widget.Button",
          "android.widget.CheckBox",
          "android.widget.EditText",
          "android.widget.ImageButton",
          "android.widget.RadioButton",
          "android.widget.Spinner",
          "android.widget.Switch",
          "android.widget.ToggleButton"
        ].include?(control_class)
      )
    next unless actionable

    bounds = node.attributes["bounds"].to_s.scan(/\d+/).map(&:to_i)
    next unless bounds.length == 4
    width_px = bounds[2] - bounds[0]
    height_px = bounds[3] - bounds[1]
    label = [
      node.attributes["content-desc"],
      node.attributes["text"],
      node.attributes["hint"]
    ].compact.map(&:strip).find { |value| !value.empty? }.to_s
    target = {
      "class" => control_class,
      "label" => label,
      "bounds" => node.attributes["bounds"],
      "width_px" => width_px,
      "height_px" => height_px,
      "width_dp" => (width_px / density_scale).round(2),
      "height_dp" => (height_px / density_scale).round(2),
      "focusable" => node.attributes["focusable"] == "true",
      "clickable" => node.attributes["clickable"] == "true",
      "long_clickable" => node.attributes["long-clickable"] == "true"
    }
    target["has_accessible_name"] = !label.empty?
    target["meets_minimum_target"] =
      target["width_dp"] >= minimum_dp &&
      target["height_dp"] >= minimum_dp
    target["viewport_clipped_candidate"] =
      !target["meets_minimum_target"] &&
      (
        (!scroll_view_top.nil? && (bounds[1] - scroll_view_top).abs <= 12) ||
        (!scroll_view_bottom.nil? && (bounds[3] - scroll_view_bottom).abs <= 12) ||
        (!primary_navigation_top.nil? && (bounds[3] - primary_navigation_top).abs <= 12)
      )
    targets << target
  end

  {
    "screen" => File.basename(path, ".xml"),
    "actionable_target_count" => targets.length,
    "primary_navigation_top_px" => primary_navigation_top,
    "scroll_view_top_px" => scroll_view_top,
    "scroll_view_bottom_px" => scroll_view_bottom,
    "targets" => targets
  }
end

full_size_labels = screen_reports
  .flat_map { |report| report.fetch("targets") }
  .select { |item| item.fetch("meets_minimum_target") }
  .map { |item| item.fetch("label") }
  .reject(&:empty?)
  .to_h { |label| [label, true] }

screen_reports.each do |report|
  report.fetch("targets").each do |target|
    target["full_size_match_in_matrix"] =
      target.fetch("viewport_clipped_candidate") &&
      full_size_labels.key?(target.fetch("label"))
    target["accepted_viewport_clip"] =
      target.fetch("viewport_clipped_candidate") &&
      target.fetch("full_size_match_in_matrix")
    target["passes"] =
      target.fetch("has_accessible_name") &&
      (
        target.fetch("meets_minimum_target") ||
        target.fetch("accepted_viewport_clip")
      ) &&
      target.fetch("focusable")
  end
  targets = report.fetch("targets")
  report["unnamed_target_count"] =
    targets.count { |item| !item.fetch("has_accessible_name") }
  report["undersized_target_count"] =
    targets.count do |item|
      !item.fetch("meets_minimum_target") &&
        !item.fetch("accepted_viewport_clip")
    end
  report["viewport_clipped_candidate_count"] =
    targets.count { |item| item.fetch("accepted_viewport_clip") }
  report["non_focusable_target_count"] =
    targets.count { |item| !item.fetch("focusable") }
  report["status"] = targets.all? { |item| item.fetch("passes") } ? "pass" : "fail"
  File.write(
    File.join(report_dir, "#{report.fetch("screen")}.json"),
    JSON.pretty_generate(report) + "\n"
  )
end

files = Dir[File.join(evidence_dir, "**", "*")].select { |path| File.file?(path) }
  .reject { |path| path.end_with?("summary.json") }
hashes = files.sort.to_h do |path|
  [path.delete_prefix("#{evidence_dir}/"), Digest::SHA256.file(path).hexdigest]
end

summary = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => screen_reports.all? { |item| item["status"] == "pass" } ? "pass" : "fail",
  "scope" => "rendered Android UIAutomator nodes on a controlled dev fixture; this is target/name/focusability measurement, not TalkBack speech or continuous traversal proof",
  "device_id" => ENV.fetch("DEVICE_ID"),
  "package" => package,
  "density_dpi" => density_dpi.to_i,
  "density_scale" => density_scale,
  "minimum_target_dp" => minimum_dp,
  "screen_count" => screen_reports.length,
  "actionable_target_count" => screen_reports.sum { |item| item["actionable_target_count"] },
  "unnamed_target_count" => screen_reports.sum { |item| item["unnamed_target_count"] },
  "undersized_target_count" => screen_reports.sum { |item| item["undersized_target_count"] },
  "accepted_viewport_clip_count" =>
    screen_reports.sum { |item| item["viewport_clipped_candidate_count"] },
  "non_focusable_target_count" => screen_reports.sum { |item| item["non_focusable_target_count"] },
  "screens" => screen_reports.map { |item| item.reject { |key, _| key == "targets" } },
  "limitations" => [
    "Injected input selects routes but is not accepted as genuine TalkBack gesture traversal.",
    "The harness does not capture spoken output or physical-device assistive-technology behavior.",
    "The 44 dp floor is a rendered native measurement; stricter product-owned 48 dp primary-control contracts remain enforced separately."
  ],
  "artifact_sha256" => hashes
}
File.write(ENV.fetch("SUMMARY_FILE"), JSON.pretty_generate(summary) + "\n")
exit(summary.fetch("status") == "pass" ? 0 : 1)
RUBY

record "summary=$SUMMARY_FILE"
record "result=pass"
printf '%s\n' "$EVIDENCE_DIR"
