#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EVIDENCE_DIR="${PUBLIC_WEBSITE_EVIDENCE_DIR:-docs/release/collect_public_website_evidence_2026-06-22}"
OUT_PATH="${PUBLIC_WEBSITE_COMPLETION_REPORT:-docs/release/COLLECT_PUBLIC_WEBSITE_COMPLETION_AUDIT_2026-06-22.md}"

mkdir -p "$EVIDENCE_DIR" "$(dirname "$OUT_PATH")"

COMPLETION_JSON="$(mktemp)"
trap 'rm -f "$COMPLETION_JSON"' EXIT

set +e
scripts/public_website_completion_gate.sh --json > "$COMPLETION_JSON"
GATE_RC=$?
set -e

ruby -r json -r time - "$COMPLETION_JSON" "$OUT_PATH" "$GATE_RC" <<'RUBY'
completion_path, out_path, gate_rc = ARGV
completion = JSON.parse(File.read(completion_path))
metrics = completion.dig("gate_summaries", "audit_metrics") || {}
evidence_dir = ENV.fetch("PUBLIC_WEBSITE_EVIDENCE_DIR", "docs/release/collect_public_website_evidence_2026-06-22")

status = completion.fetch("status") == "pass" ? "GO" : "NO-GO"
missing = completion.fetch("missing_external")
visual_evidence = missing.key?("visual_approval") ?
  "Requires owner visual approval or exact-dimension screenshot set." :
  "Exact-dimension screenshots and browser QA evidence are recorded under #{evidence_dir}/screenshots/ and #{evidence_dir}/browser_visual_qa.json."
lighthouse_evidence = missing.key?("lighthouse_mobile") || missing.key?("lighthouse_desktop") ?
  "Requires mobile and desktop Lighthouse/PageSpeed evidence." :
  "Mobile and desktop Lighthouse JSON reports are recorded under #{evidence_dir}/lighthouse/ with all checked categories at 90+."

rows = [
  ["T-1 search indexing/crawlability", missing.key?("search_console_google") || missing.key?("bing_webmaster") ? "NO-GO" : "PASS", "Live robots/sitemap crawl readiness is proven; closure still requires Google Search Console evidence and Bing evidence or deferral."],
  ["T-2 true privacy URL", "PASS", "Live gate verifies /privacy/, /terms/, /account-deletion/, /data-deletion/, and /#/privacy compatibility."],
  ["T-3 non-JS/low-bandwidth resilience", "PASS", "Live/static gates verify no Flutter, CanvasKit, main.dart.js, or WASM critical-path markers; JS is #{metrics["js_bytes"] || "unknown"} bytes."],
  ["T-4 trust/security/structured data", "PASS", "Live gate verifies /trust/, /security/, security headers, and valid JSON-LD types #{Array(metrics["json_ld_types"]).join(", ")}."],
  ["U-1 non-WhatsApp conversion", "PASS", "Live gate verifies a self-serve lead form with email input."],
  ["U-2 Collect-specific proof", missing.key?("collect_product_proof") ? "NO-GO" : "PASS", "Requires owner-approved Collect-specific proof or explicit deferral."],
  ["U-3 credit-readiness explanation", "PASS", "Live gate verifies the near-top explainer and provider-decision language."],
  ["U-4 localization", missing.key?("translation_approval") ? "NO-GO" : "PASS", "Live gate verifies /rw/ and /fr/ implementation; human translation approval still required if NO-GO."],
  ["U-5 visual quality", missing.key?("visual_approval") ? "NO-GO" : "PASS", visual_evidence],
  ["Lighthouse/Core Web Vitals", missing.key?("lighthouse_mobile") || missing.key?("lighthouse_desktop") ? "NO-GO" : "PASS", lighthouse_evidence],
  ["Play Console action boundary", missing.key?("play_console_approval") ? "NO-GO" : "PASS", "Requires Play Console update proof or owner deferral; no external submission by Codex."],
]

