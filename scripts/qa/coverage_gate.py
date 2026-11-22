#!/usr/bin/env python3
"""Fail-closed LCOV line-coverage gate; execution counts are not covered lines."""

import argparse
from decimal import Decimal, InvalidOperation
import os
from pathlib import Path
import sys


def line_coverage(report):
    """Merge repeated source/line records, counting each covered line once."""
    lines = {}
    source = None
    for number, raw in enumerate(report.splitlines(), 1):
        row = raw.strip()
        if row.startswith("SF:"):
            if source is not None or not row[3:]:
                raise ValueError(f"invalid source record at report line {number}")
            source = os.path.normpath(row[3:])
        elif row.startswith("DA:"):
            fields = row[3:].split(",")
            if source is None or len(fields) not in (2, 3):
                raise ValueError(f"invalid line record at report line {number}")
            if not all(value.isascii() and value.isdecimal() for value in fields[:2]):
                raise ValueError(f"invalid line/count at report line {number}")
            line, count = map(int, fields[:2])
            if line < 1:
                raise ValueError(f"invalid source line at report line {number}")
            key = (source, line)
            lines[key] = lines.get(key, False) or count > 0
        elif row == "end_of_record":
            if source is None:
                raise ValueError(f"end without source at report line {number}")
            source = None
    if source is not None:
        raise ValueError("truncated report: missing end_of_record")
    if not lines:
        raise ValueError("report contains no executable line records")
    return sum(lines.values()), len(lines)


def threshold_value(value):
    try:
        threshold = Decimal(value)
    except InvalidOperation as error:
        raise argparse.ArgumentTypeError("threshold must be a number from 0 to 100") from error
    if not threshold.is_finite() or not 0 <= threshold <= 100:
        raise argparse.ArgumentTypeError("threshold must be a number from 0 to 100")
    return threshold


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--threshold", type=threshold_value, default=Decimal(40))
    args = parser.parse_args(argv)
    try:
        hit, total = line_coverage(args.report.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"Coverage gate failed: {error}", file=sys.stderr)
        return 1
    coverage = Decimal(hit) * 100 / total
    passed = Decimal(hit) * 100 >= args.threshold * total
    message = (f"Line coverage: {coverage:.2f}% ({hit}/{total} unique lines; "
               f"threshold {args.threshold}%) — {'PASS' if passed else 'FAIL'}")
    print(message)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(message + "\n")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
