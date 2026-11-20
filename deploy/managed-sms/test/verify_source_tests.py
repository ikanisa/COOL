#!/usr/bin/env python3
"""Require every named SMS source test to pass; a green Deno exit can hide ignores."""
import os
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
EXPECTED = {
    './test/worker.test.ts': (
        'production entrypoint remains closed regardless of caller-controlled configuration',
        'authority and route checks ignore forged forwarding headers before admission',
        'actual gateway enforces application scopes and durable message replay identity',
        'non-receipt bodies, missing idempotency and cross-origin requests stop before database access',
        'unknown admission or connection cleanup never becomes a success',
        'unconfirmed admission close returns 503 and never retries the close',
        'oversized input is refused before admission and outbound providers remain disabled',
        'non-receipt, missing scope, empty and cross-app identities never return message or history',
        'unexpected receipt response kind, identity, envelope or duplicate JSON fails closed',
        'aborted stalled body is canceled before any database admission',
        'stalled body times out and is canceled before admission',
        'late fence close retains its pool under the background owner',
        'background grace expiry leaves an unfinished pool quarantined',
        'authorized receipt reconciliation retains expected related history',
        'only exact allowed browser preflights reach receipt routes without admission',
        'verified browser origin receives no-store CORS on early denial, success and unavailable responses',
    ),
    './test/transactions.test.ts': (
        'fresh backend transactions re-establish role, GUC and admission before every query',
        'wrong login fails before operation and rolls back',
        'lost COMMIT acknowledgement is not retried, rolled back or recycled',
        'lost rollback acknowledgement quarantines the transaction',
        'lost registration acknowledgement is not reissued or recycled',
        'lost close acknowledgement is reconciled from original status without closing twice',
        'empty identity, missing receipt kind and missing scope are denied with a confirmed rollback',
    ),
    './test/handler-access.test.ts': (
        'the real managed adapter permits valid receipt create and reconciliation',
        'real managed access check gives a uniform empty 404 for revoked, unknown and disallowed credentials only after rollback',
        'unconfirmed access rollback remains unavailable and the transaction is quarantined',
        'a malformed database lookup is uncertain rather than a confirmed credential denial',
    ),
}


def require_complete_report(xml, expected=EXPECTED):
    """Accept only the expected suites and named passing cases, with no skips."""
    try:
        root = ET.fromstring(xml)
        total = sum(len(cases) for cases in expected.values())
        if (root.tag != 'testsuites' or root.get('tests') != str(total)
                or root.get('errors') != '0' or root.get('failures') != '0'):
            raise ValueError('unexpected report totals')
        suites = list(root)
        if len(suites) != len(expected):
            raise ValueError('missing or unexpected suite')
        seen = set()
        for suite in suites:
            name = suite.get('name')
            if suite.tag != 'testsuite' or name not in expected or name in seen:
                raise ValueError('unexpected suite')
            seen.add(name)
            cases = list(suite)
            if (suite.get('tests') != str(len(expected[name])) or suite.get('disabled') != '0'
                    or suite.get('errors') != '0' or suite.get('failures') != '0'
                    or suite.get('skipped', '0') != '0' or len(cases) != len(expected[name])):
                raise ValueError('incomplete suite')
            actual = []
            for case in cases:
                if case.tag != 'testcase' or case.get('classname') != name or list(case):
                    raise ValueError('case skipped, failed or malformed')
                actual.append(case.get('name'))
            if len(set(actual)) != len(actual) or set(actual) != set(expected[name]):
                raise ValueError('missing or unexpected case')
        return total
    except (ET.ParseError, ValueError, TypeError) as exc:
        raise ValueError('SMS source test coverage unconfirmed') from exc


def main():
    deno = os.environ.get('COLLECT_DENO', 'deno')
    flags = ['--frozen-lockfile', '--lock=deno.lock', '--node-modules-dir=none']
    try:
        check = subprocess.run([deno, 'check', *flags, 'src/worker.ts', 'test/local-postgres-fixture.ts'],
                               cwd=ROOT, timeout=120, check=False)
        if check.returncode:
            return check.returncode
        run = subprocess.run([deno, 'test', *flags, '--reporter=junit',
                              'test/worker.test.ts', 'test/transactions.test.ts', 'test/handler-access.test.ts'],
                             cwd=ROOT, timeout=120, check=False, capture_output=True, text=True)
        if run.returncode:
            sys.stderr.write(run.stderr + run.stdout)
            return run.returncode
        count = require_complete_report(run.stdout)
        print(f'All {count} named managed SMS source tests passed; no skips.')
        return 0
    except (OSError, subprocess.TimeoutExpired, ValueError) as exc:
        print(f'SMS source test qualification failed: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
