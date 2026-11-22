#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "fileutils"
require "json"
require "time"
require_relative "public_app_media"
require_relative "public_photography"
require_relative "public_deployment_profile"
require_relative "public_site_routes"
require_relative "public_marketing_sections"
require_relative "public_site_assets"
require_relative "public_site_publication"
require_relative "public_site/site_chrome"
require_relative "public_site/marketing_components"
require_relative "public_site/marketing_page"
require_relative "public_site/share_landing"

module CollectPublicSite
  extend self

  BUILD_DIR = File.expand_path(ENV.fetch("PUBLIC_BUILD_DIR", "build/public_web"), ROOT)
  PUBLIC_DEPLOYMENT = CollectPublicDeployment.resolve(ROOT)
  PUBLIC_URL = PUBLIC_DEPLOYMENT.fetch("public_origin")
  ASSET_VERSION = PublicPhotography.asset_version(ROOT)
  GOOGLE_PLAY_URL = "https://play.google.com/store/apps/details?id=app.cool.mobile"
  APPLE_APP_STORE_ID = "6783960331"
  APPLE_APP_STORE_URL = "https://apps.apple.com/app/id#{APPLE_APP_STORE_ID}"
  WHATSAPP_NUMBER = "250795588248"
  DISPLAY_PHONE = "+250 795 588 248"
  SUPPORT_EMAIL = "info@ikanisa.com"
  ACCOUNT_DELETION_PORTAL_URL = PUBLIC_DEPLOYMENT.fetch("account_deletion_url")
  REGISTERED_ENTITY = "IKANISA Ltd."
  REGULATORY_FOOTER_NOTE = PRODUCT_CAPABILITIES.copy("regulatory_footer")
  INDEXNOW_KEY = ENV.fetch("PUBLIC_INDEXNOW_KEY", "").strip
  INDEXNOW_KEY_PATTERN = /\A[A-Za-z0-9-]{8,128}\z/
  # September 2026 public marketing roles; native screen families stay in Flutter.
  # These identity metadata colours follow the same public cohort as revolut.css.
  BRAND_BLACK = "#000000"

  def build
    destination_rules = {
      source_root: ROOT,
      allowed_roots: [File.join(ROOT, "build"), File.join(ROOT, ".cache")],
      explicit_path: ENV["PUBLIC_BUILD_DIR"]
    }
    public_build_destination_mode(BUILD_DIR, **destination_rules)
    public_app_screens = PublicAppMedia.new(ROOT).screens
    photography = PublicPhotography.new(ROOT)
    photography.photos
    unless INDEXNOW_KEY.empty? || INDEXNOW_KEY.match?(INDEXNOW_KEY_PATTERN)
      abort("PUBLIC_INDEXNOW_KEY must be 8-128 characters using A-Z, a-z, 0-9, or dashes only")
    end
    build_lastmod = Time.now.utc.strftime("%Y-%m-%d")

    publish_public_build(BUILD_DIR, **destination_rules) do |build_dir|
      write_assets(photography, public_app_screens, build_dir: build_dir)
      all_paths = write_routes(photography, public_app_screens: public_app_screens, build_dir: build_dir)
      write_publication_metadata(all_paths, build_lastmod, build_dir: build_dir)
    end
    puts "Prepared static public website build: #{BUILD_DIR}"
  rescue ArgumentError, IOError, SystemCallError => error
    abort(error.message)
  end
end

CollectPublicSite.build if $PROGRAM_NAME == __FILE__
