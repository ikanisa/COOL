# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../qa/lcov_coverage'

class LcovCoverageTest < Minitest::Test
  def test_repeated_execution_cannot_inflate_covered_lines
    result = LcovCoverage.measure("SF:lib/app.dart\nDA:1,900\nDA:2,0\nDA:3,0\nend_of_record\n")
    assert_equal 1, result['lines_hit']
    assert_equal 3, result['lines_total']
    assert_equal 33.33, result['percent']
    assert_equal 'mismatch', result['status']
  end

  def test_duplicate_records_merge_by_file_and_line
    result = LcovCoverage.measure(<<~LCOV)
      SF:lib/a.dart
      DA:1,0
      DA:2,3
      end_of_record
      SF:lib/a.dart
      DA:1,4
      DA:2,0
      end_of_record
      SF:lib/b.dart
      DA:1,0
      end_of_record
    LCOV
    assert_equal 2, result['lines_hit']
    assert_equal 3, result['lines_total']
    assert_equal 66.67, result['percent']
    assert_equal 'pass', result['status']
  end

  def test_missing_empty_and_malformed_line_evidence_fails_closed
    ['', "SF:a\nend_of_record\n", "DA:1,2\n", "SF:a\nDA:1,-1\nend_of_record\n",
     "SF:a\nDA:0,1\nend_of_record\n", "SF:a\nDA:1,2\n",
     "SF:a\nSF:b\nDA:1,2\nend_of_record\n", "SF:\nend_of_record\n"].each do |content|
      assert_raises(RuntimeError) { LcovCoverage.measure(content) }
    end
  end

  def test_exact_threshold_passes_without_rounding_up
    report = "SF:a\nDA:1,1\nDA:2,0\nDA:3,0\nend_of_record\n"
    assert_equal 'mismatch', LcovCoverage.measure(report, threshold: 33.34)['status']
    assert_equal 'pass', LcovCoverage.measure(report, threshold: 100.0 / 3)['status']
  end

  def test_invalid_threshold_cannot_disable_the_check
    [-1, 101, Float::NAN, Float::INFINITY].each do |threshold|
      assert_raises(RuntimeError) { LcovCoverage.measure('', threshold: threshold) }
    end
  end
end
