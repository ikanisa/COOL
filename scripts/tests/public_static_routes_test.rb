# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../public_static_site_build'
require 'tmpdir'
require_relative '../qa/public_static_routes'

class PublicStaticRoutesTest < Minitest::Test
  def extract(source)
    PublicStaticRoutes.extract(source)
  end

  def test_page_alias_and_source_lines_ignore_unrelated_content
    routes = extract(<<~'RUBY')
      FAQ = { path: '/not-a-page/' }
      PAGES = [
        {path: '/', title: 'Home'},
        {path: '/trust/', aliases: ['/security/'], sections: [{path: '/not-a-route/'}]}
      ].freeze
    RUBY
    assert_equal ['/', '/trust/', '/security/'], routes.map { |route| route[:path] }
    assert_equal [3, 4, 4], routes.map { |route| route[:line] }
    assert_equal({ path: '/security/', line: 4, kind: 'alias', primary_route: '/trust/' }, routes.last)
  end

  def test_share_pages_and_redirects_ignore_dynamic_non_route_asset_writes
    routes = extract(<<~'RUBY')
      PAGES = [{path: '/'}]
      write_file(File.join(BUILD_DIR, "#{INDEXNOW_KEY}.txt"), "#{INDEXNOW_KEY}\n")
      write_file(route_file(page[:path]), page_html(page))
      write_file(File.join(BUILD_DIR, 'app', 'index.html'), share_landing_page_html(kind: :app))
      write_file(File.join(BUILD_DIR, '_redirects'), "/c/* /group-link/?slug=:splat 302\n/invite/* /app/?publicId=:splat 302\n")
    RUBY
    assert_equal ['/', '/app/', '/c/*', '/invite/*'], routes.map { |route| route[:path] }
    assert_equal 'share_landing', routes[1][:kind]
    assert_equal '/group-link/?slug=:splat', routes[2][:redirect_target]
    assert_equal 302, routes[2][:redirect_status]
  end

  def test_dynamic_page_alias_or_share_paths_are_rejected
    [
      'PAGES = [{path: route}]',
      'PAGES = [{path: "/", aliases: [route]}]',
      'PAGES = [{path: "/"}]; write_file(File.join(BUILD_DIR, route, "index.html"), share_landing_page_html(kind: :app))',
      'PAGES = [{path: "/"}]; write_file(route, share_landing_page_html(kind: :app))',
      'PAGES = [{path: "/"}]; write_file(File.join(BUILD_DIR, "app.html"), share_landing_page_html(kind: :app))'
    ].each do |source|
      assert_raises(RuntimeError) { extract(source) }
    end
  end

  def test_missing_invalid_or_ambiguous_catalog_is_rejected
    [
      'PAGES = [', 'OTHER = [{path: "/"}]', 'PAGES = []',
      'PAGES = pages', 'PAGES = [{path: "/"}]; PAGES = [{path: "/second/"}]',
      'PAGES = [{path: "/", path: "/other/"}]',
      'PAGES = [{path: "/", aliases: ["/"]}]',
      'PAGES = [{path: "https://example.invalid/"}]'
    ].each do |source|
      assert_raises(RuntimeError) { extract(source) }
    end
  end

  def test_dynamic_redirects_or_invalid_rules_are_rejected
    [
      'rules', '"/c/* /group-link/?slug=:splat 200\\n"',
      '"/c/* /group-link/?slug=:splat 302 unexpected\\n"',
      '"/c/* https://example.invalid/ 302\\n"'
    ].each do |body|
      assert_raises(RuntimeError) do
        extract("PAGES = [{path: '/'}]; write_file(File.join(BUILD_DIR, '_redirects'), #{body})")
      end
    end
  end

  def test_source_is_never_executed
    Dir.mktmpdir('collect-static-route-test-') do |directory|
      sentinel = File.join(directory, 'must-not-be-created')
      routes = extract("PAGES = [{path: '/'}]; File.write(#{sentinel.inspect}, 'executed'); abort('executed')")
      assert_equal ['/'], routes.map { |route| route[:path] }
      refute File.exist?(sentinel)
    end
  end

  def test_repository_static_routes_match_product_baseline_and_include_entry_paths
    root = PublicStaticRoutes::ROOT
    routes = extract(File.read(File.join(root, PublicStaticRoutes::SOURCE)))
    baseline = JSON.parse(File.read(File.join(root, 'docs/release/public-website-content-baseline.json')))
    baseline_paths = baseline.fetch('hashes').keys
    assert_equal baseline_paths.sort, routes.select { |route| %w[page alias].include?(route[:kind]) }.map { |route| route[:path] }.sort
    assert_equal ['/app/', '/c/', '/group-link/'], routes.select { |route| route[:kind] == 'share_landing' }.map { |route| route[:path] }.sort
    redirects = routes.select { |route| route[:kind] == 'redirect_pattern' }
    assert_equal ['/c/*', '/cookies/', '/invite/*', '/privacy-request/', '/subprocessors/'], redirects.map { |route| route[:path] }.sort
    {
      '/privacy-request/' => '/account-deletion/',
      '/cookies/' => '/privacy/#cookies',
      '/subprocessors/' => '/privacy/#sharing'
    }.each do |path, target|
      rule = redirects.find { |route| route[:path] == path }
      assert_equal target, rule.fetch(:redirect_target), path
      assert_equal 302, rule.fetch(:redirect_status), path
    end
    assert_equal 23, routes.length
  end
