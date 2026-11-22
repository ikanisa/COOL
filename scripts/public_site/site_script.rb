# frozen_string_literal: true

require "json"

module CollectPublicSite
  SITE_BROWSER_SOURCES = %w[navigation.js group_links.js app_links.js share_links.js].freeze

  def site_js
    settings = {
      publicOrigin: PUBLIC_URL,
      googlePlayUrl: GOOGLE_PLAY_URL,
      appleAppStoreUrl: APPLE_APP_STORE_URL,
      appleAppStoreId: APPLE_APP_STORE_ID
    }
    sources = SITE_BROWSER_SOURCES.map { |name| File.read(File.join(__dir__, "browser", name)) }
    ["(() => {\n", "  const publicSite = #{JSON.generate(settings)};\n", *sources, "})();\n"].join
  end
end
