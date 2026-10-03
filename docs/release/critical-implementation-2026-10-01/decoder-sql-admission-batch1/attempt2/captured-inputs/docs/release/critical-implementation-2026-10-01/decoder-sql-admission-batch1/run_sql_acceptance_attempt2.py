"""Exact 195-source replay and affected decoder admission consumers, offline."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import types

ROOT = Path(__file__).resolve().parents[4]
PACKET = Path(__file__).resolve().parent
HELPER = ROOT / "scripts/tests/collect_current_release_upgrade_uat.py"
CONSUMER = ROOT / "scripts/tests/play_integrity_fixture_consumers_uat.py"
BASELINE = ROOT / ".cache/receipt-foundation-attempt8/schema-only.sql"
PREREQUISITE = ROOT / "scripts/sql/receipt_transport_platform_prerequisites.sql"
NEW_MIGRATION = "supabase/migrations/20261001235500_roster_decoder_toolchain_admission.sql"
RACE = "scripts/tests/roster_resource_concurrency_uat.rb"
SQL_CASES = {
    "scripts/tests/roster_resource_integrity_uat.sql": "ROSTER_RESOURCE_UAT_CHECKS:",
    "scripts/tests/roster_resource_final_compatibility_uat.sql": "FINAL146_COMPATIBILITY_PASS",
    "scripts/tests/roster_fresh_auth_recovery_uat.sql": "ROSTER_FRESH_AUTH_UAT_PASS|",
}
IDENTITIES = {
    str(HELPER.relative_to(ROOT)): "343cd3b21ac9629347b0080640891eac3bdacdea7df11752b129c5f943b6c33b",
    str(CONSUMER.relative_to(ROOT)): "a01f088d8101653618d4fb336122f75146a911fd17c299ff03c82ff407af8000",
    str(BASELINE.relative_to(ROOT)): "77262947961ac1a724195ea77bdb98088cebd30caecc625ded1d4a93ccbf6d3d",
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def load_module(path, name):
    module = types.ModuleType(name)
    module.__file__ = str(path)
    exec(compile(path.read_bytes(), str(path), "exec"), module.__dict__)
    return module


CATALOG = """
select jsonb_object_agg(n.nspname||'.'||p.proname,jsonb_build_object(
 'definition',pg_get_functiondef(p.oid),'oid',p.oid,'owner',pg_get_userbyid(p.proowner),
 'security_definer',p.prosecdef,'config',p.proconfig,'acl',p.proacl::text,
 'execute',jsonb_build_object('anon',has_function_privilege('anon',p.oid,'EXECUTE'),
  'authenticated',has_function_privilege('authenticated',p.oid,'EXECUTE'),
  'service_role',has_function_privilege('service_role',p.oid,'EXECUTE'))))
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where (n.nspname='public' and p.proname in ('verify_roster_source_integrity','_lock_notification_session_gate'))
 or (n.nspname='collect_hybrid' and p.proname in
 ('verify_roster_source_integrity_guarded_149','guard_roster_service_recovery','require_roster_actor','require_roster_actor_authority'));
