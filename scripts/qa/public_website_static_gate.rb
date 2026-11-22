# frozen_string_literal: true

require_relative "public_website/checks"
require_relative "public_website/static_routes"
require_relative "public_website/static_delivery"
require_relative "public_website/static_content"
require_relative "../public_deployment_profile"

class PublicWebsiteStaticGate
  include PublicWebsiteChecks
  include PublicWebsiteStaticRoutes
  include PublicWebsiteStaticDelivery
  include PublicWebsiteStaticContent

  def run(build_dir)
    product_capabilities = CollectProductCapabilities.new(Dir.pwd)
    expected_public_origin = CollectPublicDeployment.resolve(Dir.pwd).fetch("public_origin")
    checks = []
    headers = read(File.join(build_dir, "_headers"))
    root_html = read(route_index(build_dir, "/"))
    sitemap = read(File.join(build_dir, "sitemap.xml"))
    stylesheet = %w[styles.css sections.css revolut.css].map { |name| read(File.join(build_dir, name)) }.join("\n")

    check_routes(checks, build_dir, root_html, expected_public_origin)
    check_discovery(checks, build_dir, root_html, headers, sitemap)
    check_delivery(checks, build_dir, root_html, headers)
    check_route_copy(checks, build_dir, root_html, stylesheet, product_capabilities)
    check_presentation(checks, build_dir, root_html, stylesheet, sitemap)
    check_claims(checks, build_dir, root_html, product_capabilities)
    check_result(checks, "build_dir" => build_dir)
  end

  private

  def read(path)
    File.file?(path) ? File.read(path) : ""
  end

  def file_size(path)
    File.file?(path) ? File.size(path) : 0
  end

  def route_index(build_dir, route)
    return File.join(build_dir, "index.html") if route == "/"
    File.join(build_dir, route.delete_prefix("/").delete_suffix("/"), "index.html")
  end
end

if $PROGRAM_NAME == __FILE__
  result = PublicWebsiteStaticGate.new.run(ARGV.fetch(0))
  if ARGV.fetch(1) == "--json"
    puts JSON.pretty_generate(result)
  else
    puts "public_website_quality_gate=#{result.fetch("status")}"
    result.fetch("checks").each do |item|
      puts "[#{item.fetch("status").upcase}] #{item.fetch("id")}: #{item.fetch("message")}"
    end
  end
  exit(result.fetch("status") == "pass" ? 0 : 1)
end
