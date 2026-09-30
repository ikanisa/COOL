# frozen_string_literal: true

require 'digest'
require 'json'
require 'yaml'
require_relative 'qa/asset_manifest_integrity'

# Marketing screenshots are unchanged captures of the current application.
# This validates provenance and freshness, not complete design acceptance.
class PublicAppMedia
  def initialize(root)
    @root = root
    @directory = File.join(root, 'web/public/app-screens')
  end

  def runtime_fingerprint
    pubspec = YAML.safe_load(File.read(File.join(@root, 'pubspec.yaml')))
    directories = %w[lib android/app/src ios/Runner]
    files = directories.flat_map { |dir| Dir.glob(File.join(@root, dir, '**/*'), File::FNM_DOTMATCH) }
      .select { |path| File.file?(path) && !File.basename(path).start_with?('.') && !File.basename(path).include?('GeneratedPluginRegistrant') }
    # Android provider configuration is injected outside Git and does not
    # participate in these iOS fixture images. Its presence must not make a
    # clean website checkout appear to have changed the captured UI. Native
    # release provenance still hashes its own complete build inputs.
    files.reject! { |path| path.delete_prefix(@root + '/').match?(%r{\Aandroid/app/src/[^/]+/google-services\.json\z}) }
    # Local path forks affect the rendered app just as application sources do.
    # Bind their runtime Dart files and retained provenance; cached/generated
    # package contents and historical package tests are separate evidence.
    dependencies = %w[dependencies dev_dependencies dependency_overrides].each_with_object({}) do |section, all|
      all.merge!(pubspec.fetch(section, {}))
    end
    dependencies.each_value do |dependency|
      next unless dependency.is_a?(Hash) && dependency.key?('path')
      path = AssetManifestIntegrity.validate_relative!(dependency.fetch('path'))
      dart_files = Dir.glob(File.join(@root, path, 'lib/**/*')).select { |file| File.file?(file) }
      raise 'Local package runtime source is missing' if dart_files.empty?
      runtime_files = %w[lib android ios macos linux windows].flat_map do |platform|
        Dir.glob(File.join(@root, path, platform, '**/*')).select { |file| File.file?(file) && !File.basename(file).start_with?('.') }
      end
      metadata = %w[pubspec.yaml LICENSE COLLECT_FORK.md].map { |file| File.join(@root, path, file) }
      upstream = File.join(@root, path, 'UPSTREAM-SHA256.json')
      metadata << upstream if File.exist?(upstream)
      (runtime_files + metadata).each do |file|
        AssetManifestIntegrity.regular_path!(@root, file.delete_prefix(@root + '/'))
      end
      files += runtime_files + metadata
    end
    flutter = pubspec.fetch('flutter', {})
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
      kinds = manifest.fetch('screens').map { |row| row.fetch('capture_kind') }.uniq
      raise 'Mixed app screenshot platforms require separate provenance' unless kinds.length == 1
      raise 'App screenshot provenance is incomplete' unless provenance['status'] == 'pass' &&
        provenance['runtime_sha256'] == manifest['runtime_sha256']
      case kinds.first
      when 'native_ios_fixture'
        raise 'App screenshot native provenance is incomplete' unless provenance['installed_matches_retained_bundle'] == true
      when 'browser_flutter_fixture'
        verify_browser_provenance!(manifest, provenance)
      else
        raise 'Unsupported screenshot provenance'
      end

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
        [entry.fetch('id'), entry.merge('source' => asset, 'url' => "/assets/app-screens/#{filename}")]
      end
    end
  end

  private

  def evidence_json(relative, expected)
    raise 'Invalid app media evidence hash' unless expected.is_a?(String) && expected.match?(/\A[0-9a-f]{64}\z/)
    bytes = AssetManifestIntegrity.read_regular(@root, relative, max_bytes: 8 * 1024 * 1024) { |io| io.read }
    raise 'App media evidence changed' unless Digest::SHA256.hexdigest(bytes) == expected
    JSON.parse(bytes)
  end

  # Browser previews are never relabeled as native screenshots. The source,
  # compiled artifact, HTTP-served bytes, route markers and visual review are
  # independently bound. Existing native installed-bundle checks remain intact.
  def verify_browser_provenance!(manifest, provenance)
    raise 'Browser screenshot provenance is incomplete' unless provenance['kind'] == 'browser_flutter_fixture' &&
      provenance['native_capture_passed'] == false
    report = evidence_json(provenance.fetch('capture_report'), provenance.fetch('capture_report_sha256'))
    review = evidence_json(provenance.fetch('visual_review'), provenance.fetch('visual_review_sha256'))
    build = report.fetch('build_files')
    raise 'Browser source or build verification failed' unless
      report['kind'] == 'browser_flutter_fixture' && report['status'] == 'captured_pending_visual_review' &&
      report['sources_unchanged'] == true && !report.fetch('sources_before').empty? &&
      report['sources_before'] == report['sources_after'] &&
      report['runtime_before_sha256'] == manifest['runtime_sha256'] &&
      report['runtime_after_sha256'] == manifest['runtime_sha256'] &&
      report.fetch('errors').empty? && report.fetch('external_requests').empty? &&
      report['remote_resources_blocked_before_http'] == true &&
      Array(report['blocked_engine_font_requests']).all? { |url| url == 'https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2' } &&
      %w[provider_calls hosted_calls database_calls].all? { |key| report[key] == 0 } &&
      report.fetch('commands').any? { |row| row['name'] == 'flutter-build' && row['exit_code'] == 0 } &&
      build.length.between?(1, 10_000) && build.key?('main.dart.js') && build.key?('flutter_bootstrap.js') &&
      Digest::SHA256.hexdigest(JSON.generate(build)) == report['build_manifest_sha256'] &&
      report.fetch('served_resources')['main.dart.js'] == build['main.dart.js']
    build.each do |path, sha|
      AssetManifestIntegrity.validate_relative!(path)
      raise 'Invalid browser build hash' unless sha.is_a?(String) && sha.match?(/\A[0-9a-f]{64}\z/)
    end
    report.fetch('served_resources').each do |path, sha|
      raise 'Browser served artifact mismatch' unless build[path] == sha
    end
    raise 'Browser screenshot visual review is incomplete' unless review['status'] == 'pass' &&
      review['capture_report_sha256'] == provenance['capture_report_sha256'] &&
      review['runtime_sha256'] == manifest['runtime_sha256'] &&
      review['build_manifest_sha256'] == report['build_manifest_sha256'] &&
      review['native_acceptance'] == false
    entries = manifest.fetch('screens')
    raise 'Browser screenshot review coverage differs' unless
      entries.map { |row| row.fetch('id') }.uniq.length == entries.length &&
      report.fetch('captures').map { |row| row.fetch('id') }.sort == entries.map { |row| row.fetch('id') }.sort &&
      review.fetch('screens').map { |row| row.fetch('id') }.sort == entries.map { |row| row.fetch('id') }.sort
    entries.each do |entry|
      capture = report.fetch('captures').find { |row| row['id'] == entry['id'] }
      inspected = review.fetch('screens').find { |row| row['id'] == entry['id'] }
      raise 'Browser route capture is not verified' unless
        capture['marker_verified'] == true &&
        %w[sha256 width height app_route].all? { |key| capture[key] == entry[key] } &&
        capture['path'] == entry['capture'] && entry['platform'] == 'Chromium browser' &&
        inspected['sha256'] == entry['sha256'] && inspected['reviewed_for_website'] == true
    end
  rescue KeyError, AssetManifestIntegrity::InvalidPath, JSON::ParserError
    raise 'Browser screenshot evidence is missing or invalid'
  end
end
