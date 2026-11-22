require 'digest'
require 'json'

class NativeStateScreenshotAudit
  # These Android-only creation cases deliberately verify the same iOS
  # Groups redirect. They remain four required guard checks and captures.
  IOS_CREATION_GUARDS = %w[
    create-group-type create-group-receiver create-group-assets create-group-review
  ].freeze

  def self.evaluate(paths, platform:)
    names = paths.to_h do |path|
      [path, File.basename(path, '.png').delete_prefix('mobile_state_')]
    end
    key_for = lambda do |name|
      platform == 'ios' && IOS_CREATION_GUARDS.include?(name) ? 'ios-creation-guard' : name
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
      'platform' => platform,
      'screenshot_count' => paths.size,
      'minimum_distinct_destinations' => minimum,
      'unique_screenshots' => groups.size,
      'duplicate_groups' => duplicates,
      'unexpected_duplicate_groups' => unexpected,
      'allowed_alias_reason' => platform == 'ios' ? 'Four Android-only creation cases verify the existing iOS Groups redirect.' : nil
    }
  end
end

if $PROGRAM_NAME == __FILE__
  result = NativeStateScreenshotAudit.evaluate(
    Dir[File.join(ARGV.fetch(0), 'mobile_state_*.png')], platform: ARGV.fetch(1)
  )
  puts JSON.pretty_generate(result)
  exit(result.fetch('accepted') ? 0 : 1)
end
