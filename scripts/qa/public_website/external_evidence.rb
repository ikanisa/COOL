# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../public_lighthouse_evidence'

class PublicWebsiteExternalEvidence
  REQUIREMENTS = {
    "search_console_google" => {
      "audit_id" => "T-1",
      "description" => "Google Search Console sitemap submission or URL inspection proof.",
      "paths" => [
        ["search-console", "google-search-console.json"],
        ["search-console", "google-search-console.pdf"],
        ["search-console", "google-search-console.png"],
      ],
    },
    "bing_webmaster" => {
      "audit_id" => "T-1",
      "description" => "Bing Webmaster Tools sitemap submission proof, or owner-approved deferral.",
      "paths" => [
        ["search-console", "bing-webmaster.json"],
        ["search-console", "bing-webmaster.pdf"],
        ["search-console", "bing-webmaster.png"],
        ["owner-approvals", "bing-deferral.md"],
      ],
    },
    "lighthouse_mobile" => {
      "audit_id" => "Lighthouse",
      "description" => "Mobile Lighthouse/PageSpeed JSON for the expected URL and profile, within the seven-day QA evidence window and with all four category scores at 90+. HTML/PDF may supplement it.",
      "paths" => [
        ["lighthouse", "mobile.json"],
        ["lighthouse", "mobile.html"],
        ["lighthouse", "mobile.pdf"],
      ],
    },
    "lighthouse_desktop" => {
      "audit_id" => "Lighthouse",
      "description" => "Desktop Lighthouse/PageSpeed JSON for the expected URL and profile, within the seven-day QA evidence window and with all four category scores at 90+. HTML/PDF may supplement it.",
      "paths" => [
        ["lighthouse", "desktop.json"],
        ["lighthouse", "desktop.html"],
        ["lighthouse", "desktop.pdf"],
      ],
    },
    "visual_approval" => {
      "audit_id" => "U-5",
      "description" => "Final visual approval or complete screenshot set for required viewports.",
      "paths" => [
        ["owner-approvals", "visual-approval.md"],
        ["browser_visual_qa.json"],
        ["screenshots", "mobile_390x844.png"],
        ["screenshots", "mobile_430x932.png"],
        ["screenshots", "tablet_768x1024.png"],
        ["screenshots", "desktop_1440x1000.png"],
      ],
      "all_screenshot_paths" => true,
    },
    "play_console_approval" => {
      "audit_id" => "Play Console",
      "description" => "Play Console privacy URL/listing update evidence, or explicit owner deferral.",
      "paths" => [
        ["play-console", "privacy-url-update.md"],
        ["play-console", "privacy-url-update.png"],
        ["owner-approvals", "play-console-deferral.md"],
      ],
    },
  }.freeze

  def initialize(directory:, expected_url:, now: Time.now.utc)
    @directory = directory
    @expected_url = expected_url
    @now = now
  end

  def checks
    REQUIREMENTS.each_with_object({}) do |(id, rule), results|
      paths = rule.fetch("paths").map { |parts| File.join(@directory, *parts) }
      detail = rule.merge("paths" => paths)
      if id.start_with?("lighthouse_")
        detail["validation"] = paths.map do |path|
          PublicLighthouseEvidence.validate_file(
            path, expected_url: @expected_url, profile: id.delete_prefix("lighthouse_"), now: @now
          )
        end
        valid = detail["validation"].any? { |result| result.fetch("status") == "pass" }
      else
        valid = valid_artifacts?(id, paths)
      end
      results[id] = detail.merge("status" => valid ? "pass" : "missing_or_invalid")
    end
  end

  private

  def markdown_approval_valid?(path, required_terms)
    return false unless File.file?(path)

    text = File.read(path, encoding: "UTF-8")
    return false unless text.valid_encoding?

    text = text.downcase
    text.strip.length >= 80 &&
      %w[pending todo tbd].none? { |term| text.include?(term) } &&
      (%w[owner date] + required_terms).all? { |term| text.include?(term) }
  end

  def png_dimensions(path)
    return unless File.file?(path)

    header = File.binread(path, 24)
    return unless header&.bytesize == 24
    return unless header.start_with?("\x89PNG\r\n\x1A\n".b) && header[8, 8] == [13, "IHDR"].pack("Na4")

    width, height = header[16, 8].unpack("NN")
    [width, height] if width.positive? && height.positive?
  end

  def read_json_object(path)
    return {} unless File.file?(path)

    text = File.read(path, encoding: "UTF-8")
    return {} unless text.valid_encoding?

    value = JSON.parse(text)
    value.is_a?(Hash) ? value : {}
  rescue JSON::ParserError
    {}
  end

  def browser_visual_qa(path)
    parsed = read_json_object(path)
    results = parsed["results"]
    return unless parsed["status"] == "pass" && results.is_a?(Array) && results.length >= 4
    return unless results.all? { |result| result.is_a?(Hash) && Array(result["failures"]).empty? }

    results
  end

  def visual_capture_valid?(results, screenshot_path, expected_width, expected_height)
    result = results.find do |item|
      viewport = item["requested_viewport"]
      viewport.is_a?(Hash) && viewport["width"] == expected_width &&
        viewport["height"] == expected_height
    end
    dimensions = png_dimensions(screenshot_path)
    recorded = result && result["captured_pixels"]
    return false unless dimensions && recorded.is_a?(Hash)
    return false unless dimensions == [recorded["width"], recorded["height"]]

    # Chrome's captured surface can exclude scrollbars and browser insets.
    width_delta = expected_width - dimensions[0]
    height_delta = expected_height - dimensions[1]
    width_delta.between?(0, 20) && height_delta.between?(0, 40)
  end

  def visual_approval_valid?(paths)
    approval, report, *screenshots = paths
    return true if markdown_approval_valid?(approval, %w[visual approve])

    results = browser_visual_qa(report)
    results && [[390, 844], [430, 932], [768, 1024], [1440, 1000]].zip(screenshots).all? do |(width, height), screenshot|
      visual_capture_valid?(results, screenshot, width, height)
    end
  end

  def binary_artifact_valid?(path)
    return false unless File.file?(path) && File.size(path) > 100

    case File.extname(path)
    when ".png" then !png_dimensions(path).nil?
    when ".pdf" then File.binread(path, 5) == "%PDF-"
    else false
    end
  end

  def search_console_artifact_valid?(path)
    return binary_artifact_valid?(path) if path.end_with?(".png", ".pdf")

    text = JSON.generate(read_json_object(path)).downcase
    text.include?("collect.ikanisa.com") &&
      (text.include?("sitemap") || text.include?("url inspection") || text.include?("index"))
  end

  def indexnow_artifact_valid?(path)
    return false unless path.end_with?(".json")

    parsed = read_json_object(path)
    parsed["status"] == "pass" &&
      parsed["submission"].to_s.downcase.include?("indexnow") &&
      parsed["host"] == "collect.ikanisa.com" &&
      parsed["sitemap"] == "https://collect.ikanisa.com/sitemap.xml" &&
      parsed["url_count"].to_s.to_i.positive? &&
      [200, 202].include?(parsed["http_status"].to_s.to_i)
  end

  def valid_artifacts?(id, paths)
    case id
    when "search_console_google"
      paths.any? { |path| search_console_artifact_valid?(path) }
    when "bing_webmaster"
      paths.any? do |path|
        if path.end_with?("bing-deferral.md")
          markdown_approval_valid?(path, %w[bing defer])
        else
          indexnow_artifact_valid?(path) || search_console_artifact_valid?(path)
        end
      end
    when "visual_approval"
      visual_approval_valid?(paths)
    when "play_console_approval"
      paths.any? do |path|
        if path.end_with?("play-console-deferral.md")
          markdown_approval_valid?(path, %w[play console defer])
        elsif path.end_with?(".md")
          markdown_approval_valid?(path, %w[play console approve])
        else
          binary_artifact_valid?(path)
        end
      end
    else
      false
    end
  end
end
