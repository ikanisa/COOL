#!/usr/bin/env python3
"""Verify current synthetic financial DB restore, including ACL/schema parity.

Only fixed, task-owned Docker containers are queried. Raw dumps stay in memory;
the printed report contains hashes/counts and no SMS, Auth or provider values.
"""

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE_CONTAINER = "supabase_db_collect_financial_qa_20260928"
TARGET_CONTAINER = "supabase_db_collect_financial_restore_qa_20260928"
TARGET_DB = "collect_financial_restore_empty_20260928"
EVIDENCE = ROOT / "docs/release/financial-core-2026-09-28"
ARCHIVE = ROOT / ".cache/financial-qa-20260928/historical-upgraded.dump"


def require(ok, message):
    if not ok:
        raise SystemExit(message)


def command(*argv, input_bytes=None):
    result = subprocess.run(argv, input=input_bytes, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=30, check=False)
    require(result.returncode == 0,
            f"Command failed: {argv[0]} {argv[1]} exit={result.returncode}")
    return result.stdout


def provenance(container, project, workdir):
    raw = command("docker", "inspect", container, "--format",
                  "{{json .Config.Labels}}")
    labels = json.loads(raw)
    require(labels.get("com.supabase.cli.project") == project and
            labels.get("com.supabase.cli.workdir") == str(ROOT / workdir),
            f"Unexpected task-owned fixture labels: {container}")


def query(container, database, sql):
    raw = command("docker", "exec", "-i", container, "psql", "-XqAt",
                  "-U", "postgres", "-d", database, "-v", "ON_ERROR_STOP=1",
                  input_bytes=sql.encode())
    return raw.decode().strip()


def dump(container, database, *options):
    return command("docker", "exec", container, "pg_dump", "-U", "postgres",
                   "-d", database, "--no-comments", *options)


def data_fingerprint(dump_bytes):
    tables, sequences, other = {}, [], []
    current, rows = None, []
    for line in dump_bytes.decode().splitlines(keepends=True):
        if current is not None:
            if line == "\\.\n":
                require(current not in tables, "Duplicate COPY section")
                tables[current] = {
                    "rows": len(rows),
                    "sha256": hashlib.sha256("".join(sorted(rows)).encode()).hexdigest(),
                }
                current, rows = None, []
            else:
                rows.append(line)
        elif line.startswith("COPY ") and line.endswith(" FROM stdin;\n"):
            current = line.strip()
        elif line.startswith("SELECT pg_catalog.setval("):
            sequences.append(line.strip())
        elif line.startswith(("INSERT INTO", "SELECT pg_catalog.lo_",
                              "SELECT pg_catalog.lowrite", "SELECT pg_catalog.lo_put")):
            other.append(line.strip())
    require(current is None, "Incomplete COPY section")
    return tables, sorted(sequences), sorted(other)


def strip_restrict(text):
    return "".join(line for line in text.splitlines(keepends=True)
                   if not line.startswith(("\\restrict ", "\\unrestrict ")))


def normalized_schema(source, restored):
    old = [
        "CONSTRAINT provider_finality_requests_provider_network_check CHECK (((provider_network IS NULL) OR (((char_length(provider_network) >= 2) AND (char_length(provider_network) <= 32)) AND (provider_network ~ '^[a-z0-9_]+$'::text))))",
        "ADD CONSTRAINT notification_events_copy_length_check CHECK ((((char_length(TRIM(BOTH FROM title)) >= 1) AND (char_length(TRIM(BOTH FROM title)) <= 120)) AND ((char_length(TRIM(BOTH FROM body)) >= 1) AND (char_length(TRIM(BOTH FROM body)) <= 500)))) NOT VALID;",
    ]
    new = [
        "CONSTRAINT provider_finality_requests_provider_network_check CHECK (((provider_network IS NULL) OR ((char_length(provider_network) >= 2) AND (char_length(provider_network) <= 32) AND (provider_network ~ '^[a-z0-9_]+$'::text))))",
        "ADD CONSTRAINT notification_events_copy_length_check CHECK (((char_length(TRIM(BOTH FROM title)) >= 1) AND (char_length(TRIM(BOTH FROM title)) <= 120) AND ((char_length(TRIM(BOTH FROM body)) >= 1) AND (char_length(TRIM(BOTH FROM body)) <= 500)))) NOT VALID;",
    ]
    for before, after in zip(old, new):
        require(source.count(before) == 1 and restored.count(after) == 1,
                "Unexpected CHECK expression shape; inspect schema diff")
        source = source.replace(before, after)
    result = strip_restrict(source)
    require(result == strip_restrict(restored),
            "Schema, function, trigger, policy or ACL dump differs")
    return hashlib.sha256(result.encode()).hexdigest()


