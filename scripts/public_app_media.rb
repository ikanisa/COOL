# frozen_string_literal: true

require 'digest'
require 'json'
require 'yaml'
require_relative 'qa/asset_manifest_integrity'

# Marketing screenshots are unchanged captures of the current application.
# This validates provenance and freshness, not complete design acceptance.
class PublicAppMedia
  NATIVE_MEDIA_ROUTES = {
    'home' => '/home', 'groups' => '/groups', 'group-detail' => '/groups/qa-private-group',
    'security' => '/settings/security', 'privacy' => '/settings/legal/privacy',
    'terms' => '/settings/legal/terms', 'account-deletion' => '/settings/account/delete'
  }.freeze
  PUBLISHED_METADATA_INPUT = 'assets/brand/APPROVED_PRODUCT_VISUAL_ASSETS.sha256'
  BROWSER_DIAGNOSTIC_INPUTS = %w[scripts/qa/collect_diagnostic_observer.mjs
                                scripts/qa/public_browser_app_media.mjs].freeze
  CUA_CAPTURE_INPUTS = %w[scripts/qa/public_cua_capture_contract.json scripts/qa/serve_public_preview.py scripts/admin_cloudflare_assets.py].freeze
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

  # Browser preview compilation starts at this real fixture entrypoint. Every
  # quoted import/export/part alternative is retained, including conditional
  # branches. Native and legacy captures continue using runtime_fingerprint.
  def browser_source_snapshot
    base = File.realpath(@root)
    pubspec = YAML.safe_load(File.read(File.join(base, 'pubspec.yaml')))
    dependencies = %w[dependencies dev_dependencies dependency_overrides].each_with_object({}) do |section, all|
      all.merge!(pubspec.fetch(section, {}))
    end
    locked = YAML.safe_load(File.read(File.join(base, 'pubspec.lock')))
    external_packages = dependencies.keys + (locked.is_a?(Hash) ? locked.fetch('packages', {}).keys : [])
    local_packages = dependencies.each_with_object({}) do |(name, dependency), all|
      next unless dependency.is_a?(Hash) && dependency.key?('path')
      all[name] = File.join(base, AssetManifestIntegrity.validate_relative!(dependency.fetch('path')))
    end
    entrypoint = 'tool/public_app_media_capture.dart'
    files = []
    seen = {}
    pending = [entrypoint] + local_packages.values.flat_map { |directory|
      Dir.glob(File.join(directory, 'lib/**/*.dart')).map { |path| path.delete_prefix(base + '/') }
    }
    until pending.empty?
      name = pending.pop
      next if seen[name]
      seen[name] = true
      path = AssetManifestIntegrity.regular_path!(base, name)
      raise 'Browser local directive is not Dart source' unless name.end_with?('.dart')
      files << path
      text = File.read(path)
      text.scan(/^\s*(?:import|export|part)\s+(?!of\b)(.*?);/m).flatten.each do |directive|
        uris = directive.scan(/['"]([^'"\n]+)['"]/).flatten
        raise 'Unknown browser source directive' if uris.empty?
        uris.each do |uri|
          next if uri.start_with?('dart:')
          if uri.start_with?('package:')
            match = uri.match(/\Apackage:([a-zA-Z0-9_]+)\/(.+)\z/)
            raise 'Unknown browser package directive' unless match
            package, relative = match.captures
            AssetManifestIntegrity.validate_relative!(relative)
            if package == pubspec.fetch('name', 'collect_app')
              target = File.join(base, 'lib', relative)
            elsif local_packages.key?(package)
              target = File.join(local_packages.fetch(package), 'lib', relative)
            else
              raise 'Undeclared browser package directive' unless external_packages.include?(package)
              next
            end
          else
            raise 'Unknown browser source URI' if uri.include?(':') || uri.start_with?('/') || uri.include?('?') || uri.include?('#')
            target = File.expand_path(uri, File.dirname(path))
          end
          prefix = File.expand_path(base) + '/'
          raise 'Browser source directive escapes checkout' unless target.start_with?(prefix)
          pending << target.delete_prefix(prefix)
        end
      end
    end
    dependencies.each_value do |dependency|
      next unless dependency.is_a?(Hash) && dependency.key?('path')
      relative = AssetManifestIntegrity.validate_relative!(dependency.fetch('path'))
      directory = File.join(base, relative)
      dart = Dir.glob(File.join(directory, 'lib/**/*')).select { |file| File.file?(file) || File.symlink?(file) }
      raise 'Local browser package runtime source is missing' if dart.empty?
      files += dart
      metadata = %w[pubspec.yaml LICENSE COLLECT_FORK.md].map { |name| File.join(directory, name) }
      upstream = File.join(directory, 'UPSTREAM-SHA256.json')
      metadata << upstream if File.exist?(upstream)
      options = File.join(directory, 'analysis_options.yaml')
      metadata << options if File.exist?(options)
      files += metadata
    end
    flutter = pubspec.fetch('flutter', {})
    declared = Array(flutter['assets']).map { |entry| entry.is_a?(Hash) ? entry.fetch('path') : entry }
    declared += Array(flutter['licenses'])
    declared += Array(flutter['fonts']).flat_map { |family| family.fetch('fonts').map { |font| font.fetch('asset') } }
    declared.each do |entry|
      relative = AssetManifestIntegrity.validate_relative!(entry.sub(%r{/+\z}, ''))
      path = File.join(base, relative)
      expanded = File.directory?(path) ? Dir.glob(File.join(path, '**/*')).select { |file| File.file?(file) || File.symlink?(file) } : [path]
      raise 'Declared browser asset directory is empty' if expanded.empty?
      files += expanded
    end
    # Flutter copies the web scaffold into this build. Published screenshots
    # are derived outputs, not inputs to the app routes that produced them.
    files += Dir.glob(File.join(base, 'web/**/*')).select { |file|
      (File.file?(file) || File.symlink?(file)) && !file.start_with?(File.join(base, 'web/public/app-screens') + '/')
    }
    files += %w[.fvmrc .metadata pubspec.yaml pubspec.lock analysis_options.yaml
                scripts/public_app_media.rb scripts/qa/asset_manifest_integrity.rb].map { |name| File.join(base, name) }
    files += BROWSER_DIAGNOSTIC_INPUTS.map { |name| File.join(base, name) }
    files += CUA_CAPTURE_INPUTS.map { |name| File.join(base, name) } if File.file?(File.join(base, CUA_CAPTURE_INPUTS.first))
    raise 'Browser web entrypoint is absent' unless File.file?(File.join(base, 'web/index.html'))
    files.uniq.sort_by { |path| path.split(File::SEPARATOR) }.to_h do |path|
      relative = path.delete_prefix(File.expand_path(base) + '/')
      AssetManifestIntegrity.regular_path!(base, relative)
      [relative, Digest::SHA256.file(path).hexdigest]
    end
  end

  def browser_runtime_fingerprint
    Digest::SHA256.hexdigest(browser_source_snapshot.map { |path, digest| "#{path}\0#{digest}\n" }.join)
  end

  def screens
    @screens ||= begin
      manifest = JSON.parse(File.read(File.join(@directory, 'manifest.json')))
      fingerprint = manifest['runtime_fingerprint_version'] == 4 ? browser_runtime_fingerprint : runtime_fingerprint
      raise 'App screenshots need recapturing: runtime changed' unless manifest.fetch('runtime_sha256') == fingerprint
      provenance = JSON.parse(File.read(File.join(@directory, 'capture-provenance.json')))
      kinds = manifest.fetch('screens').map { |row| row.fetch('capture_kind') }.uniq
      raise 'Mixed app screenshot platforms require separate provenance' unless kinds.length == 1
      raise 'App screenshot provenance is incomplete' unless provenance['status'] == 'pass' &&
        provenance['runtime_sha256'] == manifest['runtime_sha256']
      case kinds.first
      when 'native_ios_fixture'
        raise 'App screenshot native provenance is incomplete' unless provenance['installed_matches_retained_bundle'] == true
        verify_native_provenance!(manifest, provenance) if provenance['kind'] == 'native_ios_fixture'
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

  def native_capture_input?(path)
    path.match?(%r{\A(?:lib|assets|licenses|android|ios|third_party)/}) ||
      %w[pubspec.yaml pubspec.lock .fvmrc .metadata tool/native_public_app_media_capture.dart
         test/fixtures/collect_repository_fixture.dart test_driver/integration_test.dart].include?(path)
  end

  # Current native publication packets bind the retained execution and review.
  # Historical inventories remain compatible with the original bundle checks.
  def verify_native_provenance!(manifest, provenance)
    report = evidence_json(provenance.fetch('capture_report'), provenance.fetch('capture_report_sha256'))
    review = evidence_json(provenance.fetch('visual_review'), provenance.fetch('visual_review_sha256'))
    log_path = provenance.fetch('native_drive_log')
    log_hash = provenance.fetch('native_drive_log_sha256')
    raise 'Invalid native capture log hash' unless log_hash.match?(/\A[0-9a-f]{64}\z/)
    log = AssetManifestIntegrity.read_regular(@root, log_path, max_bytes: 8 * 1024 * 1024) { |io| io.read }
    raise 'Native capture log changed' unless Digest::SHA256.hexdigest(log) == log_hash
    bundle = report.fetch('bundle_manifest')
    bundle.each do |path, digest|
      AssetManifestIntegrity.validate_relative!(path)
      raise 'Invalid native bundle manifest hash' unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
    end
    raise 'Native installed-bundle binding differs' unless bundle.key?('Info.plist') &&
      Digest::SHA256.hexdigest(JSON.generate(bundle.sort.to_h)) == provenance['bundle_manifest_sha256'] &&
      report['installed_matches_retained_bundle'] == true
    raise 'Native capture execution is incomplete' unless report['kind'] == 'native_ios_fixture' &&
      report['status'] == 'captured_pending_visual_review' && report['native_capture_passed'] == true &&
      provenance['native_capture_passed'] == true && report['errors'] == [] &&
      report['source_files_unchanged_before_build'] == true &&
      report['runtime_before_sha256'] == manifest['runtime_sha256'] &&
      report['runtime_after_sha256'] == manifest['runtime_sha256'] &&
      %w[provider_calls hosted_calls database_calls].all? { |key| report[key] == 0 } &&
      report.fetch('commands').all? { |row| row['exit_code'] == 0 } &&
      report.fetch('commands').map { |row| row['name'] }.uniq.length == report.fetch('commands').length &&
      %w[native-drive installed-bundle].all? { |name| report.fetch('commands').any? { |row| row['name'] == name } } &&
      report.fetch('commands').any? { |row| %w[native-build native-direct-build].include?(row['name']) } &&
      report.fetch('commands').find { |row| row['name'] == 'native-drive' }['stdout_sha256'] == log_hash &&
      log.include?('collect_native_media:complete:7:network-attempts=0')
    if provenance['source_binding_review']
      binding = evidence_json(provenance.fetch('source_binding_review'), provenance.fetch('source_binding_review_sha256'))
      raw = evidence_json(provenance.fetch('raw_capture_report'), provenance.fetch('raw_capture_report_sha256'))
      raise 'Native source-binding review differs' unless binding['status'] == 'pass' &&
        report['source_binding_review_sha256'] == provenance['source_binding_review_sha256'] &&
        report['raw_capture_report_sha256'] == provenance['raw_capture_report_sha256'] &&
        binding['kind'] == 'native_capture_source_binding_review' &&
        binding['runtime_sha256'] == manifest['runtime_sha256'] && binding['runtime_matches_capture'] == true &&
        binding['native_input_checkout_changes'] == [] && binding['native_input_export_changes'] == [] &&
        report['native_capture_inputs_unchanged'] == true &&
        [[], ['Source drift during native capture']].include?(raw['errors']) &&
        report['raw_run_errors_retained'] == raw['errors'] &&
        (raw.keys - %w[status native_capture_passed errors]).all? { |key| report[key] == raw[key] } &&
        (binding.fetch('post_export_checkout_changes') + binding.fetch('export_source_changes_during_build')).none? { |path| native_capture_input?(path) }
      inputs = binding.fetch('native_capture_inputs')
      raise 'Native input binding is incomplete' unless !inputs.empty? && inputs.length == binding['native_capture_input_count']
      export = evidence_json(provenance.fetch('source_export'), provenance.fetch('source_export_sha256'))
      driver = evidence_json(provenance.fetch('driver_source_binding'), provenance.fetch('driver_source_binding_sha256'))
      expected_inputs = export.fetch('source_sha256').select { |path, _| native_capture_input?(path) }
      raise 'Native capture driver binding differs' unless driver['path'] == 'test_driver/integration_test.dart' && export['destination'] == report['source']
      expected_inputs[driver['path']] = driver.fetch('sha256')
      raise 'Native input inventory differs from source export' unless expected_inputs == inputs
      inputs.each do |path, expected|
        raise 'Invalid native compilation input' unless native_capture_input?(path)
        preserved = provenance['preserved_publication_input']
        if path == PUBLISHED_METADATA_INPUT && preserved
          raise 'Preserved asset approval input differs' unless preserved['path'] == path && preserved['sha256'] == expected
          path = preserved.fetch('preserved')
        end
        bytes = AssetManifestIntegrity.read_regular(@root, path, max_bytes: 128 * 1024 * 1024) { |io| io.read }
        raise 'Native compilation input changed' unless Digest::SHA256.hexdigest(bytes) == expected
      end
    else
      raise 'Native source binding incomplete' unless report['source_files_unchanged_after_capture'] == true &&
        report['checkout_matches_export_after_capture'] == true
    end
    entries = manifest.fetch('screens')
    raise 'Native visual review is incomplete' unless review['status'] == 'pass' && review['native_acceptance'] == false &&
      review['capture_report_sha256'] == provenance['capture_report_sha256'] && review['runtime_sha256'] == manifest['runtime_sha256'] &&
      entries.length == 7 && entries.map { |entry| entry['id'] }.uniq.length == 7 &&
      entries.map { |entry| entry['id'] }.sort == NATIVE_MEDIA_ROUTES.keys.sort &&
      report.fetch('captures').map { |row| row['id'] }.sort == entries.map { |entry| entry['id'] }.sort &&
      review.fetch('screens').map { |row| row['id'] }.sort == entries.map { |entry| entry['id'] }.sort
    entries.each do |entry|
      capture = report.fetch('captures').find { |row| row['id'] == entry['id'] }
      inspected = review.fetch('screens').find { |row| row['id'] == entry['id'] }
      marker = "collect_native_media:pass:#{entry['id']}:#{entry['app_route']}:#{capture['marker']}"
      raise 'Native route/image review is incomplete' unless capture['marker_verified'] == true &&
        NATIVE_MEDIA_ROUTES[entry['id']] == entry['app_route'] &&
        log.include?(marker) && capture['path'] == entry['capture'] &&
        %w[sha256 width height app_route platform].all? { |key| capture[key] == entry[key] } &&
        inspected['sha256'] == entry['sha256'] && inspected['reviewed_for_website'] == true
    end
  rescue KeyError, AssetManifestIntegrity::InvalidPath, JSON::ParserError
    raise 'Native screenshot evidence is missing or invalid'
  end

  def verify_browser_diagnostic_sources!(report)
    cua = report['capture_engine'] == 'cua_repl'
    inputs = cua ? CUA_CAPTURE_INPUTS : BROWSER_DIAGNOSTIC_INPUTS
    diagnostic_sources = inputs.to_h do |relative|
      path = AssetManifestIntegrity.regular_path!(@root, relative)
      [relative, Digest::SHA256.file(path).hexdigest]
    end
    raise 'Browser diagnostic observer binding is incomplete or changed' unless
      report['diagnostic_observer_sources_before'] == diagnostic_sources &&
      report['diagnostic_observer_sources_after'] == diagnostic_sources &&
      report['capture_recorder_sha256'] == diagnostic_sources[cua ? CUA_CAPTURE_INPUTS.first : 'scripts/qa/public_browser_app_media.mjs']
    if cua
      raise 'Cua browser observations are incomplete' unless report['legacy_browser_recorder_executed'] == false &&
        report['csp_remote_blocking_verified'] == true && report['capture_observations'].is_a?(Array) &&
        report['capture_observations'].map { |r| r['id'] }.sort == report.fetch('captures').map { |r| r['id'] }.sort
      report['capture_observations'].each do |observation|
        capture = report.fetch('captures').find { |r| r['id'] == observation['id'] }
        ax = observation['ax_path']
        raise 'Cua browser observations differ from the captured route' unless
          observation['sha256'] == capture['sha256'] && observation['app_route'] == capture['app_route'] &&
          observation['url_route_verified'] == true && observation['console_errors'] == [] && observation['original_png_unedited'] == true &&
          ax.is_a?(String) && ax.start_with?('.cache/') && observation['ax_sha256'].is_a?(String) && observation['ax_sha256'].match?(/\A[a-f0-9]{64}\z/)
        bytes = AssetManifestIntegrity.read_regular(@root, ax, max_bytes: 2 * 1024 * 1024) { |io| io.read }
        raise 'Cua browser observations changed after capture' unless Digest::SHA256.hexdigest(bytes) == observation['ax_sha256'] && bytes.include?(capture['app_route'])
      end
    end
  end

  def verify_browser_provenance!(manifest, provenance)
    raise 'Browser screenshot provenance is incomplete' unless provenance['kind'] == 'browser_flutter_fixture' &&
      provenance['native_capture_passed'] == false
    report = evidence_json(provenance.fetch('capture_report'), provenance.fetch('capture_report_sha256'))
    review = evidence_json(provenance.fetch('visual_review'), provenance.fetch('visual_review_sha256'))
    verify_browser_diagnostic_sources!(report)
    if manifest['runtime_fingerprint_version'] == 4
      raise 'Browser reachable-source closure differs' unless report['runtime_fingerprint_version'] == 4 &&
        report['browser_entrypoint'] == 'tool/public_app_media_capture.dart' &&
        report['sources_before'] == browser_source_snapshot && report['sources_after'] == browser_source_snapshot
    end
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
    if report.key?('isolated_source_export')
      bindings = report['generated_bindings_before']
      pubspec = YAML.safe_load(File.read(File.join(@root, 'pubspec.yaml')))
      expected_local = {pubspec.fetch('name', 'collect_app') => report['source_root']}
      %w[dependencies dev_dependencies dependency_overrides].each do |section|
        pubspec.fetch(section, {}).each do |name, dependency|
          next unless dependency.is_a?(Hash) && dependency.key?('path')
          expected_local[name] = "#{report['source_root']}/#{AssetManifestIntegrity.validate_relative!(dependency.fetch('path'))}"
        end
      end
      raise 'Browser compilation source binding is incomplete' unless
        [true, false].include?(report['isolated_source_export']) &&
        report['source_root'].is_a?(String) && report['source_root'].start_with?('/') &&
        report['checkout_runtime_before_sha256'] == manifest['runtime_sha256'] &&
        report['checkout_runtime_after_sha256'] == manifest['runtime_sha256'] &&
        report['generated_bindings_unchanged'] == true && bindings.is_a?(Hash) &&
        bindings.keys.sort == %w[.dart_tool/package_config.json .flutter-plugins-dependencies].sort &&
        bindings == report['generated_bindings_after'] &&
        bindings.values.all? { |sha| sha.is_a?(String) && sha.match?(/\A[0-9a-f]{64}\z/) } &&
        report['resolved_local_bindings_before'] == expected_local &&
        report['resolved_local_bindings_after'] == expected_local &&
        report['capture_recorder_sha256'].is_a?(String) &&
        report['capture_recorder_sha256'].match?(/\A[0-9a-f]{64}\z/)
    end
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