end

class PublicStaticBuildOutputTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  RENDERER = CollectPublicSite

  def setup
    @temporary = File.realpath(Dir.mktmpdir('collect-public-output-'))
    @root = File.join(@temporary, 'checkout')
    FileUtils.mkdir_p(File.join(@root, 'build'))
    @allowed = %w[build .cache].map { |name| File.join(@root, name) }
    @renderer = Object.new.extend(RENDERER)
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def mode(destination, explicit_path: destination)
    @renderer.public_build_destination_mode(destination, source_root: @root, allowed_roots: @allowed, explicit_path: explicit_path)
  end

  def publish(destination, explicit_path: destination, &render)
    @renderer.publish_public_build(destination, source_root: @root, allowed_roots: @allowed,
                                               explicit_path: explicit_path, &render)
  end

  def test_new_external_release_directory_is_created_without_touching_siblings
    sentinel = File.join(@temporary, 'unique-evidence.txt')
    File.write(sentinel, 'preserved evidence')
    destination = File.join(@temporary, 'release-1')
    assert_equal :create_external, mode(destination)
    publish(destination) do |staging|
      refute File.exist?(destination)
      File.write(File.join(staging, 'index.html'), 'completed release')
    end
    assert_equal 'completed release', File.read(File.join(destination, 'index.html'))
    assert_equal 'preserved evidence', File.read(sentinel)
    assert_empty Dir.glob(File.join(@temporary, '.collect-public-*'))
  end

  def test_existing_external_directory_and_its_contents_are_preserved
    destination = File.join(@temporary, 'release-1')
    Dir.mkdir(destination)
    sentinel = File.join(destination, 'index.html')
    File.write(sentinel, 'already published')
    assert_raises(ArgumentError) { mode(destination) }
    assert_equal 'already published', File.read(sentinel)
  end

  def test_external_parent_must_exist_and_path_must_be_explicit_absolute
    destination = File.join(@temporary, 'release-1')
    assert_raises(ArgumentError) { mode(destination, explicit_path: nil) }
    assert_raises(ArgumentError) { mode(destination, explicit_path: '../../release-1') }
    assert_raises(ArgumentError) { mode(destination, explicit_path: File.join(@temporary, 'x', '..', 'release-1')) }
    assert_raises(ArgumentError) { mode(destination, explicit_path: File.join(@temporary, 'other-release')) }
    assert_raises(ArgumentError) { mode(File.join(@temporary, 'missing', 'release-1')) }
    refute File.exist?(File.join(@temporary, 'missing'))
  end

  def test_symlink_destinations_and_ancestors_are_rejected_for_all_outputs
    real = File.join(@temporary, 'real')
    Dir.mkdir(real)
    alias_path = File.join(@temporary, 'alias')
    File.symlink(real, alias_path)
    assert_raises(ArgumentError) { mode(File.join(alias_path, 'release-1')) }
    assert_raises(ArgumentError) { mode(alias_path) }
    dangling = File.join(@temporary, 'dangling')
    File.symlink(File.join(@temporary, 'absent'), dangling)
    assert_raises(ArgumentError) { mode(dangling) }
    File.symlink(real, File.join(@root, 'build', 'aliased'))
    assert_raises(ArgumentError) { mode(File.join(@root, 'build', 'aliased', 'web')) }
    assert_empty Dir.children(real)
  end

  def test_regular_file_and_ancestor_cannot_be_replaced
    sentinel = File.join(@temporary, 'release-1')
    File.write(sentinel, 'not a build')
    assert_raises(ArgumentError) { mode(sentinel) }
    assert_raises(ArgumentError) { mode(File.join(sentinel, 'web')) }
    assert_equal 'not a build', File.read(sentinel)
  end

  def test_claiming_external_directory_fails_closed_if_it_appears_after_validation
    destination = File.join(@temporary, 'release-1')
    sentinel = File.join(destination, 'unique.txt')
    assert_raises(ArgumentError) do
      publish(destination) do |staging|
        File.write(File.join(staging, 'index.html'), 'completed candidate')
        Dir.mkdir(destination)
        File.write(sentinel, 'another owner')
      end
    end
    assert_equal 'another owner', File.read(sentinel)
    assert_equal ['unique.txt'], Dir.children(destination)
    assert_empty Dir.glob(File.join(@temporary, '.collect-public-*'))
  end

  def test_internal_build_replacement_still_works_and_never_selects_the_root
    destination = File.join(@root, 'build', 'public_web')
    FileUtils.mkdir_p(destination)
    File.write(File.join(destination, 'old.html'), 'previous build')
    assert_equal :replace_internal, mode(destination, explicit_path: nil)
    publish(destination, explicit_path: nil) do |staging|
      assert_equal 'previous build', File.read(File.join(destination, 'old.html'))
      File.write(File.join(staging, 'index.html'), 'new build')
    end
    assert_equal ['index.html'], Dir.children(destination)
    assert_equal 'new build', File.read(File.join(destination, 'index.html'))
    assert_raises(ArgumentError) { mode(File.join(@root, 'build')) }
    assert_raises(ArgumentError) { mode(@root) }
    assert_raises(ArgumentError) { mode(File.join(@root, 'lib', 'release-1')) }
  end

  def test_render_failure_preserves_an_internal_build_and_leaves_external_paths_available
    internal = File.join(@root, 'build', 'public_web')
    external = File.join(@temporary, 'release-1')
    Dir.mkdir(internal)
    File.write(File.join(internal, 'index.html'), 'previous build')
    [internal, external].each do |destination|
      assert_raises(IOError) do
        publish(destination) do |staging|
          File.write(File.join(staging, 'partial.html'), 'a partial asset')
          raise IOError, 'synthetic renderer failure'
        end
      end
      assert_empty Dir.glob(File.join(File.dirname(destination), '.collect-public-*'))
    end
    assert_equal 'previous build', File.read(File.join(internal, 'index.html'))
    refute File.exist?(external)
  end

  def test_internal_promotion_failure_restores_the_previous_build
    destination = File.join(@root, 'build', 'public_web')
    Dir.mkdir(destination)
    File.write(File.join(destination, 'index.html'), 'previous build')
    rename = File.method(:rename)
    fail_promotion = lambda do |from, to|
      raise Errno::EIO, 'synthetic promotion failure' if File.basename(from) == 'site' && to == destination

      rename.call(from, to)
    end
    File.stub(:rename, fail_promotion) do
      assert_raises(Errno::EIO) do
        publish(destination) { |staging| File.write(File.join(staging, 'index.html'), 'new build') }
      end
    end
    assert_equal 'previous build', File.read(File.join(destination, 'index.html'))
    assert_empty Dir.glob(File.join(File.dirname(destination), '.collect-public-*'))
  end

  def test_well_known_copy_publishes_real_associations_without_filesystem_metadata
    source = File.join(@root, 'web', '.well-known')
    FileUtils.mkdir_p(File.join(source, 'nested'))
    files = {
      'assetlinks.json' => '[{"relation":["delegate_permission/common.handle_all_urls"]}]',
      'apple-app-site-association' => '{"applinks":{"apps":[]}}',
      'security.txt' => "Contact: mailto:info@ikanisa.com\n"
    }
    files.each { |name, bytes| File.binwrite(File.join(source, name), bytes) }
    ['._assetlinks.json', '._apple-app-site-association', '.DS_Store'].each do |name|
      File.binwrite(File.join(source, name), 'local filesystem metadata')
    end
    destination = File.join(@temporary, 'release-1')
    @renderer.copy_public_well_known(@root, destination)
    target = File.join(destination, '.well-known')
    assert_equal files.keys.sort, Dir.children(target).sort
    files.each { |name, bytes| assert_equal bytes, File.binread(File.join(target, name)) }
    assert File.file?(File.join(source, '._assetlinks.json'))
  end

  def test_published_script_policy_accepts_site_script_and_structured_data
    directive = @renderer.headers.lines.grep(/Content-Security-Policy:/).join
                       .split(';').find { |part| part.strip.start_with?('script-src ') }
    assert_equal "script-src 'self' https://static.cloudflareinsights.com", directive.strip
    # Use synthetic image dimensions for this renderer check. Release builds
    # still exercise PublicAppMedia's exact capture provenance.
    dimensions = {'url' => '/fixture.png', 'alt' => 'Fixture', 'width' => 32, 'height' => 32,
                  'capture_kind' => 'browser_flutter_fixture'}
    screens = PublicAppMedia::NATIVE_MEDIA_ROUTES.keys.to_h { |id| [id, dimensions] }
    @renderer.instance_variable_set(:@public_app_media, Struct.new(:screens).new(screens))
    pages = RENDERER.const_get(:PAGES).map { |page| @renderer.page_html(page) }
    pages.concat(%i[app group].map { |kind| @renderer.share_landing_page_html(kind: kind) })
    pages.each do |html|
      scripts = html.scan(/<script\b([^>]*)>(.*?)<\/script>/mi)
      assert_equal 2, scripts.length
      data, external = scripts.partition { |attributes, _| attributes.include?('type="application/ld+json"') }
      assert_equal 1, data.length
      assert_kind_of Hash, JSON.parse(data.first.last)
      assert_match(/\bsrc="\/site\.js\?v=[^"]+"/, external.first.first)
      assert_empty external.first.last.strip
      refute_match(/<[^>]+\son[a-z]+\s*=/i, html)
    end
  end

  def test_outside_app_deletion_heading_links_to_the_actual_portal_and_keeps_email_fallback
    details = {
      'heading' => 'Delete without the app',
      'copy' => 'Contact Collect support to request account deletion.',
      'email' => 'info@ikanisa.com'
    }
    original = @renderer.legal_hash_html(details)
    linked = @renderer.legal_named_value_html('delete_without_app', details)
    assert_includes linked, '<a class="legal-inline-link" href="https://api.collect.ikanisa.com/privacy/account-deletion">Delete without the app</a>'
    assert_includes linked, 'href="mailto:info@ikanisa.com"'
    visible = ->(html) { CGI.unescapeHTML(html.gsub(/<[^>]+>/, ' ')).split.join(' ') }
    assert_equal visible.call(original), visible.call(linked)
    assert_equal details['copy'], 'Contact Collect support to request account deletion.'
    assert_raises(RuntimeError) do
      @renderer.legal_named_value_html('delete_without_app', details.reject { |key, _| key == 'heading' })
    end
  end
end