"""


def main():
    report = PACKET / "attempt2"
    if report.exists():
        raise ValueError("Inspect an existing attempt; do not repeat an unknown outcome")
    report.mkdir()
    capture = report / "captured-inputs"
    sources = [Path(__file__), HELPER, CONSUMER, BASELINE, PREREQUISITE,
               *[ROOT / p for p in SQL_CASES], ROOT / RACE,
               ROOT / "tools/roster-decoder/decoder.py", ROOT / "tools/roster-decoder/requirements.lock",
               ROOT / "supabase/functions/_shared/roster_decoder.ts",
               *sorted((ROOT / "supabase/migrations").glob("*.sql"))]
    hashes = {}
    for source in sources:
        if not source.is_file() or source.is_symlink():
            raise ValueError("Regular contained source files required")
        rel = str(source.relative_to(ROOT))
        dest = capture / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(source.read_bytes())
        dest.chmod(0o444)
        hashes[rel] = sha(dest)
    if any(hashes.get(p) != h for p, h in IDENTITIES.items()):
        raise ValueError("The explicitly coordinated canonical installer changed")
    helper = load_module(capture / HELPER.relative_to(ROOT), "captured_decoder_sql_helper")
    helper.ROOT = capture
    helper.BASELINE = capture / BASELINE.relative_to(ROOT)
    caller = load_module(capture / CONSUMER.relative_to(ROOT), "captured_decoder_sql_caller")
    items = []
    for source in sorted((capture / "supabase/migrations").glob("*.sql")):
        version, name = source.stem.split("_", 1)
        items.append(dict(path="supabase/migrations/" + source.name, version=version,
                          name=name, body=source.read_text(), sha256=sha(source)))
    if len(items) != 195 or len({i["version"] for i in items}) != 195 or items[193]["path"] != NEW_MIGRATION or items[-1]["version"] != "20261001250000":
        raise ValueError("Exactly the current ordered 195-chain is required")
    result = dict(status="running", started_at_utc=now(), source_hashes=hashes,
                  cases=[], target={}, provider_called=False, hosted_written=False,
                  shared_database_written=False, auth_provider_runtime_tested=False,
                  scope="Actual current SQL admission and preserved roster resource/recovery races in normalized offline PostgreSQL")

    def save():
        (report / "result.json").write_text(json.dumps(result, indent=2) + "\n")

    save()
    try:
        platform, provenance = helper.platform_shape()
        result["platform_shape"] = provenance
        (report / "platform-schema-only.sql").write_text(platform)
        with helper.Target(report, "decoder_admission", result["target"]) as target:
            target.sql(platform, label="captured row-free platform")
            for item in items[:193]:
                if item["version"] == "20261001160000":
                    target.sql(caller.LOCAL_NET, user="supabase_admin", label="existing local image trusted net metadata")
                    target.sql((capture / PREREQUISITE.relative_to(ROOT)).read_text(), user="supabase_admin",
                               label="captured local private-reader prerequisite")
                    result["local_prerequisite"] = dict(net_metadata_sha256=helper.sha(caller.LOCAL_NET.encode()),
                                                       private_reader_sha256=hashes[str(PREREQUISITE.relative_to(ROOT))])
                helper.apply(target, [item], result["target"])
            if target.scalar("select count(*)from supabase_migrations.schema_migrations;") != "193":
                raise ValueError("The real immediate predecessor chain was not installed")
            names = target.json("""select jsonb_agg(format('%I.%I',n.nspname,c.relname)order by n.nspname,c.relname)
                from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind in ('r','p')
                and (n.nspname in ('auth','public','private','realtime')or n.nspname like 'collect\\_%' escape '\\');""")

            def snapshot():
                rows = []
                for name in names:
                    rows.append("select " + helper.quoted(name) + " relation,(select jsonb_build_object('rows',count(*),'sha256',"
                                "encode(extensions.digest(coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),'[]')::text,"
                                "'sha256'),'hex'))from " + name + " t) fingerprint")
                return target.json("select jsonb_object_agg(relation,fingerprint)from(" + " union all ".join(rows) + ") checks;")

            before_catalog = target.json(CATALOG)
            before_data = snapshot()
            inventory = target.json("select jsonb_agg(to_jsonb(i)order by entrypoint,identity_arguments)from collect_hybrid.roster_recovery_guard_inventory i;")
            docker = helper.DOCKER
            endpoint = subprocess.check_output([docker, "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"], text=True, timeout=10).strip()
            if not endpoint.startswith("unix://"):
                raise ValueError("Only the current local Docker Unix endpoint is permitted")
            env = {"PATH": os.pathsep.join([str(Path(docker).parent), "/usr/bin", "/bin", "/usr/sbin", "/sbin"]),
                   "DOCKER_HOST": endpoint, "COLLECT_ROSTER_PROVENANCE_QA": "isolated_clone",
                   "COLLECT_ROSTER_TARGET_MODE": "offline_current_chain", "COLLECT_ROSTER_TARGET_CONTAINER": target.name,
                   "COLLECT_ROSTER_RESOURCE_MIGRATION_SHA": hashes[NEW_MIGRATION]}

            def race(label, expected_pass):
                argv = ["/usr/bin/ruby", str(capture / RACE)]
                run = subprocess.run(argv, cwd=capture, env={**env, "COLLECT_ROSTER_CHECKPOINT": str(report / (label + "-checkpoint.json"))},
                                     capture_output=True, text=True, timeout=240)
                (report / (label + ".stdout")).write_text(run.stdout)
                (report / (label + ".stderr")).write_text(run.stderr)
                if expected_pass:
                    proof = json.loads(run.stdout) if run.returncode == 0 else None
                    passed = run.returncode == 0 and proof is not None and proof["status"] == "pass" and proof["migration_count"] == 195
                    passed = passed and proof["synthetic_graph_removed"] and proof["worker_sessions_remaining"] == 0
                    passed = passed and len(proof["scenarios"]) == 7 and proof["baseline_sha256_before"] == proof["baseline_sha256_after"]
                    passed = passed and proof["controls_sha256_before"] == proof["controls_sha256_after"]
                else:
                    proof = None
                    passed = run.returncode != 0 and "Exact isolated195, inactive providers" in run.stderr
                row = dict(case=label, status="pass" if passed else "fail", exit_code=run.returncode, proof=proof)
                result["cases"].append(row)
                save()
                if not passed:
                    raise ValueError(label + " failed; full logs and checkpoint retained")

            race("actual-pre194-refusal", False)
            if snapshot() != before_data:
                raise ValueError("The live predecessor-chain refusal mutated data")
            helper.apply(target, [items[193]], result["target"])
            after_catalog = target.json(CATALOG)
            alias = "collect_hybrid.verify_roster_source_integrity_guarded_149"
            expected_catalog = json.loads(json.dumps(before_catalog))
            expected_catalog[alias]["definition"] = expected_catalog[alias]["definition"].replace('"pillow":"12.0.0"', '"pillow":"12.3.0"').replace('"pypdf":"6.7.0"', '"pypdf":"6.19.0"')
            if after_catalog != expected_catalog or snapshot() != before_data:
                raise ValueError("Migration changed more than two private implementation pin values")
            if target.json("select jsonb_agg(to_jsonb(i)order by entrypoint,identity_arguments)from collect_hybrid.roster_recovery_guard_inventory i;") != inventory:
                raise ValueError("Recovery guard inventory changed")
            result["catalog_compare"] = dict(before=before_catalog, after=after_catalog,
                                             only_two_private_pin_values_changed=True, public_wrapper_and_acl_unchanged=True,
                                             recovery_inventory_unchanged=True, all_app_table_data_unchanged=True)
            helper.apply(target, items[194:], result["target"])
            if target.json(CATALOG) != after_catalog:
                raise ValueError("Later migrations changed the verified decoder guard or admission catalog")
            if target.scalar("select count(*)from supabase_migrations.schema_migrations;") != "195":
                raise ValueError("The exact 195-source chain registry is required")
            for source, marker in SQL_CASES.items():
                body = (capture / source).read_text()
                if not body.strip().lower().endswith("rollback;"):
                    raise ValueError("Maintained SQL UAT must roll back")
                before = snapshot()
                run = target.sql("select set_config('collect.roster_provenance_qa','isolated_clone',false);" + body,
                                 check=False, label="affected actual current fixture " + source)
                (report / (Path(source).stem + ".log")).write_text(run.stdout + run.stderr)
                passed = run.returncode == 0 and marker in run.stdout and before == snapshot()
                row = dict(source=source, status="pass" if passed else "fail", exit_code=run.returncode,
                           marker_found=marker in run.stdout, all_app_table_rollback_unchanged=before == snapshot())
                if passed and "integrity_uat" in source:
                    row["checks"] = int(next(line.split(marker, 1)[1] for line in run.stdout.splitlines() if line.startswith(marker)))
                    passed = row["checks"] == 31
                if passed and "fresh_auth" in source:
                    parsed = json.loads(next(line.split("|", 1)[1] for line in run.stdout.splitlines() if line.startswith("ROSTER_FRESH_AUTH_ASSERTIONS_JSON|")))
                    if parsed["passed"] != len(parsed["checks"]) or not parsed["checks"]:
                        passed = False
                    row["assertions"] = parsed
                row["status"] = "pass" if passed else "fail"
                result["cases"].append(row)
                save()
                print(row["status"].upper() + " " + source, flush=True)
                if not passed:
                    raise ValueError("Affected current SQL UAT failed: " + source)
            before_races = snapshot()
            race("actual-resource-concurrency", True)
            if snapshot() != before_races:
                raise ValueError("Concurrency cleanup did not restore all app tables")
            result["all_app_tables_checked"] = names
            result["status"] = "pass"
    except Exception as error:
        result.update(status="fail", error=str(error))
        raise
    finally:
        result["source_drift"] = [p for p, h in hashes.items() if not (ROOT / p).is_file() or sha(ROOT / p) != h]
        result["captured_source_drift"] = [p for p, h in hashes.items() if sha(capture / p) != h]
        result["completed_at_utc"] = now()
        if result["source_drift"] or result["captured_source_drift"]:
            result["status"] = "stale-source"
        result["artifact_sha256"] = {str(p.relative_to(report)): sha(p) for p in sorted(report.rglob("*"))
                                     if p.is_file() and p.name != "result.json"}
        save()
    if result["status"] != "pass":
        raise SystemExit(1)
    print(json.dumps({"status": "pass", "migration_count": 195, "completed_cases": len(result["cases"]),
                      "source_files": len(hashes), "owned_target_removed": result["target"].get("task_container_removed")}))


if __name__ == "__main__":
    main()
