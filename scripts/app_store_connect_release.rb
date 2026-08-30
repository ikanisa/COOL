#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "optparse"
require "time"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"

options = {
  action: "status",
  app_id: "6783960331",
  version: "1.2.2",
  build_number: "21",
  locale: "en-GB",
  metadata_path: File.expand_path("../fastlane/metadata/en-GB", __dir__)
}

OptionParser.new do |parser|
  parser.banner = "Usage: app_store_connect_release.rb [options]"
  parser.on("--action VALUE", %w[status prepare submit], "status, prepare, or submit") { |value| options[:action] = value }
  parser.on("--app-id VALUE", "App Store numeric app ID") { |value| options[:app_id] = value }
  parser.on("--version VALUE", "Marketing version") { |value| options[:version] = value }
  parser.on("--build-number VALUE", "Build number") { |value| options[:build_number] = value }
  parser.on("--locale VALUE", "App Store locale") { |value| options[:locale] = value }
  parser.on("--metadata-path VALUE", "Fastlane locale metadata directory") { |value| options[:metadata_path] = File.expand_path(value) }
end.parse!

key_id = ENV["ASC_KEY_ID"].to_s.strip
issuer_id = ENV["ASC_ISSUER_ID"].to_s.strip
private_key_path = ENV["ASC_PRIVATE_KEY_PATH"].to_s.strip
private_key_text = ENV["ASC_PRIVATE_KEY"].to_s
review_phone = ENV["COLLECT_REVIEW_PHONE"].to_s.strip
review_otp = ENV["COLLECT_REVIEW_OTP"].to_s.strip

missing = []
missing << "ASC_KEY_ID" if key_id.empty?
missing << "ASC_ISSUER_ID" if issuer_id.empty?
missing << "ASC_PRIVATE_KEY_PATH or ASC_PRIVATE_KEY" if private_key_path.empty? && private_key_text.empty?
if %w[prepare submit].include?(options[:action])
  missing << "COLLECT_REVIEW_PHONE" if review_phone.empty?
  missing << "COLLECT_REVIEW_OTP" if review_otp.empty?
end
abort JSON.pretty_generate(status: "blocked", missing: missing) unless missing.empty?

private_key_text = File.read(private_key_path) if private_key_text.empty?
private_key = OpenSSL::PKey::EC.new(private_key_text)

def b64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

def der_to_raw_ecdsa(der_signature)
  sequence = OpenSSL::ASN1.decode(der_signature)
  sequence.value.map do |integer|
    value = integer.value.to_i.to_s(16)
    value = "0#{value}" if value.length.odd?
    [value].pack("H*").rjust(32, "\0")
  end.join
end

def jwt(private_key, key_id, issuer_id)
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = { iss: issuer_id, exp: Time.now.to_i + (15 * 60), aud: "appstoreconnect-v1" }
  signing_input = "#{b64url(JSON.generate(header))}.#{b64url(JSON.generate(payload))}"
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  "#{signing_input}.#{b64url(der_to_raw_ecdsa(private_key.dsa_sign_asn1(digest)))}"
end

def request(method, path, token, body: nil)
  uri = URI("#{API_BASE}#{path}")
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  return parsed if response.code.to_i.between?(200, 299)

  warn JSON.pretty_generate(status: "failed", method: method, path: path, http_status: response.code.to_i, response: parsed)
  exit 1
end

def encoded_query(values)
  URI.encode_www_form(values)
end

def metadata_value(path, name)
  full_path = File.join(path, name)
  abort JSON.pretty_generate(status: "blocked", reason: "missing_metadata", path: full_path) unless File.file?(full_path)
  File.read(full_path).strip
end

token = jwt(private_key, key_id, issuer_id)
version_query = encoded_query(
  "filter[platform]" => "IOS",
  "filter[versionString]" => options[:version],
  "limit" => "10"
)
versions = request(:get, "/v1/apps/#{options[:app_id]}/appStoreVersions?#{version_query}", token).fetch("data")
version = versions.first
abort JSON.pretty_generate(status: "blocked", reason: "app_store_version_not_found", version: options[:version]) unless version
version_id = version.fetch("id")

