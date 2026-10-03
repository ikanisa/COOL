#!/usr/bin/env python3
"""Preserving read-only154 status refresh; never closes an acceptance criterion."""
import argparse
from collections import Counter
from copy import deepcopy
import datetime as dt
import json
from pathlib import Path
import subprocess
from zoneinfo import ZoneInfo

import local_schema_uat as local

R, U, ROOT = local.R, local.U, local.ROOT
RELEASE = ROOT / "docs/release"
NAMES = ["local-implementation-register-2026-09-30.json",
         "LOCAL_IMPLEMENTATION_REGISTER_2026-09-30.md",
         "production-remaining-tasks-2026-09-30.json",
         "PRODUCTION_REMAINING_TASKS_2026-09-30.md",
         "production-remaining-tasks-2026-09-30.validation.json"]
PACKETS = [
    "local-database-runtime-2026-09-30/install154-attempt1-guarded/result.json",
    "import-export-protection-2026-09-30/invitation-installed154-attempt6-function-name-binding/result.json",
    "import-export-protection-2026-09-30/admin-rls154-attempt3-email-integration/result.json",
    "import-export-protection-2026-09-30/admin-sensitive154-attempt3-rls-audit-effects/result.json",
    "import-export-protection-2026-09-30/admin-sensitive154-attempt4-current-nine/result.json",
    "import-export-protection-2026-09-30/invitation-save-final-attempt15/validation.json",
    "data-correctness-2026-09-30/immutable-attempt16-current-client/validation.json",
    "data-correctness-2026-09-30/sql154-attempt2/result.json",
    "data-correctness-2026-09-30/sql154-attempt4-candidate234000/result.json",
    "local-database-runtime-2026-09-30/staged-bundle154-attempt3-exact-private-tables/result.json",
    "local-database-runtime-2026-09-30/local-qa-recovery-readback/restore-readback-attempt1.json",
    "admin-full-coverage-2026-09-30/isolated-attempt47-final-current-admin/validation.json",
    "admin-full-coverage-2026-09-30/email-targeted-attempt2/validation.json",
    "asset-build-hygiene-2026-09-30/reachability-gateway-attempt59/validation.json",
]


