#!/usr/bin/env python3
import unittest
from verify_source_tests import require_complete_report

EXPECTED = {'a': ('one', 'two'), 'b': ('three',)}
GOOD = '''<testsuites tests="3" failures="0" errors="0">
<testsuite name="a" tests="2" disabled="0" errors="0" failures="0">
<testcase name="one" classname="a"/><testcase name="two" classname="a"/>
</testsuite><testsuite name="b" tests="1" disabled="0" errors="0" failures="0">
<testcase name="three" classname="b"/></testsuite></testsuites>'''


class ReportTest(unittest.TestCase):
    def test_exact_success(self):
        self.assertEqual(require_complete_report(GOOD, EXPECTED), 3)

    def test_green_but_incomplete_reports_are_rejected(self):
        changes = (
            GOOD.replace('name="two" classname="a"/>', 'name="two" classname="a"><skipped/></testcase>'),
            GOOD.replace('disabled="0"', 'disabled="1"', 1),
            GOOD.replace('name="two"', 'name="one"'),
            GOOD.replace('name="two"', 'name="different"'),
            GOOD.replace('tests="3"', 'tests="2"', 1),
            GOOD.replace('failures="0"', 'failures="1"', 1),
            GOOD.replace('classname="a"', 'classname="b"', 1),
            GOOD.replace('<testcase name="two" classname="a"/>', ''),
            GOOD.replace('name="b" tests="1"', 'name="a" tests="1"'),
            '<testsuites',
        )
        for report in changes:
            with self.subTest(report=report), self.assertRaises(ValueError):
                require_complete_report(report, EXPECTED)


if __name__ == '__main__':
    unittest.main()
