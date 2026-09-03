require 'digest'
require 'json'

class NativeRouteScreenshotAudit
  # Only these route aliases intentionally share a visual destination. All
  # other identical captures indicate stale, missing or wrong-screen evidence.
  VISUAL_ALIASES = [
    %w[settings-bank-transfer profile-edit],
    %w[root-signed-in app-invite-link app-share-entry home],
    %w[public-buri-momo diaspora-public-buri-momo],
    %w[group-create groups share-expired-request share-invalid share-expired],
    %w[shared-group-link group-detail],
    %w[auth root-redirect],
    %w[legal-privacy privacy-alias],
    %w[invite share]
  ].freeze

  def self.evaluate(paths)
    key_for = lambda do |name|
      VISUAL_ALIASES.find { |group| group.include?(name) }&.first || name
    end
    names = paths.to_h do |path|
      [path, File.basename(path, '.png').delete_prefix('mobile_route_')]
    end
    groups = paths.group_by { |path| Digest::SHA256.file(path).hexdigest }
    duplicates = groups.values.select { |items| items.length > 1 }.map do |items|
      items.map { |path| names.fetch(path) }.sort
    end
    unexpected = duplicates.reject do |items|
      items.map { |name| key_for.call(name) }.uniq.length == 1
    end
    minimum = names.values.map { |name| key_for.call(name) }.uniq.length
    {
      'accepted' => paths.any? && unexpected.empty? && groups.size >= minimum,
      'screenshot_count' => paths.size,
      'minimum_distinct_destinations' => minimum,
      'unique_screenshots' => groups.size,
      'duplicate_groups' => duplicates,
      'unexpected_duplicate_groups' => unexpected
    }
  end
end

if $PROGRAM_NAME == __FILE__
  result = NativeRouteScreenshotAudit.evaluate(Dir[File.join(ARGV.fetch(0), 'mobile_route_*.png')])
  puts JSON.pretty_generate(result)
  exit(result.fetch('accepted') ? 0 : 1)
end
