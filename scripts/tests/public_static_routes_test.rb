# frozen_string_literal: true

require 'minitest/autorun'
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
    assert_equal ['/c/*', '/invite/*'], routes.select { |route| route[:kind] == 'redirect_pattern' }.map { |route| route[:path] }.sort
    assert_equal 20, routes.length
  end
end
