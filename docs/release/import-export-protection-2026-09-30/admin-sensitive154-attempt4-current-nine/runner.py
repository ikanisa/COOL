#!/usr/bin/env python3
"""Synthetic sensitive Admin RPC/ACL/audit UAT in a disposable local database.

The shared154 database is read only. Email213000 and security233000 are applied
only to a schema/ACL clone; no customer rows, hosted Auth or providers are used.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import time

import local_schema_uat as local
import staged_bundle_upgrade_uat as bundle

R, U, ROOT = local.R, local.U, local.ROOT
MIGRATIONS = [ROOT / "supabase/migrations" / name for name in (
    "20260930213000_operator_email_auth.sql",
    "20260930233000_sensitive_admin_authority.sql",
)]
UID, SID, OTHER, OTHERSID = U.UID, U.SID, U.OTHER, U.OTHERSID
ROLE = "99710000-0000-4000-8000-000000020001"
SMS = "99710000-0000-4000-8000-000000050001"
EVENT = "99710000-0000-4000-8000-000000050002"
DEVICE = "99710000-0000-4000-8000-000000050003"
RAW_BODY = "SYNTHETIC RAW SMS; never a payment confirmation"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--current-bundle", action="store_true",
                        help="Apply all nine reviewed staged migrations before current authority tests")
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh repository release evidence directory required")
    report.mkdir(parents=True, mode=0o700)
    paths = ([ROOT / "supabase/migrations" / name for name in bundle.STAGES]
             if args.current_bundle else MIGRATIONS)
    sources = {path: path.read_bytes() for path in paths}
    evidence = dict(kind="actual_sensitive_admin_email_authority_schema154", status="running",
                    started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    installed_in_shared_source=False, cases=[], actual_blocking_races=0,
                    migration_sources={path.name: R.sha(body) for path, body in sources.items()},
                    current_staged_bundle_tested=args.current_bundle)
    for path, body in sources.items():
        (report / path.name).write_bytes(body)
    (report / "runner.py").write_bytes(Path(__file__).read_bytes())
    (report / "local_schema_uat.py").write_bytes(Path(local.__file__).read_bytes())
    if args.current_bundle:
        (report / "bundle-runner.py").write_bytes(Path(bundle.__file__).read_bytes())
    U.SQL_LOG = report / "queries.log"
    U.CONCURRENCY_LOG = report / "concurrency.log"
    sessions = []

    def save():
        R.save(report / "result.json", evidence)

    def check(value):
        assert value, value
        return True

    def case(name, fn):
        result = fn()
        evidence["cases"].append(dict(name=name, status="pass", detail=result))
        save()
        print("PASS " + name, flush=True)
        return result

    save()
    try:
        with local.isolated(report, evidence, count=154, latest="20260930230000") as db:
            def sql(body, required=True):
                return U.psql(db, body, required)

            def call(body, uid=UID, sid=SID):
                return json.loads(sql("begin;" + U.auth(uid, sid) + body + ";commit;").stdout.strip().splitlines()[-1])

            def denied(body, state="42501", reason=None, mutation="", uid=UID, sid=SID, role="authenticated"):
                identity = U.auth(uid, sid) if role == "authenticated" else "set local role " + role + ";"
                result = sql("begin;" + mutation + identity + body + ";commit;", False)
                check(result.returncode and state + ":" in result.stderr and (reason is None or reason in result.stderr))
                return dict(sqlstate=state, reason=reason)

            def truth(body):
                return check(sql(body).stdout.strip() == "t")

            def catalog():
                names = ",".join(R.literal(x) for x in R.SCHEMAS)
                return json.loads(sql(f"""select jsonb_object_agg(identity,properties) from (
                  select n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')' identity,
                    jsonb_build_object('body',p.prosrc,'volatility',p.provolatile,'owner',p.proowner,
                      'acl',p.proacl,'definer',p.prosecdef,'config',p.proconfig,
                      'result',pg_get_function_result(p.oid),'arguments',pg_get_function_arguments(p.oid)) properties
                  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ({names})
                )s;""").stdout)

            prerequisites = [path for path in paths if path.name < MIGRATIONS[1].name]
            for path in prerequisites:
                result = sql(sources[path].decode(), False)
                (report / (path.stem + "-apply.stdout.log")).write_text(result.stdout)
                (report / (path.stem + "-apply.stderr.log")).write_text(result.stderr)
                check(result.returncode == 0)
            before = catalog()
            candidate = sql(sources[MIGRATIONS[1]].decode(), False)
            (report / "security-apply.stdout.log").write_text(candidate.stdout)
            (report / "security-apply.stderr.log").write_text(candidate.stderr)
            check(candidate.returncode == 0)
            after = catalog()
            R.save(report / "catalog-before.json", before)
            R.save(report / "catalog-after.json", after)
            altered = {re.sub(r"\s+", "", value).lower() for value in re.findall(
                r"alter function ([a-z_][a-z_0-9]*\.[a-z_][a-z_0-9]*\([^;]*?\)) volatile;",
                sources[MIGRATIONS[1]].decode(), re.I)}
            bodies = {"public.assert_admin_permission(text)", "public.has_admin_permission(text,uuid)",
                      "collect_admin_access.caller_eligible(uuid)", "public.admin_reveal_raw_sms(uuid,text)",
                      "public.admin_retry_notification(uuid,text)"}
            differences = {}
            check(set(before) == set(after))
            for identity, old in before.items():
                new = after[identity]
                norm = re.sub(r"\s+", "", identity).lower()
                changed = {key for key in old if old[key] != new[key]}
                if changed:
                    differences[identity] = sorted(changed)
                    check(norm in altered or norm in bodies)
                    check(changed <= ({"body", "volatility", "config"} if norm in bodies else {"volatility"}))
                if norm in altered:
                    check(new["volatility"] == "v")
            check(len(altered) == 62)
            evidence["catalog_changes"] = differences
            case("candidate preserves all existing routine names/results/arguments/owners/ACLs and all unrelated bodies", lambda: True)
            case("all62 explicitly reviewed transitive readers are writable VOLATILE RPCs", lambda: True)
            for path in paths:
                if path.name > MIGRATIONS[1].name:
                    result = sql(sources[path].decode(), False)
                    (report / (path.stem + "-apply.stdout.log")).write_text(result.stdout)
                    (report / (path.stem + "-apply.stderr.log")).write_text(result.stderr)
                    check(result.returncode == 0)
            sql(f"""insert into public.admin_roles(id,name,description) values('{ROLE}','platform_owner','Synthetic');
              insert into public.admin_permissions(name,description) values
               ('sms.raw.reveal','Synthetic'),('sms.metadata.read','Synthetic'),('notifications.read','Synthetic'),
               ('notifications.manage','Synthetic'),('audit.read','Synthetic');
              insert into public.admin_role_permissions(role_id,permission_name) select '{ROLE}',name from public.admin_permissions;
              insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
              values('{UID}','authenticated','authenticated','synthetic-one@collect.example',now(),'{{}}','{{}}'),
                    ('{OTHER}','authenticated','authenticated','synthetic-two@collect.example',now(),'{{}}','{{}}');
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
              values('{UID}','synthetic-one@collect.example',clock_timestamp()-interval '2 minutes','Synthetic authority approval'),
                    ('{OTHER}','synthetic-two@collect.example',clock_timestamp()-interval '2 minutes','Synthetic authority approval');
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
              values('{UID}','{ROLE}','Synthetic authority grant',clock_timestamp()-interval '1 minute');
              insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
              values('{SID}','{UID}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
                    ('{OTHERSID}','{OTHER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
              insert into public.raw_payment_sms(id,receiver_user_id,raw_sender,raw_body,body_hash)
              values('{SMS}','{OTHER}','SYNTHETIC',{R.literal(RAW_BODY)},'synthetic_sensitive_body_971001');""")
            financial_before = U.fingerprint(db)
            reveal = lambda reason: f"select public.admin_reveal_raw_sms('{SMS}',{R.literal(reason) if reason is not None else 'null'})"
            case("current email-approved owner can reveal exact synthetic body", lambda: check(call(reveal("Reviewed synthetic case")) == {"ok": True, "message": RAW_BODY}))
            case("raw reveal creates both current-actor audit records without raw-body leakage", lambda: truth(f"""select
              (select count(*) from public.admin_sensitive_access_logs where actor_user_id='{UID}' and entity_id='{SMS}' and reason='Reviewed synthetic case')=1
              and (select count(*) from public.audit_logs where actor_user_id='{UID}' and action='sms.raw.revealed' and entity_id='{SMS}' and metadata->>'reason'='Reviewed synthetic case')=1
              and not exists(select 1 from public.audit_logs where metadata::text like '%{RAW_BODY}%');"""))
            for role in ("anon", "service_role"):
                case(role + " cannot reveal raw SMS", lambda role=role: denied(reveal("Synthetic reason"), role=role))
            case("approved ordinary member without Admin role cannot reveal", lambda: denied(reveal("Synthetic reason"), uid=OTHER, sid=OTHERSID))
            for name in ("compliance_admin", "operations_admin", "payments_admin", "moderation_admin", "support_admin", "read_only_admin"):
                sql("insert into public.admin_roles(name,description) values(" + R.literal(name) + ",'Synthetic');")
                mutation = f"delete from public.admin_user_roles where user_id='{UID}';" + f"insert into public.admin_user_roles(user_id,role_id,reason,created_at) select '{UID}',id,'Synthetic',clock_timestamp()-interval '1 minute' from public.admin_roles where name='{name}';" + f"insert into public.admin_role_permissions(role_id,permission_name) select id,'sms.raw.reveal' from public.admin_roles where name='{name}';"
                case(name + " cannot bypass existing platform-owner-only eligibility even with raw permission", lambda mutation=mutation: denied(reveal("Synthetic reason"), mutation=mutation))
            denials = [
                ("missing specific permission", f"delete from public.admin_role_permissions where role_id='{ROLE}' and permission_name='sms.raw.reveal';"),
                ("revoked grant", f"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='{UID}';"),
                ("revoked email approval", f"update collect_admin_access.email_approvals set revoked_at=clock_timestamp() where user_id='{UID}';"),
                ("expired email approval", f"update collect_admin_access.email_approvals set expires_at=clock_timestamp()-interval '1 second' where user_id='{UID}';"),
                ("new approval requires newer sign-in", f"update collect_admin_access.email_approvals set approved_at=clock_timestamp() where user_id='{UID}';"),
                ("new role requires newer sign-in", f"update public.admin_user_roles set created_at=clock_timestamp() where user_id='{UID}';"),
                ("unverified email", f"update auth.users set email_confirmed_at=null where id='{UID}';"),
                ("changed email", f"update auth.users set email='changed@collect.example' where id='{UID}';"),
                ("deleted Auth user", f"update auth.users set deleted_at=clock_timestamp() where id='{UID}';"),
                ("banned Auth user", f"update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='{UID}';"),
                ("anonymous Auth user", f"update auth.users set is_anonymous=true where id='{UID}';"),
                ("expired Auth session", f"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='{SID}';"),
            ]
            for name, mutation in denials:
                case(name + " refuses sensitive public RPC", lambda mutation=mutation: denied(reveal("Synthetic reason"), mutation=mutation))
            case("session bound to another user is refused", lambda: denied(reveal("Synthetic reason"), sid=OTHERSID))
            case("missing Auth session is refused", lambda: denied(reveal("Synthetic reason"), sid="99710000-0000-4000-8000-000000010099"))
            for reason in (None, "", "   ", "\t\n\r", "x" * 1001, "\u00e9" * 1001):
                case("invalid reason " + repr(reason)[:35] + " refuses reveal before output/audit", lambda reason=reason: denied(reveal(reason), "P0001", "Reason is required"))
            before_logs = json.loads(sql("select jsonb_build_array((select count(*) from public.audit_logs where action='sms.raw.revealed'),(select count(*) from public.admin_sensitive_access_logs));").stdout)
            case("nonexistent SMS does not produce success", lambda: denied("select public.admin_reveal_raw_sms(gen_random_uuid(),'Synthetic reason')", "P0001", "Raw SMS not found"))
            case("all denied reveal attempts leave audit counts unchanged", lambda: check(before_logs == [1, 1]))
            for reason in ("x", "\u00e9" * 1000, "    trimmed synthetic reason    "):
                case("bounded valid reason length " + str(len(reason.strip())) + " reveals normally", lambda reason=reason: check(call(reveal(reason))["message"] == RAW_BODY))
            case("stored reasons are trimmed and bounded by Unicode character count", lambda: truth("select count(*)=4 and bool_and(reason=btrim(reason) and char_length(reason) between 1 and 1000) from public.admin_sensitive_access_logs;"))
            for uid, sid in ((UID, SID), (OTHER, OTHERSID)):
                case("raw body direct-column ACL denies " + uid[-1], lambda uid=uid, sid=sid: denied(f"select raw_body from public.raw_payment_sms where id='{SMS}'", uid=uid, sid=sid))
            for table in ("admin_sensitive_access_logs", "audit_logs"):
                # Supabase grants may permit the statement while RLS selects no
                # writable rows. Prove unchanged records rather than requiring
                # an ACL error when the actual protection is row filtering.
                before_count = int(sql("select count(*) from public." + table).stdout)
                removed = call("with removed as(delete from public." + table + " returning id) select to_jsonb(count(*)) from removed")
                case("authenticated cannot erase " + table, lambda table=table, before_count=before_count, removed=removed:
                     check(removed == 0 and int(sql("select count(*) from public." + table).stdout) == before_count))
            for field, mutate, restore in (
                ("grant", f"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='{UID}'", f"update public.admin_user_roles set revoked_at=null where user_id='{UID}'"),
                ("email approval", f"update collect_admin_access.email_approvals set revoked_at=clock_timestamp() where user_id='{UID}'", f"update collect_admin_access.email_approvals set revoked_at=null where user_id='{UID}'"),
                ("Auth session", f"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='{SID}'", f"update auth.sessions set not_after=clock_timestamp()+interval '1 hour' where id='{SID}'"),
                ("permission", f"delete from public.admin_role_permissions where role_id='{ROLE}' and permission_name='sms.raw.reveal'", f"insert into public.admin_role_permissions(role_id,permission_name) values('{ROLE}','sms.raw.reveal')"),
            ):
                reader, writer = U.Session(db, field + "-read"), U.Session(db, field + "-revoke")
                sessions.extend((reader, writer))
                for order in ("read_first", "revoke_first"):
                    if order == "read_first":
                        reader.write("begin;" + U.auth() + reveal("Synthetic concurrency review") + ";select 'READ_HELD';")
                        reader.read("READ_HELD")
                        writer.write("begin;" + mutate + ";select 'REVOKE_DONE';")
                        waiter = "update" if field != "permission" else "delete"
                    else:
                        writer.write("begin;" + mutate + ";select 'REVOKE_HELD';")
                        writer.read("REVOKE_HELD")
                        reader.write("begin;" + U.auth() + "do $$begin begin " + reveal("Synthetic concurrency review").replace("select ", "perform ", 1) + ";perform set_config('collect.sensitive_probe','allowed',true);exception when sqlstate '42501' then perform set_config('collect.sensitive_probe',sqlstate,true);end;end$$;select 'READ_RESULT:'||current_setting('collect.sensitive_probe');select 'READ_DONE';")
                        waiter = "admin_reveal_raw_sms"
                    end = time.monotonic() + 8
                    blocked = False
                    while time.monotonic() < end:
                        blocked = sql("select exists(select 1 from pg_stat_activity where datname=" + R.literal(db) + " and wait_event_type='Lock' and query ilike " + R.literal("%" + waiter + "%") + ");").stdout.strip() == "t"
                        if blocked:
                            break
                        time.sleep(.03)
                    check(blocked)
                    if order == "read_first":
                        reader.write("commit;select 'READ_COMMITTED';")
                        reader.read("READ_COMMITTED")
                        writer.read("REVOKE_DONE")
                        writer.write("commit;select 'REVOKE_COMMITTED';")
                        writer.read("REVOKE_COMMITTED")
                    else:
                        writer.write("commit;select 'REVOKE_COMMITTED';")
                        writer.read("REVOKE_COMMITTED")
                        check("READ_RESULT:42501" in reader.read("READ_DONE"))
                        reader.write("rollback;select 'READ_CLOSED';")
                        reader.read("READ_CLOSED")
                    evidence["actual_blocking_races"] += 1
                    case(field + " " + order + " has observed PostgreSQL authority lock and correct order", lambda: True)
                    sql(restore + ";")
                reader.close()
                writer.close()
                sessions.remove(reader)
                sessions.remove(writer)
            case("all sensitive reads preserve seven financial/delivery row families", lambda: check(financial_before == U.fingerprint(db)))
            def seed_retry():
                sql(f"""delete from public.notification_events where id='{EVENT}';
                  delete from public.notification_device_tokens where id='{DEVICE}';
                  insert into public.notification_device_tokens(id,user_id,platform,provider,token,token_hash,
                    environment,registration_session_id,registration_session_created_at)
                  select '{DEVICE}','{OTHER}','android','fcm','synthetic-sensitive-retry-token',
                    encode(extensions.digest('synthetic-sensitive-retry-token','sha256'),'hex'),
                    'production','{OTHERSID}',created_at from auth.sessions where id='{OTHERSID}';
                  insert into public.notification_events(id,user_id,type,title,body)
                  values('{EVENT}','{OTHER}','group_update','Synthetic retry','Synthetic failure fixture; no provider delivery');
                  update public.notification_deliveries set status='failed',attempt_count=2,prior_attempt_count=3,
                    last_error_code='synthetic_failure' where event_id='{EVENT}';""")
                truth(f"select count(*)=1 and bool_and(status='failed') from public.notification_deliveries where event_id='{EVENT}';")

            retry = lambda reason: f"select public.admin_retry_notification('{EVENT}',{R.literal(reason) if reason is not None else 'null'})"
            seed_retry()
            for role in ("anon", "service_role"):
                case(role + " cannot trigger notification retry", lambda role=role: denied(retry("Synthetic reason"), role=role))
            case("ordinary approved member cannot trigger notification retry", lambda: denied(retry("Synthetic reason"), uid=OTHER, sid=OTHERSID))
            case("missing retry permission refuses operation", lambda: denied(retry("Synthetic reason"), mutation=f"delete from public.admin_role_permissions where role_id='{ROLE}' and permission_name='notifications.manage';"))
            for reason in (None, "", "   ", "\t\n\r", "x" * 1001, "\u00e9" * 1001):
                case("invalid retry reason " + repr(reason)[:35] + " leaves delivery failed", lambda reason=reason: denied(retry(reason), "P0001", "Reason is required"))
            case("invalid retry attempts create no retry audit or queue mutation", lambda: truth(f"select not exists(select 1 from public.audit_logs where action='notification.delivery.retried') and (select status='failed' and attempt_count=2 and prior_attempt_count=3 from public.notification_deliveries where event_id='{EVENT}');"))
            for name, mutation in (
                ("expired recipient session", f"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='{OTHERSID}';"),
                ("disabled recipient device", f"update public.notification_device_tokens set enabled=false where id='{DEVICE}';"),
                ("banned recipient", f"update auth.users set banned_until=clock_timestamp()+interval '1 hour' where id='{OTHER}';"),
            ):
                case(name + " cannot be retried", lambda mutation=mutation: denied(retry("Synthetic reason"), "P0001", "No retryable failed deliveries", mutation=mutation))
            case("valid retry returns exact queued count acknowledgement", lambda: check(call(retry("  Synthetic retry review  ")) == {"ok": True, "status": "queued", "delivery_count": 1}))
            case("retry preserves cumulative attempts, clears lease and records current actor/reason", lambda: truth(f"""select
              (select status='queued' and attempt_count=0 and prior_attempt_count=5 and claim_token is null
                and claim_expires_at is null and provider_message_id is null and last_error_code is null
                from public.notification_deliveries where event_id='{EVENT}')
              and (select count(*)=1 from public.audit_logs where action='notification.delivery.retried'
                and actor_user_id='{UID}' and entity_id='{EVENT}' and metadata=jsonb_build_object('reason','Synthetic retry review','delivery_count',1));"""))
            case("queued retry is not blindly repeated", lambda: denied(retry("Synthetic retry review"), "P0001", "No retryable failed deliveries"))
            sql(f"delete from public.notification_events where id='{EVENT}';delete from public.notification_device_tokens where id='{DEVICE}';")
            case("retry fixture cleanup restores all seven financial/delivery row families", lambda: check(financial_before == U.fingerprint(db)))
            case("source remains exactly the reviewed email and security migrations", lambda: check(all(path.read_bytes() == body for path, body in sources.items())))
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
        U.SQL_LOG = None
        U.CONCURRENCY_LOG = None
        evidence["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()


if __name__ == "__main__":
    main()
