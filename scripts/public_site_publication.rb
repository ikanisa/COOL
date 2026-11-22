# frozen_string_literal: true

require_relative "qa/bounded_git_metadata"
require_relative "public_site/publication_destination"

module CollectPublicSite
  def headers
    <<~HEADERS
      /*
        X-Frame-Options: DENY
        X-Content-Type-Options: nosniff
        Referrer-Policy: strict-origin-when-cross-origin
        Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=(), fullscreen=(self)
        Content-Security-Policy: default-src 'self'; script-src 'self' https://static.cloudflareinsights.com; style-src 'self'; img-src 'self' data:; font-src 'self' data:; connect-src 'self' https://cloudflareinsights.com https://*.cloudflareinsights.com; manifest-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; upgrade-insecure-requests

      /index.html
        Cache-Control: public, max-age=300, must-revalidate

      /
        Cache-Control: public, max-age=300, must-revalidate

      /*.html
        Cache-Control: public, max-age=300, must-revalidate

      /styles.css
        Cache-Control: public, max-age=31536000, immutable

      /site.js
        Cache-Control: public, max-age=31536000, immutable

      /sections.css
        Cache-Control: public, max-age=31536000, immutable

      /manifest.json
        Cache-Control: public, max-age=3600, must-revalidate

      /assets/*
        Cache-Control: public, max-age=31536000, immutable

      /icons/*
        Cache-Control: public, max-age=31536000, immutable

    HEADERS
  end

  def write_file(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def public_web_manifest
    {
      "name" => "Collect by IKANISA",
      "short_name" => "Collect",
      "description" => "Microsavings and group savings for daily earners.",
      "start_url" => "/",
      "display" => "standalone",
      "background_color" => BRAND_BLACK,
      "theme_color" => BRAND_BLACK,
      "icons" => [
        {
          "src" => "/icons/collect.png",
          "sizes" => "512x512",
          "type" => "image/png",
          "purpose" => "any maskable"
        }
      ]
    }
  end

  def sitemap_xml(all_paths, build_lastmod)
    sitemap_urls = all_paths.map do |path|
      "  <url><loc>#{page_url(path)}</loc><lastmod>#{build_lastmod}</lastmod></url>"
    end.join("\n")
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{sitemap_urls}
      </urlset>
    XML
  end

  def public_site_version(all_paths)
    source_metadata = BoundedGitMetadata.observe(ROOT)
    {
      "name" => "collect-public-static",
      "generated_at" => Time.now.utc.iso8601,
      "source_commit" => source_metadata.fetch("source_commit"),
      "source_dirty" => source_metadata.fetch("source_dirty"),
      "source_git_status" => source_metadata.fetch("source_git_status"),
      "source_git_status_error" => source_metadata.fetch("source_git_status_error"),
      "public_origin" => PUBLIC_URL,
      "deployment_profile" => PUBLIC_DEPLOYMENT["deployment_profile"],
      "deployment_profile_sha256" => PUBLIC_DEPLOYMENT["deployment_profile_sha256"],
      "routes" => all_paths,
      "share_routes" => ["/c/:slug", "/app", "/invite/:publicId"],
      "indexnow_key_file" => INDEXNOW_KEY.empty? ? nil : "#{INDEXNOW_KEY}.txt"
    }
  end

  def write_publication_metadata(all_paths, build_lastmod, build_dir:)
    write_file(File.join(build_dir, "_headers"), headers)
    write_file(File.join(build_dir, "robots.txt"), "User-agent: *\nAllow: /\nSitemap: #{PUBLIC_URL}/sitemap.xml\n")
    write_file(File.join(build_dir, "#{INDEXNOW_KEY}.txt"), "#{INDEXNOW_KEY}\n") unless INDEXNOW_KEY.empty?
    write_file(File.join(build_dir, "manifest.json"), JSON.pretty_generate(public_web_manifest) + "\n")
    write_file(File.join(build_dir, "sitemap.xml"), sitemap_xml(all_paths, build_lastmod))
    write_file(File.join(build_dir, "version.json"), JSON.pretty_generate(public_site_version(all_paths)) + "\n")
  end
end
