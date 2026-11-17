"""Run the existing disposable canonical-adoption/Allocate proof on a second format.

This wrapper changes only the test fixture compiler selected by the existing
qualification harness. It does not use a live database, a provider, or real SMS.
The ordinary qualifier still owns and checks clone identity, database isolation,
the work lease, source pins, cleanup, and all original financial assertions.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
from scripts.self_hosted import qualify_burimunsi_retained as qualifier


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot-directory', type=Path, required=True)
    parser.add_argument('--release', type=Path, required=True)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--reuse-empty', type=Path)
    parser.add_argument('--install-state', choices=('fenced', 'uninitialized'), default='fenced')
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    args.contract = 'canonical-adoption'
    original_compile = qualifier.compile_fixture_process
    original_format = qualifier.fixture_format
    baseline = ROOT / 'supabase/tests/burimunsi/compile-canonical-adoption-fixture.mjs'
    alternate = ROOT / 'supabase/tests/burimunsi/compile-canonical-alternate-fixture.mjs'

    def compile_variant(node, compiler, output, kind):
        if kind == 'canonical-adoption':
            if compiler != baseline:
                raise ValueError('Expected original canonical qualification compiler')
            compiler = alternate
        return original_compile(node, compiler, output, kind)

    def variant_format(kind):
        if kind == 'canonical-adoption':
            return 'collect.burimunsi.canonical-alternate-sql-fixture.v1'
        return original_format(kind)

    qualifier.compile_fixture_process = compile_variant
    qualifier.fixture_format = variant_format
    result = qualifier.qualify(args)
    if args.execute:
        if result.get('status') != 'pass' or result.get('production_acceptance') is not False:
            raise ValueError('Alternate format qualification did not pass')
        qualifier.private_json(args.directory / 'alternate-fixture-result.json', {
            'format': 'collect.burimunsi.alternate-fixture-evidence.v1',
            'status': 'pass',
            'qualifier_result': 'result.json',
            'allocation_result': 'canonical-native-allocation-result.json',
            'compiler_sha256': qualifier.sha(alternate.read_bytes()),
            'wrapper_sha256': qualifier.sha(Path(__file__).read_bytes()),
            'model_output': 'synthetic fixture; no OpenAI call',
            'production_acceptance': False,
        })
    print(json.dumps({**result, 'fixture': 'synthetic-alternate'}, sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(json.dumps({'status': 'refused_or_unconfirmed', 'error_class': type(error).__name__,
                          'private_values_disclosed': False}), file=sys.stderr)
        sys.exit(1)