def main():
    provenance(SOURCE_CONTAINER, "collect_financial_qa_20260928",
               ".cache/financial-qa-20260928")
    provenance(TARGET_CONTAINER, "collect_financial_restore_qa_20260928",
               ".cache/financial-restore-qa-20260928")
    require(ARCHIVE.is_file(), "Synthetic source archive missing")
    archive = ARCHIVE.read_bytes()
    require(len(archive) > 100_000, "Synthetic archive unexpectedly small")
    command("docker", "exec", "-i", TARGET_CONTAINER, "pg_restore", "-l",
            input_bytes=archive)
    baseline = json.loads((EVIDENCE / "historical-post-snapshot.json").read_text())
    snapshot_sql = (ROOT / "scripts/tests/historical_financial_upgrade_snapshot.sql").read_text()
    source_snapshot = json.loads(query(SOURCE_CONTAINER, "postgres", snapshot_sql))
    target_snapshot = json.loads(query(TARGET_CONTAINER, TARGET_DB, snapshot_sql))
    require(source_snapshot == target_snapshot == baseline,
            "Source, restored and archived financial snapshots differ")
    safety_sql = """
      select jsonb_build_object(
        'anon_receipt_execute',has_function_privilege('anon',
          'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)','execute'),
        'member_receipt_execute',has_function_privilege('authenticated',
          'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)','execute'),
        'anon_profile_select',has_table_privilege('anon','public.profiles','select'),
        'migrations',(select count(*) from supabase_migrations.schema_migrations),
        'cron_jobs',(select count(*) from cron.job),
        'extensions',(select jsonb_agg(jsonb_build_object('name',extname,'version',extversion)
          order by extname) from pg_extension));
    """
    source_safety = json.loads(query(SOURCE_CONTAINER, "postgres", safety_sql))
    target_safety = json.loads(query(TARGET_CONTAINER, TARGET_DB, safety_sql))
    newer_migrations = [path.name for path in
                        sorted((ROOT / "supabase/migrations").glob("*.sql"))
                        if path.name[:14] > "20260928174000"]
    require(source_safety == target_safety and
            source_safety["anon_receipt_execute"] is False and
            source_safety["member_receipt_execute"] is False and
            source_safety["anon_profile_select"] is False and
            source_safety["migrations"] == 133,
            "Restored grants, extensions, cron metadata or migration history differ")
    workers = query(TARGET_CONTAINER, TARGET_DB,
                    "select current_setting('cron.launch_active_jobs')||'|'||"
                    "current_setting('pg_net.database_name')||'|'||"
                    "current_setting('pg_net.batch_size');")
    require(workers == "off|template1|0", "Restore target workers not disabled")
    source_data = data_fingerprint(dump(SOURCE_CONTAINER, "postgres", "-a"))
    target_data = data_fingerprint(dump(TARGET_CONTAINER, TARGET_DB, "-a"))
    require(source_data == target_data and len(source_data[0]) >= 129,
            "Full table-data, sequence or other-data fingerprint differs")
    source_schema = dump(SOURCE_CONTAINER, "postgres", "-s").decode()
    target_schema = dump(TARGET_CONTAINER, TARGET_DB, "-s").decode()
    schema_hash = normalized_schema(source_schema, target_schema)
    source_roles = command("docker", "exec", SOURCE_CONTAINER, "pg_dumpall",
                           "-U", "postgres", "-l", "postgres", "--roles-only",
                           "--no-role-passwords").decode()
    target_roles = command("docker", "exec", TARGET_CONTAINER, "pg_dumpall",
                           "-U", "postgres", "-l", TARGET_DB, "--roles-only",
                           "--no-role-passwords").decode()
    require(strip_restrict(source_roles) == strip_restrict(target_roles),
            "Global role definitions differ")
    print(json.dumps({
        "status": "pass_synthetic_database_restore_not_production_recovery",
        "source_archive_sha256": hashlib.sha256(archive).hexdigest(),
        "restored_migration_count": 133,
        "newer_migrations_not_covered": newer_migrations,
        "table_copy_sections": len(source_data[0]),
        "table_rows": sum(row["rows"] for row in source_data[0].values()),
        "sequence_statements": len(source_data[1]),
        "other_data_statements": len(source_data[2]),
        "normalized_schema_acl_sha256": schema_hash,
        "global_roles_match": True,
        "financial_snapshot_sha256": baseline["evidence_sha256"],
        "extensions_match": True,
        "restore_target_workers_disabled": True,
        "limitations": ["synthetic local database only", "Storage object bytes absent",
                        "no hosted settings or provider evidence", "no approved RPO/RTO",
                        "newer source migrations are outside this restore"],
    }, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
