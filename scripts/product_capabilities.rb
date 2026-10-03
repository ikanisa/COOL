# frozen_string_literal: true

require 'digest'
require 'json'
require 'uri'

# Product facts and copy only. revolut-design remains the sole visual authority.
# "supported" means an observed source path, not a published/approved service.
class CollectProductCapabilities
  SOURCE = 'content/product/collect_capabilities.json'
  PLATFORMS = %w[android ios web basic_phone].freeze
  STATES = %w[supported assisted planned provider_dependent unavailable].freeze
  IDS = %w[group_records private_group_creation momo_ussd receipt_sms support basic_phone credit_readiness loans insurance].freeze
  PAGE_PATHS = %w[/ /group-savings/ /insurance/ /craas/ /community-groups/ /our-partners/].freeze
  METADATA_PATHS = %w[
    fastlane/metadata/en-GB/description.txt fastlane/metadata/en-GB/promotional_text.txt
    fastlane/metadata/en-GB/keywords.txt fastlane/metadata/en-GB/review_notes.txt
    fastlane/metadata/en-GB/release_notes.txt fastlane/metadata/android/en-US/full_description.txt
    fastlane/metadata/android/en-US/short_description.txt
  ].freeze
  IMPLEMENTED = %w[group_records private_group_creation momo_ussd receipt_sms support].freeze
  SHA256 = /\A[0-9a-f]{64}\z/

  class UniqueObject < Hash
    def []=(key, value)
      raise 'Duplicate capability field' if key?(key)
      super
    end
  end

  attr_reader :data, :sha256

  def initialize(root, bytes: nil)
    @root = File.expand_path(root)
    bytes ||= read_regular(SOURCE)
    @sha256 = Digest::SHA256.hexdigest(bytes)
    @data = JSON.parse(bytes, object_class: UniqueObject)
    validate!
    deep_freeze(@data)
  end

  def read_regular(name)
    raise 'Unsafe capability source path' unless name.is_a?(String) && name.match?(%r{\A[a-zA-Z0-9_. /-]+\z}) &&
      !name.start_with?('/') && !name.split('/').any? { |part| ['.', '..', ''].include?(part) }
    cursor = @root
    name.split('/').each do |part|
      cursor = File.join(cursor, part)
      raise 'Aliased capability source path' if File.symlink?(cursor)
    end
    raise 'Missing capability source' unless File.file?(cursor)
    File.binread(cursor)
  end

  def validate!
    raise 'Unknown capability registry schema' unless data['schema_version'] == 1 && data['product'] == 'Collect' &&
      data['region'] == 'RW' && data['currency'] == 'RWF' && data['status'] == 'engineering_observed'
    approval = data.fetch('approval')
    unless %w[owner_approved publication_approved legal_release_approved provider_approved].all? { |key| approval[key] == false } &&
           approval['approved_by'].nil? && approval['approval_evidence'].nil?
      raise 'Engineering capability registry cannot grant owner, partner or publication approval'
    end
    sources = data.fetch('source_inputs')
    raise 'Capability evidence inventory is empty' unless sources.is_a?(Hash) && !sources.empty?
    sources.each do |path, expected|
      raise 'Invalid capability evidence digest' unless expected.is_a?(String) && expected.match?(SHA256)
      raise "Capability source changed: #{path}" unless Digest::SHA256.hexdigest(read_regular(path)) == expected
    end
    rows = data.fetch('capabilities')
    raise 'Incomplete or duplicate capability catalog' unless rows.is_a?(Array) && rows.map { |row| row['id'] }.sort == IDS.sort
    rows.each do |row|
      availability = row.fetch('availability')
      unless availability.is_a?(Hash) && availability.keys.sort == PLATFORMS.sort && availability.values.all? { |state| STATES.include?(state) }
        raise 'Incomplete or unsupported capability platform state'
      end
      unless row['owner_approved'] == false && row['provider_approved'] == false && row['hosted_conversion_verified'] == false
        raise 'Capability row falsely claims external approval or observed conversion'
      end
      evidence = row.fetch('evidence')
      raise 'Capability has no source evidence' unless evidence.is_a?(Array) && !evidence.empty? && evidence.all? { |path| sources.key?(path) }
      raise 'Capability has no eligibility boundary' unless row['eligibility'].is_a?(Array) && row['eligibility'].any?
      %w[label summary].each { |key| nonempty_text!(row.fetch(key)) }
      %w[implemented_action fallback_action].each do |key|
        action = row.fetch(key)
        nonempty_text!(action.fetch('label'))
        unless ['https://play.google.com/store/apps/details?id=app.cool.mobile', 'mailto:info@ikanisa.com'].include?(action['href'])
          raise 'Unverified capability conversion destination'
        end
      end
      unless row.dig('fallback_action', 'href') == 'mailto:info@ikanisa.com'
        raise 'Unavailable capability must use information/support contact, not enrollment'
      end
      if !IMPLEMENTED.include?(row['id']) && availability.values.any? { |state| %w[supported assisted].include?(state) }
        raise 'Unapproved planned/provider-dependent service cannot become active'
      end
      if %w[private_group_creation momo_ussd receipt_sms].include?(row['id']) &&
         availability.any? { |platform, state| platform != 'android' && state != 'unavailable' }
        raise 'Android-only capability cannot advertise another platform'
      end
    end
    raise 'Static capability routes changed without integration review' unless data.fetch('static_pages').keys.sort == PAGE_PATHS.sort
    raise 'Store metadata catalog changed without integration review' unless data.fetch('store_metadata').keys.sort == METADATA_PATHS.sort
    data.fetch('store_metadata').each_value { |copy| nonempty_text!(copy) }
    if data.fetch('store_metadata').values_at(*METADATA_PATHS.reject { |path| path.end_with?('review_notes.txt', 'release_notes.txt') }).any? { |copy| copy.match?(/SEPA|bank.transfer|Revolut/i) }
      raise 'Obsolete payment rail in public metadata'
    end
    raise 'Store keyword limit exceeded' if data.dig('store_metadata', 'fastlane/metadata/en-GB/keywords.txt').bytesize > 100
    raise 'Store promotional-text limit exceeded' if data.dig('store_metadata', 'fastlane/metadata/en-GB/promotional_text.txt').length > 170
    raise 'Android short-description limit exceeded' if data.dig('store_metadata', 'fastlane/metadata/android/en-US/short_description.txt').length > 80
  end

  def nonempty_text!(text)
    raise 'Invalid capability copy' unless text.is_a?(String) && !text.strip.empty? && !text.include?("\0")
  end

  def deep_freeze(value)
    case value
    when Hash then value.each { |key, item| deep_freeze(key); deep_freeze(item) }
    when Array then value.each { |item| deep_freeze(item) }
    end
    value.freeze
  end

  def capability(id)
    data.fetch('capabilities').find { |row| row.fetch('id') == id } or raise 'Unknown Collect capability'
  end

  def state(id, region:, platform:)
    raise 'Unsupported Collect region' unless region == data.fetch('region')
    raise 'Unknown Collect platform' unless PLATFORMS.include?(platform)
    capability(id).fetch('availability').fetch(platform)
  end

  # Use only to describe an observed software action. This never authorizes
  # publishing a service or treats a coded route as hosted conversion proof.
  def source_action(id, region:, platform:, require_approved: false)
    row = capability(id)
    current_state = state(id, region: region, platform: platform)
    raise 'Capability is unavailable on this platform' unless %w[supported assisted].include?(current_state)
    if require_approved && !row['owner_approved']
      raise 'Capability has no owner-approved availability evidence'
    end
    row.fetch('implemented_action')
  end

  def public_action(id, region: 'RW', platform: 'android')
    row = capability(id)
    current_state = state(id, region: region, platform: platform)
    return row.fetch('fallback_action') unless %w[supported assisted].include?(current_state)
    source_action(id, region: region, platform: platform)
  end

  def copy(key)
    data.fetch('common').fetch(key)
  end

  def page(path, key)
    value = data.fetch('static_pages').fetch(path).fetch(key.to_s)
    symbolize(value)
  end

  def detail(key)
    data.fetch('detail').fetch(key)
  end

  def faqs
    data.fetch('public_faqs')
  end

  def symbolize(value)
    case value
    when Hash then value.to_h { |key, item| [key.to_sym, symbolize(item)] }
    when Array then value.map { |item| symbolize(item) }
    else value
    end
  end
end
