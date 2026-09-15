#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EVIDENCE_DIR="${PUBLIC_WEBSITE_EVIDENCE_DIR:-output/public_website_evidence}"
OUT_PATH="${PUBLIC_WEBSITE_COMPLETION_REPORT:-.cache/public_website_completion_report/REPORT.md}"

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
evidence_dir = ENV.fetch("PUBLIC_WEBSITE_EVIDENCE_DIR", "output/public_website_evidence")

code_green = %w[static_quality_gate live_quality_gate live_audit_evidence].all? { |id| completion.dig("code_checks", id) == true }
external = completion.fetch("external_checks", {})
external_passed = ->(id) { external[id].is_a?(Hash) && external.dig(id, "status") == "pass" }
required_external = %w[search_console_google bing_webmaster lighthouse_mobile lighthouse_desktop visual_approval play_console_approval]
unverified_external = required_external.reject { |id| external_passed.call(id) }
missing = completion.fetch("missing_external", {})
status = completion.fetch("status") == "pass" && code_green && unverified_external.empty? ? "GO" : "NO-GO"
code_status = code_green ? "PASS" : "UNVERIFIED"
code_evidence = code_green ? "The recorded combined static/live/audit checks pass." : "Combined code checks failed or are missing; this requirement is not independently verified."
visual_passed = external_passed.call("visual_approval")
indexing_passed = %w[search_console_google bing_webmaster].all? { |id| external_passed.call(id) }
lighthouse_passed = %w[lighthouse_mobile lighthouse_desktop].all? { |id| external_passed.call(id) }
play_passed = external_passed.call("play_console_approval")
route_evidence = visual_passed ?
  "The gate accepted the supplied browser evidence or visual approval artifact. Full independent and owner acceptance remain separate." :
  "Current browser visual evidence or the required approval artifact is missing or invalid."
lighthouse_evidence = lighthouse_passed ?
  "Mobile and desktop Lighthouse JSON reports are recorded under #{evidence_dir}/lighthouse/ with all four checked categories at 90+." :
  "A required mobile or desktop Lighthouse/PageSpeed report is missing, invalid or below budget; inspect the gate's per-report validation issues."

rows = [
  ["T-1 search indexing/crawlability", indexing_passed ? "PASS" : "NO-GO", indexing_passed ? "The gate accepted indexing evidence or a permitted deferral; consult those artifacts for the exact provider status." : "Search Console and Bing evidence or a permitted deferral are incomplete. Crawl readiness and actual indexing are separate checks."],
  ["T-2 true privacy URL", code_status, "#{code_evidence} Inspect privacy content, destination checks and /#/privacy compatibility; publication status is not inferred from a failed check."],
  ["T-3 non-JS/low-bandwidth resilience", code_green ? "PASS" : "UNVERIFIED", "Live/static checks inspect non-Flutter critical-path markers; their combined result is #{code_green ? 'pass' : 'not verified'}. JS is #{metrics["js_bytes"] || "unknown"} bytes. Actual slow/failed-media tasks require separate runtime evidence."],
  ["T-4 trust/security/structured data", code_green ? "PASS" : "UNVERIFIED", "Combined quality checks are #{code_green ? 'passing' : 'not verified'}; observed JSON-LD types: #{Array(metrics["json_ld_types"]).join(", ")}."],
  ["U-1 public app and WhatsApp support", code_status, "#{code_evidence} CTA markup checks do not establish store availability or a completed support conversation."],
  ["U-2 Collect-specific proof", code_status, "#{code_evidence} Content-baseline checks do not establish a concluded partnership."],
  ["U-3 credit-readiness explanation", code_green ? "PASS" : "UNVERIFIED", "Live gate inspects the near-top explainer and provider-decision language; combined quality result is #{code_green ? 'pass' : 'not verified'}."],
  ["U-4 language product decision", code_status, "#{code_evidence} Review language metadata and route results for the declared product language decision."],
  ["U-5 visual quality", visual_passed ? "PASS" : "NO-GO", route_evidence],
  ["Lighthouse lab reports", lighthouse_passed ? "PASS" : "NO-GO", lighthouse_evidence],
  ["Field Core Web Vitals", "UNVERIFIED", "Field Core Web Vitals remain unverified by this gate; Lighthouse lab scores do not establish real-user LCP, INP or CLS percentiles."],
  ["Play Console action boundary", play_passed ? "PASS" : "NO-GO", play_passed ? "The gate accepted a Play Console artifact or permitted deferral under #{evidence_dir}/play-console/; this result does not itself establish publication." : "Play Console evidence or explicit release-owner deferral is missing or invalid. This report does not authorize a store action."],
]

