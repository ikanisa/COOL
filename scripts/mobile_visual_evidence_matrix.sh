#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER="${FLUTTER:-/Volumes/PRO-G40/flutter_3_44/bin/flutter}"
EVIDENCE_DIR="${MOBILE_VISUAL_MATRIX_DIR:-$ROOT_DIR/.cache/mobile_visual_evidence_matrix/$(date -u +%Y%m%dT%H%M%SZ)}"
ROUTES="${MOBILE_VISUAL_MATRIX_ROUTES:-home,groups,group-detail,contribution,payment-intent,payment-pending,ledger,settings,notifications,auth}"
DEVICE_PIXEL_RATIO="${MOBILE_VISUAL_MATRIX_DEVICE_PIXEL_RATIO:-1}"

matrix_specs=(
  "compact_dark|360x780|dark|1.0"
  "baseline_dark|390x844|dark|1.0"
  "large_dark|430x932|dark|1.0"
  "baseline_light|390x844|light|1.0"
  "baseline_dark_200_text|390x844|dark|2.0"
)

mkdir -p "$EVIDENCE_DIR"

run_spec() {
  local name="$1"
  local viewport="$2"
  local theme="$3"
  local text_scale="$4"
  local out_dir="$EVIDENCE_DIR/$name"
  mkdir -p "$out_dir"

  printf '[mobile-visual-matrix] %s viewport=%s theme=%s text_scale=%s routes=%s\n' \
    "$name" "$viewport" "$theme" "$text_scale" "$ROUTES"

  COLLECT_VISUAL_EVIDENCE_DIR="$out_dir" \
  COLLECT_VISUAL_MOBILE_VIEWPORT="$viewport" \
  COLLECT_VISUAL_THEME_MODE="$theme" \
  COLLECT_VISUAL_TEXT_SCALE="$text_scale" \
  COLLECT_VISUAL_DEVICE_PIXEL_RATIO="$DEVICE_PIXEL_RATIO" \
  COLLECT_VISUAL_EVIDENCE_ROUTES="$ROUTES" \
  COLLECT_VISUAL_CAPTURE_ADMIN=0 \
  "$FLUTTER" test --no-pub test/visual_evidence_capture_test.dart \
    >"$out_dir/flutter_test.log" 2>&1
}

for spec in "${matrix_specs[@]}"; do
  IFS='|' read -r name viewport theme text_scale <<<"$spec"
  run_spec "$name" "$viewport" "$theme" "$text_scale"
done

MOBILE_VISUAL_MATRIX_ROUTES="$ROUTES" ruby -r json -r time -e '
  evidence_dir = ARGV.fetch(0)
  specs = ARGV.drop(1)
  entries = specs.map do |spec|
    name, viewport, theme, text_scale = spec.split("|", 4)
    summary_path = File.join(evidence_dir, name, "mobile", "summary.json")
    summary = File.file?(summary_path) ? JSON.parse(File.read(summary_path)) : {}
    {
      "name" => name,
      "viewport" => viewport,
      "theme_mode" => theme,
      "text_scale" => text_scale.to_f,
      "status" => summary.fetch("status", "missing"),
      "route_count" => summary.fetch("route_count", 0),
      "summary" => summary_path.delete_prefix("#{Dir.pwd}/")
    }
  end
  required = {
    "compact_phone" => entries.any? { |item| item["viewport"] == "360x780" && item["status"] == "pass" },
    "baseline_phone" => entries.any? { |item| item["viewport"] == "390x844" && item["status"] == "pass" },
    "large_phone" => entries.any? { |item| item["viewport"] == "430x932" && item["status"] == "pass" },
    "light_mode" => entries.any? { |item| item["theme_mode"] == "light" && item["status"] == "pass" },
    "dark_mode" => entries.any? { |item| item["theme_mode"] == "dark" && item["status"] == "pass" },
    "large_text_200" => entries.any? { |item| item["text_scale"] >= 2.0 && item["status"] == "pass" }
  }
  aggregate_status = entries.all? { |item| item["status"] == "pass" } && required.values.all? ? "pass" : "fail"
  output = {
    "generated_at" => Time.now.utc.iso8601,
    "status" => aggregate_status,
    "routes" => ENV.fetch("MOBILE_VISUAL_MATRIX_ROUTES", ""),
    "checks" => required,
    "entries" => entries,
    "privacy" => "Synthetic fixture screenshots; do not include raw SMS, OTPs, PINs, signing secrets, or production customer data."
  }
  File.write(File.join(evidence_dir, "summary.json"), JSON.pretty_generate(output) + "\n")
  exit(aggregate_status == "pass" ? 0 : 1)
' "$EVIDENCE_DIR" "${matrix_specs[@]}"

printf '[mobile-visual-matrix] pass evidence=%s\n' "$EVIDENCE_DIR"
