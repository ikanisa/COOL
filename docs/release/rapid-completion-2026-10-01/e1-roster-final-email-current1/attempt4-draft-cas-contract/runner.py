#!/usr/bin/env python3
"""Finite final-email roster SQL acceptance in an ordinary-owner schema clone."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "scripts/tests"))
import local_schema_uat as local

R, U = local.R, local.U
OUT = Path(__file__).resolve().parent
STAGES = (
    "20260930213000_operator_email_auth.sql",
    "20260930220527_operator_email_cutover_guard.sql",
    "20260930233000_sensitive_admin_authority.sql",
    "20260930235500_operator_reason_whitespace.sql",
)
ACTOR = "991e1000-0000-4000-8000-000000000001"
PEER = "991e1000-0000-4000-8000-000000000002"
ROLE = "991e1000-0000-4000-8000-000000000003"
OLD = "991e1000-0000-4000-8000-000000000011"
FRESH = "991e1000-0000-4000-8000-000000000012"
PEERSID = "991e1000-0000-4000-8000-000000000013"
evidence = dict(status="running", kind="essential_final_email_roster_actual_sql", cases=[],
                actual_blocking_races=0, shared_source_written=False,
                provider_called=False, hosted_called=False, signed_jwt_tested=False,
                scope="Final email roster dependency closure only; no full migration replay, provider extraction or exhaustive matrix",
                started_at=datetime.now(timezone.utc).isoformat())
sources = {ROOT / "supabase/migrations" / n: (ROOT / "supabase/migrations" / n).read_bytes() for n in STAGES}
POLICY_SOURCE = ROOT / "supabase/migrations/20260930140000_roster_resource_integrity.sql"
sources[POLICY_SOURCE] = POLICY_SOURCE.read_bytes()
RECOVERY_SOURCE = ROOT / "supabase/migrations/20260930170000_roster_fresh_auth_recovery.sql"
sources[RECOVERY_SOURCE] = RECOVERY_SOURCE.read_bytes()
sources[Path(__file__).resolve()] = Path(__file__).read_bytes()
evidence["source_sha256"] = {str(p.relative_to(ROOT)): R.sha(b) for p, b in sources.items()}


def save():
    R.save(OUT / "result.json", evidence)


def require(ok, detail="Required assertion failed"):
    if not ok:
        raise AssertionError(detail)
    return True


def case(name, fn):
    try:
        value = fn()
        evidence["cases"].append(dict(name=name, status="pass", detail=value))
        print("PASS " + name, flush=True)
        save()
        return value
    except Exception as error:
        evidence["cases"].append(dict(name=name, status="failed", detail=str(error)))
        save()
        raise


def uid(n):
    return "991e1000-0000-4000-8000-" + str(n).zfill(12)


def claims(actor=ACTOR, sid=FRESH):
    value = json.dumps(dict(sub=actor, session_id=sid, role="authenticated", aal="aal1", exp=int(time.time()) + 3600))
    return "set local role authenticated;select set_config('request.jwt.claims'," + R.literal(value) + ",true);"


def lit(value):
    return R.literal(value)


def payload(value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return text, hashlib.sha256(text.encode()).hexdigest()


def main():
    if (OUT / "result.json").exists():
        raise RuntimeError("Fresh evidence result required")
    for p, b in sources.items():
        if p.name != "runner.py":
            (OUT / p.name).write_bytes(b)
    save()
    U.SQL_LOG = OUT / "queries.log"
    U.CONCURRENCY_LOG = OUT / "concurrency.log"
    sessions = []
    try:
        with local.isolated(OUT, evidence, count=154, latest="20260930230000") as db:
            def sql(body, required=True):
                return U.psql(db, "set statement_timeout='30s';set lock_timeout='15s';" + body, required)

            def scalar(body):
                return sql(body).stdout.strip().splitlines()[-1]

            def call(body, actor=ACTOR, sid=FRESH):
                return json.loads(scalar("begin;" + claims(actor, sid) + "select " + body + ";commit;"))

            def deny(body, state="42501", reason=None, actor=ACTOR, sid=FRESH, role="authenticated"):
                auth = claims(actor, sid) if role == "authenticated" else "set local role " + role + ";select set_config('request.jwt.claims','{\"role\":\"" + role + "\"}',true);"
                result = sql("begin;" + auth + "select " + body + ";rollback;", False)
                require(result.returncode != 0 and state + ":" in result.stderr and (reason is None or reason in result.stderr), result.stderr)
                return dict(sqlstate=state, message=reason)

            for p, b in sources.items():
                if p.name not in STAGES:
                    continue
                result = sql(b.decode(), False)
                (OUT / (p.stem + ".stdout.log")).write_text(result.stdout)
                (OUT / (p.stem + ".stderr.log")).write_text(result.stderr)
                case("ordinary clone owner applies " + p.name, lambda result=result: require(result.returncode == 0, result.stderr))
            case("clone owner is NOSUPERUSER with scheduling and network dispatch disabled", lambda: require(json.loads(scalar("select jsonb_build_object('superuser',(select rolsuper from pg_roles where rolname=current_user),'cron',current_setting('cron.launch_active_jobs'),'net',current_setting('pg_net.batch_size'))")) == dict(superuser=False, cron="off", net="0")))
            policy_seed = "insert into collect_hybrid.roster_resource_policy values(true,100,104857600,2,1000,1073741824,20,100000,1000000,10000,1);"
            require(sources[POLICY_SOURCE].decode().count(policy_seed) == 1, "Installed policy seed boundary changed")
            installed_policy = U.psql("postgres", "select statements[1] from supabase_migrations.schema_migrations where version='20260930140000';").stdout
            require(installed_policy.rstrip() == sources[POLICY_SOURCE].decode().rstrip(), "Resource policy source differs from installed baseline")
            recovery_seed = "insert into collect_hybrid.roster_recovery_budget values(true,1);"
            require(sources[RECOVERY_SOURCE].decode().count(recovery_seed) == 1, "Installed recovery budget initializer changed")
            installed_recovery = U.psql("postgres", "select statements[1] from supabase_migrations.schema_migrations where version='20260930170000';").stdout
            require(installed_recovery.rstrip() == sources[RECOVERY_SOURCE].decode().rstrip(), "Recovery source differs from installed baseline")
            sql(policy_seed + recovery_seed)
            evidence["schema_clone_reference_policy"] = dict(source_sha256=R.sha(sources[POLICY_SOURCE]), seed_sha256=R.sha(policy_seed.encode()), source_rows_copied=False)
            sql(f"""insert into public.admin_roles(id,name,description) values('{ROLE}','platform_owner','Synthetic final email roster');
              insert into public.admin_permissions(name,description) values('users.read','Synthetic'),('collections.moderate','Synthetic'),('admin_users.manage','Synthetic');
              insert into public.admin_role_permissions(role_id,permission_name) select '{ROLE}',name from public.admin_permissions;
              insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
              values('{ACTOR}','authenticated','authenticated','roster-one@collect.example',clock_timestamp(),'{{}}','{{}}'),
                    ('{PEER}','authenticated','authenticated','roster-two@collect.example',clock_timestamp(),'{{}}','{{}}');
              update public.profiles set country_code='RW',currency_code='RWF' where id in ('{ACTOR}','{PEER}');
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
              select id,email,clock_timestamp()-interval '20 minutes','Synthetic final email approval' from auth.users;
              update collect_admin_access.operator_auth_policy set mode='email',revision=revision+1 where id;
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
              values('{ACTOR}','{ROLE}','Synthetic owner',clock_timestamp()-interval '19 minutes'),('{PEER}','{ROLE}','Synthetic peer',clock_timestamp()-interval '19 minutes');
              insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
              values('{OLD}','{ACTOR}',clock_timestamp()-interval '18 minutes',clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
                    ('{PEERSID}','{PEER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
              insert into public.feature_flags(key,enabled,description) values('hybrid_member_onboarding',true,'Synthetic final email roster');""")
            case("email cutover fixture has no legacy phone approval", lambda: require(scalar("select count(*) from collect_admin_access.whatsapp_approvals") == "0"))

            def prepare(n):
                return json.loads(scalar(f"""begin;set local role service_role;select set_config('request.jwt.claims','{{"role":"service_role"}}',true);
                  do $$ declare reservation jsonb; source jsonb; initial jsonb; begin
                    reservation:=public.reserve_roster_resources('{ACTOR}','{OLD}','{uid(100+n)}',repeat('a',64),'image',99,null);
                    perform public.verify_roster_source_integrity((reservation->>'reservation_id')::uuid,'{ACTOR}','{OLD}',repeat('b',64),repeat('c',64),'collect-roster-decoder-v1',
                    '{{"python":"3.12","pillow":"12.0.0","pypdfium2":"5.2.0","pypdf":"6.7.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}}',
                    '{{"frames":1,"pages":0,"pixels":100,"expanded_bytes":400}}');
                    source:=public.create_roster_import_source('{ACTOR}','{OLD}','{uid(100+n)}','image',repeat('a',64),99,'synthetic.png','image/png','image/png',null,null,true,
                    'roster-ai-extraction-v1','{{"provider":"openai","model":"synthetic-model","prompt_version":"roster-extraction-v1"}}');
                    initial:=public.complete_roster_import_preview((source->>'import_id')::uuid,'{ACTOR}','{OLD}',
                    '[{{"source_row":1,"member_name":"Synthetic Ada {n}","momo_name":"SYNTHETIC ADA","momo_number":"078991{n:04}","confidence":0.93}}]',
                    '{{"processing_method":"openai_structured_extraction","provider_response_id":"synthetic-response-{n}","provider_response_sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"}}');
                    perform public.finish_roster_resources((reservation->>'reservation_id')::uuid,'{ACTOR}','{OLD}','preview_ready');
                    perform set_config('collect.qa.source',(jsonb_build_object('source',source,'initial',initial))::text,true);
                  end $$;select current_setting('collect.qa.source');commit;"""))

            fixtures = [prepare(n) for n in range(1, 4)]
            s, initial = fixtures[0]["source"], fixtures[0]["initial"]
            rows = [dict(member_name="Reviewed Synthetic Ada", momo_name="SYNTHETIC ADA", momo_number="0789910001")]
            p1, h1 = payload(dict(parent_revision_id=initial["revision_id"], rows=rows, title="Synthetic original group", reason="Saved first synthetic reason"))
            draft1 = call(f"public.admin_save_roster_import_draft('{s['import_id']}','{uid(401)}',null,{lit(p1)},'{h1}')", sid=OLD)
            old_tag = scalar(f"select collect_hybrid.roster_interrupted_etag('{s['import_id']}','{FRESH}')")
            p2, h2 = payload(dict(parent_revision_id=initial["revision_id"], rows=rows, title="Synthetic changed group", reason="Saved changed synthetic reason"))
            call(f"public.admin_save_roster_import_draft('{s['import_id']}','{uid(402)}','{uid(401)}',{lit(p2)},'{h2}')", sid=OLD)
            sql(f"delete from auth.sessions where id='{OLD}';insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values('{FRESH}','{ACTOR}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');")
            inspected = call(f"public.admin_inspect_interrupted_roster_import('{s['import_id']}')")
            tag = inspected["etag"]
            case("actual changed draft CAS refuses the genuinely prior etag", lambda: deny(f"public.admin_transfer_interrupted_roster_import('{uid(501)}','{s['import_id']}','{old_tag}',true)", "55000", "roster_draft_superseded"))
            case("current email-approved cross-actor cannot inspect another actor import", lambda: deny(f"public.admin_inspect_interrupted_roster_import('{s['import_id']}')", actor=PEER, sid=PEERSID, reason="roster_import_unavailable"))
            transfer = f"public.admin_transfer_interrupted_roster_import('{uid(502)}','{s['import_id']}','{tag}',true)"
            ack = call(transfer)
            keys = set("contract_version ok state request_id from_import_id root_import_id to_import_id actor_id destination_session_id destination_reference_id initial_revision_id checkpoint_id draft_sha256 source_etag original_proof_sha256 expires_at".split())
            case("email recovery transfer exact ACK binds request actor fresh session source and immutable proof", lambda: require(set(ack) == keys and ack["contract_version"] == 1 and ack["ok"] is True and ack["state"] == "transferred" and ack["request_id"] == uid(502) and ack["actor_id"] == ACTOR and ack["destination_session_id"] == FRESH and ack["from_import_id"] == s["import_id"] and ack["root_import_id"] == s["import_id"] and ack["source_etag"] == tag and ack["expires_at"] == initial["expires_at"]))
            case("exact transfer replay is byte-equivalent without another transfer audit", lambda: require(call(transfer) == ack and scalar("select count(*) from public.audit_logs where action='roster.import.recovery_transferred'") == "1"))
            recovered = call(f"public.admin_recover_roster_import('{ack['destination_reference_id']}',null)")
            case("recovery preserves saved rows and source proof while requiring new human review", lambda: require(json.loads(recovered["draft"]["payload"])["rows"] == rows and recovered["initial_preview"]["can_submit"] is False and recovered["initial_preview"]["requires_human_review"] is True and recovered["initial_preview"]["source_receipt"] == initial["source_receipt"] and recovered["initial_preview"]["expires_at"] == initial["expires_at"]))
            case("current email-approved cross-actor cannot recover or observe exact transfer receipt", lambda: (deny(f"public.admin_recover_roster_import('{ack['destination_reference_id']}',null)", actor=PEER, sid=PEERSID, reason="roster_import_unavailable"), deny(f"public.admin_get_roster_transfer_status('{uid(502)}')", actor=PEER, sid=PEERSID, reason="roster_import_unavailable")))
            recovery_call = f"public.admin_recover_roster_import('{ack['destination_reference_id']}',null)"
            for name, mutate, restore in (
                ("session", f"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='{FRESH}'", f"update auth.sessions set not_after=clock_timestamp()+interval '1 hour' where id='{FRESH}'"),
                ("role", f"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='{ACTOR}'", f"update public.admin_user_roles set revoked_at=null where user_id='{ACTOR}'"),
                ("email approval", f"update collect_admin_access.email_approvals set revoked_at=clock_timestamp() where user_id='{ACTOR}'", f"update collect_admin_access.email_approvals set revoked_at=null where user_id='{ACTOR}'"),
            ):
                sql(mutate + ";")
                case("committed " + name + " revocation denies recovery under final email authority", lambda: deny(recovery_call, reason="roster_actor_unavailable"))
                sql(restore + ";")
                require(call(recovery_call) == recovered, "Restored authority must recover exact prior receipt")
            for api_role in ("anon", "service_role"):
                case(api_role + " cannot use private roster recovery", lambda api_role=api_role: deny(recovery_call, role=api_role))
            review_id, commit_id = uid(601), uid(602)
            review_text, review_sha = payload(dict(p_request_id=review_id, p_import_id=ack["to_import_id"], p_parent_revision_id=ack["initial_revision_id"], p_rows=rows, p_reason="Reviewed all recovered synthetic rows"))
            call(f"public.admin_stage_roster_import_intent('{review_id}','{ack['to_import_id']}','review',{lit(review_text)},'{review_sha}')")
            reviewed_ack = call(f"public.admin_execute_roster_import_intent('{review_id}','{review_sha}',true)")
            reviewed = reviewed_ack["result"]
            case("saved review intent executes with exact request payload hash and reviewed revision", lambda: require(reviewed_ack["request_id"] == review_id and reviewed_ack["import_id"] == ack["to_import_id"] and reviewed_ack["kind"] == "review" and reviewed_ack["payload_sha256"] == review_sha and reviewed["processing_method"] == "human_review" and reviewed["can_submit"] is True))
            reason = "Committed all recovered synthetic rows"
            commit_text, commit_sha = payload(dict(p_request_id=commit_id, p_import_id=ack["to_import_id"], p_revision_id=reviewed["revision_id"], p_reviewed_rows_sha256=reviewed["reviewed_rows_sha256"], p_human_affirmed=True, p_mode="create", p_collection_id=None, p_title="Synthetic email recovered group", p_reason=reason))
            call(f"public.admin_stage_roster_import_intent('{commit_id}','{ack['to_import_id']}','commit',{lit(commit_text)},'{commit_sha}')")
            committed_ack = call(f"public.admin_execute_roster_import_intent('{commit_id}','{commit_sha}',true)")
            committed = committed_ack["result"]
            case("saved commit intent binds exact reviewed rows request and durable collection", lambda: require(committed_ack["request_id"] == commit_id and committed_ack["payload_sha256"] == commit_sha and committed_ack["kind"] == "commit" and committed["ok"] is True and committed["request_id"] == commit_id and committed["import_id"] == ack["to_import_id"] and committed["revision_id"] == reviewed["revision_id"] and committed["reviewed_rows_sha256"] == reviewed["reviewed_rows_sha256"] and committed["roster_count"] == 1 and committed["mode"] == "create"))
            replay = call(f"public.admin_execute_roster_import_intent('{commit_id}','{commit_sha}',true)")
            case("explicit commit replay creates one durable commit and one audit", lambda: require(replay["result"] == (committed | dict(replayed=True)) and scalar("select count(*) from collect_hybrid.roster_import_commits") == "1" and scalar("select count(*) from public.audit_logs where action='roster.import.committed'") == "1"))
            audit = json.loads(scalar("select jsonb_build_object('actor',actor_user_id,'entity_type',entity_type,'entity_id',entity_id,'metadata',metadata) from public.audit_logs where action='roster.import.committed'"))
            case("durable import audit exactly binds actor collection source reviewed hash affirmation count and reason", lambda: require(audit == dict(actor=ACTOR, entity_type="collection", entity_id=committed["collection_id"], metadata=dict(request_id=commit_id, import_id=ack["to_import_id"], revision_id=reviewed["revision_id"], source_sha256=s["source_sha256"], reviewed_rows_sha256=reviewed["reviewed_rows_sha256"], human_affirmed=True, mode="create", row_count=1, reason=reason))))
            case("durable commit recovery returns the same recorded result", lambda: require(call(f"public.admin_recover_roster_import('{ack['destination_reference_id']}','{commit_id}')")["intent"]["result"] == committed))

            def race(n, revoke_first):
                source = fixtures[n - 1]["source"]["import_id"]
                tag = call(f"public.admin_inspect_interrupted_roster_import('{source}')")["etag"]
                action = f"public.admin_transfer_interrupted_roster_import('{uid(700+n)}','{source}','{tag}',true)"
                revocation = f"public.admin_revoke_email_operator_v1('{ACTOR}','Synthetic current email revocation')"
                holder, waiter = U.Session(db, "e1_holder_" + str(n)), U.Session(db, "e1_waiter_" + str(n))
                sessions.extend((holder, waiter))
                for session in (holder, waiter):
                    session.write("set statement_timeout='30s';set lock_timeout='15s';select 'PID:'||pg_backend_pid();select 'READY';")
                    lines = session.read("READY")
                    session.pid = int(next(x[4:] for x in lines if x.startswith("PID:")))
                if revoke_first:
                    waiter.write("begin isolation level repeatable read;select count(*) from collect_admin_access.email_approvals;select 'SNAPSHOT';")
                    waiter.read("SNAPSHOT")
                holder.write("begin;" + (claims(PEER, PEERSID) if revoke_first else claims()) + "select 'RESULT:'||(" + (revocation if revoke_first else action) + ")::text;select 'HELD';")
                held = holder.read("HELD")
                if not revoke_first:
                    waiter.write("begin;")
                waiter.write((claims() if revoke_first else claims(PEER, PEERSID)) + "select 'RESULT:'||(" + (action if revoke_first else revocation) + ")::text;commit;select 'DONE';")
                observed = None
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    observation = json.loads(scalar(f"select jsonb_build_object('waiting',wait_event_type='Lock','blockers',pg_blocking_pids(pid)) from pg_stat_activity where pid={waiter.pid}"))
                    if observation["waiting"] and holder.pid in observation["blockers"]:
                        observed = observation
                        break
                    time.sleep(.05)
                require(observed is not None, "Actual approval/transfer blocking was not observed")
                holder.write("commit;select 'COMMITTED';")
                holder.read("COMMITTED")
                done = waiter.read("DONE")
                if revoke_first:
                    require(any("40001:" in x or ("42501:" in x and "roster_actor_unavailable" in x) for x in done), done)
                    require(not any(x.startswith("RESULT:") for x in done), done)
                    require(scalar(f"select count(*) from collect_hybrid.roster_recovery_transfers where request_id='{uid(700+n)}'") == "0")
                    result = dict(observed=observed, established_snapshot=True, denial="40001" if any("40001:" in x for x in done) else "42501")
                else:
                    transfer_ack = json.loads(next(x[7:] for x in held if x.startswith("RESULT:")))
                    revoke_ack = json.loads(next(x[7:] for x in done if x.startswith("RESULT:")))
                    require(transfer_ack["request_id"] == uid(700+n) and transfer_ack["destination_session_id"] == FRESH and revoke_ack == dict(ok=True, status="revoked", user_id=ACTOR))
                    deny(f"public.admin_recover_roster_import('{transfer_ack['destination_reference_id']}',null)", reason="roster_actor_unavailable")
                    result = dict(observed=observed, transfer_committed_before_revoke=True, subsequent_recovery_denied=True)
                for session in (holder, waiter):
                    session.close()
                    sessions.remove(session)
                sql(f"update collect_admin_access.email_approvals set revoked_at=null,revoked_by=null where user_id='{ACTOR}';")
                evidence["actual_blocking_races"] += 1
                return result

            case("public email revocation wins before established-snapshot transfer and leaves no branch", lambda: race(2, True))
            case("transfer wins before public email revocation but cannot be recovered after committed revoke", lambda: race(3, False))
            case("captured final dependency source bytes remain unchanged", lambda: require(all(p.read_bytes() == b for p, b in sources.items())))
            evidence["actual_dependency_definitions"] = json.loads(scalar("select jsonb_object_agg(p.oid::regprocedure::text,encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex')) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='collect_hybrid' and p.proname in ('require_roster_actor_authority','require_roster_actor','require_roster_caller','require_fresh_roster_auth')) or (n.nspname='public' and p.proname in ('admin_transfer_interrupted_roster_import','admin_recover_roster_import','admin_execute_roster_import_intent','admin_commit_roster_import','admin_revoke_email_operator_v1','assert_admin_permission'))"))
        evidence["status"] = "pass"
    except Exception as error:
        evidence.update(status="failed", failure=str(error))
        raise
    finally:
        for session in sessions:
            try:
                session.close()
            except Exception as error:
                evidence.setdefault("cleanup_errors", []).append(str(error))
        U.SQL_LOG = U.CONCURRENCY_LOG = None
        evidence["completed_at"] = datetime.now(timezone.utc).isoformat()
        save()


if __name__ == "__main__":
    main()
