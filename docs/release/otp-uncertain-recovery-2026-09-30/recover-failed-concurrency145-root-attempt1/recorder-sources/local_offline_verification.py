#!/usr/bin/env python3
"""Root-owned recorder for the exact offline Collect migration fixture.

No hosted URL or alternate database can be selected. Each invocation preserves a
fresh backup, full table fingerprints and catalog controls before running reviewed
SQL. Existing output directories are never reused. Sequence counters are excluded
from rollback equivalence; rows, grants, policies, routines and triggers are not.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "collect_fixture", ROOT / "scripts/tests/notification_upgrade_telemetry.py"
)
FIXTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FIXTURE)
SCHEMAS = (
    "public", "private", "collect_hybrid", "collect_security",
    "collect_admin_access", "collect_auth_security", "collect_member_actions",
    "collect_profile_access", "auth", "realtime", "supabase_migrations",
)
ALLOWED_UPGRADES = {
    "20260930110000": (142, "20260930100000", "retire_legacy_bank_scheduler"),
    "20260930120000": (143, "20260930110000", "roster_import_reload_recovery"),
    "20260930130000": (144, "20260930120000", "signed_otp_uncertain_recovery"),
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def save(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def guard(count: int, latest: str) -> dict:
    FIXTURE.fixture_identity()
    result = json.loads(FIXTURE.sql("""select jsonb_build_object(
      'user',current_user,'database',current_database(),
      'superuser',(select rolsuper from pg_roles where rolname=current_user),
      'stats_visible',pg_has_role(current_user,'pg_read_all_stats','USAGE'),
      'cron_dml',has_table_privilege(current_user,'cron.job','INSERT,UPDATE,DELETE,MAINTAIN'),
      'cron',current_setting('cron.launch_active_jobs'),
      'net',current_setting('pg_net.batch_size'),
      'count',(select count(*) from supabase_migrations.schema_migrations),
      'latest',(select max(version) from supabase_migrations.schema_migrations),
      'busy',(select count(*) from pg_stat_activity where datname=current_database()
        and pid<>pg_backend_pid() and backend_type='client backend' and state<>'idle'));"""))
    expected = dict(user="postgres", database="postgres", superuser=False,
                    stats_visible=True, cron_dml=False, cron="off", net="0",
                    count=count, latest=latest, busy=0)
    if result != expected:
        raise RuntimeError("Exact quiet offline normal-owner fixture required: " + json.dumps(result))
    return result


def snapshot() -> dict:
    names = ",".join(literal(name) for name in SCHEMAS)
    # Every baseline application/Auth/Realtime/migration table is included.
    # A single read-only transaction supplies consistent row and catalog hashes.
    body = f"""create function pg_temp.collect_offline_snapshot() returns jsonb
    language plpgsql as $$ declare item record; n bigint; h text; rows jsonb:='{{}}'::jsonb;
    begin
      for item in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ({names}) and c.relkind in ('r','p') order by n.nspname,c.relname loop
        execute format('select count(*),encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E''\\n'' order by to_jsonb(t)::text),''''),''sha256''),''hex'') from %I.%I t',item.nspname,item.relname) into n,h;
        rows:=rows||jsonb_build_object(item.nspname||'.'||item.relname,jsonb_build_object('rows',n,'sha256',h));
      end loop;
      return jsonb_build_object('tables',rows,
        'controls_sha256',(with controls(family,body) as (
          select 'schema',jsonb_build_object('name',n.nspname,'owner',n.nspowner,'acl',n.nspacl) from pg_namespace n where n.nspname in ({names})
          union all select 'relation',jsonb_build_object('name',n.nspname||'.'||c.relname,'owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity)
            from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
          union all select 'column',jsonb_build_object('table',c.oid::regclass::text,'name',a.attname,'type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
            from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
            where n.nspname in ({names}) and a.attnum>0 and not a.attisdropped
          union all select 'routine',jsonb_build_object('name',p.oid::regprocedure::text,'owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef)
            from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ({names})
          union all select 'trigger',jsonb_build_object('table',t.tgrelid::regclass::text,'name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
            from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
          union all select 'constraint',jsonb_build_object('table',c.conrelid::regclass::text,'name',c.conname,'definition',pg_get_constraintdef(c.oid))
            from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname in ({names})
          union all select 'policy',jsonb_build_object('table',p.polrelid::regclass::text,'name',p.polname,'roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
            from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
        ) select encode(extensions.digest(coalesce(string_agg(family||':'||body::text,E'\\n' order by family,body::text),''),'sha256'),'hex') from controls),
        'cron_jobs',(select coalesce(jsonb_agg(jsonb_build_object('id',jobid,'metadata_sha256',encode(extensions.digest(to_jsonb(j)::text,'sha256'),'hex')) order by jobid),'[]') from cron.job j),
        'cron_history',(select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(coalesce(string_agg(to_jsonb(d)::text,E'\\n' order by to_jsonb(d)::text),''),'sha256'),'hex')) from cron.job_run_details d));
    end $$;
    begin isolation level repeatable read read only;
    select pg_temp.collect_offline_snapshot(); rollback;"""
    return json.loads(FIXTURE.sql(body))


def prepare(output: Path, count: int, latest: str) -> dict:
    if output.exists():
        raise RuntimeError("Preserve prior evidence: output directory already exists")
    output.mkdir(parents=True, mode=0o700)
    sources = output / "recorder-sources"
    sources.mkdir(mode=0o700)
    (sources / "local_offline_verification.py").write_bytes(Path(__file__).read_bytes())
    (sources / "notification_upgrade_telemetry.py").write_bytes(Path(FIXTURE.__file__).read_bytes())
    identity = guard(count, latest)
    before = snapshot()
    backup_dir = ROOT / ".cache/local-offline-backups-20260930" / output.name
    if backup_dir.exists():
        raise RuntimeError("Backup destination already exists")
    backup_dir.mkdir(parents=True, mode=0o700)
    backup = backup_dir / "before.dump"
    with backup.open("xb") as handle:
        result = subprocess.run([
            "docker", "exec", FIXTURE.CONTAINER, "sh", "-c",
            'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump -Fc -U supabase_admin -d postgres',
        ], stdout=handle, stderr=subprocess.PIPE, timeout=60)
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace")[-6000:])
    listed = subprocess.run(["docker", "exec", "-i", FIXTURE.CONTAINER,
                             "pg_restore", "--list"], input=backup.read_bytes(),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    if listed.returncode:
        raise RuntimeError("Backup archive cannot be decoded")
    (output / "backup-archive-list.txt").write_bytes(listed.stdout)
    if snapshot() != before:
        raise RuntimeError("Fixture changed during backup; do not execute")
    save(output / "before.json", before)
    manifest = dict(schema_version=1, started_at_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                    identity=identity, backup=str(backup), backup_sha256=sha(backup.read_bytes()),
                    recorder_sha256=sha(Path(__file__).read_bytes()),
                    telemetry_helper_sha256=sha(Path(FIXTURE.__file__).read_bytes()),
                    backup_archive_decodable=True,
                    sequences_restored=False, provider_calls=False, hosted_writes=False)
    save(output / "checkpoint.json", manifest)
    return before


def reviewed_source(path: Path, digest: str, output: Path) -> str:
    if not re.fullmatch("[0-9a-f]{64}", digest) or sha(path.read_bytes()) != digest:
        raise RuntimeError("Root-reviewed source SHA mismatch")
    source = path.read_text()
    (output / "reviewed-source.sql").write_text(source)
    checkpoint = json.loads((output / "checkpoint.json").read_text())
    checkpoint.update(reviewed_source=str(path.resolve()), reviewed_source_sha256=digest)
    save(output / "checkpoint.json", checkpoint)
    return source


def execute(source: str, output: Path, role: str = "postgres") -> None:
    # The credential is expanded inside the exact container, never copied to
    # command arguments, logs, host environment or public evidence.
    command = ["docker", "exec", "-i", FIXTURE.CONTAINER, "sh", "-c",
               'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -XqAt -U ' + role
               + ' -d postgres -v ON_ERROR_STOP=1']
    body = ("set application_name='collect_offline_root'; set timezone='UTC'; "
            "set standard_conforming_strings=on; set statement_timeout='30s'; "
            "set collect.legacy_bank_scheduler_qa='isolated_clone'; "
            "set collect.roster_provenance_qa='isolated_clone'; "
            "set collect.otp_qa_fixture='collect_fin_concurrency_qa_20260929';\n") + source
    with (output / "stdout").open("xb") as out, (output / "stderr").open("xb") as err:
        result = subprocess.run(command, input=body.encode(), stdout=out, stderr=err, timeout=60)
    checkpoint = json.loads((output / "checkpoint.json").read_text())
    checkpoint.update(sql_role=role, sql_return_code=result.returncode,
                      executed_sql_sha256=sha(body.encode()))
    save(output / "checkpoint.json", checkpoint)
    if result.returncode:
        raise RuntimeError("SQL failed; preserve output and inspect authoritative state before retrying")


def finish(output: Path, before: dict, after: dict, *, unchanged: bool,
           expected_changed_tables: tuple[str, ...] = ()) -> None:
    save(output / "after.json", after)
    result = json.loads((output / "checkpoint.json").read_text())
    result.update(status="pass", completed_at_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                  unchanged=after == before, old_tables_preserved=all(
                      table == "supabase_migrations.schema_migrations" or after["tables"].get(table) == rows
                      for table, rows in before["tables"].items()),
                  expected_changed_tables=list(expected_changed_tables),
                  unaffected_tables_preserved=all(
                      table == "supabase_migrations.schema_migrations" or table in expected_changed_tables
                      or after["tables"].get(table) == rows
                      for table, rows in before["tables"].items()),
                  tables_before=len(before["tables"]), tables_after=len(after["tables"]),
                  stdout_sha256=sha((output / "stdout").read_bytes()),
                  stderr_sha256=sha((output / "stderr").read_bytes()))
    failures = []
    if unchanged and not result["unchanged"]:
        failures.append("Rollback/replay fixture or control fingerprints changed")
    if not result["unaffected_tables_preserved"]:
        failures.append("Original application/Auth/Realtime table fingerprints changed")
    if result.get("sql_return_code", 0) != 0:
        failures.append("Reviewed command failed")
    result.update(status="fail" if failures else "pass", failures=failures,
                  exact_rollback_equivalence_required=unchanged)
    save(output / "result.json", result)
    if failures:
        raise RuntimeError("; ".join(failures))
    print(json.dumps({key: result[key] for key in ("unchanged", "old_tables_preserved", "unaffected_tables_preserved", "expected_changed_tables", "tables_before", "tables_after")}))


def main() -> None:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("sql", "apply"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--latest", required=True)
    parser.add_argument("--role", choices=("postgres", "supabase_admin"), default="postgres")
    parser.add_argument("--version")
    parser.add_argument("--expect-unchanged", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch("[0-9]{14}", args.latest) or args.count not in (142, 143, 144, 145):
        parser.error("Reviewed142–145 local fixture only")
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "docs/release"):
        parser.error("Evidence must be inside this repository's docs/release")
    # Validate bytes before backup or any database mutation.
    if sha(args.source.read_bytes()) != args.sha256:
        parser.error("Reviewed source hash differs")
    before = prepare(output, args.count, args.latest)
    source = reviewed_source(args.source, args.sha256, output)
    if args.mode == "apply":
        expected = ALLOWED_UPGRADES.get(args.version)
        if not expected or (args.count, args.latest) != expected[:2] or args.role != "postgres":
            raise RuntimeError("Normal-owner exact sequential migration required")
        canonical = ROOT / "supabase/migrations" / (args.version + "_" + expected[2] + ".sql")
        if args.source.resolve() != canonical:
            raise RuntimeError("Only the exact reviewed migration path can be applied")
        stripped = re.sub(r"\A\s*begin(?:\s+isolation\s+level\s+serializable)?\s*;", "", source, count=1, flags=re.I)
        if stripped == source or not re.search(r"commit;\s*\Z", stripped, flags=re.I):
            raise RuntimeError("Explicit migration transaction required")
        stripped = re.sub(r"commit;\s*\Z", "", stripped, count=1, flags=re.I)
        if args.version == "20260930120000" and before["tables"].get("collect_hybrid.legacy_bank_scheduler_verifications", {}).get("rows") != 1:
            raise RuntimeError("143 postcommit final verification required before144")
        atomic_guard = (
            "do $$ begin if current_user<>'postgres' or current_database()<>'postgres'"
            " or (select rolsuper from pg_roles where rolname=current_user)"
            " or current_setting('cron.launch_active_jobs')<>'off'"
            " or current_setting('pg_net.batch_size')<>'0'"
            " or (select count(*) from supabase_migrations.schema_migrations)<>" + str(args.count)
            + " or (select max(version) from supabase_migrations.schema_migrations)<>" + literal(args.latest)
            + " then raise exception 'Exact offline sequential upgrade required'; end if; end $$;\n"
        )
        source = "begin isolation level serializable;\n" + atomic_guard + stripped + "\n" + (
            "insert into supabase_migrations.schema_migrations(version,name,statements) values ("
            + literal(args.version) + "," + literal(expected[2]) + ",array[" + literal(source) + "]);\ncommit;\n"
        )
        (output / "executed-upgrade.sql").write_text(source)
    try:
        execute(source, output, args.role)
    except Exception as error:
        failure = dict(status="failed", error_type=type(error).__name__, message=str(error))
        try:
            after = snapshot()
            save(output / "after-failure.json", after)
            failure["baseline_restored"] = after == before
        except Exception as readback_error:
            failure["readback_error"] = str(readback_error)
        save(output / "failure.json", failure)
        raise
    after = snapshot()
    finish(output, before, after, unchanged=args.expect_unchanged)
    guard(args.count + (args.mode == "apply"), args.version if args.mode == "apply" else args.latest)


if __name__ == "__main__":
    main()
