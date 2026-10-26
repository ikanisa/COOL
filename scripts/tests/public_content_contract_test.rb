# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../qa/public_content_contract'

class PublicContentContractTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('collect-public-content-')
    @historical_copy = 'Historical product copy'
    @old = Digest::SHA256.hexdigest(@historical_copy)
    @html = '<main>Collect Rwanda MoMo contributions</main><script>not visible</script>'
    @current = Digest::SHA256.hexdigest(PublicContentContract.visible_text(@html))
    @baseline = { 'schema_version' => 1, 'hashes' => { '/' => @old } }
    write(PublicContentContract::BASELINE, JSON.generate(@baseline))
    @sources = PublicContentContract::SOURCES.to_h do |name|
      write(name, 'source evidence for ' + name)
      [name, Digest::SHA256.file(File.join(@root, name)).hexdigest]
    end
    @review = { 'status' => 'pass', 'routes' => [{ 'route' => '/', 'historical_matches_baseline' => true, 'historical_sha256' => @old, 'current_sha256' => @current }] }
    write(PublicContentContract::REVIEW, JSON.generate(@review))
    @corpus = { '/' => { 'text' => @historical_copy, 'sha256' => @old, 'expected' => @old } }
    write(PublicContentContract::HISTORICAL_TEXT, JSON.generate(@corpus))
    @contract = { 'schema_version' => 1, 'status' => 'local_engineering_reviewed', 'hashes' => { '/' => @current },
                  'historical_baseline_sha256' => Digest::SHA256.file(File.join(@root, PublicContentContract::BASELINE)).hexdigest,
                  'historical_comparison_sha256' => Digest::SHA256.file(File.join(@root, PublicContentContract::REVIEW)).hexdigest,
                  'historical_visible_text_sha256' => Digest::SHA256.file(File.join(@root, PublicContentContract::HISTORICAL_TEXT)).hexdigest,
                  'reviewed_source_sha256' => @sources, 'legal_release_approved' => false, 'publication_approved' => false }
    save_contract
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write(name, body)
    path = File.join(@root, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, body)
  end

  def save_contract
    write(PublicContentContract::CURRENT, JSON.generate(@contract))
  end

  def evaluate(pages = { '/' => @html }, routes = ['/'])
    PublicContentContract.evaluate(root: @root, pages: pages, routes: routes)
  end

  def assert_failed
    result = evaluate
    assert_equal 'fail', result.fetch('status')
    result
  end

  def test_actual_reviewed_contract_preserves_historical_baseline
    before = File.binread(File.join(@root, PublicContentContract::BASELINE))
    result = evaluate
    assert_equal 'pass', result['status']
    assert_equal false, result['legal_release_approved']
    assert_equal false, result['publication_approved']
    assert_equal before, File.binread(File.join(@root, PublicContentContract::BASELINE))
    refute_equal @old, @current
  end

  def test_unreviewed_visible_copy_change_fails
    assert_equal 'fail', evaluate({ '/' => @html.sub('Rwanda', 'Worldwide') })['status']
  end

  def test_new_explicit_comparison_preserves_the_historical_baseline
    baseline = File.binread(File.join(@root, PublicContentContract::BASELINE))
    comparison = 'docs/release/current-legal-presentation-review.json'
    updated = @review.merge('reason' => 'Current supported request instructions')
    write(comparison, JSON.generate(updated))
    @contract['current_comparison_file'] = comparison
    @contract['current_comparison_sha256'] = Digest::SHA256.file(
      File.join(@root, comparison),
    ).hexdigest
    save_contract
    assert_equal 'pass', evaluate['status']
    assert_equal baseline, File.binread(File.join(@root, PublicContentContract::BASELINE))
    assert_equal @review, JSON.parse(File.read(File.join(@root, PublicContentContract::REVIEW)))
  end

  def test_new_comparison_does_not_hide_mutation_of_the_historical_review
    comparison = 'docs/release/current-legal-presentation-review.json'
    write(comparison, JSON.generate(@review))
    @contract['current_comparison_file'] = comparison
    @contract['current_comparison_sha256'] = Digest::SHA256.file(File.join(@root, comparison)).hexdigest
    save_contract
    write(PublicContentContract::REVIEW, JSON.generate(@review.merge('unexpected' => true)))
    assert_failed
  end

  def test_comparison_pointer_cannot_escape_controlled_release_evidence
    ['../outside.json', '/tmp/outside.json', 'scripts/unreviewed.json'].each do |comparison|
      @contract['current_comparison_file'] = comparison
      save_contract
      assert_equal 'fail', evaluate['status']
    end
  end

  def test_added_route_fails
    assert_equal 'fail', evaluate({ '/' => @html, '/foreign/' => @html }, ['/', '/foreign/'])['status']
  end

  def test_missing_route_fails
    assert_equal 'fail', evaluate({}, [])['status']
  end

  def test_duplicate_route_fails
    assert_equal 'fail', evaluate({ '/' => @html }, ['/', '/'])['status']
  end

  def test_historical_baseline_mutation_fails
    write(PublicContentContract::BASELINE, JSON.generate(@baseline.merge('scope' => 'unexpected rebaseline')))
    assert_failed
  end

  def test_old_baseline_cannot_bypass_missing_current_review
    File.delete(File.join(@root, PublicContentContract::CURRENT))
    assert_equal 'fail', evaluate({ '/' => 'Historical product copy' })['status']
  end

  def test_changed_actual_product_source_fails
    write('docs/PRODUCT.md', 'new unsupported capability')
    assert_failed
  end

  def test_changed_builder_source_fails
    write('scripts/public_static_site_build.rb', 'modified builder')
    assert_failed
  end

  def test_changed_legal_input_fails
    write('content/legal/collect_privacy_policy.yaml', 'modified privacy terms')
    assert_failed
  end

  def test_source_inventory_cannot_omit_input
    @contract['reviewed_source_sha256'].delete('docs/PRODUCT.md')
    save_contract
    assert_failed
  end

  def test_source_inventory_cannot_escape_root
    @contract['reviewed_source_sha256']['../../outside'] = '0' * 64
    save_contract
    assert_failed
  end

  def test_unreviewed_contract_status_fails
    @contract['status'] = 'candidate_local_engineering_content_review'
    save_contract
    assert_failed
  end

  def test_unknown_schema_fails
    @contract['schema_version'] = 99
    save_contract
    assert_failed
  end

  def test_engineering_contract_cannot_claim_legal_approval
    @contract['legal_release_approved'] = true
    save_contract
    assert_failed
  end

  def test_engineering_contract_cannot_claim_publication_approval
    @contract['publication_approved'] = true
    save_contract
    assert_failed
  end

  def test_changed_historical_review_fails
    @review['routes'][0]['historical_matches_baseline'] = false
    write(PublicContentContract::REVIEW, JSON.generate(@review))
    assert_failed
  end

  def test_missing_historical_corpus_fails_even_with_valid_comparison_hashes
    File.delete(File.join(@root, PublicContentContract::HISTORICAL_TEXT))
    assert_failed
  end

  def test_changed_historical_corpus_bytes_fail
    write(PublicContentContract::HISTORICAL_TEXT, JSON.generate(@corpus.merge('/extra/' => @corpus['/'])))
    assert_failed
  end

  def test_refreshing_corpus_digest_cannot_hide_changed_historical_copy
    @corpus['/']['text'] = 'Unreviewed replacement history'
    refresh_corpus_digest
    assert_failed
  end

  def test_refreshing_corpus_digest_cannot_hide_a_missing_historical_route
    @corpus.clear
    refresh_corpus_digest
    assert_failed
  end

  def test_historical_corpus_cannot_claim_a_different_baseline_digest
    @corpus['/']['expected'] = Digest::SHA256.hexdigest('different baseline')
    refresh_corpus_digest
    assert_failed
  end

  def refresh_corpus_digest
    write(PublicContentContract::HISTORICAL_TEXT, JSON.generate(@corpus))
    @contract['historical_visible_text_sha256'] = Digest::SHA256.file(
      File.join(@root, PublicContentContract::HISTORICAL_TEXT),
    ).hexdigest
    save_contract
  end

  def test_digest_refresh_cannot_bypass_explicit_delta_review
    @contract['hashes']['/'] = Digest::SHA256.hexdigest('Unreviewed new content')
    save_contract
    assert_failed
  end

  def test_symlinked_evidence_refused
    source = File.join(@root, 'docs/PRODUCT.md')
    moved = source + '.original'
    File.rename(source, moved)
    File.symlink(moved, source)
    assert_failed
  end

  def test_normalization_retains_existing_year_whitespace_and_script_rules
    first = '<p>Collect  Rwanda</p><footer>© 2026</footer><style>hidden styles</style>'
    second = '<p>Collect Rwanda</p><footer>© 2027</footer><script>hidden code</script>'
    assert_equal PublicContentContract.visible_text(first), PublicContentContract.visible_text(second)
  end

  def test_normalization_counts_duplicate_desktop_cta_only_once
    html = '<div class="header-actions"><a>Get the App</a></div><div class="mobile-menu-actions"><a>Get the App</a></div>'
    assert_equal 'Get the App', PublicContentContract.visible_text(html)
  end
end
