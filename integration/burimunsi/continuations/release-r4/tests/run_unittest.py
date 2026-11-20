#!/usr/bin/env python3
"""Run the real suite and write counts from unittest, not from a claimed pass flag."""
import argparse
import json
from pathlib import Path
import sys
import unittest

def main():
    p=argparse.ArgumentParser();p.add_argument('--result',type=Path,required=True);a=p.parse_args()
    if a.result.exists():raise SystemExit('Result output already exists')
    suite=unittest.defaultTestLoader.discover(str(Path(__file__).resolve().parent),pattern='test_*.py')
    r=unittest.TextTestRunner(verbosity=2).run(suite)
    failed=len(r.failures)+len(r.errors)+len(r.expectedFailures)+len(r.unexpectedSuccesses)
    skipped=len(r.skipped);executed=r.testsRun-skipped
    out={'executed':executed,'failed':failed,'skipped':skipped,'blocked':0,
         'collected':r.testsRun,'failed_test_ids':[t.id() for t,_ in r.failures+r.errors],
         'skipped_test_ids':[t.id() for t,_ in r.skipped]}
    a.result.parent.mkdir(parents=True,exist_ok=True)
    with a.result.open('x') as f:json.dump(out,f,sort_keys=True,indent=2);f.write('\n')
    return 0 if executed>0 and failed==0 and skipped==0 else 2
if __name__=='__main__':raise SystemExit(main())
