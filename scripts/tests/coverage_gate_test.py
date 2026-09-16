import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GATE = Path(__file__).resolve().parents[1] / "qa/coverage_gate.py"
SPEC = importlib.util.spec_from_file_location("coverage_gate", GATE)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def record(source, counts):
    return (f"SF:{source}\n" + "".join(
        f"DA:{index},{count}\n" for index, count in enumerate(counts, 1)
    ) + "end_of_record\n")


class CoverageGateTest(unittest.TestCase):
    def test_repeated_execution_cannot_inflate_coverage(self):
        self.assertEqual((1, 5), gate.line_coverage(record("lib/a.dart", [999, 0, 0, 0, 0])))

    def test_merge_records_counts_each_source_line_once(self):
        report = record("./lib/a.dart", [0, 8]) + record("lib/a.dart", [7, 0])
        report += record("lib/b.dart", [0, 0])
        self.assertEqual((2, 4), gate.line_coverage(report))

    def test_checksum_and_metadata_do_not_affect_line_counts(self):
        report = "TN:unit\nSF:lib/a.dart\nDA:1,5,abc123\nLF:1\nLH:1\nend_of_record\n"
        self.assertEqual((1, 1), gate.line_coverage(report))

    def test_invalid_or_missing_records_fail_closed(self):
        for report in ("", "TN:unit\n", "SF:a\nend_of_record\n", "DA:1,1\n",
                       "SF:\nDA:1,1\nend_of_record\n", "SF:a\nSF:b\n",
                       "SF:a\nDA:1,1\n", "end_of_record\n",
                       "SF:a\nDA:0,1\nend_of_record\n",
                       "SF:a\nDA:1,-1\nend_of_record\n",
                       "SF:a\nDA:x,1\nend_of_record\n",
                       "SF:a\nDA:1,1,checksum,extra\nend_of_record\n"):
            with self.subTest(report=report), self.assertRaises(ValueError):
                gate.line_coverage(report)

    def invoke(self, content, threshold="40"):
        with tempfile.TemporaryDirectory() as temporary:
            report = Path(temporary) / "coverage.info"
            if content is not None:
                report.write_text(content)
            return subprocess.run([sys.executable, str(GATE), str(report),
                                   "--threshold", threshold], capture_output=True, text=True)

    def test_missing_file_and_empty_report_exit_failure(self):
        for content in (None, ""):
            self.assertEqual(1, self.invoke(content).returncode)

    def test_exact_threshold_and_below_threshold(self):
        passing = self.invoke(record("lib/a.dart", [7, 1, 0, 0, 0]))
        self.assertEqual(0, passing.returncode, passing.stderr)
        self.assertIn("40.00% (2/5 unique lines", passing.stdout)
        failing = self.invoke(record("lib/a.dart", [999, 0, 0, 0, 0]))
        self.assertEqual(1, failing.returncode)
        self.assertIn("20.00%", failing.stdout)

    def test_display_rounding_cannot_pass_below_threshold(self):
        result = self.invoke(record("a", [1, 0, 0]), "33.334")
        self.assertEqual(1, result.returncode)

    def test_invalid_threshold_is_rejected(self):
        for threshold in ("-1", "101", "nan", "inf", "bad"):
            self.assertEqual(2, self.invoke(record("a", [1]), threshold).returncode)


if __name__ == "__main__":
    unittest.main()
