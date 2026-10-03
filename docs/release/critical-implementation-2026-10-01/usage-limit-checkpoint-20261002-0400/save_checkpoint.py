"""Preserve completed in-flight evidence after account usage cutoff; no implementation."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import shutil
import stat
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = HERE.parent
EXECUTION = BASE / "ordinary-schema-catalog-execution1"
PREPARATION = BASE / "ordinary-schema-catalog-preparation1"
CANDIDATE = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ORDINARY-SCHEMA-20261002-CANDIDATE1")
OUTPUT = CANDIDATE / "docs/release/ordinary-effective-catalog1"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    with path.open("x") as stream:
        stream.write(json.dumps(value, indent=2) + "\n" if isinstance(value, (dict, list)) else value)


def row(path):
    info = path.lstat()
    assert stat.S_ISREG(info.st_mode) and not path.is_symlink() and info.st_nlink == 1, path
    return {"path": str(path.relative_to(ROOT)), "bytes": info.st_size, "sha256": sha(path)}


def seal(folder):
    assert not (folder / "packet-files.json").exists()
    files = [row(path) for path in sorted(folder.rglob("*")) if path.is_file()]
    write(folder / "packet-files.json", {"status": "sealed", "files": files})
    write(folder / "SHA256SUMS", "".join(item["sha256"] + "  " + item["path"] + "\n" for item in files)
          + sha(folder / "packet-files.json") + "  " + str((folder / "packet-files.json").relative_to(ROOT)) + "\n")
    for item in files:
        assert row(ROOT / item["path"]) == item
    return {"manifest_sha256": sha(folder / "packet-files.json"), "leaf_count": len(files)}


def inventory(folder):
    return {str(path.relative_to(folder)): sha(path) for path in sorted(folder.rglob("*")) if path.is_file()}


result = json.loads((EXECUTION / "execution-result.json").read_text())
assert result["status"] == "pass" and result["exit_code"] == 0 and result["case_count"] == 37
assert result["private_source_unchanged"] is True and result["source_before"] == result["source_after"]
assert len(result["source_before"]) == 215 and not result["current_source_drift"] and not result["current_added_migrations"]
assert all(item["absent_after_rehearsal"] for item in result["owned_cleanup"])
proof = json.loads((OUTPUT / "result.json").read_text())
assert proof["status"] == "pass" and len(proof["cases"]) == 37
assert all(item["status"] == "pass" for item in proof["cases"])
assert len(proof["source_inventory"]) == 208 and proof["all_task_containers_removed"] is True
assert not any(proof[key] for key in ["shared_database_written", "source_rows_copied", "hosted_called", "provider_called", "signed_jwt_tested", "managed_hosted_owner_parity"])
versions = [item["version"] for item in proof["source_inventory"]]
assert len(set(versions)) == 208
catalogs = []
for phase, state in proof["phases"].items():
    assert state["status"] == "pass" and len(state["migrations"]) == 208
    for migration in state["migrations"]:
        authority = migration["actual_installer_authority"]
        assert migration["status"] == "pass" and authority["superuser"] is False
        assert authority["current_user"] == authority["current_role"] == "postgres"
    assert state["scheduler_readback"] == {"cron": "off", "net": "0", "history": 0}
    for boundary, record in state["effective_catalogs"].items():
        path = OUTPUT / record["path"]
        assert sha(path) == record["sha256"]
        catalog = json.loads(path.read_text())
        digest = hashlib.sha256(json.dumps(catalog, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        assert digest == record["canonical_sha256"] and catalog["server"]["major"] == 17
        assert catalog["migrations"] == versions[:124] if boundary == "predecessor" else catalog["migrations"] == versions
        assert record["query_sha256"] == sha(OUTPUT / "collect_recovery_source_catalog.sql")
        catalogs.append({"phase": phase, "boundary": boundary, **record})
assert proof["phases"]["clean"]["effective_catalogs"]["final"] == proof["phases"]["populated"]["effective_catalogs"]["final"] | {"path": proof["phases"]["clean"]["effective_catalogs"]["final"]["path"]}
assert proof["populated_predecessor_fingerprints"] == proof["populated_after_upgrade_fingerprints"]
assert len(proof["populated_after_upgrade_fingerprints"]) == 18
copy_before = inventory(OUTPUT)
destination = EXECUTION / "observed-output"
assert not destination.exists()
shutil.copytree(OUTPUT, destination)
assert inventory(OUTPUT) == copy_before == inventory(destination)
current_drift = {rel: sha(ROOT / rel) for rel, digest in result["source_after"].items() if sha(ROOT / rel) != digest}
known = {rel for rel in result["source_after"] if rel.startswith("supabase/migrations/")}
added = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "supabase/migrations").glob("*.sql") if str(path.relative_to(ROOT)) not in known)
checks = []
docker = "/Volumes/PRO-G40/Applications/Docker.app/Contents/Resources/bin/docker"
socket = (EXECUTION / "local-docker-socket.stdout").read_text().strip()
assert socket.startswith("unix://")
for target in result["owned_cleanup"]:
    name = target["name"]
    response = subprocess.run([docker, "container", "inspect", name], env={"PATH": "/usr/bin:/bin", "DOCKER_HOST": socket}, capture_output=True, text=True, timeout=15)
    assert response.returncode == 1 and ("no such container: " + name in response.stderr.lower() or "no such object: " + name in response.stderr.lower())
    checks.append({"name": name, "exit_code": response.returncode, "absent": True, "stderr": response.stderr})
write(EXECUTION / "owner-readback.json", {
    "status": "pass", "at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "actual_case_count": 37, "migration_count": 208, "source_input_count": 215,
    "copy_files": len(copy_before), "copy_bytes": sum((OUTPUT / rel).stat().st_size for rel in copy_before),
    "catalogs": catalogs, "preserved_projection_count": 18,
    "fresh_owned_container_absence": checks, "current_source_drift": current_drift, "current_added_migrations": added,
    "source_current_at_readback": not current_drift and not added,
    "authority_limit": "Local postgres NOSUPERUSER retains platform CREATE ROLE/CREATE DB/BYPASSRLS and trusted role memberships; hosted installer parity is unproved.",
    "acceptance_limits": ["Domain and caller ownership map", "historical bank and broader retained data coverage", "committed recovery and forward replay", "hosted managed authority parity", "signed JWT and provider/runtime acceptance"],
    "full_BE08_closed": False, "production_ready": False,
})
write(EXECUTION / "README.md", "# Ordinary installer and complete catalog evidence\n\nThe actual frozen 208-migration clean and populated rehearsal passed all 37 checks in 113.805 seconds. All application migrations executed as postgres NOSUPERUSER after explicit platform setup. The 124-version synthetic predecessor retained all 18 tested projections through the remaining migrations. Final complete catalogs are byte-identical and canonically identical; predecessor and final catalogs include owners, role memberships, effective ACLs, columns, policies, functions and dependencies. The observed output is copied byte-for-byte into this packet; source and container cleanup receipts are retained.\n\nThis proves the recorded local platform shape, whose installer still has CREATE ROLE, CREATE DB, BYPASSRLS and trusted role memberships. Managed hosted authority parity, runtime/provider acceptance, domain and caller ownership mapping, broader historical bank fixtures, and committed recovery with forward replay remain open. BE-08 is not closed.\n")
execution_seal = seal(EXECUTION)
write(PREPARATION / "README.md", "# Maintained rehearsal enhancement\n\nThe maintained ordinary-installer runner was extended to capture the complete unchanged recovery catalog at the 124-version predecessor and both 208-version final boundaries, bind catalog versions/query/hashes, and require full final catalog equality. Existing ordinary authority, financial data preservation, disabled scheduler, source and cleanup assertions remain. No application migration or catalog query was edited. Before copies, exact after runner and the 215-input candidate copy contract are retained. The separate execution packet contains the actual pass.\n")
preparation_seal = seal(PREPARATION)
prior = json.loads((BASE / "root-register-heading-correction1/correction.json").read_text())
register_hashes = {rel: sha(ROOT / rel) for rel in prior["current_six_register_hashes"]}
assert register_hashes == prior["current_six_register_hashes"]
ledger = json.loads((BASE / "implementation-ledger.json").read_text())
assert len(ledger["items"]) == 40
closed = sorted(item["id"] for item in ledger["items"] if item["full_finding_closed"])
assert closed == ["ARC-04", "PD-02", "PD-14"]
proposal_files = []
for name in ["kotlin-sdk-native-snapshot-preparation2", "postgres-admission-preparation1"]:
    folder = BASE / name
    files = []
    for path in sorted(folder.rglob("*")):
        if "negative-fixtures" in path.parts:
            continue
        info = path.lstat()
        if stat.S_ISREG(info.st_mode):
            files.append(row(path))
        elif not stat.S_ISDIR(info.st_mode):
            raise AssertionError("Unexpected proposal nonregular file: " + str(path))
    proposal_files.append({"folder": str(folder.relative_to(ROOT)), "state": "unfinished_unreviewed_unpromoted", "files": files, "negative_fixtures_excluded_and_untrusted": name.startswith("kotlin")})
write(HERE / "proposal-files-at-cutoff.json", proposal_files)
write(HERE / "checkpoint.json", {
    "at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "goal_status_observed": "usageLimited", "reason": "Both active review agents errored with account usage limit; goal tool reports usageLimited. No usage reset authorized or consumed.",
    "goal_complete": False, "production_ready": False, "closed_ids": closed, "full_findings_open": 37,
    "canonical_registers_unchanged": register_hashes,
    "completed_pending_register_integration": {
        "migration_version_validation": {"manifest_sha256": sha(BASE / "migration-version-validation1/packet-files.json"), "behavioral_tests": 8, "current_migrations": 208},
        "ordinary_schema_catalog_preparation": preparation_seal,
        "ordinary_schema_catalog_execution": execution_seal,
    },
    "unfinished_proposals": [item["folder"] for item in proposal_files],
    "required_next_steps": [
        "Verify checkpoint and completed packet hashes; reconcile completed BE-08 partial results into all canonical registers while preserving all original criteria and original 102 production / 24 local rows.",
        "Review native derivative diff, current 34-test source binding and 31 original regression results; complete its seal. Require a fresh source fence and separate exact app-export admission before execution. No app export, app pub, Gradle or native stage has been executed by that proposal.",
        "Review and finish PostgreSQL admission proposal; it has only original baseline results (34 delivery and 5 secret-transport checks). Proposed tests and integration acceptance are unfinished. Preserve existing release guards and never fabricate approvals.",
        "Complete BE-08 domain/caller/owner map, broader historical bank fixtures, committed recovery and forward replay, and remaining original acceptance criteria.",
    ],
    "scope": "Evidence preservation and handover only after usage cutoff. No new implementation, deployment, SQL, provider, signing, publication or messages to other human chats."
})
write(HERE / "README.md", "# Usage-limit handover, 2 October 2026\n\nThe implementation goal is incomplete. The goal tool reports `usageLimited`; both active review agents stopped on the account usage limit. No reset was requested or consumed.\n\nCompleted work preserved at cutoff: the migration validator now uses complete legacy 12-digit and current 14-digit versions, refuses malformed and symlink inputs, and passes eight behavioral tests. The extended ordinary-installer rehearsal actually passed 37 checks across all 208 migrations on clean and populated local databases, with exact matching complete final catalogs and 18 preserved synthetic predecessor projections. Both task containers are absent. Full BE-08 acceptance remains open.\n\nThe completed packets are sealed and referenced in checkpoint.json. Their integration into the six canonical registers is pending; those registers retain their exact previous hashes and original rows. Three findings remain closed (ARC-04, PD-02, PD-14), and 37 remain open. Production remains NO-GO.\n\nThe native snapshot and PostgreSQL admission agent folders are incomplete private proposals. Their non-fixture files are hashed in proposal-files-at-cutoff.json for handover. They have not received final root review or promotion. Native negative fixtures remain untrusted, excluded from the checkpoint seal and must never be executed. Follow the exact pending steps in checkpoint.json once usage permits continuation.\n")
checkpoint_seal = seal(HERE)
print(json.dumps({"execution": execution_seal, "preparation": preparation_seal, "checkpoint": checkpoint_seal, "current_source_drift": current_drift, "current_added_migrations": added, "closed_ids": closed}))
