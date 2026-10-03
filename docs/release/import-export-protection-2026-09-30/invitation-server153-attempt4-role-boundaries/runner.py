#!/usr/bin/env python3
"""Actual invitation RPC/ACL/receipt/revocation UAT with synthetic local rows."""
import argparse
import datetime
import json
from pathlib import Path
import time
import uuid

import local_schema_uat as local

R, U, ROOT = local.R, local.U, local.ROOT
MIGRATION = ROOT / "supabase/migrations/20260930230000_group_share_rotation_receipts.sql"
UID, SID = U.UID, U.SID
MEMBER, MEMBERSID = U.OTHER, U.OTHERSID
OUTSIDER = "99710000-0000-4000-8000-000000000003"
OUTSIDERSID = "99710000-0000-4000-8000-000000010004"
GROUP = "99710000-0000-4000-8000-000000030001"
GROUP2 = "99710000-0000-4000-8000-000000030002"


def auth(uid=UID, sid=SID, exp=None):
    claims = dict(sub=uid, session_id=sid, role="authenticated", aal="aal1",
                  exp=int(time.time()) + 3600 if exp is None else exp)
    return "set local role authenticated;select set_config('request.jwt.claims'," + R.literal(json.dumps(claims)) + ",true);"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = args.output.resolve()
    if not report.is_relative_to(ROOT / "docs/release") or report.exists():
        parser.error("Fresh local release evidence directory required")
    report.mkdir(parents=True, mode=0o700)
    source = MIGRATION.read_bytes()
    evidence = dict(kind="group_share_rotation_actual_local_schema153", status="running",
                    started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), cases=[],
                    migration_sha256=R.sha(source), runner_sha256=R.sha(Path(__file__).read_bytes()),
                    installed_in_shared_source=False, actual_blocking_races=0)
    (report / "migration.sql").write_bytes(source)
    (report / "runner.py").write_bytes(Path(__file__).read_bytes())
    (report / "local_schema_uat.py").write_bytes(Path(local.__file__).read_bytes())

    def save():
        R.save(report / "result.json", evidence)

    def case(name, action):
        detail = action()
        evidence["cases"].append(dict(name=name, status="pass", detail=detail))
        save()
        print("PASS " + name, flush=True)
        return detail

    def check(value):
        assert value, value
        return True

    sessions = []
    U.SQL_LOG = report / "queries.log"
    U.CONCURRENCY_LOG = report / "concurrency.log"
    save()
    try:
        with local.isolated(report, evidence) as db:
            def sql(body, check=True):
                return U.psql(db, body, check)

            def call(body, uid=UID, sid=SID, exp=None):
                value = sql("begin;" + auth(uid, sid, exp) + body + ";commit;")
                return json.loads(value.stdout.strip().splitlines()[-1])

            def error(body, state, reason=None, uid=UID, sid=SID, role="authenticated", exp=None):
                claims = auth(uid, sid, exp) if role == "authenticated" else "set local role " + role + ";"
                result = sql("begin;" + claims + body + ";commit;", False)
                check(result.returncode and state + ":" in result.stderr and (reason is None or reason in result.stderr))
                return dict(sqlstate=state, reason=reason)

            sql(f"""insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
              values('{UID}','authenticated','authenticated','250788971001',now(),'{{}}','{{}}'),
                    ('{MEMBER}','authenticated','authenticated','250788971002',now(),'{{}}','{{}}'),
                    ('{OUTSIDER}','authenticated','authenticated','250788971003',now(),'{{}}','{{}}');
              insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
              values('{SID}','{UID}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
                    ('{MEMBERSID}','{MEMBER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
                    ('{OUTSIDERSID}','{OUTSIDER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
              insert into public.collections(id,slug,creator_user_id,title,category)
              values('{GROUP}','synthetic-invitation-one','{UID}','Synthetic invitation','Family / friends'),
                    ('{GROUP2}','synthetic-invitation-two','{UID}','Synthetic invitation two','Family / friends');
              insert into public.collection_members(collection_id,user_id,role,status)
              values('{GROUP}','{MEMBER}','member','active');
              insert into public.collection_share_secrets(collection_id,share_code)
              values('{GROUP}',gen_random_uuid()),('{GROUP2}',gen_random_uuid());""")
            prior_code = call(f"select to_jsonb(public.get_group_share_code('{GROUP}'))")
            case("legacy owner positive control has a real existing secret", lambda: check(str(uuid.UUID(prior_code)) == prior_code))
            financial = U.fingerprint(db)
            installation = sql(source.decode(), False)
            (report / "install.stdout.log").write_text(installation.stdout)
            (report / "install.stderr.log").write_text(installation.stderr)
            check(installation.returncode == 0)
            case("installation preserves all synthetic financial families", lambda: check(financial == U.fingerprint(db)))
            truth = lambda body: check(sql(body).stdout.strip() == "t")
            case("private immutable receipt table has RLS and no API grants", lambda: truth("select c.relrowsecurity and not exists(select 1 from unnest(array['anon','authenticated','service_role']) r where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')) from pg_class c where c.oid='collect_member_actions.group_share_rotations'::regclass;"))
            case("private helpers have no API execute grants", lambda: truth("select count(distinct p.oid)=2 and count(*)=6 and bool_and(not has_function_privilege(r,p.oid,'EXECUTE')) from pg_proc p cross join unnest(array['anon','authenticated','service_role']) r where p.pronamespace='collect_member_actions'::regnamespace and p.proname in ('guard_group_share_rotation','require_group_share_actor');"))
            for role in ("anon", "service_role"):
                case(role + " cannot read private invitation", lambda role=role: error(f"select public.get_group_share_code('{GROUP}')", "42501", role=role))
                case(role + " cannot rotate invitation", lambda role=role: error(f"select public.rotate_group_share_code_v2('{GROUP}',gen_random_uuid())", "42501", role=role))
            old = call(f"select to_jsonb(public.get_group_share_code('{GROUP}'))")
            case("installation preserves existing invitation code", lambda: check(old == prior_code))
            case("owner and active ordinary member read same current code", lambda: check(old == call(f"select to_jsonb(public.get_group_share_code('{GROUP}'))", MEMBER, MEMBERSID)))
            case("nonmember read denied", lambda: error(f"select public.get_group_share_code('{GROUP}')", "42501", "group_share_permission_required", OUTSIDER, OUTSIDERSID))
            case("ordinary member cannot rotate", lambda: error(f"select public.rotate_group_share_code_v2('{GROUP}',gen_random_uuid())", "42501", "group_share_permission_required", MEMBER, MEMBERSID))
            case("legacy unidentified rotation refused", lambda: error(f"select public.rotate_group_share_code('{GROUP}')", "22023", "group_share_rotation_request_required"))
            case("null request refused", lambda: error(f"select public.rotate_group_share_code_v2('{GROUP}',null)", "22023", "group_share_request_invalid"))
            request = str(uuid.uuid4())
            receipt = call(f"select public.rotate_group_share_code_v2('{GROUP}','{request}')")
            case("exact bound rotation receipt returns new canonical code", lambda: check(set(receipt) == {"contract_version", "ok", "collection_id", "request_id", "share_code"} and receipt["contract_version"] == 1 and receipt["ok"] is True and receipt["collection_id"] == GROUP and receipt["request_id"] == request and str(uuid.UUID(receipt["share_code"])) == receipt["share_code"] and receipt["share_code"] != old))
            case("same actor replay returns identical receipt", lambda: check(receipt == call(f"select public.rotate_group_share_code_v2('{GROUP}','{request}')")))
            case("replay creates exactly one receipt and redacted audit", lambda: truth(f"select (select count(*) from collect_member_actions.group_share_rotations where request_id='{request}')=1 and (select count(*) from public.audit_logs where action='group.share_link_rotated' and entity_id='{GROUP}' and actor_user_id='{UID}' and metadata->>'request_id'='{request}')=1 and not exists(select 1 from public.audit_logs where metadata::text like '%{receipt['share_code']}%');"))
            case("request replay cannot bind another collection", lambda: error(f"select public.rotate_group_share_code_v2('{GROUP2}','{request}')", "40001", "group_share_request_conflict"))
            call(f"select public.rotate_group_share_code_v2('{GROUP}',gen_random_uuid())")
            case("superseded replay refused", lambda: error(f"select public.rotate_group_share_code_v2('{GROUP}','{request}')", "55000", "group_share_rotation_superseded"))
            for operation in (f"update collect_member_actions.group_share_rotations set actor_id='{MEMBER}' where request_id='{request}'", f"delete from collect_member_actions.group_share_rotations where request_id='{request}'"):
                case("receipt immutability " + operation.split()[0], lambda operation=operation: error(operation, "55000", "group_share_receipt_immutable", role="postgres"))
            case("expired JWT refused", lambda: error(f"select public.get_group_share_code('{GROUP}')", "42501", "group_share_session_required", exp=int(time.time()) - 1))
            case("malformed JWT expiry refused", lambda: error(f"select public.get_group_share_code('{GROUP}')", "42501", "group_share_session_required", exp="not-a-number"))
            case("missing Auth session refused", lambda: error(f"select public.get_group_share_code('{GROUP}')", "42501", "group_share_session_required", sid=str(uuid.uuid4())))
            sql(f"""insert into public.admin_roles(id,name,description)
              values('99710000-0000-4000-8000-000000020001','platform_owner','Synthetic invitation authority');
              insert into public.admin_permissions(name,description) values('collections.moderate','Synthetic');
              insert into public.admin_role_permissions(role_id,permission_name)
              values('99710000-0000-4000-8000-000000020001','collections.moderate');
              insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
              values('{OUTSIDER}','+250788971003',clock_timestamp()-interval '2 minutes','Synthetic authority');
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
              values('{OUTSIDER}','99710000-0000-4000-8000-000000020001','Synthetic authority',clock_timestamp()-interval '1 minute');""")
            case("nonmember platform owner cannot read private invitation", lambda: error(f"select public.get_group_share_code('{GROUP}')", "42501", "group_share_permission_required", OUTSIDER, OUTSIDERSID))
            platform_receipt = call(f"select public.rotate_group_share_code_v2('{GROUP2}',gen_random_uuid())", OUTSIDER, OUTSIDERSID)
            case("current platform-owner moderation may rotate as before", lambda: check(platform_receipt['ok'] is True and platform_receipt['collection_id'] == GROUP2))
            sql(f"insert into public.collection_members(collection_id,user_id,role,status) values('{GROUP2}','{MEMBER}','receiver','active');")
            receiver_receipt = call(f"select public.rotate_group_share_code_v2('{GROUP2}',gen_random_uuid())", MEMBER, MEMBERSID)
            case("current active receiver may rotate as before", lambda: check(receiver_receipt['ok'] is True and receiver_receipt['collection_id'] == GROUP2))
            case("another authorized actor cannot replay the receiver request", lambda: error(f"select public.rotate_group_share_code_v2('{GROUP2}','{receiver_receipt['request_id']}')", "40001", "group_share_request_conflict"))
            # Real committed revoke after an established snapshot, plus both
            # blocking operation orders. Synthetic identities only.
            for field, mutate, restore, uid, sid in (
                ("membership", f"update public.collection_members set status='removed' where collection_id='{GROUP}' and user_id='{MEMBER}'", f"update public.collection_members set status='active' where collection_id='{GROUP}' and user_id='{MEMBER}'", MEMBER, MEMBERSID),
                ("archive", f"update public.collections set archived_at=clock_timestamp() where id='{GROUP}'", f"update public.collections set archived_at=null where id='{GROUP}'", UID, SID),
                ("Auth expiry", f"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='{SID}'", f"update auth.sessions set not_after=clock_timestamp()+interval '1 hour' where id='{SID}'", UID, SID),
            ):
                a, b = U.Session(db, field + "-reader"), U.Session(db, field + "-revoke")
                sessions.extend((a, b))
                a.write("begin isolation level repeatable read;select count(*) from public.collections;select 'SNAPSHOT_READY';")
                a.read("SNAPSHOT_READY")
                sql(mutate + ";")
                a.write(auth(uid, sid) + f"""do $$begin begin
                  perform public.get_group_share_code('{GROUP}');
                  perform set_config('collect.invitation_probe','allowed',true);
                  exception when sqlstate '40001' or sqlstate '42501' then
                  perform set_config('collect.invitation_probe',sqlstate,true);end;end$$;
                  select 'RR_RESULT:'||current_setting('collect.invitation_probe');select 'RR_DONE';""")
                observed = a.read("RR_DONE")
                case(field + " established snapshot denies committed revoke", lambda observed=observed: check("RR_RESULT:40001" in observed or "RR_RESULT:42501" in observed))
                a.write("rollback;select 'RR_CLOSED';")
                a.read("RR_CLOSED")
                sql(restore + ";")
                for order in ("read_first", "revoke_first"):
                    if order == "read_first":
                        a.write("begin;" + auth(uid, sid) + f"select public.get_group_share_code('{GROUP}');select 'READ_HELD';")
                        a.read("READ_HELD")
                        b.write("begin;" + mutate + ";select 'REVOKE_DONE';")
                        waiter = "update"
                    else:
                        b.write("begin;" + mutate + ";select 'REVOKE_HELD';")
                        b.read("REVOKE_HELD")
                        a.write("begin;" + auth(uid, sid) + f"""do $$begin begin
                          perform public.get_group_share_code('{GROUP}');
                          perform set_config('collect.invitation_probe','allowed',true);
                          exception when sqlstate '42501' then
                          perform set_config('collect.invitation_probe',sqlstate,true);end;end$$;
                          select 'READ_RESULT:'||current_setting('collect.invitation_probe');select 'READ_DONE';""")
                        waiter = "get_group_share_code"
                    end = time.monotonic() + 8
                    blocked = False
                    while time.monotonic() < end:
                        blocked = sql("select exists(select 1 from pg_stat_activity where datname=" + R.literal(db) + " and wait_event_type='Lock' and query ilike " + R.literal("%" + waiter + "%") + ");").stdout.strip() == "t"
                        if blocked:
                            break
                        time.sleep(.03)
                    check(blocked)
                    if order == "read_first":
                        a.write("commit;select 'READ_COMMITTED';")
                        a.read("READ_COMMITTED")
                        b.read("REVOKE_DONE")
                        b.write("commit;select 'REVOKE_COMMITTED';")
                        b.read("REVOKE_COMMITTED")
                    else:
                        b.write("commit;select 'REVOKE_COMMITTED';")
                        b.read("REVOKE_COMMITTED")
                        denied = a.read("READ_DONE")
                        check("READ_RESULT:42501" in denied)
                        a.write("rollback;select 'READ_CLOSED';")
                        a.read("READ_CLOSED")
                    evidence["actual_blocking_races"] += 1
                    case(field + " " + order + " uses actual authority row wait", lambda: True)
                    sql(restore + ";")
                a.close()
                b.close()
                sessions.remove(a)
                sessions.remove(b)
            # Real rotations fill the cap; fixtures never bypass receipt guards.
            existing = int(sql(f"select count(*) from collect_member_actions.group_share_rotations where collection_id='{GROUP}';").stdout)
            for _ in range(60 - existing):
                call(f"select public.rotate_group_share_code_v2('{GROUP}',gen_random_uuid())")
            case("rolling hourly quota refuses sixty-first actual rotation", lambda: error(f"select public.rotate_group_share_code_v2('{GROUP}',gen_random_uuid())", "55000", "group_share_rate_limited"))
            case("all invitation operations preserve financial fingerprints", lambda: check(financial == U.fingerprint(db)))
            check(MIGRATION.read_bytes() == source)
            evidence["migration_source_unchanged"] = True
        evidence["status"] = "pass"
    except Exception as error:
        evidence.update(status="failed", failure=str(error))
        raise
    finally:
        for session in sessions:
            try:
                session.close()
            except Exception as error:
                evidence.setdefault("worker_cleanup_errors", []).append(str(error))
        U.SQL_LOG = None
        U.CONCURRENCY_LOG = None
        evidence["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()


if __name__ == "__main__":
    main()
