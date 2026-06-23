#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EVIDENCE_DIR="${PUBLIC_WEBSITE_EVIDENCE_DIR:-output/public_website_evidence}"
MODE="${1:-}"

mkdir -p "$EVIDENCE_DIR"

STATIC_JSON="$(mktemp)"
LIVE_JSON="$(mktemp)"
AUDIT_JSON="$(mktemp)"
trap 'rm -f "$STATIC_JSON" "$LIVE_JSON" "$AUDIT_JSON"' EXIT

scripts/public_website_quality_gate.sh --json > "$STATIC_JSON"
scripts/public_website_live_gate.sh --json > "$LIVE_JSON"
scripts/public_website_audit_evidence.sh > "$AUDIT_JSON"

ruby -r json -r time - "$STATIC_JSON" "$LIVE_JSON" "$AUDIT_JSON" "$EVIDENCE_DIR" "$MODE" <<'RUBY'
static_path, live_path, audit_path, evidence_dir, mode = ARGV

static = JSON.parse(File.read(static_path))
live = JSON.parse(File.read(live_path))
audit = JSON.parse(File.read(audit_path))

required_external = {
  "search_console_google" => {
    "audit_id" => "T-1",
    "description" => "Google Search Console sitemap submission or URL inspection proof.",
    "paths" => [
      File.join(evidence_dir, "search-console", "google-search-console.json"),
      File.join(evidence_dir, "search-console", "google-search-console.pdf"),
      File.join(evidence_dir, "search-console", "google-search-console.png"),
    ],
  },
  "bing_webmaster" => {
    "audit_id" => "T-1",
    "description" => "Bing Webmaster Tools sitemap submission proof, or owner-approved deferral.",
    "paths" => [
      File.join(evidence_dir, "search-console", "bing-webmaster.json"),
      File.join(evidence_dir, "search-console", "bing-webmaster.pdf"),
      File.join(evidence_dir, "search-console", "bing-webmaster.png"),
      File.join(evidence_dir, "owner-approvals", "bing-deferral.md"),
    ],
  },
  "lighthouse_mobile" => {
    "audit_id" => "Lighthouse",
    "description" => "Mobile Lighthouse/PageSpeed report with green target evidence.",
    "paths" => [
      File.join(evidence_dir, "lighthouse", "mobile.json"),
      File.join(evidence_dir, "lighthouse", "mobile.html"),
      File.join(evidence_dir, "lighthouse", "mobile.pdf"),
    ],
  },
  "lighthouse_desktop" => {
    "audit_id" => "Lighthouse",
    "description" => "Desktop Lighthouse/PageSpeed report with green target evidence.",
    "paths" => [
      File.join(evidence_dir, "lighthouse", "desktop.json"),
      File.join(evidence_dir, "lighthouse", "desktop.html"),
      File.join(evidence_dir, "lighthouse", "desktop.pdf"),
    ],
  },
  "collect_product_proof" => {
    "audit_id" => "U-2",
    "description" => "Owner-approved Collect-specific traction/proof, or explicit deferral.",
    "paths" => [
      File.join(evidence_dir, "owner-approvals", "collect-product-proof.md"),
      File.join(evidence_dir, "owner-approvals", "collect-product-proof-deferral.md"),
    ],
  },
  "visual_approval" => {
    "audit_id" => "U-5",
    "description" => "Final visual approval or complete screenshot set for required viewports.",
    "paths" => [
      File.join(evidence_dir, "owner-approvals", "visual-approval.md"),
      File.join(evidence_dir, "browser_visual_qa.json"),
      File.join(evidence_dir, "screenshots", "mobile_390x844.png"),
      File.join(evidence_dir, "screenshots", "mobile_430x932.png"),
      File.join(evidence_dir, "screenshots", "tablet_768x1024.png"),
      File.join(evidence_dir, "screenshots", "desktop_1440x1000.png"),
    ],
    "all_screenshot_paths" => true,
  },
  "play_console_approval" => {
    "audit_id" => "Play Console",
    "description" => "Play Console privacy URL/listing update evidence, or explicit owner deferral.",
    "paths" => [
      File.join(evidence_dir, "play-console", "privacy-url-update.md"),
      File.join(evidence_dir, "play-console", "privacy-url-update.png"),
      File.join(evidence_dir, "owner-approvals", "play-console-deferral.md"),
    ],
  },
}

def markdown_approval_valid?(path, required_terms)
  return false unless File.file?(path)

  text = File.read(path).downcase
  return false if text.strip.length < 80
  return false if text.include?("pending") || text.include?("todo") || text.include?("tbd")

  base_terms = ["owner", "date"]
  (base_terms + required_terms).all? { |term| text.include?(term) }
end

def binary_artifact_valid?(path)
  File.file?(path) && File.size(path) > 100
end

def lighthouse_json_valid?(path)
  return false unless File.file?(path)

  parsed = JSON.parse(File.read(path))
  categories = parsed.dig("lighthouseResult", "categories") || parsed["categories"]
  return false unless categories.is_a?(Hash)

  {
    "performance" => 0.9,
    "accessibility" => 0.9,
    "best-practices" => 0.9,
    "seo" => 0.9,
  }.all? do |id, threshold|
    score = categories.dig(id, "score")
    score.is_a?(Numeric) && score >= threshold
  end
