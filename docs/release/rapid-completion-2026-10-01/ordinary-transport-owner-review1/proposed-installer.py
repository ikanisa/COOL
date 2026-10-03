#!/usr/bin/env python3
"""All current application migrations under ordinary local installer authority.

Creates only task-owned networkless containers. A privileged setup installs
the retained Auth/storage platform shape, pg_cron and pg_net before postgres is demoted.
Every application migration then executes as current_user postgres NOSUPERUSER.
This proves local installer behavior; managed hosted platform parity is separate.
"""
import argparse
import datetime
import json
from pathlib import Path

import collect_current_release_upgrade_uat as replay

ROOT = replay.ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh local release evidence directory required")
    report.mkdir(mode=0o700, parents=True)
    items = []
    captured = report / "captured-migrations"
    captured.mkdir()
    for path in sorted((ROOT / "supabase/migrations").glob("*.sql")):
        body = path.read_bytes()
        version, name = path.stem.split("_", 1)
        items.append(dict(path=str(path.relative_to(ROOT)), version=version, name=name,
            sha256=replay.sha(body), body=body.decode()))
        (captured / path.name).write_bytes(body)
    if len({i["version"] for i in items}) != len(items):
        raise RuntimeError("Unique migration versions required")
    helper_paths = [Path(__file__), Path(replay.__file__)]
    helpers = {p: p.read_bytes() for p in helper_paths}
    for path, body in helpers.items(): (report / path.name).write_bytes(body)
    platform, provenance = replay.platform_shape()
    (report / "platform-bootstrap.sql").write_text(platform)
    evidence = dict(kind="ordinary_local_installer_all_current_clean_populated", status="running",
        source_inventory=[{k:v for k,v in i.items() if k != "body"} for i in items],
        platform_bootstrap=provenance, cases=[], phases={}, shared_database_written=False,
        source_rows_copied=False, hosted_called=False, provider_called=False,
        signed_jwt_tested=False, managed_hosted_owner_parity=False,
        started_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    targets = []
    def save(): (report / "result.json").write_text(json.dumps(evidence, indent=2) + "\n")
    def case(name, value=True):
        if not value: raise AssertionError(name)
        evidence["cases"].append(dict(name=name, status="pass")); save(); print("PASS " + name, flush=True)
    def ordinary(target):
        state = target.json("select jsonb_build_object('current_user',current_user,'current_role',current_role,'superuser',rolsuper,'create_db',rolcreatedb,'create_role',rolcreaterole,'bypass_rls',rolbypassrls)from pg_roles where rolname=current_user;")
        if state["current_user"] != "postgres" or state["current_role"] != "postgres" or state["superuser"] is not False:
            raise RuntimeError("Ordinary installer authority was lost: " + json.dumps(state))
        return state
    def apply(target, selected, outcome):
        for item in selected:
            authority = ordinary(target)
            before = replay.fingerprints(target, evidence["preserved_columns"]) if outcome.get("populated_fixture_ready") else None
            replay.apply(target, [item], outcome)
            outcome["migrations"][-1]["actual_installer_authority"] = authority
            ordinary(target)
            if before is not None:
                after = replay.fingerprints(target, evidence["preserved_columns"])
                if before != after: raise AssertionError("Canonical predecessor changed at " + item["path"])
                outcome["migrations"][-1]["canonical_predecessor_preserved"] = True
            save()
    save()
    try:
        retained = json.loads(replay.HOSTED.read_text())
        registered = retained["migrations"]
        if len(registered) != 124 or [i["version"] for i in items[:124]] != [r["version"] for r in registered]:
            raise RuntimeError("Reviewed predecessor version prefix changed")
        (report / "retained-predecessor-metadata.json").write_bytes(replay.HOSTED.read_bytes())
        evidence["predecessor"] = dict(count=124, latest=registered[-1]["version"],
            source="Retained metadata and synthetic fixtures; hosted currentness unverified",
            metadata_sha256=replay.sha(replay.HOSTED.read_bytes()))
        for phase in ("clean", "populated"):
            outcome = evidence["phases"][phase] = {}
            target = replay.Target(report, "ordinary_" + phase, outcome)
            targets.append(target)
            with target:
                target.sql(platform, label="privileged retained platform bootstrap before any application migration")
                # pg_cron's C APIs execute their internal writes as the
                # extension owner. The cached managed image owns cron.job as
                # supabase_admin; install its platform extension under that
                # same role before demoting the application installer.
                target.sql("create extension if not exists pg_cron with schema pg_catalog;", user="supabase_admin", label="managed platform owner pg_cron prerequisite")
                # The retained local platform also owns pg_net as
                # supabase_admin (extensions schema, version0.20.0). Its
                # installation requires platform authority. Application
                # migrations may check its presence after postgres is demoted;
                # they must not acquire superuser to install it themselves.
                target.sql("create extension if not exists pg_net with schema extensions;", user="supabase_admin", label="retained platform owner pg_net prerequisite before installer demotion")
                # LOCAL REHEARSAL ONLY: exact retained platform definer metadata.
                # Owner preparation below refuses an undeclared invoker platform.
                target.sql('alter function net.http_get(text,jsonb,jsonb,integer)security definer;alter function net.http_get(text,jsonb,jsonb,integer)set search_path=net;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)security definer;alter function net.http_post(text,jsonb,jsonb,jsonb,integer)set search_path=net;', user="supabase_admin", label="local exact retained pg_net trusted function shape; not application DDL")
                target.sql("-- PROPOSAL ONLY. Execute as the actual pg_net table owner before ordinary\n-- application migrations. Do not execute this as the application installer.\n-- This preserves existing trusted platform functions and worker identity.\n-- postgres may already inherit pg_read_all_data: these revokes normalize its\n-- direct grants, not that inherited authority. No membership is changed here.\nbegin;\ndo $platform_owner$\nbegin\n if not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')\n  from pg_class c where c.oid=to_regclass('net._http_response')),false)\n  or not coalesce((select pg_has_role(current_user,c.relowner,'USAGE')\n  from pg_class c where c.oid=to_regclass('net.http_request_queue')),false)then\n  raise exception 'receipt_transport_platform_owner_required'using errcode='42501';\n end if;\n -- Receipt dispatch must already have a trusted platform definer. Do not\n -- introduce definer authority or grant queue DML to the application reader.\n if not exists(select 1 from pg_proc p join pg_class q\n  on q.oid=to_regclass('net.http_request_queue')\n  where p.oid=to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)')\n   and p.prosecdef and p.proowner=q.relowner)then\n  raise exception 'receipt_transport_platform_dispatch_prerequisite'using errcode='55000';\n end if;\nend$platform_owner$;\ncreate index if not exists collect_receipt_http_response_id on net._http_response(id);\ndo $private_tables$\ndeclare relation regclass;columns text;\nbegin\n foreach relation in array array['net._http_response'::regclass,'net.http_request_queue'::regclass]loop\n  select string_agg(quote_ident(attname),','order by attnum)into columns\n   from pg_attribute where attrelid=relation and attnum>0 and not attisdropped;\n  execute format('revoke all privileges on table %s from public,anon,authenticated,service_role,postgres',relation);\n  -- Table REVOKE alone does not remove column ACLs.\n  execute format('revoke all privileges (%s) on table %s from public,anon,authenticated,service_role,postgres',columns,relation);\n end loop;\nend$private_tables$;\ngrant usage on schema net to postgres;\ngrant select(id,status_code,content,timed_out,error_msg,created)on net._http_response to postgres;\ngrant select(id)on net.http_request_queue to postgres;\ndo $private_readers$\nbegin\n if exists(select 1 from(values('anon'),('authenticated'),('service_role'))r(role_name)\n  cross join(values('net._http_response'),('net.http_request_queue'))t(relation)\n  where has_table_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')\n   or has_any_column_privilege(r.role_name,t.relation,'SELECT,INSERT,UPDATE,REFERENCES'))then\n  raise exception 'receipt_transport_private_tables_prerequisite'using errcode='55000';\n end if;\nend$private_readers$;\ncommit;\n", user="supabase_admin", label="declared platform-owner index private ACL and seven-column transport prerequisites")
                outcome["net_platform_ownership"] = target.json("select jsonb_build_object('extension_owner',pg_get_userbyid(e.extowner),'schema',n.nspname,'version',e.extversion)from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pg_net';")
                case(phase + " retained pg_net platform prerequisite matches reviewed local ownership",
                    outcome["net_platform_ownership"] == {"extension_owner":"supabase_admin","schema":"extensions","version":"0.20.0"})
                # The retained quiet154 managed platform grants postgres the
                # alter_job owner API, while denying it to anon/authenticated.
                # A fresh extension installed by supabase_admin does not carry
                # that installer grant automatically. Recreate only this
                # execution prerequisite; direct cron DML remains forbidden.
                target.sql("grant execute on function cron.alter_job(bigint,text,text,text,text,boolean)to postgres;", user="supabase_admin", label="retained platform installer cron owner API execution prerequisite")
                outcome["platform_bootstrap_privileged"] = True
                outcome["platform_owner_normalization"] = outcome.pop("installer_normalization")
                target.sql("alter role postgres nosuperuser;", user="supabase_admin", label="end platform setup and demote application installer")
                outcome["ordinary_installer"] = ordinary(target)
                case(phase + " application installer is actually NOSUPERUSER before migration 1")
                outcome["cron_platform_ownership"] = target.json("select jsonb_build_object('extension_owner',(select pg_get_userbyid(extowner)from pg_extension where extname='pg_cron'),'job_owner',(select pg_get_userbyid(relowner)from pg_class where oid='cron.job'::regclass),'installer_cron_dml',has_table_privilege(current_user,'cron.job','INSERT,UPDATE,DELETE,MAINTAIN')); ")
                case(phase + " managed cron extension and job ownership agree without installer DML",
                    outcome["cron_platform_ownership"] == {"extension_owner":"supabase_admin","job_owner":"supabase_admin","installer_cron_dml":False})
                outcome["cron_owner_api_authority"] = target.json("select jsonb_build_object('installer_execute',has_function_privilege('postgres','cron.alter_job(bigint,text,text,text,text,boolean)','EXECUTE'),'anon_execute',has_function_privilege('anon','cron.alter_job(bigint,text,text,text,text,boolean)','EXECUTE'),'authenticated_execute',has_function_privilege('authenticated','cron.alter_job(bigint,text,text,text,text,boolean)','EXECUTE')); ")
                case(phase + " retained cron owner API executes only for the installer among tested roles",
                    outcome["cron_owner_api_authority"] == {"installer_execute":True,"anon_execute":False,"authenticated_execute":False})
                # Exercise the real owner API, then roll back the synthetic
                # probe. Disabled launch controls remain in force throughout.
                outcome["cron_api_probe"] = target.json("begin;select cron.schedule('collect-ordinary-installer-probe','0 0 1 1 *','select 1');select jsonb_build_object('creator_owned_job',exists(select 1 from cron.job where jobname='collect-ordinary-installer-probe'and username=current_user),'owner_api_unscheduled',cron.unschedule('collect-ordinary-installer-probe'));rollback;")
                case(phase + " ordinary installer schedules and unschedules through owner APIs",
                    outcome["cron_api_probe"] == {"creator_owned_job":True,"owner_api_unscheduled":True})
                case(phase + " rolled-back cron probe leaves no job or run history",
                    target.scalar("select not exists(select 1 from cron.job where jobname='collect-ordinary-installer-probe')and not exists(select 1 from cron.job_run_details);") == "t")
                case(phase + " retained platform starts without Auth users or application profiles",
                    target.scalar("select not exists(select 1 from auth.users)and to_regclass('public.profiles')is null;") == "t")
                if phase == "clean":
                    apply(target, items, outcome)
                    case("every current application migration replays under ordinary local authority",
                        int(target.scalar("select count(*)from supabase_migrations.schema_migrations;")) == len(items))
                else:
                    apply(target, items[:124], outcome)
                    case("populated predecessor reaches the exact retained version boundary",
                        target.json("select jsonb_build_object('count',count(*),'latest',max(version))from supabase_migrations.schema_migrations;") == {"count":124,"latest":"20260906160000"})
                    replay.seed_populated(target, evidence, case)
                    outcome["populated_fixture_ready"] = True
                    apply(target, items[124:], outcome)
                    replay.verify_populated(target, evidence, case, len(items))
                ordinary(target)
                outcome["scheduler_readback"] = target.json("select jsonb_build_object('cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'),'history',(select count(*)from cron.job_run_details));")
                case(phase + " schedules remain disabled with no cron history or network dispatch",
                    outcome["scheduler_readback"] == {"cron":"off","net":"0","history":0})
                outcome["status"] = "pass"; save()
        case("both task-owned containers have been removed", all(t.evidence.get("task_container_removed") for t in targets))
        case("all captured helper source bytes remain unchanged", all(p.read_bytes() == body for p,body in helpers.items()))
        current = {str(p.relative_to(ROOT)):replay.sha(p.read_bytes()) for p in sorted((ROOT / "supabase/migrations").glob("*.sql"))}
        case("entire migration set and source bytes match the captured ordinary rehearsal",
            current == {i["path"]:i["sha256"] for i in items})
        evidence["status"] = "pass"
    except Exception as error: evidence.update(status="failed", failure=str(error)); save(); raise
    finally:
        for target in targets: target.close()
        evidence["all_task_containers_removed"] = all(not t.made and t.evidence.get("task_container_removed") for t in targets)
        evidence["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat(); save()


if __name__ == "__main__": main()