def inventory():
    return [{"path": str(path.relative_to(ROOT)), "version": path.name.split("_", 1)[0],
             "bytes": path.stat().st_size, "sha256": R.sha(path.read_bytes()),
             "normalized_sha256": R.sha(path.read_text().rstrip().encode())}
            for path in sorted((ROOT / "supabase/migrations").glob("*.sql"))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(RELEASE):
        parser.error("Fresh release evidence directory required")
    report.mkdir(parents=True, mode=0o700)
    old = {name: (RELEASE / name).read_bytes() for name in NAMES}
    for name, body in old.items():
        (report / name).write_bytes(body)
    (report / "runner.py").write_bytes(Path(__file__).read_bytes())
    prior = {name: R.sha(body) for name, body in old.items()}
    original_local = json.loads(old[NAMES[0]])
    original_prod = json.loads(old[NAMES[2]])
    local_data, production = deepcopy(original_local), deepcopy(original_prod)
    guard = R.guard(154, "20260930230000")
    before = R.snapshot()
    raw_migrations = inventory()
    migrations = deepcopy(raw_migrations)
    registry = json.loads(U.psql("postgres", """select jsonb_agg(jsonb_build_object(
      'version',version,'name',name,'normalized_sha256',encode(extensions.digest(rtrim(statements[1],E'\\n\\r '),'sha256'),'hex')) order by version)
      from supabase_migrations.schema_migrations;""").stdout)
    installed = {item["version"]: item for item in registry}
    for item in migrations:
        item["installed"] = item["version"] in installed
        item["registry_normalized_source_match"] = item["installed"] and item["normalized_sha256"] == installed[item["version"]]["normalized_sha256"]
    staged = [item["version"] for item in migrations if not item["installed"]]
    now = dt.datetime.now(dt.timezone.utc)
    timestamp = now.isoformat()
    date = now.astimezone(ZoneInfo("Africa/Kigali")).strftime("%d %B %Y")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    status = subprocess.check_output(["git", "status", "--porcelain=v1"], cwd=ROOT, text=True)
    R.save(report / "source-table-catalog-cron.json", before)
    R.save(report / "migration-source-inventory.json", migrations)
    evidence = []
    for relative in PACKETS:
        path = RELEASE / relative
        body = path.read_bytes()
        decoded = json.loads(body)
        evidence.append(dict(path=str(path.relative_to(ROOT)), sha256=R.sha(body),
                             observed_status=decoded.get("status", decoded.get("result", "see_scoped_manifest"))))
    readback = dict(captured_at_utc=timestamp, guard=guard, migration_count=154,
                    latest_installed_version="20260930230000", table_count=len(before["tables"]),
                    source_migration_count=len(migrations), staged_source_versions=staged,
                    source_inventory_sha256=R.sha((report / "migration-source-inventory.json").read_bytes()),
                    table_catalog_cron_sha256=R.sha((report / "source-table-catalog-cron.json").read_bytes()),
                    head=head, working_tree_status_entries=len(status.splitlines()),
                    source_frozen=False, hosted_state_refreshed=False, provider_called=False)
    if inventory() != raw_migrations or before != R.snapshot():
        raise RuntimeError("Source changed during read-only capture; prior registers preserved")
    R.guard(154, "20260930230000")
    R.save(report / "current-readback.json", readback)
    # Preserve earlier status fields in the immutable five-file backup. These
    # notes describe remaining scope without replacing any acceptance criterion.
    notes = {
      "L01": "Roster recovery/Auth/calendar have scoped local evidence; current combined email/approval source must pass VM, Chrome and normal browser acceptance. Recent compile failures are retained; no final-source closure.",
      "L03": "Current independent email transport/session cohort passes17 cases. Complete all-provider/dialog/current-operation coverage and one-source integration remain; co-resident source drift is explicitly recorded.",
      "L04": "Exact invitation ACK/save and scoped Admin sensitive contracts pass. New email/operator approval contracts and final current action/audit/source integration remain.",
      "L05": "Dated Admin47 passes1697 cases; current inventory discovers25 routes/64 active endpoint and27 provider declarations before newer approval arrivals. Navigation151 and shadow152 are installed; current email/approval/receipt cohorts and complete final matrix remain.",
      "L08": "Full nine-stage candidate bundle passes71 sensitive public RPC/role/ACL/reason/audit/retry cases and8 actual blocking authority races with stronger catalog preservation. Dated email/legacy-transition/cutover RLS19 controls remain separately scoped. Shared154 unchanged; full final role/cross-group/RLS/current-source acceptance remains.",
      "L12": "Installed154 invitation passes40 cases/6 blocking races; QR save receipt passes80 client tests. Staged email/security sensitive reasons, audit and retry checks pass. Full current import/export resource/formula/permission/audit coverage remains.",
      "L15": "Dated client data16 passes710 VM and265 Chrome cases. Actual154 SQL retains55 passes/2 unsafe amount failures; additive234000 passes80 candidate cases with atomic unsafe-data aborts, exact bounds and API preservation. Current positive history/aggregate and full consumer/SQL integration remain;234000 is not installed in shared154.",
      "L20": "Navigation151, shadow152 and runtime authority153 are installed. Dated26-family inventory/control evidence remains; email-aware current authority, complete all-family consumer/write/conflict/audit and final-source acceptance remain.",
      "L21": "Gateway entrypoint was missing from reachability coverage; eight new graph regressions pass after correction. Current Public media/asset/license/reachability closure remains after evolving source integration.",
      "L22": "Unsigned native artifacts and scoped688-component SBOM evidence are dated. Current Gateway flavor graph, format/analysis/native lint, clean-export production/Gateway builds and one-source provenance remain.",
      "L23": "Restored exact quiet normal-owner154 QA preserves all153 tables and cron rows/history. All nine staged migrations pass27 populated synthetic clone assertions and preserve existing pending requests/financial rows;13 exact new private tables have RLS/no API DML. Shared154 is unchanged. Last complete clean replay remains141; final clean/populated/compatibility/full-suite/races remain.",
      "L24": "All24 local and102 production criteria, original closure IDs and five prior registers are preserved. Fresh154/153-table readback, actual staged source inventory and scoped packets are bound. Final frozen-source reproducible handover remains.",
    }
    for item in local_data["items"]:
        if item["id"] in notes:
            item["verified_progress"] = notes[item["id"]]
        if item["id"] in ("L08", "L12", "L15"):
            item["status"] = "in_progress"
    local_data.update(captured_at_utc=timestamp, snapshot_revision=original_local["snapshot_revision"] + 1,
                      current_local_migration_count=154, current_local_table_count=len(before["tables"]),
                      source_migration_count=len(migrations), staged_source_migrations=staged)
    local_data["latest_verified_local_result"] = dict(migration_count=154, table_count=len(before["tables"]),
        readback=str((report / "current-readback.json").relative_to(ROOT)),
        readback_sha256=R.sha((report / "current-readback.json").read_bytes()), evidence_packets=evidence,
        scope="Fresh154 readback and explicitly scoped packets; final whole-source acceptance unproven", whole_goal_complete=False)
    local_data["previous_latest_verified_local_result"] = original_local["latest_verified_local_result"]
    closed = [item["id"] for item in local_data["items"] if item["status"] == "complete"]
    assert closed == original_local["locally_closed_goal_items"] and len(closed) == 6
    assert [item["id"] for item in local_data["items"]] == [item["id"] for item in original_local["items"]]
    assert all(item["local_acceptance"] == prior_item["local_acceptance"] for item, prior_item in zip(local_data["items"], original_local["items"]))
    observation = dict(captured_at_utc=timestamp, fixture="collect_fin_concurrency_qa_20260929",
        migration_count=154, table_count=len(before["tables"]), last_migration="20260930230000",
        cron_launch_active_jobs="off", pg_net_batch_size=0, worker_sessions_remaining=guard["busy"],
        docker_labels_verified=True, scope="Exact quiet shared-source guard/readback; unique synthetic clones are separately scoped")
    production["historical_local_fixture_readonly_observation"] = original_prod["local_fixture_readonly_observation"]
    production.update(captured_at_utc=timestamp, as_of=now.astimezone(ZoneInfo("Africa/Kigali")).date().isoformat(),
        supersedes_captured_at_utc=original_prod["captured_at_utc"], snapshot_revision=original_prod["snapshot_revision"] + 1,
        installed_table_count=len(before["tables"]), isolated_local_registry_migration_count=154,
        isolated_local_table_count=len(before["tables"]), local_upgrade_registry_migration_count=154,
        source_migration_count=len(migrations), staged_source_versions=staged, staged_source_migrations=staged,
        local_fixture_readonly_observation=observation, local_progress_refreshed_at_utc=timestamp,
        local_progress_readback=local_data["latest_verified_local_result"]["readback"],
        local_progress_note=f"6 local goals closed;18 open.154 installed/153 tables;{len(migrations)} current source migrations with{len(staged)} staged versions. Email/security and amount corrections are staged, not shared-source acceptance. Final clean replay141 and whole-source verification remain.",
        current_local_scoped_packets=evidence, base_commit=head, working_tree_status_entries=len(status.splitlines()),
        frozen_candidate=False, external_state_refreshed_for_this_report=False)
    assert production["items"] == original_prod["items"] and len(production["items"]) == 102
    assert production["locally_closed_ids"] == original_prod["locally_closed_ids"] == ["G06"]
    assert production["open_acceptance_checks"] == 101
    local_md = f"# Collect local implementation register\n\nCaptured: {timestamp}. Revision{local_data['snapshot_revision']}.\n\n**6 of24 local goals verified complete;18 remain open.** Original102 production criteria retain their acceptance scope.\n\nInstalled local registry:154 migrations/{len(before['tables'])} tables. {len(migrations)} source files; staged versions: {', '.join(staged)}. Final whole-source acceptance is pending.\n\n| ID | Task | Status | Remaining scope or verified result |\n| --- | --- | --- | --- |\n"
    local_md += "\n".join(f"| {item['id']} | {item['title']} | {item['status']} | {item.get('verified_progress', item['local_acceptance']).replace('|', '/')} |" for item in local_data["items"])
    local_md += "\n\n## Original local acceptance criteria" + old[NAMES[1]].decode().split("## Original local acceptance criteria", 1)[1]
    prod_suffix = "## G — Source and governance" + old[NAMES[3]].decode().split("## G — Source and governance", 1)[1]
    production_md = f"# Collect — exhaustive remaining production tasks\n\n**Snapshot: {date} (Africa/Kigali), revision{production['snapshot_revision']}. Release decision: NO-GO.**\n\n**101 acceptance checks remain open:99 of100 original tasks, plus X01 and X02.** G06 remains locally closed; every original acceptance criterion is preserved.\n\n| Priority | Open |\n| --- | ---: |\n| P0 |24|\n| P1 |71|\n| P2 |4|\n| Crosscutting |2|\n| **Total** |**101**|\n\nEvidence states remain67 Partial,27 External,7 Unverified.\n\nSource: HEAD {head} plus{len(status.splitlines())} working-tree entries captured at {timestamp}. No release candidate is frozen. {len(migrations)} source migrations are present; the exact quiet local registry has154 installed migrations/{len(before['tables'])} tables. Staged versions: {', '.join(staged)}. Last complete clean replay remains141.\n\n## Latest verified local progress and limits\n\n"
    production_md += "\n".join(f"- **{item['id']}:** {item['verified_progress']}" for item in local_data["items"] if item["id"] in notes)
    production_md += f"\n\nThe [local progress packet]({report.relative_to(RELEASE)}/validation.json) preserves all five prior registers and binds the current154 readback, migration inventory and scoped packets. Six local closures remain L02/L06/L09/L10/L11/L13;18 local goals remain open. Hosted/provider/device/signing/store acceptance is not refreshed.\n\n" + prod_suffix
    bodies = {NAMES[0]: (json.dumps(local_data, indent=2, sort_keys=True) + "\n").encode(),
              NAMES[1]: local_md.encode(), NAMES[2]: (json.dumps(production, indent=2, sort_keys=True) + "\n").encode(),
              NAMES[3]: production_md.encode()}
    validation = dict(status="pass", scope="Register integrity and scoped154 progress only; not whole-system acceptance",
        validated_at_utc=timestamp, snapshot_revision=production["snapshot_revision"], local_snapshot_revision=local_data["snapshot_revision"],
        all_original_ids_preserved=True, original_criteria_preserved=True, local_criteria_preserved=True,
        closed_ids=["G06"], local_goal_closed_ids=closed, unique_open_rows=101,
        installed_migration_count=154, installed_table_count=len(before["tables"]),
        source_migration_count=len(migrations), staged_source_versions=staged,
        last_complete_clean_replay=141, full_current_source_acceptance=False, external_state_refreshed=False,
        prior_revision_preserved=prior, new_scoped_evidence_packets=evidence,
        priority_counts=dict(Counter(item["priority"] for item in production["items"] if item["open"])),
        sha256={name: R.sha(body) for name, body in bodies.items()})
    bodies[NAMES[4]] = (json.dumps(validation, indent=2, sort_keys=True) + "\n").encode()
    if any((RELEASE / name).read_bytes() != body for name, body in old.items()):
        raise RuntimeError("A register owner changed the source during refresh; do not overwrite")
    for name, body in bodies.items():
        temporary = RELEASE / (name + ".refresh154.tmp")
        with temporary.open("xb") as handle:
            handle.write(body)
        temporary.replace(RELEASE / name)
    assert all((RELEASE / name).read_bytes() == body for name, body in bodies.items())
    validation["published_sha256"] = {name: R.sha(body) for name, body in bodies.items()}
    R.save(report / "validation.json", validation)
    print(json.dumps(dict(status="pass", installed=154, tables=len(before["tables"]),
                          source=len(migrations), staged=staged, local_closed=6, local_open=18,
                          production_open=101, prior_registers_preserved=5)))


if __name__ == "__main__":
    main()
