#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_ROOT="${APP_STORE_IOS_SCREENSHOT_OUTPUT_ROOT:-$ROOT_DIR/output/app_store/ios_screenshots}"
EVIDENCE_ROOT="${APP_STORE_IOS_SCREENSHOT_EVIDENCE_ROOT:-$ROOT_DIR/.cache/app_store_ios_screenshots_current_$TIMESTAMP}"
PHONE_EVIDENCE_DIR="$EVIDENCE_ROOT/phone_raw"
IPAD_EVIDENCE_DIR="$EVIDENCE_ROOT/ipad_raw"

PHONE_SOURCE_DIR="$OUTPUT_ROOT/source/iphone65"
IPAD_SOURCE_DIR="$OUTPUT_ROOT/source/ipadPro129"
PHONE_FINAL_DIR="$OUTPUT_ROOT/final/iphone65"
IPAD_FINAL_DIR="$OUTPUT_ROOT/final/ipadPro129"

routes=(
  "01-home|home"
  "02-contribute|contribution"
  "03-bank-details|settings-bank-transfer"
  "04-ledger|ledger"
  "05-share|share"
)

fail() {
  printf '[app-store-ios-screenshots][FAIL] %s\n' "$*" >&2
  exit 1
}

run_capture() {
  local viewport="$1"
  local evidence_dir="$2"

  MOBILE_ROUTE_RENDER_EVIDENCE_DIR="$evidence_dir" \
    MOBILE_ROUTE_RENDER_ROUTE_FILTER="home,contribution,settings-bank-transfer,ledger,share" \
    MOBILE_ROUTE_RENDER_VIEWPORT="$viewport" \
    MOBILE_ROUTE_RENDER_BUILD_ARGS="--release --no-wasm-dry-run --no-pub -t tool/main_store_preview.dart --dart-define=COLLECT_MOBILE_EVIDENCE_PLATFORM=ios" \
    "$ROOT_DIR/scripts/mobile_route_render_smoke.sh"
}

stage_device_set() {
  local raw_dir="$1"
  local source_dir="$2"
  local final_dir="$3"
  local source_suffix="$4"
  local final_height="$5"

  rm -rf "$source_dir" "$final_dir"
  mkdir -p "$source_dir" "$final_dir"

  for spec in "${routes[@]}"; do
    IFS='|' read -r slot route_name <<<"$spec"
    local raw_png="$raw_dir/$route_name-$source_suffix.png"
    local source_png="$source_dir/$slot.png"
    local final_png="$final_dir/$slot.png"

    [[ -s "$raw_png" ]] || fail "Missing current route screenshot: $raw_png"
    cp "$raw_png" "$source_png"
    sips --resampleHeight "$final_height" "$source_png" --out "$final_png" >/dev/null
    [[ -s "$final_png" ]] || fail "Failed to write final screenshot: $final_png"
  done
}

validate_dimensions() {
  local expected_width="$1"
  local expected_height="$2"
  shift 2

  for png in "$@"; do
    local width height
    width="$(sips -g pixelWidth "$png" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$png" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    [[ "$width" == "$expected_width" && "$height" == "$expected_height" ]] || \
      fail "Unexpected dimensions for $png: ${width}x${height}, expected ${expected_width}x${expected_height}"
  done
}

run_capture "414x896" "$PHONE_EVIDENCE_DIR"
run_capture "1024x1366" "$IPAD_EVIDENCE_DIR"

stage_device_set "$PHONE_EVIDENCE_DIR" "$PHONE_SOURCE_DIR" "$PHONE_FINAL_DIR" "414x896" "2688"
stage_device_set "$IPAD_EVIDENCE_DIR" "$IPAD_SOURCE_DIR" "$IPAD_FINAL_DIR" "1024x1366" "2732"

phone_final=()
while IFS= read -r path; do
  phone_final+=("$path")
done < <(find "$PHONE_FINAL_DIR" -maxdepth 1 -type f -name '*.png' | sort)

ipad_final=()
while IFS= read -r path; do
  ipad_final+=("$path")
done < <(find "$IPAD_FINAL_DIR" -maxdepth 1 -type f -name '*.png' | sort)

[[ "${#phone_final[@]}" -eq 5 ]] || fail "Expected 5 iPhone screenshots, found ${#phone_final[@]}"
[[ "${#ipad_final[@]}" -eq 5 ]] || fail "Expected 5 iPad screenshots, found ${#ipad_final[@]}"

validate_dimensions "1242" "2688" "${phone_final[@]}"
validate_dimensions "2048" "2732" "${ipad_final[@]}"

ruby -r json -r time -e '
  root, output_root, evidence_root, phone_dir, ipad_dir = ARGV
  def rel(root, path)
    path.sub(%r{\A#{Regexp.escape(root)}/?}, "")
  end
  manifest = {
    "status" => "pass",
    "generated_at" => Time.now.utc.iso8601,
    "source" => "Current Flutter iOS-platform synthetic store preview",
    "capture_boundary" => "Store artwork generated from the dedicated tool/main_store_preview.dart target with deterministic synthetic data and iOS-only product controls enabled. The target is not referenced by any production build wrapper, Xcode configuration, or application entry point; this is not physical-device or native-runtime evidence.",
    "apple_rejection" => {
      "submission_id" => "e6cd1894-6497-4a83-acec-c59ef3bb584a",
      "guideline" => "2.3.3",
      "review_date" => "2026-07-02",
      "version_reviewed" => "1.2.2 (9)",
      "fix" => "Replace stale/padded screenshot slots with current app-in-use iPhone 6.5-inch and 13-inch iPad screenshots."
    },
    "routes" => [
      { "slot" => "01-home", "route" => "/home", "purpose" => "collections overview and featured groups" },
      { "slot" => "02-contribute", "route" => "/groups/col-church/contribute", "purpose" => "bank-transfer request, approved beneficiary, and external banking handoff" },
      { "slot" => "03-bank-details", "route" => "/settings/bank-transfer", "purpose" => "approved beneficiary and reusable bank details" },
      { "slot" => "04-ledger", "route" => "/groups/col-church/ledger", "purpose" => "collection ledger and transactions" },
      { "slot" => "05-share", "route" => "/groups/col-church/share", "purpose" => "shareable collection QR and link" }
    ],
    "devices" => {
      "iphone_6_5" => {
        "dimensions" => "1242x2688",
        "screenshots" => Dir[File.join(phone_dir, "*.png")].sort.map { |path| rel(root, path) }
      },
      "ipad_13" => {
        "dimensions" => "2048x2732",
        "screenshots" => Dir[File.join(ipad_dir, "*.png")].sort.map { |path| rel(root, path) }
      }
    },
    "evidence" => {
      "root" => rel(root, evidence_root),
      "phone_raw_summary" => rel(root, File.join(evidence_root, "phone_raw", "summary.json")),
      "ipad_raw_summary" => rel(root, File.join(evidence_root, "ipad_raw", "summary.json"))
    },
    "secret_handling" => "Screenshots use fixture/evidence-mode data only; do not include production OTPs, raw SMS bodies, service keys, signing keys, or private receiver data."
  }
  File.write(File.join(output_root, "manifest.json"), JSON.pretty_generate(manifest) + "\n")
' "$ROOT_DIR" "$OUTPUT_ROOT" "$EVIDENCE_ROOT" "$PHONE_FINAL_DIR" "$IPAD_FINAL_DIR"

printf '[app-store-ios-screenshots] pass output=%s evidence=%s\n' "$OUTPUT_ROOT" "$EVIDENCE_ROOT"