build_query = encoded_query(
  "filter[app]" => options[:app_id],
  "filter[version]" => options[:build_number],
  "sort" => "-uploadedDate",
  "limit" => "10"
)
builds = request(:get, "/v1/builds?#{build_query}", token).fetch("data")
build = builds.find { |item| item.dig("attributes", "version") == options[:build_number] }
build_id = build && build.fetch("id")
build_state = build && build.dig("attributes", "processingState")

localizations = request(:get, "/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations?limit=200", token).fetch("data")
localization = localizations.find { |item| item.dig("attributes", "locale") == options[:locale] }
review_details = request(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail", token).fetch("data")
selected_build = request(:get, "/v1/appStoreVersions/#{version_id}/build", token).fetch("data")
status = {
  status: "ok",
  action: options[:action],
  app_id: options[:app_id],
  version_id: version_id,
  version: version.dig("attributes", "versionString"),
  app_store_state: version.dig("attributes", "appStoreState"),
  release_type: version.dig("attributes", "releaseType"),
  target_build: { id: build_id, number: options[:build_number], processing_state: build_state },
  selected_build: selected_build && { id: selected_build["id"], number: selected_build.dig("attributes", "version"), processing_state: selected_build.dig("attributes", "processingState") },
  locale: localization && localization.dig("attributes", "locale"),
  review_details_present: !review_details.nil?
}

if options[:action] == "status"
  puts JSON.pretty_generate(status)
  exit 0
end

abort JSON.pretty_generate(status.merge(status: "blocked", reason: "build_not_found")) unless build_id
abort JSON.pretty_generate(status.merge(status: "blocked", reason: "build_not_ready")) unless build_state == "VALID"
abort JSON.pretty_generate(status.merge(status: "blocked", reason: "localization_not_found")) unless localization
abort JSON.pretty_generate(status.merge(status: "blocked", reason: "review_details_not_found")) unless review_details

request(:patch, "/v1/appStoreVersions/#{version_id}", token, body: {
  data: { type: "appStoreVersions", id: version_id, attributes: { releaseType: "AFTER_APPROVAL" } }
})
request(:patch, "/v1/appStoreVersions/#{version_id}/relationships/build", token, body: {
  data: { type: "builds", id: build_id }
})

localization_attributes = {
  description: metadata_value(options[:metadata_path], "description.txt"),
  keywords: metadata_value(options[:metadata_path], "keywords.txt"),
  marketingUrl: metadata_value(options[:metadata_path], "marketing_url.txt"),
  promotionalText: metadata_value(options[:metadata_path], "promotional_text.txt"),
  supportUrl: metadata_value(options[:metadata_path], "support_url.txt")
}
request(:patch, "/v1/appStoreVersionLocalizations/#{localization.fetch("id")}", token, body: {
  data: { type: "appStoreVersionLocalizations", id: localization.fetch("id"), attributes: localization_attributes }
})

request(:patch, "/v1/appStoreReviewDetails/#{review_details.fetch("id")}", token, body: {
  data: {
    type: "appStoreReviewDetails",
    id: review_details.fetch("id"),
    attributes: {
      contactFirstName: "IKANISA",
      contactLastName: "Support",
      contactPhone: review_phone,
      contactEmail: "info@ikanisa.com",
      demoAccountName: review_phone,
      demoAccountPassword: review_otp,
      demoAccountRequired: true,
      notes: metadata_value(options[:metadata_path], "review_notes.txt")
    }
  }
})

if options[:action] == "prepare"
  puts JSON.pretty_generate(status.merge(status: "prepared", release_type: "AFTER_APPROVAL", selected_build: { id: build_id, number: options[:build_number], processing_state: build_state }))
  exit 0
end

submission = request(:post, "/v1/appStoreVersionSubmissions", token, body: {
  data: {
    type: "appStoreVersionSubmissions",
    relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } }
  }
}).fetch("data")

puts JSON.pretty_generate(status.merge(status: "submitted", submission_id: submission.fetch("id"), release_type: "AFTER_APPROVAL", selected_build: { id: build_id, number: options[:build_number], processing_state: build_state }))
