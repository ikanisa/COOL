#!/usr/bin/env python3
"""Actual public table/RLS reads after committed Admin authority revocation."""
import argparse
import datetime
import json
from pathlib import Path

import local_schema_uat as local
import staged_bundle_upgrade_uat as bundle

R, U, ROOT = local.R, local.U, local.ROOT
MIGRATION = ROOT / "supabase/migrations/20260930233000_sensitive_admin_authority.sql"
EMAIL_MIGRATION = ROOT / "supabase/migrations/20260930213000_operator_email_auth.sql"
UID, OTHER, SID, OTHERSID = U.UID, U.OTHER, U.SID, U.OTHERSID
ROLE = "99710000-0000-4000-8000-000000020001"
GROUP = "99710000-0000-4000-8000-000000030001"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--current-bundle", action="store_true",
                        help="Test RLS against all reviewed staged migrations")
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh release evidence directory required")
    report.mkdir(parents=True, mode=0o700)
    source = MIGRATION.read_bytes()
    email_source = EMAIL_MIGRATION.read_bytes()
    paths = ([ROOT / "supabase/migrations" / name for name in bundle.STAGES]
             if args.current_bundle else [EMAIL_MIGRATION, MIGRATION])
    sources = {path: path.read_bytes() for path in paths}
    evidence = dict(kind="actual_admin_public_table_rls_snapshot", status="running",
                    candidate_installed_in_shared_source=False, migration_sha256=R.sha(source),
                    email_migration_sha256=R.sha(email_source),
                    started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    cases=[], positive_controls=0, actual_blocking_races=0,
                    current_staged_bundle_tested=args.current_bundle,
                    migration_sources={path.name: R.sha(body) for path, body in sources.items()})
    (report / "migration.sql").write_bytes(source)
    (report / "email-migration.sql").write_bytes(email_source)
    (report / "runner.py").write_bytes(Path(__file__).read_bytes())
    (report / "local_schema_uat.py").write_bytes(Path(local.__file__).read_bytes())
    if args.current_bundle:
        (report / "bundle-runner.py").write_bytes(Path(bundle.__file__).read_bytes())
        for path, body in sources.items():
            (report / path.name).write_bytes(body)
    U.SQL_LOG = report / "queries.log"
    U.CONCURRENCY_LOG = report / "concurrency.log"
    sessions = []

    def save():
        R.save(report / "result.json", evidence)

    def check(value):
        assert value, value
        return True

    save()
    try:
        with local.isolated(report, evidence, count=154, latest="20260930230000") as db:
            if args.current_bundle:
                bundle.seed_schema_clone_permission_catalog(db, report, evidence)
            def sql(body):
                return U.psql(db, body).stdout

            applied = U.psql(db, "\n".join(body.decode() for body in sources.values()), False)
            (report / "apply.stdout.log").write_text(applied.stdout)
            (report / "apply.stderr.log").write_text(applied.stderr)
            check(applied.returncode == 0)
            sql(f"""insert into public.admin_roles(id,name,description) values('{ROLE}','platform_owner','Synthetic RLS owner');
              insert into public.admin_permissions(name,description) values('collections.read','Synthetic'),('users.read','Synthetic');
              insert into public.admin_role_permissions(role_id,permission_name) select '{ROLE}',name from public.admin_permissions;
              insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
              values('{UID}','authenticated','authenticated','250788971001',now(),'{{}}','{{}}'),
                    ('{OTHER}','authenticated','authenticated','250788971002',now(),'{{}}','{{}}');
              insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
              values('{UID}','+250788971001',clock_timestamp()-interval '2 minutes','Synthetic'),
                    ('{OTHER}','+250788971002',clock_timestamp()-interval '2 minutes','Synthetic');
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
              values('{UID}','{ROLE}','Synthetic',clock_timestamp()-interval '1 minute'),
                    ('{OTHER}','{ROLE}','Synthetic',clock_timestamp()-interval '1 minute');
              insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
              values('{SID}','{UID}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
                    ('{OTHERSID}','{OTHER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
              insert into public.collections(id,slug,creator_user_id,title,category)
              values('{GROUP}','synthetic-rls-private','{UID}','Synthetic private group','Family / friends');""")
            query = f"select coalesce(jsonb_agg(id),'[]'::jsonb) from public.collections where id='{GROUP}'"
            def revoked_reads(cohort, approval_table):
              for kind, revoke, restore in (
                ("role", f"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='{OTHER}'", f"update public.admin_user_roles set revoked_at=null where user_id='{OTHER}'"),
                ("Auth session", f"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='{OTHERSID}'", f"update auth.sessions set not_after=clock_timestamp()+interval '1 hour' where id='{OTHERSID}'"),
                ("approval", f"update collect_admin_access.{approval_table} set revoked_at=clock_timestamp() where user_id='{OTHER}'", f"update collect_admin_access.{approval_table} set revoked_at=null where user_id='{OTHER}'"),
            ):
                positive = json.loads(sql("begin;" + U.auth(OTHER, OTHERSID) + query + ";commit;").strip().splitlines()[-1])
                check(positive == [GROUP])
                evidence["positive_controls"] += 1
                reader = U.Session(db, cohort + " " + kind)
                sessions.append(reader)
                reader.write("begin isolation level repeatable read;select count(*) from public.collections;select 'SNAPSHOT_READY';")
                reader.read("SNAPSHOT_READY")
                sql(revoke + ";")
                denied = json.loads(sql("begin;" + U.auth(OTHER, OTHERSID) + query + ";commit;").strip().splitlines()[-1])
                check(denied == [])
                evidence["cases"].append(dict(name=cohort + " " + kind + " committed revoke denies fresh Read Committed RLS read", status="pass"))
                reader.write(U.auth(OTHER, OTHERSID) + f"""do $$declare result jsonb;begin begin
                  {query} into result;
                  perform set_config('collect.rls_probe',case when jsonb_array_length(result)>0 then 'allowed' else 'denied' end,true);
                  exception when sqlstate '40001' or sqlstate '42501' then
                  perform set_config('collect.rls_probe',sqlstate,true);end;end$$;
                  select 'RLS_RESULT:'||current_setting('collect.rls_probe');select 'RLS_DONE';""")
                lines = reader.read("RLS_DONE")
                result = next(line.removeprefix("RLS_RESULT:") for line in lines if line.startswith("RLS_RESULT:"))
                evidence["cases"].append(dict(name=cohort + " " + kind + " committed revoke precedes established-snapshot RLS read",
                                              observed=result, status="fail" if result == "allowed" else "pass"))
                save()
                reader.write("rollback;select 'CLOSED';")
                reader.read("CLOSED")
                reader.close()
                sessions.remove(reader)
                sql(restore + ";")
                print(cohort + " " + kind + "=" + result, flush=True)
            revoked_reads("legacy transition", "whatsapp_approvals")
            sql(f"""update auth.users set email=case when id='{UID}' then 'synthetic-one@collect.example' else 'synthetic-two@collect.example' end,
              email_confirmed_at=clock_timestamp() where id in ('{UID}','{OTHER}');
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
              select id,email,clock_timestamp()-interval '2 minutes','Synthetic email approval' from auth.users where id in ('{UID}','{OTHER}');""")
            revoked_reads("email transition", "email_approvals")
            sql("update collect_admin_access.operator_auth_policy set mode='email',revision=revision+1 where id;")
            revoked_reads("email cutover", "email_approvals")
            sql(f"delete from collect_admin_access.email_approvals where user_id='{OTHER}';")
            denied = json.loads(sql("begin;" + U.auth(OTHER, OTHERSID) + query + ";commit;").strip().splitlines()[-1])
            check(denied == [])
            evidence["cases"].append(dict(name="legacy-only identity denied after email cutover", status="pass"))
            check(MIGRATION.read_bytes() == source)
            check(EMAIL_MIGRATION.read_bytes() == email_source)
            check(all(path.read_bytes() == body for path, body in sources.items()))
            evidence["source_unchanged"] = True
        evidence["status"] = "failed" if any(x['status'] == 'fail' for x in evidence['cases']) else "pass"
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
    if evidence["status"] != "pass":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
