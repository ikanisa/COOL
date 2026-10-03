#!/usr/bin/env python3
"""Bounded proof of the root-owned two-line helper correction."""
from pathlib import Path
import ast
import datetime as dt
import hashlib
import importlib.util
import json
import shutil
import sys

ROOT = Path(sys.argv[1]).resolve()
OUT = Path(__file__).resolve().parent
BASE = OUT.parent.parent
OLD = BASE / "consumer-validation2"
REVIEW = BASE / "current-source-after-comment-correction.json"


def write(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def sha(data):
    return hashlib.sha256(data).hexdigest()


spec = importlib.util.spec_from_file_location("held_consumer_proof_helpers", OLD / "attempt3/run-proof.py")
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)
helpers.OUT = OUT
helpers.ROOT = ROOT
helpers.REVIEW = REVIEW


def ordinary216():
    path = ROOT / "docs/release/critical-implementation-2026-10-01/ordinary-schema-catalog209-execution1/execution-result.json"
    original = json.loads(path.read_text())["source_after"]
    assert len(original) == 216
    current = {name: sha((ROOT / name).read_bytes()) if (ROOT / name).is_file() else None for name in original}
    changes = [name for name in original if original[name] != current[name]]
    migrations = {name for name in original if name.startswith("supabase/migrations/") and name.endswith(".sql")}
    live_migrations = {str(p.relative_to(ROOT)) for p in (ROOT / "supabase/migrations").glob("*.sql")}
    assert len(migrations) == 209 and migrations == live_migrations and not changes
    return {"receipt": str(path), "receipt_identity": helpers.identity(path),
            "source_after_sha256": original, "current_sha256": current,
            "changed": changes, "migration_count": 209, "total_source_count": 216,
            "scope": "exact retained ordinary209 source list; outside216 tooling is guarded separately"}


def inheritance():
    old = (OUT.parent / "helper-before.sh").read_text()
    current = (ROOT / "scripts/supabase_cli_helpers.sh").read_text()
    old_line = r'''sql = sql.sub(/\Abegin\s*;\s*/i, "")'''
    new_lines = r'''# Preserve leading line comments while removing the outer transaction wrapper.
sql = sql.sub(/\A((?:\s+|--[^\r\n]*(?:\r?\n|\z))*)begin\s*;\s*/i, '\1')'''
    assert old.count(old_line) == 1
    assert old.replace(old_line, new_lines, 1) == current
    prior_source = (OLD / "attempt3/additional-ordering.py").read_text()
    new_source = (OUT / "management-consumer.py").read_text()
    name = "test_management_fallback_checks_exact_version_before_each_sql_write"
    def method(source):
        return next(n for n in ast.walk(ast.parse(source)) if isinstance(n, ast.FunctionDef) and n.name == name)
    original = method(prior_source)
    proposed = method(new_source)
    prefix_preserved = [ast.dump(n, include_attributes=False) for n in original.body] == [ast.dump(n, include_attributes=False) for n in proposed.body[:len(original.body)]]
    assert prefix_preserved
    old_source = json.loads((OLD / "source-hold-release.json").read_text())["all403_transitive_inputs"]
    current_source = helpers.snapshot()
    changes = [n for n in sorted(set(old_source) | set(current_source)) if old_source.get(n) != current_source.get(n)]
    assert changes == ["scripts/supabase_cli_helpers.sh"]
    return {"complete_helper_delta_is_only_reviewed_line_comment_normalizer_and_comment": True,
            "remaining_terminator_commit_readback_server_guards_unchanged": True,
            "old_helper_identity": helpers.identity(OUT.parent / "helper-before.sh"),
            "current_helper_identity": helpers.identity(ROOT / "scripts/supabase_cli_helpers.sh"),
            "original_failed_probe_method_ast_sha256": sha(ast.dump(original, include_attributes=False).encode()),
            "all_original_probe_statements_and_assertions_retained_as_exact_ast_prefix": prefix_preserved,
            "additional_probe_assertions": "exact209 readback, last208+209 versions, preserved comment, human/release flags false",
            "source_changes_since_original_failure": changes,
            "unaffected_previous_results": {"maintained27": "27PASS historical source before parser correction; normalization path not exercised",
                                           "additional3": "full staging and two readiness refusals PASS historical source; no normalization-path execution"},
            "not_claimed": "new full45 run, new full27 run, green original4 probe run, real database/provider acceptance"}


