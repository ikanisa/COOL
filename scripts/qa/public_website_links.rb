# frozen_string_literal: true

require 'cgi'
require 'uri'

module PublicWebsiteLinks
  def self.origin(uri)
    [uri.scheme, uri.host, uri.port]
  end

  # The caller supplies read-only fetching and may reuse its response cache.
  # This checks navigation destinations, not form submission or legal content.
  def self.check(base_url:, pages:, fetcher:)
    base = URI(base_url)
    raise 'HTTP(S) website origin required' unless %w[http https].include?(base.scheme) && base.host
    targets = {}
    failures = []
    checked = 0
    pages.each do |source, html|
      markup = html.gsub(/<!--.*?-->/m, '').gsub(/<(script|style)\b.*?<\/\1>/mi, '')
      hrefs = markup.scan(/<a\b[^>]*\shref\s*=\s*(["'])(.*?)\1[^>]*>/mi).map { |match| CGI.unescapeHTML(match[1]) }.uniq
      hrefs.each do |href|
        next if href.match?(/\A(?:mailto|tel|collect|intent):/i)
        begin
          target = URI.join(base_url, source, href)
          next unless origin(target) == origin(base)
          checked += 1
          fragment = target.fragment
          target.fragment = nil
          response = targets[target.to_s] ||= fetcher.call(target.to_s)
          status = response.fetch(:status)
          if status != 200
            failures << { source: source, href: href, status: status, reason: 'destination_not_http_200' }
          elsif fragment && !fragment.empty? && response.fetch(:content_type, 'text/html').include?('text/html')
            identifiers = response.fetch(:body).scan(/<[a-z][^>]*\s(?:id|name)\s*=\s*(["'])(.*?)\1/mi).map { |match| CGI.unescapeHTML(match[1]) }
            unless identifiers.include?(URI::DEFAULT_PARSER.unescape(fragment))
              failures << { source: source, href: href, status: status, reason: 'missing_fragment_target' }
            end
          end
        rescue URI::InvalidURIError => error
          failures << { source: source, href: href, reason: 'invalid_url', error: error.message }
        end
      end
    end
    { links_checked: checked, destinations_checked: targets.length, failures: failures }
  end
end
