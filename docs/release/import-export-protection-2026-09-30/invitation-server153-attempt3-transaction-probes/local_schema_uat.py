#!/usr/bin/env python3
"""Schema-only synthetic UAT in the exact quiet offline Collect container.

No host, credentials, source rows or alternative project are accepted. The
shared database is read for schema/ACLs and full before/after fingerprints.
Every synthetic write is confined to a unique disposable database.
"""
from contextlib import contextmanager
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[2]


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(file))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


R = module("offline_schema_recorder", "local_offline_verification.py")
U = module("offline_schema_transport", "shadow_supervisor_uat.py")


def save(path, value):
    R.save(path, value)


@contextmanager
def isolated(report, evidence, count=153, latest="20260930220000"):
    # These are reviewed installed baselines, not caller-selected hosts/roles.
    if (count, latest) != (153, "20260930220000"):
        raise RuntimeError("Reviewed installed153 baseline required")
    before = R.snapshot()
    evidence["source_guard"] = R.guard(count, latest)
    save(report / "source-before.json", before)
    names = ",".join(R.literal(x) for x in R.SCHEMAS)
    dump = U.command([
        U.DOCKER, "exec", U.CONTAINER, "pg_dump", "-U", "postgres", "-d", "postgres",
        "--schema-only", "--no-owner", "--no-privileges", "--no-publications",
        "--no-subscriptions", "--exclude-extension=pg_cron", "--exclude-extension=pg_net",
        "--exclude-extension=pg_stat_statements", "--exclude-extension=pg_graphql",
        "--exclude-schema=graphql", "--exclude-schema=graphql_public",
        "--exclude-schema=cron", "--exclude-schema=net",
    ]).stdout
    acl = "set search_path=public,auth;" + U.psql("postgres", f"""
      with targets as (
        select 'FUNCTION' kind,p.oid::regprocedure::text identity,
          coalesce(p.proacl,acldefault('f',p.proowner)) acl
          from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ({names})
        union all select case when c.relkind='S' then 'SEQUENCE' else 'TABLE' end,
          format('%I.%I',n.nspname,c.relname),
          coalesce(c.relacl,acldefault(case when c.relkind='S' then 'S'::"char" else 'r'::"char" end,c.relowner))
          from pg_class c join pg_namespace n on n.oid=c.relnamespace
          where n.nspname in ({names}) and c.relkind in ('r','p','v','m','S')
        union all select 'SCHEMA',quote_ident(n.nspname),coalesce(n.nspacl,acldefault('n',n.nspowner))
          from pg_namespace n where n.nspname in ({names})
      ) select string_agg(statement,E'\\n' order by priority,kind,identity) from (
        select 0 priority,kind,identity,
          format('REVOKE ALL ON %s %s FROM PUBLIC,anon,authenticated,service_role;',kind,identity) statement from targets
        union all select 1,kind,identity,format('GRANT %s ON %s %s TO %s;',x.privilege_type,kind,identity,
          case when x.grantee=0 then 'PUBLIC' else quote_ident(r.rolname) end)
          from targets cross join lateral aclexplode(acl)x left join pg_roles r on r.oid=x.grantee
          where x.grantee=0 or r.rolname in ('anon','authenticated','service_role')
      )s;
    """).stdout
    if before != R.snapshot():
        raise RuntimeError("Shared database changed during schema/ACL capture")
    R.guard(count, latest)
    (report / "schema-only.sql").write_text(dump)
    (report / "api-acl.sql").write_text(acl)
    evidence.update(schema_only_sha256=R.sha(dump.encode()), api_acl_sha256=R.sha(acl.encode()),
                    source_rows_copied=False, hosted_called=False, provider_called=False,
                    signed_jwt_tested=False, owner_normalization="No-owner restore; API ACLs reconstructed exactly")
    db = "collect_local_uat_" + uuid.uuid4().hex[:16]
    evidence["database"] = db
    made = False
    try:
        U.psql("postgres", "create database " + db + " template template0;")
        made = True
        mock = ("create schema cron;create table cron.job(jobid bigint primary key,jobname text,active boolean);"
                "create table cron.job_run_details(jobid bigint,status text,end_time timestamptz);")
        restore = U.psql(db, mock + dump + acl, False)
        (report / "restore.stdout.log").write_text(restore.stdout)
        (report / "restore.stderr.log").write_text(restore.stderr)
        if restore.returncode:
            raise RuntimeError("Schema/ACL restore failed: " + restore.stderr[-2500:])
        yield db
    finally:
        if made:
            cleanup = U.psql("postgres", "drop database " + db + " with (force);", False)
            evidence["isolated_database_removed"] = cleanup.returncode == 0
            if cleanup.returncode:
                evidence["cleanup_error"] = cleanup.stderr[-1500:]
        after = R.snapshot()
        save(report / "source-after.json", after)
        evidence["all_source_tables_catalog_cron_preserved"] = before == after
        evidence["source_table_count"] = len(before["tables"])
        evidence["source_guard_after"] = R.guard(count, latest)
        if before != after or (made and not evidence.get("isolated_database_removed")):
            raise RuntimeError("Shared source preservation or disposable cleanup failed")
