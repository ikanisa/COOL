#!/usr/bin/env python3
"""Current-bundle actual CAS/session races for every runtime-control family.

Uses the exact quiet local QA, a schema/ACL-only disposable clone and synthetic
identities. Each counted race requires an observed PostgreSQL lock wait whose
blocking PID is the actual other worker. No shared rows or providers are written.
"""
import argparse
import datetime
import json
from pathlib import Path
import time

import current_runtime_control_bundle_uat as V
import data_correctness_sql_uat as data
import local_schema_uat as local
import staged_bundle_upgrade_uat as bundle

ROOT, R, U = local.ROOT, local.R, local.U
RACER = "99790000-0000-4000-8000-000000000003"
RACERSID = "99790000-0000-4000-8000-000000010003"
OWNEDSID = "99790000-0000-4000-8000-000000010004"


def seed(db, specs):
    permissions = sorted({"audit.read"} | {s[k] for s in specs.values()
        for k in ("permission", "read_permission", "additional_permission") if k in s})
    U.psql(db, f"""insert into public.admin_roles(id,name,description)
      values('{V.ROLE}','platform_owner','Synthetic current runtime race');
      insert into public.admin_permissions(name)select name from unnest(array[
        {','.join(R.literal(p) for p in permissions)}])name on conflict(name)do nothing;
      insert into public.admin_role_permissions(role_id,permission_name)
        select '{V.ROLE}',name from public.admin_permissions;
      insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
      values('{V.UID}','authenticated','authenticated','synthetic-runtime@collect.example',clock_timestamp(),'{{}}','{{}}'),
        ('{RACER}','authenticated','authenticated','synthetic-runtime-racer@collect.example',clock_timestamp(),'{{}}','{{}}');
      insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
      values('{V.UID}','synthetic-runtime@collect.example',clock_timestamp()-interval '2 minutes','Synthetic runtime approval'),
        ('{RACER}','synthetic-runtime-racer@collect.example',clock_timestamp()-interval '2 minutes','Synthetic runtime approval');
      insert into public.admin_user_roles(user_id,role_id,reason,created_at)
      values('{V.UID}','{V.ROLE}','Synthetic race role',clock_timestamp()-interval '1 minute'),
        ('{RACER}','{V.ROLE}','Synthetic race role',clock_timestamp()-interval '1 minute');
      insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
      values('{V.SID}','{V.UID}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
        ('{RACERSID}','{RACER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
        ('{OWNEDSID}','{V.UID}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
      insert into public.collections(id,slug,creator_user_id,title,collection_type)
        values('{V.GROUP}','qa-runtime-current','{V.UID}','Synthetic runtime group','ikimina');
      insert into collect_hybrid.member_records(id,collect_id,origin,created_by)
        values('{V.MEMBER}','971901','admin_assisted','{V.UID}');
      insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
        values('{V.MEMBER}','Synthetic Runtime Member','Synthetic Runtime Member','+250788979001');""")
    for family, row in V.fixtures().items():
        relation = specs[family]["relation"]
        identity = {key: row[key] for key in specs[family]["identity"]}
        record = f"jsonb_populate_record(null::{relation},{V.j(row)})"
        existing = data.scalar(db, f"select to_jsonb(exists(select 1 from {relation} t where to_jsonb(t)@>{V.j(identity)}));")
        if existing:
            assignments = ",".join(f"{key}=({record}).{key}" for key in row if key not in identity)
            U.psql(db, f"update {relation} t set {assignments} where to_jsonb(t)@>{V.j(identity)};")
        else:
            columns = ",".join(row)
            values = ",".join(f"({record}).{key}" for key in row)
            U.psql(db, f"insert into {relation}({columns})select {values};")


