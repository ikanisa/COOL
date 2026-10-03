#!/usr/bin/env python3
"""Read-only verifier for the isolated 133 -> 134 notification upgrade.

Only fixed task-owned local Docker containers are queried. The report includes
hashes, counts and grant booleans, never Auth, SMS or provider row contents.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from verify_financial_synthetic_restore import data_fingerprint, dump


ROOT = Path(__file__).resolve().parents[2]
SOURCE = "supabase_db_collect_financial_qa_20260928"
TARGET = "supabase_db_collect_notification_qa_20260929"
TARGET_DB = "collect_notification_upgrade_20260929"
WORK = ROOT / ".cache/historical-134-qa-20260929"
PACKET = ROOT / "docs/release/admin-notification-paging-2026-09-29"
MIGRATION = ROOT / "supabase/migrations/20260929110000_admin_notification_page_before_delivery_counts.sql"
EXPECTED_ARCHIVE_SHA256 = "6037999ae339ecadf2494100e24e27da1c2d24b1087e7e550762e50edec446b9"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def output(*args: str, input_text: str | None = None) -> str:
    result = subprocess.run(args, input=input_text, capture_output=True,
                            text=True, timeout=45, check=False)
    require(result.returncode == 0,
            f"Readback failed: {args[0]} {args[1]} exit={result.returncode}")
    return result.stdout.strip()


def query(container: str, database: str, sql: str) -> str:
    require((container, database) in ((SOURCE, "postgres"), (TARGET, TARGET_DB)),
            "Unrecognized local database")
    return output("docker", "exec", "-i", container, "psql", "-XqAt",
                  "-U", "postgres", "-d", database, "-v", "ON_ERROR_STOP=1",
                  input_text=sql)


def verify_containers() -> None:
    source = json.loads(output("docker", "inspect", SOURCE, "--format",
                               "{{json .Config.Labels}}"))
    require(source.get("com.supabase.cli.project") ==
            "collect_financial_qa_20260928" and
            source.get("com.supabase.cli.workdir") ==
            str(ROOT / ".cache/financial-qa-20260928"),
            "Source fixture provenance mismatch")
    target = json.loads(output("docker", "inspect", TARGET))[0]
    labels = target["Config"]["Labels"]
    ports = target["HostConfig"]["PortBindings"]
    config = (ROOT / ".cache/notification-clean-qa-20260929/supabase/config.toml").read_text()
    require(labels.get("com.supabase.cli.project") ==
            "collect_notification_qa_20260929" and
            labels.get("com.docker.compose.project") ==
            "collect_notification_qa_20260929" and
            ports["5432/tcp"][0]["HostPort"] == "55522" and
            'project_id = "collect_notification_qa_20260929"' in config,
            "Target fixture provenance mismatch")


def main() -> None:
    verify_containers()
    archive = WORK / "source-133.dump"
    require(archive.is_file() and archive.stat().st_size > 100_000,
            "Historical source archive missing")
    archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    require(archive_sha == EXPECTED_ARCHIVE_SHA256,
            "Historical source archive changed")
    migration_sha = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    clean = json.loads((PACKET / "clean-134-replay.json").read_text())
    require(clean.get("status") == "pass" and
            len(clean.get("migrations", [])) == 134 and
            clean["migrations"][-1]["sha256"] == migration_sha,
            "Clean replay does not cover the current migration source")

    snapshot_sql = (ROOT / "scripts/tests/historical_financial_upgrade_snapshot.sql").read_text()
    baseline = json.loads((ROOT / "docs/release/financial-core-2026-09-28/historical-post-snapshot.json").read_text())
    restored_pre = json.loads((WORK / "restored-pre-snapshot.json").read_text())
    source = json.loads(query(SOURCE, "postgres", snapshot_sql))
    target = json.loads(query(TARGET, TARGET_DB, snapshot_sql))
    require(source == restored_pre == baseline and
            source["migration_count"] == 133 and
            source["last_migration"] == "20260928174000",
            "Historical predecessor snapshot changed")
    target_financial = {key: value for key, value in target.items()
                        if key not in ("migration_count", "last_migration")}
    source_financial = {key: value for key, value in source.items()
                        if key not in ("migration_count", "last_migration")}
    require(target_financial == source_financial and
            target["migration_count"] == 134 and
            target["last_migration"] == "20260929110000" and
            target["evidence_rows"] == 16 and
            target["group_balance_rwf"] == 1500,
            "Historical financial evidence changed during migration 134")

    source_data = data_fingerprint(dump(SOURCE, "postgres", "-a"))
    target_data = data_fingerprint(dump(TARGET, TARGET_DB, "-a"))
    source_tables = source_data[0].copy()
    target_tables = target_data[0].copy()
    source_migration = [key for key in source_tables
                        if "supabase_migrations.schema_migrations" in key]
    target_migration = [key for key in target_tables
                        if "supabase_migrations.schema_migrations" in key]
    require(len(source_migration) == len(target_migration) == 1,
            "Migration-history COPY section missing")
    require(source_tables.pop(source_migration[0])["rows"] == 133 and
            target_tables.pop(target_migration[0])["rows"] == 134 and
            source_tables == target_tables and source_data[1:] == target_data[1:],
            "Non-migration table data or sequence changed")

    boundary_sql = """
      select jsonb_build_object(
        'anon_notification_execute', has_function_privilege('anon',
          'public.admin_list_notifications(text,text,integer,integer,text)','execute'),
        'member_notification_execute', has_function_privilege('authenticated',
          'public.admin_list_notifications(text,text,integer,integer,text)','execute'),
        'anon_receipt_execute', has_function_privilege('anon',
          'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)','execute'),
        'member_receipt_execute', has_function_privilege('authenticated',
          'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)','execute'),
        'anon_profile_select', has_table_privilege('anon','public.profiles','select'),
        'admin_indexes', (select count(*) from pg_indexes
          where schemaname='public' and tablename='notification_events'
            and indexname in ('notification_events_admin_created_idx',
                              'notification_events_admin_status_created_idx')),
        'cron_jobs', (select count(*) from cron.job),
        'temporary_session', (select count(*) from auth.sessions
          where id='99830000-0000-4000-8000-000000000001'),
        'temporary_approval', (select count(*) from collect_admin_access.whatsapp_approvals
          where user_id='99100000-0000-4000-8000-000000000001'));
    """
    boundary = json.loads(query(TARGET, TARGET_DB, boundary_sql))
    require(boundary == {
        "anon_notification_execute": False,
        "member_notification_execute": True,
        "anon_receipt_execute": False,
        "member_receipt_execute": False,
        "anon_profile_select": False,
        "admin_indexes": 2,
        "cron_jobs": 1,
        "temporary_session": 0,
        "temporary_approval": 0,
    }, "Upgraded function grants, indexes or rollback state changed")
    settings = query(TARGET, TARGET_DB,
        "select current_setting('cron.launch_active_jobs')||'|'||"
        "current_setting('cron.database_name')||'|'||"
        "current_setting('pg_net.database_name')||'|'||"
        "current_setting('pg_net.batch_size');")
    require(settings in (f"off|{TARGET_DB}|template1|0",
                         "off|postgres|template1|0"),
            "Scheduler or network worker is not isolated")
    uat = (PACKET / "historical-134-uat.stdout").read_text()
    require(uat.count("HISTORICAL_NOTIFICATION_134_UAT_PASS: 3 pages, grants and indexes") == 1,
            "Historical notification page UAT missing")

    print(json.dumps({
        "status": "pass_local_synthetic_historical_133_to_134",
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "source_fixture": "collect_financial_qa_20260928/postgres",
        "target_fixture": "collect_notification_qa_20260929/" + TARGET_DB,
        "source_archive_sha256": archive_sha,
        "migration_sha256": migration_sha,
        "migration_count": "133 -> 134",
        "financial_evidence_rows": target["evidence_rows"],
        "financial_evidence_sha256": target["evidence_sha256"],
        "group_balance_rwf": target["group_balance_rwf"],
        "unchanged_table_sections": len(source_tables),
        "unchanged_table_rows": sum(item["rows"] for item in source_tables.values()),
        "sequence_statements_match": True,
        "grants_and_indexes": boundary,
        "scheduler_and_network_workers": settings,
        "notification_page_cases": 3,
        "limitations": [
            "synthetic historical fixture with 16 selected financial/evidence rows",
            "no representative customer history or hosted schema readback",
            "no signed-client compatibility or rollback/roll-forward acceptance",
            "no independent provider evidence or production approval",
        ],
    }, sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