lines = []
lines << "# Collect Public Website Completion Report"
lines << ""
lines << "Generated: #{Time.now.utc.iso8601}"
lines << ""
lines << "Overall status: **#{status}**"
lines << ""
lines << (code_green ? "The recorded code checks pass; external and full-system acceptance remain separate." : "One or more code checks failed. Code-owned remediation is not yet verified.")
lines << ""
lines << "## Gate Summary"
lines << ""
lines << "- Static quality gate: #{completion.dig("gate_summaries", "static", "passed")}/#{completion.dig("gate_summaries", "static", "total")} passed"
lines << "- Live quality gate: #{completion.dig("gate_summaries", "live", "passed")}/#{completion.dig("gate_summaries", "live", "total")} passed"
lines << "- Live audit evidence: #{completion.dig("code_checks", "live_audit_evidence") ? "pass" : "fail"}"
lines << "- External missing or invalid artifacts: #{unverified_external.length}"
lines << ""
lines << "## Live Metrics"
lines << ""
lines << "- Root response: #{metrics["root_elapsed_ms"] || "unknown"} ms"
lines << "- Root HTML: #{metrics["root_html_bytes"] || "unknown"} bytes"
lines << "- CSS: #{metrics["css_bytes"] || "unknown"} bytes"
lines << "- JS: #{metrics["js_bytes"] || "unknown"} bytes"
lines << "- Root HTML, base stylesheet and site script bytes: #{metrics["critical_first_party_bytes"] || "unknown"} (excludes other stylesheets, fonts and images)"
lines << "- Cloudflare cache: #{metrics["root_cf_cache_status"] || "unknown"}"
lines << "- JSON-LD types: #{Array(metrics["json_ld_types"]).join(", ")}"
lines << ""
lines << "## Code-Owned Evidence"
lines << ""
lines << "- Indexing readiness: `#{evidence_dir}/search-console/indexing-readiness.json`"
lines << "- Bing indexing: a public IndexNow ownership key is built into the static release; `scripts/public_website_indexnow_submit.sh` records the Bing-recommended submission response"
lines << "- CI guard: `scripts/public_website_ci_gate.sh` and `.github/workflows/public-website.yml` run static public gates, production live gates, and code-owned completion checks"
lines << "- Language decision: static and live gates verify English-only metadata and reject Kinyarwanda/French routes, sitemap entries, hreflang values, and switcher UI"
lines << ""
lines << "## Required Pending Evidence"
lines << ""
unless visual_passed
  lines << "- Visual QA or owner visual approval remains missing; accepted paths are listed under `visual_approval` below."
else
  lines << "- Visual QA: `#{evidence_dir}/browser_visual_qa.json`"
  lines << "- Screenshots: `#{evidence_dir}/screenshots/mobile_390x844.png`, `mobile_430x932.png`, `tablet_768x1024.png`, `desktop_1440x1000.png`"
end
unless lighthouse_passed
  lines << "- Lighthouse/PageSpeed evidence is missing, invalid or below budget; inspect `lighthouse_mobile` and `lighthouse_desktop` validation below."
else
  lines << "- Lighthouse mobile: `#{evidence_dir}/lighthouse/mobile.json`"
  lines << "- Lighthouse desktop: `#{evidence_dir}/lighthouse/desktop.json`"
end
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
if unverified_external.empty?
  lines << "None."
else
  unverified_external.each do |id|
    item = missing[id] || external[id] || {}
    lines << "### #{id} (#{item.fetch("audit_id", "unverified")})"
    lines << ""
    lines << item.fetch("description", "No accepted result is recorded for this requirement.")
    Array(item["validation"]).each do |validation|
      next if validation["status"] == "pass"

      lines << "- #{validation["path"]}: #{Array(validation["issues"]).join(' ')}"
    end
    lines << ""
    lines << "Accepted evidence paths:"
    Array(item["paths"]).each { |path| lines << "- `#{path}`" }
    lines << ""
  end
end
lines << "## Commands"
lines << ""
lines << "```bash"
lines << "scripts/public_website_quality_gate.sh --json"
lines << "scripts/public_website_live_gate.sh --json"
lines << "scripts/public_website_audit_evidence.sh"
lines << "node scripts/public_website_browser_qa.js"
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
