#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

module LcovCoverage
  def self.measure(content, threshold: 40)
    raise 'Coverage threshold must be between 0 and 100' unless
      threshold.is_a?(Numeric) && threshold.finite? && threshold.between?(0, 100)
    files = {}
    current = nil
    content.each_line.with_index(1) do |raw, number|
      line = raw.strip
      if line.start_with?('SF:')
        raise "Unterminated coverage record at line #{number}" if current
        current = line.delete_prefix('SF:')
        raise "Missing source file at line #{number}" if current.empty?
        files[current] ||= {}
      elsif line.start_with?('DA:')
        match = line.match(/\ADA:([1-9][0-9]*),([0-9]+)(?:,[^,]+)?\z/)
        raise "Invalid line coverage at line #{number}" unless current && match
        source_line, count = match.captures.first(2).map(&:to_i)
        # Repeated records may merge runs. A covered source line still counts
        # once, regardless of its execution count or number of records.
        files[current][source_line] = files[current].fetch(source_line, false) || count.positive?
      elsif line == 'end_of_record'
        raise "Coverage record has no source at line #{number}" unless current
        current = nil
      end
    end
    raise 'Unterminated coverage record' if current
    total = files.values.sum(&:length)
    raise 'No source line coverage was recorded' if total.zero?
    hit = files.values.sum { |lines| lines.values.count(true) }
    percent = hit * 100.0 / total
    { 'status' => percent >= threshold ? 'pass' : 'mismatch',
      'lines_hit' => hit, 'lines_total' => total, 'percent' => percent.round(2),
      'threshold' => threshold, 'files' => files.length }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    raise 'Usage: lcov_coverage.rb <lcov.info> [threshold-percent]' unless (1..2).cover?(ARGV.length)
    threshold = ARGV[1] ? Float(ARGV[1]) : 40
    result = LcovCoverage.measure(File.read(ARGV[0]), threshold: threshold)
    puts JSON.pretty_generate(result)
    exit(result['status'] == 'pass' ? 0 : 1)
  rescue StandardError => error
    puts JSON.generate('status' => 'unverified', 'reason' => error.message)
    exit 1
  end
end
