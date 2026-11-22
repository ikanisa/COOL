# frozen_string_literal: true

require 'cgi'
require 'digest'
require 'fileutils'
require 'json'
require_relative 'qa/asset_manifest_integrity'

# Build-time validation and delivery markup for Collect's existing photographs.
# PNG originals remain the fallback. This does not validate visual acceptance.
class PublicPhotography
  BANK = 'assets/marketing/rwanda'
  DIRECTORY = 'web/public/photography'
  GENERATOR = 'scripts/assets/build_public_photography.mjs'
  RENDERER_INPUTS = %w[
    scripts/public_static_site_build.rb scripts/public_marketing_sections.rb scripts/public_legal_rendering.rb
    scripts/public_site_routes.rb scripts/public_site_assets.rb scripts/public_site_publication.rb scripts/public_photography.rb
    web/public/layout.css web/public/revolut.css web/public/photography/manifest.json
  ].freeze

  def initialize(root)
    @root = File.expand_path(root)
  end

  def self.asset_version(root)
    root = File.expand_path(root)
    templates = Dir.glob(File.join(root, 'scripts/public_site/**/*.{rb,js}')).sort.map { |file| file.delete_prefix(root + '/') }
    digest = Digest::SHA256.new
    (RENDERER_INPUTS + templates).each do |file|
      digest.update("#{file}\0#{AssetManifestIntegrity.sha256(root, file)}\n")
    end
    "collect-static-#{digest.hexdigest[0, 16]}"
  end

  def photos
    @photos ||= begin
      manifest = JSON.parse(File.read(File.join(@root, DIRECTORY, 'manifest.json')))
      raise 'Unsupported public photo manifest' unless manifest['schema_version'] == 1 && manifest['records'].is_a?(Array)
      raise 'Public photo generator changed; regenerate and review delivery artifacts' unless Digest::SHA256.file(File.join(@root, GENERATOR)).hexdigest == manifest['generator_sha256']
      expected = Dir.glob(File.join(@root, BANK, '*.png')).map { |file| file.delete_prefix(@root + '/') }.sort
      records = manifest.fetch('records')
      raise 'Public photo inventory is incomplete or duplicated' unless !expected.empty? && records.map { |item| item.fetch('source') }.sort == expected

      records.to_h { |item| [verify_photo(item), item] }
    end
  end

  def prepare_html(html)
    raise 'Public photo markup was already prepared' if html.include?('class="public-photography"')

    html.gsub(/<img\b[^>]*>/i) do |tag|
      source = tag.match(/\bsrc=(["'])(.*?)\1/i)&.[](2)
      next tag unless source&.start_with?("/#{BANK}/")
      match = source.match(%r{\A/#{BANK}/([a-z0-9-]+\.png)\z})
      raise 'Unrecognized public photo reference' unless match
      photo = photos.fetch(match[1]) { raise 'Public photo delivery is missing' }
      if tag.match?(/\bloading=["']lazy["']/i) && !tag.match?(/\bfetchpriority=/i)
        tag = tag.sub(/<img\b/i, '<img fetchpriority="low"')
      end
      %(<picture class="public-photography"><source type="image/webp" srcset="#{CGI.escapeHTML(photo.fetch('url'))}">#{tag}</picture>)
    end
  end

  def prepare_css(css)
    selector = '.rwanda-story > img {'
    raise 'Public story photo selector changed; review delivery styling' unless css.scan(selector).length == 1
    background = photos.fetch('kigali-hills.png')
    fallback = "/#{BANK}/kigali-hills.png"
    raise 'Public hero photo background changed; review delivery styling' unless css.include?("url(\"#{fallback}\")")

    # Keep the enhancement beside the original declaration so later responsive
    # and forced-colour background overrides retain their original precedence.
    background_rule = /background:\s*[^;{}]*url\("#{Regexp.escape(fallback)}"\)[^;{}]*;/
    raise 'Public hero background declaration changed; review delivery styling' unless css.scan(background_rule).length == 1
    enhanced = css.sub(background_rule) do |declaration|
      %(#{declaration} background-image: image-set(url("#{background.fetch('url')}") type("image/webp"), url("#{fallback}") type("image/png"));)
    end

    enhanced.sub(selector, '.rwanda-story > img, .rwanda-story > .public-photography > img {') + <<~CSS

      .public-photography { display: contents; }
      .public-photography > source { display: none; }
    CSS
  end

  def copy_to(build_directory)
    photos.each_value do |photo|
      destination = File.join(build_directory, photo.fetch('url').delete_prefix('/'))
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(File.join(@root, photo.fetch('file')), destination)
    end
  end

  private

  def verify_photo(item)
    source = item.fetch('source')
    raise 'Invalid public photo source path' unless source.match?(%r{\Aassets/marketing/rwanda/[a-z0-9-]+\.png\z})
    digest = item.fetch('sha256')
    raise 'Invalid public photo digest' unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
    filename = "#{File.basename(source, '.png')}-#{digest[0, 12]}.webp"
    raise 'Invalid public photo delivery path' unless item['file'] == "#{DIRECTORY}/#{filename}" && item['url'] == "/#{BANK}/#{filename}"
    verify_original(File.join(@root, source), item)
    verify_webp(File.join(@root, item.fetch('file')), item.fetch('bytes'), digest)
    raise 'Photo alpha or colour-profile preservation is unverified' unless item['alpha_unchanged'] == true && item['colour_profile_unchanged'] == true
    File.basename(source)
  end

  def verify_original(path, item)
    raise 'Original public photo changed' unless File.size(path) == item.fetch('source_bytes') && Digest::SHA256.file(path).hexdigest == item.fetch('source_sha256')
    header = File.binread(path, 24)
    raise 'Invalid original photo dimensions' unless header.bytesize == 24 && header.start_with?("\x89PNG\r\n\x1a\n".b) &&
      header.byteslice(16, 8).unpack('NN') == [item.fetch('width'), item.fetch('height')]
  end

  def verify_webp(path, expected_size, digest)
    size = File.size(path)
    raise 'Public photo delivery artifact changed' unless size == expected_size && Digest::SHA256.file(path).hexdigest == digest
    header = File.binread(path, 12)
    raise 'Invalid WebP delivery container' unless header.start_with?('RIFF') && header.byteslice(8, 4) == 'WEBP' &&
      header.byteslice(4, 4).unpack1('V') + 8 == size
  end
end
