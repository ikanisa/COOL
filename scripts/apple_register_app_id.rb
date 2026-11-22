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
  bundle_id: "app.cool.mobile",
  name: "Collect",
  platform: "IOS",
  capability: "ASSOCIATED_DOMAINS"
}

OptionParser.new do |parser|
  parser.banner = "Usage: apple_register_app_id.rb [options]"
  parser.on("--bundle-id VALUE", "Explicit Bundle ID, default app.cool.mobile") { |value| options[:bundle_id] = value }
  parser.on("--name VALUE", "Bundle ID display name, default Collect") { |value| options[:name] = value }
  parser.on("--platform VALUE", "Apple platform enum, default IOS") { |value| options[:platform] = value }
  parser.on("--capability VALUE", "Capability enum to enable, default ASSOCIATED_DOMAINS") { |value| options[:capability] = value }
end.parse!

key_id = ENV["ASC_KEY_ID"].to_s.strip
issuer_id = ENV["ASC_ISSUER_ID"].to_s.strip
private_key_path = ENV["ASC_PRIVATE_KEY_PATH"].to_s.strip
private_key_text = ENV["ASC_PRIVATE_KEY"].to_s

missing = []
missing << "ASC_KEY_ID" if key_id.empty?
missing << "ASC_ISSUER_ID" if issuer_id.empty?
missing << "ASC_PRIVATE_KEY_PATH or ASC_PRIVATE_KEY" if private_key_path.empty? && private_key_text.empty?

unless missing.empty?
  warn JSON.pretty_generate(
    status: "blocked",
    reason: "missing_app_store_connect_api_credentials",
    missing: missing,
    required_role: "Apple Developer/App Store Connect API key with permission to manage Certificates, Identifiers & Profiles",
    example: "ASC_KEY_ID=ABC123DEFG ASC_ISSUER_ID=<app-store-connect-issuer-id> ASC_PRIVATE_KEY_PATH=/secure/path/AuthKey_ABC123DEFG.p8 ruby scripts/apple_register_app_id.rb"
  )
  exit 2
end

private_key_text = File.read(private_key_path) if private_key_text.empty?
private_key = OpenSSL::PKey::EC.new(private_key_text)

def b64url(value)
  Base64.urlsafe_encode64(value, padding: false)
end

def der_to_raw_ecdsa(der_signature)
  sequence = OpenSSL::ASN1.decode(der_signature)
  raise "unexpected ECDSA signature format" unless sequence.is_a?(OpenSSL::ASN1::Sequence)

  sequence.value.map do |integer|
    value = integer.value.to_i.to_s(16)
    value = "0#{value}" if value.length.odd?
    [value].pack("H*").rjust(32, "\0")
  end.join
end

def jwt(private_key, key_id, issuer_id)
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = {
    iss: issuer_id,
    exp: Time.now.to_i + (15 * 60),
    aud: "appstoreconnect-v1"
  }
  signing_input = "#{b64url(JSON.generate(header))}.#{b64url(JSON.generate(payload))}"
  der_signature = private_key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
  "#{signing_input}.#{b64url(der_to_raw_ecdsa(der_signature))}"
end

def request(method, path, token, body: nil)
  uri = URI("#{API_BASE}#{path}")
  klass = {
    get: Net::HTTP::Get,
    post: Net::HTTP::Post
  }.fetch(method)

  req = klass.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = "application/json"
  req.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  parsed = response.body.to_s.empty? ? {} : JSON.parse(response.body)
  [response.code.to_i, parsed]
end

token = jwt(private_key, key_id, issuer_id)
encoded_filter = URI.encode_www_form("filter[identifier]" => options[:bundle_id])
code, existing = request(:get, "/v1/bundleIds?#{encoded_filter}", token)

unless code.between?(200, 299)
  warn JSON.pretty_generate(status: "failed", step: "lookup_bundle_id", http_status: code, response: existing)
  exit 1
end

bundle = existing.fetch("data").first
created = false

unless bundle
  body = {
    data: {
      type: "bundleIds",
      attributes: {
        identifier: options[:bundle_id],
        name: options[:name],
        platform: options[:platform]
      }
    }
  }
  code, created_response = request(:post, "/v1/bundleIds", token, body: body)
  unless code.between?(200, 299)
    warn JSON.pretty_generate(status: "failed", step: "create_bundle_id", http_status: code, response: created_response)
    exit 1
  end
  bundle = created_response.fetch("data")
  created = true
end

bundle_id_resource = bundle.fetch("id")
capability_path = "/v1/bundleIds/#{bundle_id_resource}/bundleIdCapabilities"
code, capabilities = request(:get, capability_path, token)

unless code.between?(200, 299)
  warn JSON.pretty_generate(status: "failed", step: "list_capabilities", http_status: code, response: capabilities)
  exit 1
end

capability_exists = capabilities.fetch("data").any? do |item|
  item.dig("attributes", "capabilityType") == options[:capability]
end

capability_created = false
unless capability_exists
  body = {
    data: {
      type: "bundleIdCapabilities",
      attributes: {
        capabilityType: options[:capability]
      },
      relationships: {
        bundleId: {
          data: {
            id: bundle_id_resource,
            type: "bundleIds"
          }
        }
      }
    }
  }
  code, capability_response = request(:post, "/v1/bundleIdCapabilities", token, body: body)
  unless code.between?(200, 299)
    warn JSON.pretty_generate(status: "failed", step: "enable_capability", http_status: code, response: capability_response)
    exit 1
  end
  capability_created = true
end

puts JSON.pretty_generate(
  status: "ok",
  bundle_id: options[:bundle_id],
  bundle_resource_id: bundle_id_resource,
  created_bundle_id: created,
  capability: options[:capability],
  created_capability: capability_created
)