if __name__ == "__main__":
    if (OUT / "inputs-before.json").exists():
        raise SystemExit("Refuse proof overwrite")
    before = helpers.snapshot()
    hashes = json.loads(REVIEW.read_text())["after_sha256"]
    assert len(before) == 403 and len(hashes) == 12
    assert all(before[n]["sha256"] == digest for n, digest in hashes.items())
    inherited = inheritance()
    write("invariant-inheritance.json", inherited)
    ordinary_before = ordinary216()
    write("ordinary216-before.json", ordinary_before)
    write("inputs-before.json", {"at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                                 "reviewed12_inputs": {n: before[n] for n in hashes},
                                 "all403_transitive_inputs": before,
                                 "review_receipt_identity": helpers.identity(REVIEW)})
    runtime = json.loads((OLD / "attempt3/execution-inputs.json").read_text())
    env = runtime["environment"]
    python_before = helpers.identity(helpers.PYTHON)
    node = Path(runtime["node_path"])
    node_before = helpers.identity(node)
    assert python_before == runtime["python"] and node_before == runtime["node_identity"]
    write("execution-inputs.json", {"python_path": str(helpers.PYTHON), "python": python_before,
                                   "python_version": sys.version, "node_path": str(node), "node": node_before,
                                   "environment": env, "credential_inheritance": False,
                                   "consumer_script": helpers.identity(OUT / "management-consumer.py"),
                                   "runner": helpers.identity(Path(__file__)),
                                   "borrowed_bound_process_helper": helpers.identity(OLD / "attempt3/run-proof.py"),
                                   "postgres_local_probe_C_locale_and_one_second_fixture_bound_unchanged": True,
                                   "real_provider_docker_database_download_execution": False})
    results = []
    results.append(helpers.run("node-local-version", [str(node), "--version"], 5, env))
    assert results[-1]["exit_code"] == 0
    results.append(helpers.run("affected-management-and-boundaries", [str(helpers.PYTHON), "-I", "-B", str(OUT / "management-consumer.py"), str(ROOT)], 350, env))
    after = helpers.snapshot()
    changes = [n for n in sorted(set(before) | set(after)) if before.get(n) != after.get(n)]
    ordinary_after = ordinary216()
    write("ordinary216-after.json", ordinary_after)
    python_after = helpers.identity(helpers.PYTHON)
    node_after = helpers.identity(node)
    space = shutil.disk_usage(ROOT)
    result = {"at_utc": dt.datetime.now(dt.timezone.utc).isoformat(), "results": results,
              "reviewed12_inputs_after": {n: after[n] for n in hashes}, "all403_transitive_inputs_after": after,
              "source_identity_changes": changes,
              "all209_sql_and_retained_ordinary216_hashes_unchanged": ordinary_after["current_sha256"] == ordinary_before["current_sha256"],
              "python_after": python_after, "node_after": node_after,
              "runtime_identity_changes": python_before != python_after or node_before != node_after,
              "owned_groups_observed_absent_at_completion": all(r["process_group_absent"] for r in results),
              "output_threshold_is_polled_not_strict_stream_cap": True,
              "separate_group_descendant_census_not_claimed": True,
              "source_hold_released": not changes and python_before == python_after and node_before == node_after,
              "all_exit_codes_zero": all(r["exit_code"] == 0 for r in results),
              "disk_available_bytes": space.free, "disk_available_gib": round(space.free / 1024**3, 3),
              "storage_peak_or_native_floor_causality_not_claimed": True,
              "maintained_source_modified_by_worker": False}
    write("completed-results.json", result)
    raise SystemExit(0 if result["source_hold_released"] and result["all_exit_codes_zero"] and result["owned_groups_observed_absent_at_completion"] else 1)
