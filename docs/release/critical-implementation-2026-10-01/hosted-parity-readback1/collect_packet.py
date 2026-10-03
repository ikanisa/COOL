"""Local metadata analysis only; never calls a hosted service or release runner."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import time
import tomllib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
TARGET = "lhbowpbcpwoiparwnwgt"
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def save(name, value):
    with (HERE / name).open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def identity(path):
    details = path.lstat()
    if not stat.S_ISREG(details.st_mode):
        raise ValueError("source input is not a regular file: " + str(path))
    return dict(path=str(path.relative_to(ROOT)), sha256=SHA(path.read_bytes()),
                bytes=details.st_size, mode=stat.S_IMODE(details.st_mode),
                mtime_ns=details.st_mtime_ns, device=details.st_dev, inode=details.st_ino)


def runtime(path):
    details = path.lstat()
    return dict(path=str(path), resolved_path=str(path.resolve()), sha256=SHA(path.read_bytes()),
                bytes=path.stat().st_size, mode=stat.S_IMODE(details.st_mode),
                mtime_ns=details.st_mtime_ns, symlink_target=os.readlink(path) if path.is_symlink() else None)


originals = sorted((ROOT / "supabase/migrations").glob("*.sql"))
source = sorted(path for path in (ROOT / "supabase/functions").rglob("*.ts")
                if not path.name.endswith("_test.ts"))
bound = originals + source + [ROOT / name for name in (
    "supabase/.temp/project-ref", "supabase/config.toml", "contracts/edge-functions.json",
    "scripts/edge_function_inventory.rb", "scripts/edge_function_inventory.sh",
    "scripts/supabase_deploy.sh", "scripts/qa/backend_release_delivery.py",
    "scripts/supabase_production_readiness.sh", "supabase/functions/deno.lock",
    "docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json",
    "docs/release/collect-codex-goal-2026-09-30/hosted-readback/README.md")]
bound = sorted(set(bound))
before = [identity(path) for path in bound]
save("inputs-before.json", before)
dated_path = ROOT / "docs/release/collect-codex-goal-2026-09-30/hosted-readback/metadata.json"
dated = json.loads(dated_path.read_text())
linked = (ROOT / "supabase/.temp/project-ref").read_text().strip()
assert linked == dated["project"]["id"] == dated["project"]["ref"] == TARGET
config = tomllib.loads((ROOT / "supabase/config.toml").read_text())
manifest = json.loads((ROOT / "contracts/edge-functions.json").read_text())
local_migrations = [dict(version=path.name.split("_", 1)[0], name=path.name.split("_", 1)[1][:-4],
                         path=str(path.relative_to(ROOT)), sha256=SHA(path.read_bytes())) for path in originals]
current_ids = [row["version"] for row in local_migrations]
dated_ids = [row["version"] for row in dated["migrations"]]
assert len(current_ids) == len(set(current_ids)) == 209 and current_ids == sorted(current_ids)
assert len(dated_ids) == len(set(dated_ids)) and dated_ids == sorted(dated_ids)
entries = {row["name"]: row for row in manifest["functions"]}
config_modes = {name: value["verify_jwt"] for name, value in config["functions"].items()}
source_names = sorted(path.parent.name for path in (ROOT / "supabase/functions").glob("*/index.ts"))
readiness = (ROOT / "scripts/supabase_production_readiness.sh").read_text()
probe = readiness.split("check_functions() {", 1)[1].split("\ncheck_secrets() {", 1)[0]
probe_names = {"auth-send-whatsapp-otp"}
for match in re.finditer(r"for fn in ([^;\n]+); do", probe):
    probe_names.update(match.group(1).split())
expected = sorted(entries)
assert len(expected) == 13 and expected == source_names == sorted(config_modes) == sorted(probe_names)
assert config_modes == {name: row["verify_jwt"] for name, row in entries.items()}
dated_edge = {row["name"]: row for row in dated["edge_functions"]}
kept = {"id", "name", "slug", "status", "version", "verify_jwt", "created_at", "updated_at", "ezbr_sha256", "entrypoint_path", "import_map_path"}
project_fields = {key: value for key, value in dated["project"].items()
                  if key in {"id", "ref", "name", "region", "status", "created_at", "database"}}
local_entries = [dict(name=name, verify_jwt=entries[name]["verify_jwt"], auth=entries[name]["auth"],
                      source_index_path="supabase/functions/" + name + "/index.ts",
                      source_index_sha256=SHA((ROOT / "supabase/functions" / name / "index.ts").read_bytes())) for name in expected]
save("local-and-retained-inventory.json", dict(
    target_ref=TARGET,
    target_binding=dict(linked_ref=linked, retained_project_ref=dated["project"]["ref"],
                        local_project_id=config["project_id"], local_project_id_is_hosted_ref=False),
    current_source=dict(migrations=local_migrations, migration_count=len(current_ids), edge_functions=local_entries,
                        deploy_inventory="contracts/edge-functions.json consumed by backend_release_delivery.py",
                        deploy_consumer_lines=[423, 377, 378, 379], source_deploy_config_probe_names_equal=True,
                        probe_names=sorted(probe_names), probe_block_sha256=SHA(probe.encode()), probes_executed=False),
    retained_hosted=dict(source_path=str(dated_path.relative_to(ROOT)), source_sha256=SHA(dated_path.read_bytes()),
                         source_producer_date="2026-09-30 from retained README heading; precise original observation timestamp not supplied",
                         current_observation=False, project=project_fields, migrations=dated["migrations"],
                         edge_functions=[{key: value for key, value in dated_edge[name].items() if key in kept} for name in sorted(dated_edge)]),
    current_vs_retained=dict(
        current_migration_count=len(current_ids), retained_migration_count=len(dated_ids),
        retained_ids_are_exact_current_prefix=current_ids[:len(dated_ids)] == dated_ids,
        source_migrations_absent_from_retained_inventory=[row for row in local_migrations if row["version"] not in dated_ids],
        retained_migrations_outside_current_source=[row for row in dated["migrations"] if row["version"] not in current_ids],
        common_id_name_differences=[dict(version=row["version"], current=row["name"], retained=next(x["name"] for x in dated["migrations"] if x["version"] == row["version"])) for row in local_migrations if row["version"] in dated_ids and row["name"] != next(x["name"] for x in dated["migrations"] if x["version"] == row["version"])],
        current_function_count=len(expected), retained_function_count=len(dated_edge),
        current_functions_absent_from_retained_inventory=sorted(set(entries) - set(dated_edge)),
        retired_functions_present_in_retained_inventory=sorted(set(manifest["retired"]) & set(dated_edge)),
        other_retained_extra_functions=sorted(set(dated_edge) - set(entries) - set(manifest["retired"])),
        common_function_jwt_differences=[dict(name=name, current=entries[name]["verify_jwt"], retained=dated_edge[name]["verify_jwt"]) for name in sorted(set(entries) & set(dated_edge)) if entries[name]["verify_jwt"] != dated_edge[name]["verify_jwt"]],
        bundle_hash_comparison="Not performed: retained ezbr_sha256 identifies deployed bundles; local index-file hashes are a different object. No fresh deployed metadata or downloadable bundle was obtained.")))

ruby = Path("/usr/bin/ruby")
runtime_before = dict(python=runtime(Path(sys.executable)), ruby=runtime(ruby))
env = {"PATH": os.defpath, "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8", "PYTHONDONTWRITEBYTECODE": "1"}
argv = [str(ruby), str(ROOT / "scripts/edge_function_inventory.rb"), "auth-check"]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
clock = time.monotonic()
try:
    result = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True, text=True, timeout=15)
    receipt = dict(exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr, timed_out=False)
except subprocess.TimeoutExpired as error:
    receipt = dict(exit_code=None, stdout=(error.stdout or b"").decode() if isinstance(error.stdout, bytes) else error.stdout,
                   stderr=(error.stderr or b"").decode() if isinstance(error.stderr, bytes) else error.stderr, timed_out=True)
receipt.update(argv=argv, started_at_utc=started, actual_seconds=round(time.monotonic()-clock, 3), deadline_seconds=15,
               clean_environment=env, scope="Maintained local static entrypoint/JWT/auth wiring check only; no endpoint or database invocation")
save("static-inventory-check.json", receipt)
after = [identity(path) for path in bound]
save("inputs-after.json", after)
runtime_after = dict(python=runtime(Path(sys.executable)), ruby=runtime(ruby))
save("runtime-identities.json", dict(before=runtime_before, after=runtime_after, unchanged=runtime_before == runtime_after))
assert before == after and runtime_before == runtime_after
save("observation-summary.json", dict(
    status="fresh_hosted_access_refused_static_and_dated_analysis_only", target_ref=TARGET,
    source_inputs=len(before), source_inputs_unchanged=True, current_migrations=209, current_functions=13,
    local_static_inventory_check_pass=receipt["exit_code"] == 0,
    exact_project_metadata_calls=1, exact_project_metadata_successes=0,
    permission_refusals=1, further_hosted_calls=0, sql_calls=0, public_endpoint_probes=0,
    project_list_selection=False, token_refresh=False, downloads=False,
    secrets_keys_logs_customer_auth_rows_requested=False, external_mutations=0,
    current_hosted_metadata_migrations_functions_catalog_server_parity="unknown",
    actual_pg_client_or_toolchain_manifest_approval=False, current_hosted_runtime_acceptance=False,
    open_findings=["BE-01", "BE-03", "BE-10", "ARC-03"], production_ready=False,
    not_inferred=["outage", "authentication cause", "current missing migrations", "current retired endpoints", "fresh function/JWT/bundle parity", "approved hosted target/toolchain", "production release acceptance"]))
print(json.dumps(dict(status="local_packet_collected", inputs=len(before), local_static_pass=receipt["exit_code"] == 0,
                      fresh_hosted="permission_refused", hosted_sql_calls=0)))
