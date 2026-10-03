#!/usr/bin/env python3
"""All current application migrations under ordinary local installer authority.

Creates only task-owned networkless containers. A privileged setup installs
the retained Auth/storage platform shape and pg_cron before postgres is demoted.
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