def receipt(lines):
    return json.loads(next(line.removeprefix("RESULT:") for line in lines if line.startswith("RESULT:")))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bundle-proof", type=Path, required=True)
    args = parser.parse_args()
    report, proof_path = args.output.resolve(), args.bundle_proof.resolve()
    if report.exists() or not report.is_relative_to(ROOT/"docs/release") or not proof_path.is_relative_to(ROOT/"docs/release"):
        parser.error("Fresh local release output and accepted local bundle proof required")
    stages = {ROOT/"supabase/migrations"/name:(ROOT/"supabase/migrations"/name).read_bytes() for name in bundle.STAGES}
    migration_inventory = {str(p.relative_to(ROOT)):R.sha(p.read_bytes())
        for p in sorted((ROOT/"supabase/migrations").glob("*.sql"))}
    proof = json.loads(proof_path.read_text())
    if proof.get("status") != "pass" or proof.get("source_migration_sha256") != {p.name:R.sha(b) for p,b in stages.items()}:
        raise RuntimeError("Current accepted staged-bundle proof required")
    if not all(proof.get(k) for k in ("all_source_tables_catalog_cron_preserved","isolated_database_removed","recorder_sources_unchanged")):
        raise RuntimeError("Bundle preservation proof incomplete")
    specs = V.specs_from_source(V.SPEC_SOURCE.read_bytes())
    if len(specs) != 26 or set(specs) != set(V.fixtures()) or set(specs) != set(V.patches()):
        raise RuntimeError("Full26 fixture/patch/source registry required")
    tracked = stages | {Path(__file__):Path(__file__).read_bytes(),Path(V.__file__):Path(V.__file__).read_bytes(),
        Path(bundle.__file__):Path(bundle.__file__).read_bytes(),Path(data.__file__):Path(data.__file__).read_bytes(),V.SPEC_SOURCE:V.SPEC_SOURCE.read_bytes()}
    report.mkdir(mode=0o700,parents=True)
    for path,body in tracked.items(): (report/path.name).write_bytes(body)
    (report/"bundle-proof.json").write_bytes(proof_path.read_bytes())
    R.save(report/"migration-source-inventory.json",migration_inventory)
    evidence = dict(kind="current_full26_runtime_cas_session_races",status="running",cases=[],actual_blocking_races=0,
        source_rows_copied=False,shared_source_written=False,provider_called=False,triggers_disabled=False,
        signed_jwt_tested=False,full_client_consumer_acceptance=False,families=sorted(specs),
        bundle_proof_sha256=R.sha(proof_path.read_bytes()),migration_sources={p.name:R.sha(b) for p,b in stages.items()},
        started_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    evidence["migration_inventory_sha256"] = R.sha((report/"migration-source-inventory.json").read_bytes())
    U.SQL_LOG, U.CONCURRENCY_LOG = report/"queries.log", report/"concurrency.log"
    sessions = []
    def save(): R.save(report/"result.json",evidence)
    def require(ok, detail):
        if not ok: raise AssertionError(json.dumps(detail))
        return detail
    def case(name, action):
        try:
            value=action();evidence["cases"].append(dict(name=name,status="pass",detail=value));print("PASS "+name,flush=True)
        except Exception as error:
            evidence["cases"].append(dict(name=name,status="failed",error=str(error)));save();raise
        save()
    save()
    try:
        with local.isolated(report,evidence,count=154,latest="20260930230000") as db:
            installed=set(data.scalar("postgres","select to_jsonb(array_agg(version order by version))from supabase_migrations.schema_migrations;"))
            actual={p.name for p in (ROOT/"supabase/migrations").glob("*.sql")if p.name.split("_",1)[0]not in installed}
            require(actual==set(bundle.STAGES),dict(unreviewed=sorted(actual-set(bundle.STAGES)),missing=sorted(set(bundle.STAGES)-actual)))
            bundle.seed_schema_clone_permission_catalog(db,report,evidence)
            for path,body in stages.items(): U.psql(db,body.decode())
            seed(db,specs)
            finance=data.financial(db)
            def scalar(sql): return data.scalar(db,sql)
            def call(body): return U.call(db,"select "+body,V.UID,V.SID)
            def open_session(name):
                session=U.Session(db,name);sessions.append(session)
                session.write("set application_name="+R.literal(name)+";set statement_timeout='20s';select 'PID:'||pg_backend_pid();select 'READY';")
                lines=session.read("READY");session.pid=int(next(x.removeprefix("PID:")for x in lines if x.startswith("PID:")))
                return session
            def blocking(waiter,holder):
                for _ in range(100):
                    state=scalar(f"select coalesce((select jsonb_build_object('pid',pid,'wait',wait_event_type,'blockers',pg_blocking_pids(pid))from pg_stat_activity where pid={waiter.pid}),'{{}}'::jsonb);")
                    if state.get("wait")=="Lock" and holder.pid in state.get("blockers",[]):
                        evidence["actual_blocking_races"]+=1;return state
                    time.sleep(.05)
                raise RuntimeError("Actual worker lock overlap not observed")
            def rejected(lines,state):
                return any("ERROR:" in line and state+":" in line for line in lines) and not any(line.startswith("RESULT:")for line in lines)
            def restore_session(): U.psql(db,f"update auth.sessions set not_after=clock_timestamp()+interval '1 hour'where id='{V.SID}';")
            for index,(family,row)in enumerate(V.fixtures().items()):
                spec=specs[family];identity={key:row[key]for key in spec["identity"]}
                get=f"public.admin_get_runtime_control_v1({R.literal(family)},{V.j(identity)})"
                field=next(iter(V.patches()[family]));revert={field:row.get(field,True)}
                update=lambda patch,revision:f"public.admin_update_runtime_control_v1({R.literal(family)},{V.j(identity)},{V.j(patch)},{revision},{R.literal(V.REASON)})"
                events=lambda:scalar("select coalesce(jsonb_agg(to_jsonb(t)order by revision),'[]'::jsonb) "
                    "from collect_security.runtime_control_events t where family="+R.literal(family)
                    +"and identity_sha256=collect_security.runtime_control_hash("+V.j(identity)+");")
                a,b=open_session(f"collect_runtime_current_{index}_a"),open_session(f"collect_runtime_current_{index}_b")
                try:
                    before=call(get);revision=before["revision"];audit_seed=events()
                    b_uid,b_sid=(V.UID,OWNEDSID)if spec.get("user_owned")else(RACER,RACERSID)
                    a.write("begin;"+U.auth(V.UID,V.SID)+"select 'RESULT:'||"+update(V.patches()[family],revision)+"::text;select 'WINNER_HELD';")
                    winner=receipt(a.read("WINNER_HELD"));require(winner["changed"]and winner["revision"]==revision+1,winner)
                    b.write("begin;"+U.auth(b_uid,b_sid)+"select 'RESULT:'||"+update(revert,revision)+"::text;commit;select 'LOSER_DONE';")
                    overlap=blocking(b,a);a.write("commit;select 'WINNER_DONE';");a.read("WINNER_DONE");loser=b.read("LOSER_DONE")
                    case(family+" simultaneous expected revision has exactly one winner",lambda:require(rejected(loser,"40001")and call(get)["revision"]==revision+1,dict(overlap=overlap,winner=winner,loser_sqlstate="40001")))

                    a.write("begin;"+U.auth(V.UID,V.SID)+"select 'RESULT:'||"+update(revert,revision+1)+"::text;select 'WRITE_HELD';")
                    prior=receipt(a.read("WRITE_HELD"));require(prior["changed"]and prior["revision"]==revision+2,prior)
                    b.write(f"begin;update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='{V.SID}';commit;select 'REVOKED';")
                    overlap=blocking(b,a);a.write("commit;select 'WRITE_DONE';");a.read("WRITE_DONE");b.read("REVOKED")
                    denied=U.psql(db,"begin;"+U.auth(V.UID,V.SID)+"select "+get+";rollback;",False)
                    case(family+" write before session revocation commits and subsequent read is denied",lambda:require(denied.returncode and "42501:"in denied.stderr,dict(overlap=overlap,receipt=prior,subsequent_read_sqlstate="42501")))
                    restore_session();snapshot=call(get);audit_before_revocation=events()

                    b.write(f"begin;update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='{V.SID}';select 'REVOCATION_HELD';")
                    b.read("REVOCATION_HELD")
                    a.write("begin;"+U.auth(V.UID,V.SID)+"select 'RESULT:'||"+update(V.patches()[family],revision+2)+"::text;commit;select 'AFTER_REVOKE';")
                    overlap=blocking(a,b);b.write("commit;select 'REVOKE_COMMITTED';");b.read("REVOKE_COMMITTED");late=a.read("AFTER_REVOKE")
                    restore_session();current=call(get)
                    case(family+" committed session revocation refuses the blocked write without row or revision change",lambda:require(rejected(late,"42501")and current==snapshot,dict(overlap=overlap,denied_sqlstate="42501",getter_unchanged=True)))
                    case(family+" only the two legitimate writes create exact actor/session/reason audits",lambda:require(
                        events()==audit_before_revocation and len(audit_before_revocation)==len(audit_seed)+2
                        and audit_before_revocation[:len(audit_seed)]==audit_seed
                        and [event["revision"]for event in audit_before_revocation[len(audit_seed):]]==[revision+1,revision+2]
                        and all(event["actor_id"]==V.UID and event["session_id"]==V.SID
                            and event["authority"]=="live_operator"
                            and event["reason_sha256"]==R.sha(V.REASON.encode())
                            and event["reason_characters"]==len(V.REASON)for event in audit_before_revocation[len(audit_seed):]),
                        dict(retained_seed_event_count=len(audit_seed),new_operator_event_count=2,
                            failed_writes_created_events=False)))
                finally:
                    for session in(a,b): session.close();sessions.remove(session)
            case("all26 families have three actually observed blocking races",lambda:require(evidence["actual_blocking_races"]==78,dict(count=evidence["actual_blocking_races"])))
            case("all financial and delivery fingerprints remain unchanged",lambda:require(data.financial(db)==finance,{}))
            case("all captured sources remain byte-identical",lambda:require(all(path.read_bytes()==body for path,body in tracked.items()),{}))
            case("whole migration file set and every source byte remain unchanged",lambda:require(
                migration_inventory=={str(p.relative_to(ROOT)):R.sha(p.read_bytes())for p in sorted((ROOT/"supabase/migrations").glob("*.sql"))},{}))
        evidence["status"]="pass"
    except Exception as error:
        evidence.update(status="failed",failure=str(error));raise
    finally:
        for session in sessions: session.close()
        U.SQL_LOG=U.CONCURRENCY_LOG=None
        evidence["completed_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat();save()


if __name__=="__main__": main()
