# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'base64'
require_relative '../public_photography'

class PublicPhotographyTest < Minitest::Test
  PNG = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAADUlEQVQImWMQCaj4DwADNAHc03+V3gAAAABJRU5ErkJggg==').freeze
  WEBP = Base64.decode64('UklGRh4AAABXRUJQVlA4TBEAAAAvAAAAAAdQqFIUr/+BiOh/AAA=').freeze
  NAMES = %w[banking-together community-savings everyday-payments kigali-hills kigali-woman-hero shared-goals].freeze

  def setup
    @directory = Dir.mktmpdir('collect-public-photography-')
    write('scripts/assets/build_public_photography.mjs', 'fixture generator')
    @manifest = { 'schema_version' => 1, 'generator_sha256' => digest('fixture generator'), 'records' => [] }
    NAMES.each do |name|
      source = "assets/marketing/rwanda/#{name}.png"
      filename = "#{name}-#{digest(WEBP)[0, 12]}.webp"
      file = "web/public/photography/#{filename}"
      write(source, PNG)
      write(file, WEBP)
      @manifest['records'] << { 'source' => source, 'source_sha256' => digest(PNG), 'source_bytes' => PNG.bytesize,
        'file' => file, 'url' => "/assets/marketing/rwanda/#{filename}", 'sha256' => digest(WEBP), 'bytes' => WEBP.bytesize,
        'width' => 1, 'height' => 1, 'alpha_unchanged' => true, 'colour_profile_unchanged' => true }
    end
    save_manifest
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def digest(bytes)
    Digest::SHA256.hexdigest(bytes)
  end

  def write(relative, bytes)
    file = File.join(@directory, relative)
    FileUtils.mkdir_p(File.dirname(file))
    File.binwrite(file, bytes)
  end

  def save_manifest
    write('web/public/photography/manifest.json', JSON.generate(@manifest))
  end

  def photos
    PublicPhotography.new(@directory)
  end

  def test_fallback_preserves_image_identity_attributes_and_link
    image = '<img class="hero-editorial" src="/assets/marketing/rwanda/kigali-woman-hero.png" alt="" width="1672" height="941" fetchpriority="high">'
    rendered = photos.prepare_html("<a href='/groups/'>#{image}</a>")
    assert_includes rendered, image
    assert_includes rendered, "<a href='/groups/'>"
    assert_includes rendered, '<source type="image/webp"'
    assert_includes rendered, @manifest['records'][4]['url']
    assert_equal 1, rendered.scan('<img ').length
  end

  def test_lazy_photographs_receive_low_priority_without_overriding_explicit_priority
    original = '<img src="/assets/marketing/rwanda/community-savings.png" alt="Community" loading="lazy" decoding="async">'
    result = photos.prepare_html(original)
    assert_includes result, '<img fetchpriority="low"'
    assert_includes result, 'loading="lazy" decoding="async"'
    result = photos.prepare_html(original.sub('loading=', 'fetchpriority="high" loading='))
    refute_includes result, 'fetchpriority="low"'
    assert_equal 1, result.scan('fetchpriority=').length
  end

  def test_logos_native_screens_and_unrelated_content_remain_unchanged
    html = '<img src="/icons/collect.png" alt=""><img src="/assets/app-screens/home.png" alt="Collect app"><p>Own product content</p>'
    assert_equal html, photos.prepare_html(html)
  end

  def test_missing_unknown_or_already_prepared_photo_reference_is_rejected
    assert_raises(RuntimeError) { photos.prepare_html('<img src="/assets/marketing/rwanda/missing.png">') }
    assert_raises(RuntimeError) { photos.prepare_html('<img src="/assets/marketing/rwanda/../private.png">') }
    result = photos.prepare_html('<img src="/assets/marketing/rwanda/shared-goals.png">')
    assert_raises(RuntimeError) { photos.prepare_html(result) }
  end

  def test_css_retains_png_background_and_existing_geometry_with_picture_support
    css = '.rwanda-story > img { width: 100%; height: auto; } .hero { background: blue url("/assets/marketing/rwanda/kigali-hills.png") center / cover; } @media (forced-colors: active) { .hero { background: Canvas; } }'
    rendered = photos.prepare_css(css)
    assert_includes rendered, 'width: 100%; height: auto;'
    assert_includes rendered, 'background: blue url("/assets/marketing/rwanda/kigali-hills.png") center / cover;'
    assert_includes rendered, 'display: contents;'
    assert_includes rendered, '.public-photography > source { display: none; }'
    assert_includes rendered, 'type("image/webp")'
    assert_includes rendered, 'type("image/png")'
    assert_operator rendered.index('background-image: image-set('), :<, rendered.index('@media (forced-colors: active)')
    assert_equal 1, rendered.scan('background-image: image-set(').length
    assert_raises(RuntimeError) { photos.prepare_css('.new-selector img {}') }
  end

  def test_original_and_encoded_byte_changes_are_rejected
    write(@manifest['records'][0]['source'], PNG + 'changed')
    assert_raises(RuntimeError) { photos.photos }
    write(@manifest['records'][0]['source'], PNG)
    write(@manifest['records'][0]['file'], WEBP + 'changed')
    assert_raises(RuntimeError) { photos.photos }
  end

  def test_generator_drift_requires_regeneration
    write('scripts/assets/build_public_photography.mjs', 'new encoder options')
    assert_raises(RuntimeError) { photos.photos }
  end

  def test_missing_and_duplicate_inventory_records_are_rejected
    record = @manifest['records'].pop
    save_manifest
    assert_raises(RuntimeError) { photos.photos }
    @manifest['records'] += [record, record]
    save_manifest
    assert_raises(RuntimeError) { photos.photos }
  end

  def test_delivery_paths_cannot_escape_or_lose_the_content_hash
    @manifest['records'][0]['file'] = '../unexpected.webp'
    save_manifest
    assert_raises(RuntimeError) { photos.photos }
  end

  def test_dimensions_and_preservation_flags_are_checked
    @manifest['records'][0]['width'] = 2
    save_manifest
    assert_raises(RuntimeError) { photos.photos }
    @manifest['records'][0]['width'] = 1
    @manifest['records'][0]['alpha_unchanged'] = false
    save_manifest
    assert_raises(RuntimeError) { photos.photos }
  end

  def test_delivery_copy_keeps_originals_and_uses_hashed_asset_urls
    build = File.join(@directory, 'output')
    photos.copy_to(build)
    @manifest['records'].each do |record|
      assert_equal WEBP, File.binread(File.join(build, record['url'].delete_prefix('/')))
      assert_equal PNG, File.binread(File.join(@directory, record['source']))
    end
  end

  def test_stylesheet_cache_version_changes_with_delivery_dependencies
    %w[scripts/public_static_site_build.rb scripts/public_photography.rb web/public/revolut.css].each { |file| write(file, 'initial source') }
    first = PublicPhotography.asset_version(@directory)
    assert_equal first, PublicPhotography.asset_version(@directory)
    write('web/public/revolut.css', 'updated picture selector')
    refute_equal first, PublicPhotography.asset_version(@directory)
  end
end