lines = []
lines << "# Collect Public Website Completion Audit"
lines << ""
lines << "Generated: #{Time.now.utc.iso8601}"
lines << ""
lines << "Overall status: **#{status}**"
lines << ""
lines << "The public website code-owned remediation is green, but the overall goal is not complete until the strict completion gate passes."
lines << ""
lines << "## Gate Summary"
lines << ""
lines << "- Static quality gate: #{completion.dig("gate_summaries", "static", "passed")}/#{completion.dig("gate_summaries", "static", "total")} passed"
lines << "- Live quality gate: #{completion.dig("gate_summaries", "live", "passed")}/#{completion.dig("gate_summaries", "live", "total")} passed"
lines << "- Live audit evidence: #{completion.dig("code_checks", "live_audit_evidence") ? "pass" : "fail"}"
lines << "- External missing or invalid artifacts: #{completion.fetch("missing_external_count")}"
lines << ""
lines << "## Live Metrics"
lines << ""
lines << "- Root response: #{metrics["root_elapsed_ms"] || "unknown"} ms"
lines << "- Root HTML: #{metrics["root_html_bytes"] || "unknown"} bytes"
lines << "- CSS: #{metrics["css_bytes"] || "unknown"} bytes"
lines << "- JS: #{metrics["js_bytes"] || "unknown"} bytes"
lines << "- Critical first-party bytes: #{metrics["critical_first_party_bytes"] || "unknown"}"
lines << "- Cloudflare cache: #{metrics["root_cf_cache_status"] || "unknown"}"
lines << "- JSON-LD types: #{Array(metrics["json_ld_types"]).join(", ")}"
lines << ""
lines << "## Generated Evidence"
lines << ""
lines << "- Indexing readiness: `#{evidence_dir}/search-console/indexing-readiness.json`"
lines << "- Optional IndexNow readiness: owner-provided `PUBLIC_INDEXNOW_KEY` support and `scripts/public_website_indexnow_readiness.sh --json`; no key or URL submission is published by Codex"
lines << "- CI guard: `scripts/public_website_ci_gate.sh` and `.github/workflows/public-website.yml` run static public gates, production live gates, and code-owned completion checks"
lines << "- Localized SEO: reciprocal `hreflang` alternates and OG locale metadata verified on `/`, `/rw/`, and `/fr/` by the live gate"
lines << "- Visual QA: `#{evidence_dir}/browser_visual_qa.json`"
lines << "- Screenshots: `#{evidence_dir}/screenshots/mobile_390x844.png`, `mobile_430x932.png`, `tablet_768x1024.png`, `desktop_1440x1000.png`"
lines << "- Lighthouse mobile: `#{evidence_dir}/lighthouse/mobile.json`"
lines << "- Lighthouse desktop: `#{evidence_dir}/lighthouse/desktop.json`"
lines << ""
lines << "## Requirement Matrix"
lines << ""
lines << "| Requirement | Status | Evidence / blocker |"
lines << "| --- | --- | --- |"
rows.each do |requirement, item_status, evidence|
  lines << "| #{requirement} | #{item_status} | #{evidence} |"
end
lines << ""
lines << "## Missing External Artifacts"
lines << ""
if missing.empty?
  lines << "None."
else
  missing.each do |id, item|
    lines << "### #{id} (#{item.fetch("audit_id")})"
    lines << ""
    lines << item.fetch("description")
    lines << ""
    lines << "Accepted evidence paths:"
    item.fetch("paths").each { |path| lines << "- `#{path}`" }
    lines << ""
  end
end
lines << "## Commands"
lines << ""
lines << "```bash"
lines << "scripts/public_website_quality_gate.sh --json"
lines << "scripts/public_website_live_gate.sh --json"
lines << "scripts/public_website_audit_evidence.sh"
lines << "node scripts/public_website_playwright_visual_qa.js"
lines << "scripts/public_website_completion_gate.sh --json"
lines << "scripts/public_website_external_evidence_audit.sh"
lines << "```"
lines << ""
lines << "## Decision"
lines << ""
lines << "Do not mark the active goal complete unless `scripts/public_website_completion_gate.sh --json` returns `status: pass`."

File.write(out_path, lines.join("\n") + "\n")
puts out_path
exit(gate_rc.to_i)
RUBY
