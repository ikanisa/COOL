#!/usr/bin/env python3
"""Generate the reproduced two-body sensitive-reason correction as a candidate.

The original authority, bounds, locks, audit and retry bodies are retained.
No database is contacted and migration sources are not changed here.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "supabase/migrations/20260930233000_sensitive_admin_authority.sql"
NAME = "20260930235700_sensitive_reason_whitespace.sql"
INITIALIZERS = {
    "admin_reveal_raw_sms": "reason text := btrim(coalesce(p_reason,''));",
    "admin_retry_notification": "reason text := trim(coalesce(p_reason, ''));",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    output = parser.parse_args().output.resolve()
    if output.exists() or not output.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh local release candidate directory required")
    source = BASE.read_bytes()
    originals, corrected = {}, []
    for name, initializer in INITIALIZERS.items():
        matches = re.findall(r"CREATE OR REPLACE FUNCTION public\." + name
                             + r"\(.*?AS \$function\$.*?\$function\$;", source.decode(), re.S)
        if len(matches) != 1 or matches[0].count(initializer) != 1:
            raise RuntimeError("Exact original sensitive routine/initializer required: " + name)
        originals[name] = matches[0]
        corrected.append(matches[0].replace(initializer,
                         "reason text := collect_admin_access.normalized_operator_reason(p_reason);"))
    candidate = ("begin;\n\n"
        "-- Actual current-bundle probes allowed BOM-only reasons and retained\n"
        "-- invisible Unicode padding in reveal/retry audit reasons. Normalize\n"
        "-- through235500's private helper before the original1..1000 bounds.\n"
        "-- Keep authority, locks, API attributes, audit, retry and ACK semantics.\n"
        "do $$begin\n"
        " if to_regprocedure('collect_admin_access.normalized_operator_reason(text)') is null then\n"
        "  raise exception 'sensitive_reason_normalizer_required' using errcode='55000';\n"
        " end if;\nend$$;\n\n" + "\n\n".join(corrected)
        + "\n\nnotify pgrst,'reload schema';\ncommit;\n")
    output.mkdir(parents=True, mode=0o700)
    (output / NAME).write_text(candidate)
    (output / "baseline-source.sql").write_bytes(source)
    (output / "runner.py").write_bytes(Path(__file__).read_bytes())
    for name, body in originals.items():
        (output / (name + "-prior.sql")).write_text(body + "\n")
    (output / "generation.json").write_text(json.dumps({
        "kind": "pure_source_two_sensitive_reason_body_correction",
        "source": str(BASE.relative_to(ROOT)),
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "candidate": NAME, "candidate_sha256": hashlib.sha256(candidate.encode()).hexdigest(),
        "replacement_count": 2, "outer_sql_terminators_retained": True,
        "database_called": False, "source_migrations_written": False,
        "sql_acceptance_verified": False,
    }, indent=2) + "\n")
    if BASE.read_bytes() != source:
        raise RuntimeError("Original sensitive migration changed during generation")


if __name__ == "__main__":
    main()
