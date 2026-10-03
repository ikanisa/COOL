#!/usr/bin/env python3
"""Actual offline rollback probes for151 installer's precommit guards."""
import argparse
import importlib.util
import json
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("installer", Path(__file__).with_name("staged_runtime_installation.py"))
I = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(I)
R = I.R


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    output = a.output.resolve()
    if not output.is_relative_to(I.ROOT / "docs/release") or output.exists():
        p.error("Fresh repository evidence directory required")
    R.guard(150, "20260930180000")
    source_path = I.ROOT / "supabase/migrations/20260930200000_admin_automation_navigation.sql"
    source = source_path.read_text()
    output.mkdir(mode=0o700)
    probes = (
        ("original_row_deletion", "delete from public.app_realtime_events;", "Original row removed or changed"),
        ("original_function_configuration", "alter function public.user_can_read_collection(uuid,uuid) set statement_timeout='17s';", "Unexpected original catalog mutation"),
        ("undeclared_table", "create table collect_security.unexpected_upgrade_probe(id integer);", "Unexpected new catalog object"),
    )
    cases = []
    for name, mutation, expected in probes:
        target = output / name
        before = R.prepare(target, 150, "20260930180000")
        candidate = source.removesuffix("commit;\n") + mutation + "\ncommit;\n"
        reviewed = target / "guard-probe-source.sql"
        reviewed.write_text(candidate)
        R.reviewed_source(reviewed, R.sha(reviewed.read_bytes()), target)
        sql = I.transaction(candidate, "20260930200000", commit=True)
        (target / "executed-upgrade.sql").write_text(sql)
        rejected = False
        try:
            R.execute(sql, target)
        except RuntimeError:
            rejected = True
        after = R.snapshot()
        R.save(target / "after.json", after)
        stderr = (target / "stderr").read_text()
        case = dict(name=name, rejection_observed=rejected,
                    intended_guard_observed=expected in stderr,
                    full_baseline_restored=before == after,
                    executed_sql_sha256=R.sha(sql.encode()),
                    stdout_sha256=R.sha((target / "stdout").read_bytes()),
                    stderr_sha256=R.sha((target / "stderr").read_bytes()))
        cases.append(case)
        R.save(target / "validation.json", case)
        if not all(case[k] for k in ("rejection_observed", "intended_guard_observed", "full_baseline_restored")):
            R.save(output / "validation.json", dict(status="fail", cases=cases))
            raise RuntimeError("Actual protection probe did not prove rejection and full restoration: " + name)
        R.guard(150, "20260930180000")
    R.save(output / "validation.json", dict(status="pass", cases=cases,
        original_source_sha256=R.sha(source_path.read_bytes()),
        installer_sha256=R.sha(Path(I.__file__).read_bytes()),
        harness_sha256=R.sha(Path(__file__).read_bytes()),
        provider_calls=False, hosted_writes=False, baseline_table_count=149,
        sequences_restored=False))
    print(json.dumps(dict(status="pass", actual_corruption_probes=len(cases))))


if __name__ == "__main__":
    main()
