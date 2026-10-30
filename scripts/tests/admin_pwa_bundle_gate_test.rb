#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'digest'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class AdminPwaBundleGateTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  OPTIONAL_RENDERER_PATHS = %w[
    canvaskit/canvaskit.js.symbols canvaskit/chromium/canvaskit.js.symbols
    canvaskit/experimental_webparagraph/canvaskit.js
    canvaskit/experimental_webparagraph/canvaskit.js.symbols
    canvaskit/experimental_webparagraph/canvaskit.wasm
    canvaskit/skwasm.js canvaskit/skwasm.js.symbols canvaskit/skwasm.wasm
    canvaskit/skwasm_heavy.js canvaskit/skwasm_heavy.js.symbols canvaskit/skwasm_heavy.wasm
    canvaskit/wimp.js canvaskit/wimp.js.symbols canvaskit/wimp.wasm
  ].freeze

  def test_manifest_gate_rejects_an_empty_compiled_bundle
    Dir.mktmpdir('collect-admin-bundle-gate-') do |build_dir|
      File.write(File.join(build_dir, 'main.dart.js'), '')
      _out, err, status = Open3.capture3(
        { 'ADMIN_PWA_BUILD_DIR' => build_dir },
        'bash', File.join(ROOT, 'scripts/admin_pwa_manifest_gate.sh')
      )
      refute status.success?
      assert_includes err, 'missing or empty build/web/main.dart.js'

      File.write(File.join(build_dir, 'main.dart.js'), 'synthetic compiled bytes')
      _out, err, status = Open3.capture3(
        { 'ADMIN_PWA_BUILD_DIR' => build_dir },
        'bash', File.join(ROOT, 'scripts/admin_pwa_manifest_gate.sh')
      )
      refute status.success? # Other PWA files were deliberately not built.
      refute_includes err, 'missing or empty build/web/main.dart.js'
    end
  end

  def test_release_builder_rejects_successful_compile_without_bundle
    Dir.mktmpdir('collect-admin-builder-gate-') do |root|
      scripts = File.join(root, 'scripts')
      prepare_diagnostic_builder_fixture(root)
      fake_flutter = File.join(root, 'fake-flutter')
      File.write(fake_flutter, <<~SH)
        #!/usr/bin/env bash
        mkdir -p build/web
        : > build/web/main.dart.js
      SH
      FileUtils.chmod(0o755, fake_flutter)
      env = {
        'FLUTTER' => fake_flutter,
        'COLLECT_SKIP_DOTENV' => '1',
        # This fixture tests missing compiler output, independent of a caller's
        # selected shipping backend and unavailable provider configuration.
        'COLLECT_BACKEND' => 'cloudflare',
      }
      _out, err, status = Open3.capture3(
        env, 'bash', File.join(scripts, 'admin_pwa_release_build.sh'),
        chdir: root
      )
      refute status.success?
      assert_includes err, 'did not produce a nonempty main.dart.js bundle'
    end
  end

  def test_release_builder_checks_compiled_labels_before_asset_postprocessing
    Dir.mktmpdir('collect-admin-compiled-labels-') do |root|
      prepare_diagnostic_builder_fixture(root)
      fake_flutter = File.join(root, 'fake-flutter')
      File.write(fake_flutter, <<~'SH')
        #!/usr/bin/env bash
        mkdir -p build/web
        printf 'window.syntheticCompilerFixture = true;' > build/web/main.dart.js
      SH
      FileUtils.chmod(0o755, fake_flutter)
      env = { 'FLUTTER' => fake_flutter, 'COLLECT_BACKEND' => 'cloudflare' }
      wrapper = File.join(root, 'scripts/admin_pwa_release_build.sh')
      out, err, status = Open3.capture3(env, 'bash', wrapper, chdir: root)
      refute status.success?
      assert_includes err, 'Client diagnostic source binding failed'
      assert_empty out

      File.write(fake_flutter, <<~'SH')
        #!/usr/bin/env bash
        python3 - "$@" <<'PY'
        import json, sys
        from pathlib import Path
        config = next(value.split('=', 1)[1] for value in sys.argv
                      if value.startswith('--dart-define-from-file='))
        labels = json.loads(Path(config).read_text())
        Path('build/web').mkdir(parents=True, exist_ok=True)
        Path('build/web/main.dart.js').write_text('const syntheticCompilerLabels=' + json.dumps(
            [labels['COLLECT_BUILD_SOURCE_ID'], labels['COLLECT_BUILD_VERSION']]) + ';')
        PY
      SH
      # Stop deliberately at the next stage: this fixture proves wrapper
      # ordering and actual label inspection, not a Flutter compilation.
      File.write(File.join(root, 'scripts/admin_cloudflare_assets.py'), 'raise SystemExit(67)')
      out, err, status = Open3.capture3(env, 'bash', wrapper, chdir: root)
      assert_equal 67, status.exitstatus, err
      proof = JSON.parse(out)
      assert_equal 'quoted_label_bytes_present', proof.fetch('verification_scope')
      assert_equal '1.2.4+23', proof.fetch('build_version')
      assert_equal false, proof.fetch('signing_or_deployment_acceptance')
      assert_equal Digest::SHA256.file(File.join(root, 'build/web/main.dart.js')).hexdigest,
                   proof.fetch('sha256')
    end
  end

  def test_default_builder_rejects_missing_supabase_configuration_before_compiler
    Dir.mktmpdir('collect-admin-default-config-') do |root|
      scripts = File.join(root, 'scripts')
      FileUtils.mkdir_p(File.join(scripts, 'supabase'))
      %w[scripts/admin_pwa_release_build.sh scripts/supabase/admin_build_config.py].each do |name|
        FileUtils.cp(File.join(ROOT, name), File.join(root, name))
      end
      marker = File.join(root, 'compiler-invoked')
      fake_flutter = File.join(root, 'fake-flutter')
      File.write(fake_flutter, "#!/usr/bin/env bash\ntouch '#{marker}'\nexit 40\n")
      FileUtils.chmod(0o755, fake_flutter)
      env = { 'FLUTTER' => fake_flutter, 'COLLECT_BACKEND' => nil,
              'SUPABASE_URL' => nil, 'SUPABASE_PUBLISHABLE_KEY' => nil,
              'APP_PUBLIC_URL' => nil, 'ADMIN_APP_URL' => nil,
              'FLUTTER_ADMIN_WEB_BUILD_ARGS' => nil }
      _out, err, status = Open3.capture3(env, 'bash', File.join(scripts, 'admin_pwa_release_build.sh'), chdir: root)
      refute status.success?
      assert_includes err, 'Invalid Admin public build configuration'
      refute File.exist?(marker), 'Unconfigured default must fail before invoking Flutter'
    end
  end

  def test_default_hosting_gate_requires_supabase_metadata
    with_postprocessed_fixture do |build_dir, _|
      env = { 'ADMIN_PWA_BUILD_DIR' => build_dir, 'COLLECT_BACKEND' => nil }
      command = ['bash', File.join(ROOT, 'scripts/admin_pwa_hosting_gate.sh')]
      out, err, status = Open3.capture3(env, *command)
      refute status.success?
      assert_includes out + err, 'version.json must declare the explicitly selected Collect backend'
      path = File.join(build_dir, 'version.json')
      version = JSON.parse(File.read(path))
      version.merge!('backend' => 'supabase', 'supabase_project_ref' => 'rrlduytparvsjfmegalh',
                     'authentication' => 'supabase_auth_cookie_with_email_verification', 'admin_transport' => 'same_origin_static_proxy',
                     'supabase_schema_sha256' => 'a' * 64, 'legacy_data_import_required' => true,
                     'supabase_qualification_complete' => false)
      File.write(path, JSON.generate(version))
      out, err, status = Open3.capture3(env, *command)
      assert status.success?, out + err
      version['authentication'] = 'supabase_auth_cookie_with_totp'
      File.write(path, JSON.generate(version))
      out, err, status = Open3.capture3(env, *command)
      refute status.success?, 'Retired authenticator policy metadata must not satisfy the current normal gate'
      assert_includes out + err, 'Supabase build requires project, migration, identity and qualification metadata'
    end
  end

  def test_postprocessor_protects_both_html_shell_paths_without_changing_payloads
    with_postprocessed_fixture do |build_dir, original_main|
      headers = File.read(File.join(build_dir, '_headers'))
      ['/', '/index.html'].each do |route|
        block = headers.split("#{route}\n", 2).last.split(/^\//, 2).first
        assert_includes block, 'Cache-Control: no-store, no-transform'
      end
      assert_includes headers, "Cache-Control: public, max-age=31536000, immutable"
      assert_equal original_main, File.binread(File.join(build_dir, 'main.dart.js'))
      out, err, status = hosting_gate(build_dir)
      assert status.success?, out + err
    end
  end

  def test_admin_favicon_redirect_reuses_the_approved_png_and_stays_out_of_the_runtime_cache
    with_postprocessed_fixture do |build_dir, _|
      assert_equal "/favicon.ico /icons/collect-web-512.png 302\n", File.read(File.join(build_dir, '_redirects'))
      assert_equal "cae23ce3562e8aac2e248e7b22f7feed194f4fcfd2b57725ec1026f064bb0ad9",
                   Digest::SHA256.file(File.join(build_dir, 'icons/collect-web-512.png')).hexdigest
      worker = File.read(File.join(build_dir, 'custom-sw.js'))
      refute_includes worker, './_redirects'
      assert_empty Dir.glob(File.join(build_dir, '_build', '**', '_redirects'))
      out, err, status = hosting_gate(build_dir)
      assert status.success?, out + err
    end
  end

  def test_hosting_gate_rejects_missing_external_permanent_and_html_favicon_routes
    with_postprocessed_fixture do |build_dir, _|
      path = File.join(build_dir, '_redirects')
      [nil, "/favicon.ico https://unreviewed.example/icon.png 302\n",
       "/favicon.ico /icons/collect-web-512.png 301\n",
       "/favicon.ico /index.html 200\n"].each do |rule|
        rule ? File.write(path, rule) : FileUtils.rm_f(path)
        out, err, status = hosting_gate(build_dir)
        refute status.success?, rule.inspect
        assert_includes out + err, 'Admin favicon must temporarily redirect to the approved same-origin Collect PNG'
      end
    end
  end

  def test_production_header_preparation_admits_same_origin_captcha_and_preserves_the_allowlist
    source = File.read(File.join(ROOT, 'web/_headers'))
    assert_equal ['https://api.collect.ikanisa.com'], source[/frame-src ([^;]+);/, 1].split
    with_postprocessed_fixture do |build_dir, _|
      headers = File.read(File.join(build_dir, '_headers'))
      assert_equal ["'self'", 'https://api.collect.ikanisa.com'], headers[/frame-src ([^;]+);/, 1].split
      assert_equal ["'self'"], headers[/connect-src ([^;]+);/, 1].split
      assert_includes headers, "frame-ancestors 'none'"
      assert_includes headers, 'X-Frame-Options: DENY'
      out, err, status = hosting_gate(build_dir)
      assert status.success?, out + err
    end
    assert_equal source, File.read(File.join(ROOT, 'web/_headers'))
  end

  def test_hosting_gate_rejects_missing_same_origin_or_unreviewed_frame_sources
    with_postprocessed_fixture do |build_dir, _|
      path = File.join(build_dir, '_headers')
      complete = File.read(path)
      original = "frame-src 'self' https://api.collect.ikanisa.com;"
      ['', 'frame-src https://api.collect.ikanisa.com;', "frame-src 'none';",
       'frame-src *;', "frame-src 'self' https://unreviewed.example;",
       "unused-frame-src 'self' https://api.collect.ikanisa.com;",
       original + " frame-src 'self';"].each do |policy|
        unsafe = complete.sub(original, policy)
        refute_equal complete, unsafe
        File.write(path, unsafe)
        out, err, status = hosting_gate(build_dir)
        refute status.success?, policy
        assert_includes out + err, 'Admin frames must allow self and only the reviewed API origin'
      end
    end
  end

  def test_hosting_gate_rejects_transformable_html_for_either_shell_path
    with_postprocessed_fixture do |build_dir, _|
      path = File.join(build_dir, '_headers')
      complete = File.read(path)
      ['/', '/index.html'].each do |route|
        unsafe = complete.sub("#{route}\n  Cache-Control: no-store, no-transform", "#{route}\n  Cache-Control: no-store")
        refute_equal complete, unsafe
        File.write(path, unsafe)
        out, err, status = hosting_gate(build_dir)
        refute status.success?
        assert_includes out + err, "route #{route} must include Cache-Control: no-store, no-transform"
      end
    end
  end


  def test_public_shipping_configuration_preserves_both_hosts_and_canonical_api_routing
    public_config = JSON.parse(File.read(File.join(ROOT, 'deploy/admin.wrangler.jsonc')))
    candidate = JSON.parse(File.read(File.join(ROOT, 'deploy/platform-admin/wrangler.jsonc')))
    api = JSON.parse(File.read(File.join(ROOT, 'deploy/platform-api/wrangler.jsonc')))
    configurations = {
      'deploy/admin.wrangler.jsonc' => [public_config, 'collect-admin', 'https://admin.collect.ikanisa.com'],
      'deploy/platform-admin/wrangler.jsonc' => [candidate, 'collect-platform-admin', 'https://platform-admin.collect.ikanisa.com']
    }
    proxy = File.join(ROOT, 'deploy/platform-admin/src/index.js')
    configurations.each do |path, (config, name, origin)|
      assert_equal name, config.fetch('name')
      assert_equal origin, config.fetch('vars').fetch('ADMIN_ORIGIN')
      assert_equal '2026-10-14', config.fetch('compatibility_date')
      assert_equal proxy, File.expand_path(config.fetch('main'), File.dirname(File.join(ROOT, path)))
      assert_equal [{ 'binding' => 'PLATFORM_API', 'service' => 'collect-platform-api' }], config.fetch('services')
      assert_equal 'ASSETS', config.fetch('assets').fetch('binding')
      assert_equal 'single-page-application', config.fetch('assets').fetch('not_found_handling')
      assert_equal ['/api', '/api/*'], config.fetch('assets').fetch('run_worker_first')
      assert_equal [origin.delete_prefix('https://')], config.fetch('routes').map { |route| route.fetch('pattern') }
      assert config.fetch('routes').all? { |route| route.fetch('custom_domain') == true }
      assert_includes api.fetch('vars').fetch('ADMIN_ORIGINS').split(','), origin
    end
    assert_equal File.join(ROOT, 'build/web'), File.expand_path(public_config.fetch('assets').fetch('directory'), File.join(ROOT, 'deploy'))
    assert_equal true, public_config.fetch('workers_dev')
    assert_equal true, public_config.fetch('preview_urls')
    assert_equal false, public_config.fetch('routes').first.fetch('previews_enabled')
  end

  def test_supabase_proxies_preserve_host_authority_and_never_serve_api_failures_as_html
    script = <<~'JS'
      import assert from 'node:assert/strict';
      import {readFileSync} from 'node:fs';
      import {resolve,dirname} from 'node:path';
      import {pathToFileURL} from 'node:url';
      import {SUPABASE_ORIGIN} from './deploy/platform-admin/src/supabase-transport.js';
      for(const path of ['deploy/admin.wrangler.jsonc','deploy/platform-admin/wrangler.jsonc']){
        const config=JSON.parse(readFileSync(path,'utf8'));
        const {createAdminWorker}=await import(pathToFileURL(resolve(dirname(path),config.main)));
        const origin=config.vars.ADMIN_ORIGIN;
        let forwarded=null,upstreamCalls=0,assetReads=0,legacyCalls=0;
        const request=new Request(origin+'/api/admin/auth/session?cursor=a%2Bb&cursor=c',{headers:{Origin:origin,Cookie:'__Host-collect_admin=transport_fixture'}});
        const cookie='__Host-collect_admin=transport_fixture; Path=/; Secure; HttpOnly; SameSite=Strict';
        const worker=createAdminWorker({fetchImpl:async received=>{
          upstreamCalls++;forwarded=received;
          return Response.json({user:null},{headers:{'Set-Cookie':cookie,'Cache-Control':'public'}});
        }});
        // Explicit Supabase test inputs qualify this adapter at both configured
        // host identities; they do not change either shipping configuration.
        const env={...config.vars,COLLECT_BACKEND:'supabase',SUPABASE_URL:SUPABASE_ORIGIN,
          ASSETS:{fetch(){assetReads++;throw new Error('Unexpected SPA fallback');}},
          PLATFORM_API:{fetch(){legacyCalls++;throw new Error('Unexpected legacy fallback');}}};
        const response=await worker.fetch(request,env);
        assert.equal(response.status,200);assert.equal(upstreamCalls,1);
        assert.equal(forwarded.url,SUPABASE_ORIGIN+'/functions/v1/admin-api/api/admin/auth/session?cursor=a%2Bb&cursor=c');
        assert.equal(forwarded.method,'GET');
        assert.equal(forwarded.headers.get('Origin'),origin);assert.equal(forwarded.headers.get('Cookie'),'__Host-collect_admin=transport_fixture');
        assert.equal(response.headers.get('Set-Cookie'),cookie);assert.match(response.headers.get('Cache-Control'),/\bno-store\b/);
        assert.deepEqual(await response.json(),{user:null});
        for(const [url,fields,status,code] of [
          [origin+'/api/unknown',{},404,'not_found'],
          [origin+'/api/admin/auth/session',{SUPABASE_URL:undefined},503,'backend_configuration_invalid'],
          ['https://unconfigured.example/api/admin/auth/session',{},403,'origin_denied'],
        ]){
          const result=await worker.fetch(new Request(url),{...env,...fields});
          assert.equal(result.status,status);assert.match(result.headers.get('Content-Type'),/^application\/json/);
          assert.match(result.headers.get('Cache-Control'),/\bno-store\b/);assert.equal((await result.json()).error.code,code);
          assert.equal(upstreamCalls,1,'Refused requests must not reach the upstream');
        }
        const unavailable=createAdminWorker({fetchImpl:async()=>{upstreamCalls++;throw new Error('Synthetic lost upstream response');}});
        const uncertain=await unavailable.fetch(request,env);
        assert.equal(uncertain.status,502);assert.match(uncertain.headers.get('Content-Type'),/^application\/json/);
        assert.match(uncertain.headers.get('Cache-Control'),/\bno-store\b/);
        assert.deepEqual(await uncertain.json(),{code:'proxy_outcome_unknown',reason:'proxy_upstream_failure'});
        assert.equal(upstreamCalls,2,'A dispatched read must never be automatically retried');
        assert.equal(assetReads,0);assert.equal(legacyCalls,0);
      }
    JS
    out, err, status = Open3.capture3('node', '--input-type=module', '-', stdin_data: script, chdir: ROOT)
    assert status.success?, out + err
  end

  def test_non_wasm_precache_keeps_both_runtime_variants_and_all_required_assets
    required = %w[
      canvaskit/canvaskit.js canvaskit/canvaskit.wasm
      canvaskit/chromium/canvaskit.js canvaskit/chromium/canvaskit.wasm
      canvaskit/future-runtime.wasm assets/AssetManifest.bin assets/AssetManifest.bin.json
      assets/FontManifest.json assets/assets/typefaces/Inter-Variable.ttf
      assets/packages/font_awesome_flutter/lib/fonts/fa-brands-400.ttf
      assets/shaders/ink_sparkle.frag assets/assets/marketing/rwanda/community-savings.png
      assets/assets/group_covers/rwanda/covers/rw-01-neighbourhood-ikimina-v1.webp
    ]
    optional = OPTIONAL_RENDERER_PATHS
    payloads = (required + optional).to_h { |path| [path, "fixture bytes for #{path}"] }
    fresh_bootstrap = reviewed_bootstrap
      .sub(/_build\/[a-f0-9]{64}\//, '__COLLECT_ADMIN_ASSET_BASE__')
      .sub(/collect-admin-[a-f0-9]{16}/, '__COLLECT_ADMIN_SW_VERSION__')
    [reviewed_bootstrap, fresh_bootstrap].each do |bootstrap_source|
      with_postprocessed_fixture(runtime_files: payloads, bootstrap_source: bootstrap_source) do |build_dir, _|
      worker = File.read(File.join(build_dir, 'custom-sw.js'))
      urls = JSON.parse(worker[/const CACHE_URLS = (\[.*?\]);/m, 1])
      hashes = JSON.parse(worker[/const CACHE_HASHES = (\{.*?\});/m, 1])
      base = File.read(File.join(build_dir, 'flutter_bootstrap.js'))[/var adminAssetBase = '([^']+)'/, 1]
      assert_equal urls.sort, hashes.keys.sort
      (required + %w[main.dart.js icons/collect-web-512.png]).each do |path|
        assert_includes urls, "./#{base}#{path}"
      end
      optional.each do |path|
        refute_includes urls, "./#{base}#{path}"
        refute hashes.key?("./#{base}#{path}")
      end
      payloads.each do |path, original|
        assert_equal original, File.binread(File.join(build_dir, path))
        assert_equal original, File.binread(File.join(build_dir, base, path))
      end
      urls.each do |url|
        path = url == './' ? 'index.html' : url.delete_prefix('./')
        assert_equal Digest::SHA256.file(File.join(build_dir, path)).hexdigest, hashes.fetch(url)
      end
      out, err, status = hosting_gate(build_dir)
      assert status.success?, out + err
      end
    end
  end

  def test_filesystem_metadata_is_preserved_but_never_versioned_or_precached
    metadata = {'assets/._lazy.txt' => 'retained AppleDouble bytes', 'assets/nested/.DS_Store' => 'retained Finder bytes'}
    with_postprocessed_fixture(runtime_files: metadata.merge('assets/lazy.txt' => 'real runtime bytes')) do |build_dir, _|
      worker = File.read(File.join(build_dir, 'custom-sw.js'))
      urls = JSON.parse(worker[/const CACHE_URLS = (\[.*?\]);/m, 1])
      hashes = JSON.parse(worker[/const CACHE_HASHES = (\{.*?\});/m, 1])
      base = File.read(File.join(build_dir, 'flutter_bootstrap.js'))[/var adminAssetBase = '([^']+)'/, 1]
      metadata.each do |path, bytes|
        assert_equal bytes, File.binread(File.join(build_dir, path))
        refute File.exist?(File.join(build_dir, base, path))
        refute urls.any? { |url| url.include?(path) }
        refute hashes.keys.any? { |url| url.include?(path) }
      end
      assert_includes urls, "./#{base}assets/lazy.txt"
    end
  end

  def test_unreviewed_renderer_inputs_retain_the_complete_precache
    payloads = OPTIONAL_RENDERER_PATHS.to_h { |path| [path, "optional fixture #{path}"] }
    alternatives = [
      reviewed_config.merge('engineRevision' => 'future-engine'),
      reviewed_config.merge('useLocalCanvasKit' => false),
      reviewed_config.merge('builds' => reviewed_config.fetch('builds') + [{'compileTarget' => 'dart2wasm', 'renderer' => 'skwasm'}]),
      reviewed_config.merge('builds' => []),
      nil, true,
    ].map { |config| reviewed_bootstrap.sub(/^_flutter\.buildConfig = .*;$/, "_flutter.buildConfig = #{JSON.generate(config)};") }
    alternatives += [
      reviewed_bootstrap.sub(/_flutter\.loader\.load\([\s\S]*\z/, "const opts = {entrypointBaseUrl: adminAssetBase, assetBase: adminAssetBase, canvasKitBaseUrl: adminAssetBase + 'canvaskit/', canvasKitVariant: 'experimentalWebParagraph'};\n_flutter.loader.load({config: opts});"),
      reviewed_bootstrap.sub('_flutter.loader.load(', "_flutter.buildConfig.builds.unshift(skwasmBuild);\n_flutter.loader.load("),
      reviewed_bootstrap.sub("canvasKitBaseUrl: adminAssetBase + 'canvaskit/',", "canvasKitBaseUrl: adminAssetBase + 'canvaskit/', canvasKitVariant: 'experimentalWebParagraph',"),
    ]
    alternatives.each do |bootstrap|
      with_postprocessed_fixture(runtime_files: payloads, bootstrap_source: bootstrap) do |build_dir, _|
        worker = File.read(File.join(build_dir, 'custom-sw.js'))
        urls = JSON.parse(worker[/const CACHE_URLS = (\[.*?\]);/m, 1])
        base = File.read(File.join(build_dir, 'flutter_bootstrap.js'))[/var adminAssetBase = '([^']+)'/, 1]
        OPTIONAL_RENDERER_PATHS.each { |path| assert_includes urls, "./#{base}#{path}" }
      end
    end
  end

  private

  def prepare_diagnostic_builder_fixture(root)
    %w[scripts/admin_pwa_release_build.sh scripts/supabase/admin_build_config.py
       scripts/qa/client_diagnostic_identity.py].each do |name|
      destination = File.join(root, name)
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(File.join(ROOT, name), destination)
    end
    FileUtils.mkdir_p(File.join(root, 'lib'))
    File.write(File.join(root, 'lib/main_admin_cloudflare.dart'), "void main() {}\n")
    File.write(File.join(root, 'pubspec.yaml'), "name: synthetic_admin\nversion: 1.2.4+23\n")
    File.write(File.join(root, 'pubspec.lock'), "packages: {}\n")
  end

  def reviewed_config
    JSON.parse(reviewed_bootstrap[/^_flutter\.buildConfig = (.*);$/, 1])
  end

  def reviewed_bootstrap
    File.read(File.join(ROOT, 'scripts/tests/fixtures/admin_canvaskit_bootstrap.js'))
  end

  def hosting_gate(build_dir)
    Open3.capture3(
      { 'ADMIN_PWA_BUILD_DIR' => build_dir, 'COLLECT_BACKEND' => 'cloudflare' },
      'bash', File.join(ROOT, 'scripts/admin_pwa_hosting_gate.sh')
    )
  end

  def with_postprocessed_fixture(runtime_files: {}, bootstrap_source: nil)
    Dir.mktmpdir('collect-admin-html-integrity-') do |root|
      build_dir = File.join(root, 'build/web')
      FileUtils.mkdir_p(File.join(build_dir, 'icons'))
      FileUtils.mkdir_p(File.join(root, 'scripts/templates'))
      FileUtils.mkdir_p(File.join(root, 'lib/app/theme'))
      %w[scripts/templates/admin_pwa_service_worker.js lib/app/theme/collect_colors.dart].each do |name|
        FileUtils.cp(File.join(ROOT, name), File.join(root, name))
      end
      FileUtils.mkdir_p(File.join(root, 'web'))
      FileUtils.cp(File.join(ROOT, 'web/_headers'), File.join(root, 'web/_headers'))
      builder = File.read(File.join(ROOT, 'scripts/admin_pwa_release_build.sh'))
      header_marker = "python3 - <<'PY_HEADERS'\n"
      assert_equal 2, builder.split(header_marker, 2).length
      header_preparation = builder.split(header_marker, 2).last.split("\nPY_HEADERS\n", 2).first
      out, err, status = Open3.capture3('python3', '-c', header_preparation, chdir: root)
      assert status.success?, out + err
      FileUtils.cp(File.join(ROOT, 'web/robots.txt'), File.join(build_dir, 'robots.txt'))
      FileUtils.cp(File.join(ROOT, 'web/icons/collect-web-512.png'), File.join(build_dir, 'icons/collect-web-512.png'))
      %w[index.html flutter_bootstrap.js].each do |name|
        FileUtils.cp(File.join(ROOT, 'web', name), File.join(build_dir, name))
      end
      File.write(File.join(build_dir, 'flutter_bootstrap.js'), bootstrap_source) if bootstrap_source
      runtime_files.each do |path, bytes|
        target = File.join(build_dir, path)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite(target, bytes)
      end
      %w[manifest.json version.json].each { |name| File.write(File.join(build_dir, name), '{}') }
      original_main = 'window.syntheticPostprocessorFixture = true;'
      File.write(File.join(build_dir, 'main.dart.js'), original_main)
      builder = File.read(File.join(ROOT, 'scripts/admin_pwa_release_build.sh'))
      metadata = File.join(root, 'public-build-metadata.json')
      File.write(metadata, JSON.generate({ 'backend' => 'cloudflare' }))
      marker = "ruby -r digest -r json -r open3 <<'RUBY'\n"
      assert_equal 2, builder.split(marker, 2).length
      postprocessor = builder.split(marker, 2).last.split("\nRUBY\n", 2).first
      out, err, status = Open3.capture3(
        { 'COLLECT_ADMIN_BUILD_METADATA' => metadata },
        'ruby', '-r', 'digest', '-r', 'json', '-r', 'open3', '-e', postprocessor,
        chdir: root
      )
      assert status.success?, out + err
      yield build_dir, original_main
    end
  end
end
