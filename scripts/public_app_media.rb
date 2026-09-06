# frozen_string_literal: true

require 'digest'
require 'json'
require 'yaml'

# Marketing screenshots are unchanged captures of the current application.
# This validates provenance and freshness, not complete design acceptance.
class PublicAppMedia
  def initialize(root)
    @root = root
    @directory = File.join(root, 'web/public/app-screens')
  end

  def runtime_fingerprint
    directories = %w[lib android/app/src ios/Runner]
    files = directories.flat_map { |dir| Dir.glob(File.join(@root, dir, '**/*'), File::FNM_DOTMATCH) }
      .select { |path| File.file?(path) && !File.basename(path).start_with?('.') && !File.basename(path).include?('GeneratedPluginRegistrant') }
    # Android provider configuration is injected outside Git and does not
    # participate in these iOS fixture images. Its presence must not make a
    # clean website checkout appear to have changed the captured UI. Native
    # release provenance still hashes its own complete build inputs.
    files.reject! { |path| path.delete_prefix(@root + '/').match?(%r{\Aandroid/app/src/[^/]+/google-services\.json\z}) }
    flutter = YAML.safe_load(File.read(File.join(@root, 'pubspec.yaml'))).fetch('flutter', {})
    declared = Array(flutter['assets']).map { |entry| entry.is_a?(Hash) ? entry.fetch('path') : entry }
    declared += Array(flutter['licenses'])
    declared += Array(flutter['fonts']).flat_map { |family| family.fetch('fonts').map { |font| font.fetch('asset') } }
    declared.each do |entry|
      path = File.join(@root, entry)
      files += File.directory?(path) ? Dir.glob(File.join(path, '**/*')).select { |file| File.file?(file) && !File.basename(file).start_with?('.') } : [path]
    end
    files += %w[pubspec.yaml pubspec.lock].map { |path| File.join(@root, path) }
    Digest::SHA256.hexdigest(files.uniq.sort_by { |path| path.split(File::SEPARATOR) }.map { |path|
      "#{path.delete_prefix(@root + '/')}\0#{Digest::SHA256.file(path).hexdigest}\n"
    }.join)
  end

  def screens
    @screens ||= begin
      manifest = JSON.parse(File.read(File.join(@directory, 'manifest.json')))
      raise 'App screenshots need recapturing: runtime changed' unless manifest.fetch('runtime_sha256') == runtime_fingerprint
      provenance = JSON.parse(File.read(File.join(@directory, 'capture-provenance.json')))
      raise 'App screenshot native provenance is incomplete' unless provenance['status'] == 'pass' &&
        provenance['installed_matches_retained_bundle'] == true &&
        provenance['runtime_sha256'] == manifest['runtime_sha256']

      manifest.fetch('screens').to_h do |entry|
        filename = entry.fetch('file')
        raise 'Invalid app screenshot filename' unless filename.match?(/\A[a-z0-9-]+\.png\z/)
        asset = File.join(@directory, filename)
        capture = File.expand_path(entry.fetch('capture'), @root)
        raise 'App screenshot capture must be repository-local' unless capture.start_with?(@root + '/.cache/')
        raise 'App screenshot is not visually reviewed' unless entry['reviewed_for_website'] == true
        expected = entry.fetch('sha256')
        original = provenance.fetch('captures').find { |row| row['path'] == entry['capture'] }
        raise 'App screenshot is absent from native capture provenance' unless original &&
          %w[sha256 width height].all? { |key| original[key] == entry[key] }
        # The original run is a local QA artifact. Its checked-in hash inventory
        # keeps clean-checkout builds reproducible without shipping the simulator.
        candidates = [asset]
        candidates << capture if File.file?(capture)
        raise 'App screenshot differs from its original capture' unless candidates.all? { |path| Digest::SHA256.file(path).hexdigest == expected }
        header = File.binread(asset, 24)
        raise 'App screenshot is not a PNG' unless header.start_with?("\x89PNG\r\n\x1a\n".b)
        dimensions = header.byteslice(16, 8).unpack('NN')
        raise 'App screenshot dimensions differ from its capture' unless dimensions == [entry.fetch('width'), entry.fetch('height')]
        raise 'Unsupported screenshot provenance' unless entry['capture_kind'] == 'native_ios_fixture'
        [entry.fetch('id'), entry.merge('source' => asset, 'url' => "/assets/app-screens/#{filename}")]
      end
    end
  end
end
