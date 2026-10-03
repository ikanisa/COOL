# frozen_string_literal: true

# Evidence recorder only. Does not change the active content contract or grant
# approval. Reads actual full current HTML after the strict media publication.
require 'digest'
require 'json'
require 'fileutils'
require_relative '../../../../scripts/qa/public_content_contract'

root = File.expand_path('../../../..', __dir__)
build = File.expand_path(ARGV.fetch(0), root)
raise 'Current build must be repository-local' unless build.start_with?(root + '/.cache/')
baseline_path = File.join(root, PublicContentContract::BASELINE)
previous_path = File.join(root, PublicContentContract::CURRENT)
baseline = JSON.parse(File.read(baseline_path))
previous = JSON.parse(File.read(previous_path))
historical_path = File.join(root, 'docs/release/asset-build-hygiene-2026-09-30/public-historical-content-review-attempt121/historical-visible-text.json')
historical = JSON.parse(File.read(historical_path))
previous_review_path = File.join(root, previous.fetch('current_comparison_file'))
previous_review = JSON.parse(File.read(previous_review_path))
previous_rows = previous_review.fetch('routes').to_h { |row| [row.fetch('route'), row] }
texts = {}
rows = baseline.fetch('hashes').sort.map do |route, expected_historical|
  relative = route == '/' ? 'index.html' : route.delete_prefix('/') + 'index.html'
  path = File.join(build, relative)
  raise 'Current rendered HTML absent or aliased' unless File.file?(path) && !File.symlink?(path)
  html = File.read(path, encoding: Encoding::UTF_8)
  raise 'Current HTML must be valid UTF-8' unless html.valid_encoding?
  current = PublicContentContract.visible_text(html)
  historical_text = historical.fetch(route).fetch('text')
  raise 'Historical text fails original baseline' unless Digest::SHA256.hexdigest(historical_text) == expected_historical
  prior_file = previous_rows.fetch(route).fetch('current_text_file')
  prior = PublicContentContract.read_regular(root, prior_file).force_encoding(Encoding::UTF_8)
  prior_file_sha256 = Digest::SHA256.hexdigest(prior)
  # The prior human-readable text files append one newline; the active
  # visible_text contract deliberately hashes the joined text without it.
  prior = prior.delete_suffix("\n")
  raise 'Prior reviewed content evidence changed' unless Digest::SHA256.hexdigest(prior) == previous.fetch('hashes').fetch(route)
  name = route == '/' ? 'home' : route.delete_prefix('/').delete_suffix('/')
  File.binwrite(File.join(__dir__, name + '.current.txt'), current)
  texts[route] = { 'text' => current, 'sha256' => Digest::SHA256.hexdigest(current), 'actual_html_sha256' => Digest::SHA256.hexdigest(html) }
  {
    'route' => route,
    'historical_matches_baseline' => true,
    'historical_sha256' => expected_historical,
    'historical_text_evidence' => historical_path.delete_prefix(root + '/'),
    'previous_reviewed_sha256' => Digest::SHA256.hexdigest(prior),
    'previous_text_file' => prior_file,
    'previous_text_file_sha256' => prior_file_sha256,
    'previous_text_normalization' => 'Remove exactly one terminal newline from retained human-readable text before comparing the existing visible_text digest',
    'current_sha256' => Digest::SHA256.hexdigest(current),
    'current_text_file' => File.join(__dir__, name + '.current.txt').delete_prefix(root + '/'),
    'current_html_file' => path.delete_prefix(root + '/'),
    'current_html_sha256' => Digest::SHA256.hexdigest(html),
    'evidence_mode' => 'actual_current_full_page_html_after_strict_current_media_publication',
    'current_rendering_changed' => prior != current,
    'removed_lines' => prior.lines.map(&:chomp) - current.lines.map(&:chomp),
    'added_lines' => current.lines.map(&:chomp) - prior.lines.map(&:chomp),
    'historical_removed_lines' => historical_text.lines.map(&:chomp) - current.lines.map(&:chomp),
    'historical_added_lines' => current.lines.map(&:chomp) - historical_text.lines.map(&:chomp),
    'review_status' => 'pending_explicit_delta_review'
  }
end
record = {
  'status' => 'pending_explicit_delta_review',
  'scope' => 'Actual current full public HTML and visible product text. Historical baseline retained. No visual, legal, publication, hosted/native or release acceptance.',
  'source_build_directory' => build,
  'historical_baseline_sha256' => Digest::SHA256.file(baseline_path).hexdigest,
  'historical_visible_text_sha256' => Digest::SHA256.file(historical_path).hexdigest,
  'historical_review_sha256' => Digest::SHA256.file(File.join(root, PublicContentContract::REVIEW)).hexdigest,
  'previous_contract_sha256' => Digest::SHA256.file(previous_path).hexdigest,
  'previous_review_file' => previous.fetch('current_comparison_file'),
  'previous_review_sha256' => Digest::SHA256.file(previous_review_path).hexdigest,
  'builder_sha256' => Digest::SHA256.file(File.join(root, 'scripts/public_static_site_build.rb')).hexdigest,
  'capability_registry_sha256' => Digest::SHA256.file(File.join(root, 'content/product/collect_capabilities.json')).hexdigest,
  'legal_release_approved' => false,
  'publication_approved' => false,
  'routes' => rows
}
File.write(File.join(__dir__, 'current-visible-text.json'), JSON.pretty_generate(texts) + "\n")
File.write(File.join(__dir__, 'content-comparison.pending.json'), JSON.pretty_generate(record) + "\n")
puts JSON.generate('status' => record['status'], 'routes' => rows.length, 'changed_routes' => rows.count { |row| row['current_rendering_changed'] })
