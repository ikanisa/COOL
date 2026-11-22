# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'net/http'
require 'rbconfig'
require 'rexml/document'
require 'time'
require 'uri'

class PublicWebsiteIndexNow
  KEY_PATTERN = /\A[A-Za-z0-9-]{8,128}\z/

  def initialize(build_dir:, public_url:, key:)
    @build_dir = build_dir
    @public_url = public_url.delete_suffix('/')
    @key = key
    @urls = read_sitemap_urls
  end

  def self.owner_key
    key = ENV.fetch('PUBLIC_INDEXNOW_KEY', '').strip
    return key unless key.empty?

    source = ENV.fetch('PUBLIC_INDEXNOW_KEY_SOURCE', 'content/public_website_indexnow_key.txt')
    File.file?(source) ? File.read(source).gsub(/[[:space:]]/, '') : ''
  end

  def readiness
    key_provided = !@key.empty?
    valid_key = @key.match?(KEY_PATTERN)
    key_filename = "#{@key}.txt" if valid_key
    key_file_matches = valid_key && key_file_valid?(key_filename) if key_provided
    same_host = same_host_urls?
    status = if !key_provided
      'owner_key_not_provided'
    elsif key_file_matches && same_host
      'ready'
    else
      'fail'
    end

    {
      'checked_at_utc' => Time.now.utc.iso8601,
      'status' => status,
      'public_url' => @public_url,
      'build_dir' => @build_dir,
      'key_provided' => key_provided,
      'key_valid' => valid_key,
      'key_file' => key_filename,
      'key_file_valid' => key_file_matches,
      'key_location' => key_filename && "#{@public_url}/#{key_filename}",
      'url_count' => @urls.length,
      'same_host_urls' => same_host,
      'sample_urls' => @urls.first(5),
      'not_submitted_by_codex' => true,
      'submission_boundary' => 'Readiness only; URL submission is performed by scripts/public_website_indexnow_submit.sh during an authorized release.',
    }
  end

  def submission_payload
    {
      'host' => URI(@public_url).host,
      'key' => @key,
      'keyLocation' => "#{@public_url}/#{@key}.txt",
      'urlList' => @urls,
    }
  end

  def submission_evidence(endpoint, http_status)
    payload = submission_payload
    {
      'checked_at_utc' => Time.now.utc.iso8601,
      'status' => [200, 202].include?(http_status) ? 'pass' : 'fail',
      'submission' => 'Bing-recommended IndexNow URL submission',
      'endpoint' => endpoint,
      'host' => payload.fetch('host'),
      'key_location' => payload.fetch('keyLocation'),
      'sitemap' => "#{@public_url}/sitemap.xml",
      'url_count' => @urls.length,
      'sample_urls' => @urls.first(5),
      'http_status' => http_status,
    }
  end

  private

  def key_file_valid?(filename)
    path = File.join(@build_dir, filename)
    File.file?(path) && File.read(path).strip == @key
  end

  def read_sitemap_urls
    path = File.join(@build_dir, 'sitemap.xml')
    return [] unless File.file?(path)

    doc = REXML::Document.new(File.read(path))
    REXML::XPath.match(doc, "/*[local-name()='urlset']/*[local-name()='url']/*[local-name()='loc']")
      .map { |node| node.text.to_s.strip }
  rescue REXML::ParseException
    []
  end

  def same_host_urls?
    return false if @urls.empty?

    public_origin = URI(@public_url)
    return false unless public_origin.is_a?(URI::HTTPS) && public_origin.host && public_origin.port == 443 &&
                        public_origin.path.empty? && !public_origin.userinfo && !public_origin.query && !public_origin.fragment

    @urls.all? do |url|
      target = URI(url)
      target.is_a?(URI::HTTPS) && target.host == public_origin.host && target.port == public_origin.port &&
        !target.userinfo && !target.fragment
    end
  rescue URI::InvalidURIError
    false
  end
end

if $PROGRAM_NAME == __FILE__
  mode = ARGV.fetch(0)
  key = PublicWebsiteIndexNow.owner_key
  if mode == 'submit'
    unless key.match?(PublicWebsiteIndexNow::KEY_PATTERN)
      warn 'IndexNow key is missing or invalid.'
      exit 2
    end

    built = system({ 'PUBLIC_INDEXNOW_KEY' => key }, RbConfig.ruby,
                   'scripts/public_static_site_build.rb', out: File::NULL)
    exit($?&.exitstatus || 1) unless built
  end

  site = PublicWebsiteIndexNow.new(
    build_dir: ENV.fetch('PUBLIC_BUILD_DIR', 'build/public_web'),
    public_url: ENV.fetch('PUBLIC_WEBSITE_URL', 'https://collect.ikanisa.com'),
    key: key
  )
  report = site.readiness

  if mode == 'readiness'
    if ARGV[1] == '--json'
      puts JSON.pretty_generate(report)
    else
      puts "#{report.fetch('status')} key_provided=#{report.fetch('key_provided')} urls=#{report.fetch('url_count')} same_host=#{report.fetch('same_host_urls')}"
    end
    exit(report.fetch('status') == 'fail' ? 1 : 0)
  end

  exit 64 unless mode == 'submit'
  abort 'IndexNow build is not ready for URL submission.' unless report.fetch('status') == 'ready'

  endpoint = ENV.fetch('PUBLIC_INDEXNOW_ENDPOINT', 'https://api.indexnow.org/indexnow')
  evidence_path = ENV.fetch('PUBLIC_INDEXNOW_EVIDENCE', 'output/public_website_evidence/search-console/bing-webmaster.json')
  FileUtils.mkdir_p(File.dirname(evidence_path))

  uri = URI(endpoint)
  request = Net::HTTP::Post.new(uri)
  request['Content-Type'] = 'application/json; charset=utf-8'
  request.body = JSON.generate(site.submission_payload)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 30) do |http|
    http.request(request)
  end

  evidence = site.submission_evidence(endpoint, response.code.to_i)
  json = JSON.pretty_generate(evidence)
  File.write(evidence_path, "#{json}\n")
  puts json
  exit(evidence.fetch('status') == 'pass' ? 0 : 1)
end
