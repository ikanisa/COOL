#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="${MOBILE_ROUTE_RENDER_EVIDENCE_DIR:-}"
OUTPUT_FORMAT="${1:-}"
if [[ "$OUTPUT_FORMAT" != "" && "$OUTPUT_FORMAT" != "--json" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

ROOT_DIR="$ROOT_DIR" EVIDENCE_DIR="$EVIDENCE_DIR" OUTPUT_FORMAT="$OUTPUT_FORMAT" ruby -r json -r pathname <<'RUBY'
root = Pathname.new(ENV.fetch('ROOT_DIR')).realpath
requested = ENV.fetch('EVIDENCE_DIR')
failures = []
summary_path = nil
if requested.empty?
  failures << 'Set MOBILE_ROUTE_RENDER_EVIDENCE_DIR to a completed route capture directory.'
else
  directory = Pathname.new(requested).expand_path
  bundle = ENV.fetch('QA_UAT_BUNDLE_DIR', '')
  allowed_bundle = !bundle.empty? && File.expand_path(requested) ==
    File.expand_path('mobile_route_render_smoke', bundle)
  unless directory.directory? && !directory.symlink? &&
      (directory.realpath.to_s.start_with?("#{root}/.cache/") || allowed_bundle)
    failures << 'Route evidence must be in the repository .cache or the selected QA bundle.'
  else
    summary_path = directory.join('summary.json')
    failures << 'Missing route capture summary.' unless summary_path.file? && !summary_path.symlink?
  end
end
summary = {}
if failures.empty?
  begin
    summary = JSON.parse(summary_path.read)
    failures << 'Route capture did not pass.' unless summary['status'] == 'pass'
    captures = summary['captures']
    failures << 'Route captures are missing.' unless captures.is_a?(Array) && captures.length >= 10
    if captures.is_a?(Array)
      captures.each do |capture|
        unless capture.is_a?(Hash)
          failures << 'Invalid route capture record.'
          next
        end
        path = capture['path'].to_s
        if !path.end_with?('.png') || Pathname.new(path).absolute? || path.include?('..') || path.include?('/')
          failures << 'Invalid screenshot path in route capture.'
          next
        end
        image = summary_path.dirname.join(path)
        unless image.file? && !image.symlink? && image.size > 8_000
          failures << "Missing or undersized screenshot: #{path}"
          next
        end
        failures << "Invalid route capture metadata: #{path}" unless capture['status'] == 'pass' &&
          capture['bytes'] == image.size && capture['width'].to_i >= 300 && capture['height'].to_i >= 500 &&
          capture['distinct_rgb'].to_i >= 8 && capture['non_background_pixels'].to_i >= 100
        metadata = summary_path.dirname.join("#{path}.json")
        failures << "Missing screenshot check: #{path}" unless metadata.file? && !metadata.symlink?
      end
      failures << 'Route count does not match captures.' unless summary['route_count'] == captures.length
    end
  rescue JSON::ParserError, TypeError
    failures << 'Malformed route capture summary.'
  end
end
result = {
  'status' => failures.empty? ? 'pass' : 'fail',
  'evidence_source' => 'mobile_route_render_smoke',
  'summary' => summary_path&.to_s,
  'route_count' => summary['route_count'],
  'design_authority' => 'revolut-design',
  'release_approval' => false,
  'failures' => failures
}
if ENV.fetch('OUTPUT_FORMAT') == '--json'
  puts JSON.pretty_generate(result)
else
  puts "[mobile-route-artifact] status=#{result.fetch('status')} routes=#{result['route_count']}"
  failures.each { |failure| warn "[mobile-route-artifact][FAIL] #{failure}" }
end
exit(failures.empty? ? 0 : 1)
RUBY