rescue JSON::ParserError
  false
end

def lighthouse_artifact_valid?(path)
  return lighthouse_json_valid?(path) if path.end_with?(".json")
  binary_artifact_valid?(path)
end

def png_dimensions(path)
  return nil unless File.file?(path)

  File.open(path, "rb") do |file|
    signature = file.read(8)
    return nil unless signature == "\x89PNG\r\n\x1A\n".b

    length = file.read(4).unpack1("N")
    type = file.read(4)
    return nil unless type == "IHDR" && length >= 8

    data = file.read(length)
    [data[0, 4].unpack1("N"), data[4, 4].unpack1("N")]
  end
end

def png_dimension_valid?(path, expected_width, expected_height)
  dimensions = png_dimensions(path)
  dimensions == [expected_width, expected_height]
end

def browser_visual_qa_valid?(path)
  return false unless File.file?(path)

  parsed = JSON.parse(File.read(path))
  return false unless parsed["status"] == "pass"

  results = parsed["results"]
  results.is_a?(Array) &&
    results.length >= 4 &&
    results.all? { |result| Array(result["failures"]).empty? }
rescue JSON::ParserError
  false
end

def search_console_artifact_valid?(path)
  return false unless File.file?(path)
  return true if path.end_with?(".png", ".pdf") && File.size(path) > 100

  parsed = JSON.parse(File.read(path))
  text = JSON.generate(parsed).downcase
  text.include?("collect.ikanisa.com") &&
    (text.include?("sitemap") || text.include?("url inspection") || text.include?("index"))
rescue JSON::ParserError
  false
end

def external_rule_valid?(id, rule)
  paths = rule.fetch("paths")
  case id
  when "search_console_google"
    paths.any? { |path| search_console_artifact_valid?(path) }
  when "bing_webmaster"
    paths.any? do |path|
      path.end_with?("bing-deferral.md") ? markdown_approval_valid?(path, ["bing", "defer"]) : search_console_artifact_valid?(path)
    end
  when "lighthouse_mobile", "lighthouse_desktop"
    paths.any? { |path| lighthouse_artifact_valid?(path) }
  when "collect_product_proof"
    paths.any? do |path|
      if path.end_with?("collect-product-proof-deferral.md")
        markdown_approval_valid?(path, ["collect", "proof", "defer"])
      else
        markdown_approval_valid?(path, ["collect", "proof", "approve"])
      end
    end
  when "visual_approval"
    approval = paths.first
    browser_qa = paths[1]
    screenshot_paths = paths[2..]
    markdown_approval_valid?(approval, ["visual", "approve"]) ||
      (
        browser_visual_qa_valid?(browser_qa) &&
        png_dimension_valid?(screenshot_paths[0], 390, 844) &&
        png_dimension_valid?(screenshot_paths[1], 430, 932) &&
        png_dimension_valid?(screenshot_paths[2], 768, 1024) &&
        png_dimension_valid?(screenshot_paths[3], 1440, 1000)
      )
  when "play_console_approval"
    paths.any? do |path|
      if path.end_with?("play-console-deferral.md")
        markdown_approval_valid?(path, ["play", "console", "defer"])
      elsif path.end_with?(".md")
        markdown_approval_valid?(path, ["play", "console", "approve"])
      else
        binary_artifact_valid?(path)
      end
    end
  else
    false
  end
end

external_checks = required_external.transform_values do |rule|
  id = required_external.key(rule)
  valid = external_rule_valid?(id, rule)
  rule.merge("status" => valid ? "pass" : "missing_or_invalid")
end

code_checks = {
  "static_quality_gate" => static.fetch("status") == "pass",
  "live_quality_gate" => live.fetch("status") == "pass",
  "live_audit_evidence" => audit.fetch("status") == "pass",
}

missing_external = external_checks.select { |_id, item| item.fetch("status") != "pass" }
status = code_checks.values.all? && missing_external.empty? ? "pass" : "fail"

payload = {
  "checked_at_utc" => Time.now.utc.iso8601,
  "status" => status,
  "code_checks" => code_checks,
  "external_checks" => external_checks,
  "missing_external_count" => missing_external.length,
  "missing_external" => missing_external,
  "gate_summaries" => {
    "static" => static["summary"],
    "live" => live["summary"],
    "audit_metrics" => audit["metrics"],
  },
}

File.write(File.join(evidence_dir, "completion_gate.json"), JSON.pretty_generate(payload))

if mode == "--json"
  puts JSON.pretty_generate(payload)
else
  puts "#{status} code=#{code_checks.values.count(true)}/#{code_checks.length} external_missing=#{missing_external.length}"
  missing_external.each do |id, item|
    warn "MISSING #{id} (#{item.fetch("audit_id")}): #{item.fetch("description")}"
    warn "  accepted paths: #{item.fetch("paths").join(", ")}"
  end
end

exit(status == "pass" ? 0 : 1)
RUBY
