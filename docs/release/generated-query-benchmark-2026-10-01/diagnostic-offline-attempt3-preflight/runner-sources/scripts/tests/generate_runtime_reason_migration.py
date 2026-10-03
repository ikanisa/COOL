#!/usr/bin/env python3
"""Generate the one-body runtime reason correction from preserved147 source.

No database or provider is contacted. The candidate is saved outside migration
sources until its ordinary-owner current-bundle SQL acceptance is reviewed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "supabase/migrations/20260930150000_runtime_control_governance.sql"
NAME = "20260930235600_runtime_control_reason_whitespace.sql"
OLD = "reason_text text:=btrim(coalesce(p_reason,''));"
NEW = "reason_text text:=collect_admin_access.normalized_operator_reason(p_reason);"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists() or not output.is_relative_to(ROOT / 'docs/release'):
        parser.error('Fresh local release candidate directory required')
    source = BASE.read_bytes()
    matches = re.findall(r'create function public\.admin_update_runtime_control_v1\(.*?end \$\$;', source.decode(), re.S)
    if len(matches) != 1 or matches[0].count(OLD) != 1:
        raise RuntimeError('Exact single original runtime updater and reason initializer required')
    original = matches[0]
    corrected = original.replace('create function ', 'create or replace function ', 1).replace(OLD, NEW)
    candidate = ("begin;\n\n"
        "-- Current SQL probes accepted invisible Unicode reasons before real\n"
        "-- settings changes. Reuse235500's private normalization before the\n"
        "-- existing8..500 bound and audit hash. Preserve all family, permission,\n"
        "-- identity, parent, revision, publication, ACK and no-op contracts.\n"
        "do $$begin\n"
        " if to_regprocedure('collect_admin_access.normalized_operator_reason(text)') is null then\n"
        "  raise exception 'runtime_control_reason_normalizer_required' using errcode='55000';\n"
        " end if;\n"
        "end$$;\n\n" + corrected + "\n\nnotify pgrst,'reload schema';\ncommit;\n")
    output.mkdir(parents=True, mode=0o700)
    (output / NAME).write_text(candidate)
    (output / 'prior-function.sql').write_text(original + '\n')
    (output / 'baseline-source.sql').write_bytes(source)
    (output / 'runner.py').write_bytes(Path(__file__).read_bytes())
    (output / 'generation.json').write_text(json.dumps({
        'kind':'pure_source_single_runtime_reason_body_correction',
        'source':str(BASE.relative_to(ROOT)), 'source_sha256':hashlib.sha256(source).hexdigest(),
        'candidate':NAME, 'candidate_sha256':hashlib.sha256(candidate.encode()).hexdigest(),
        'database_called':False, 'source_migrations_written':False,
        'replacement_count':1, 'outer_sql_terminator_retained':True,
        'sql_acceptance_verified':False,
    }, indent=2) + '\n')
    if BASE.read_bytes() != source:
        raise RuntimeError('Baseline source changed during generation')


if __name__ == '__main__':
    main()
