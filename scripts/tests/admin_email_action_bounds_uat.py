#!/usr/bin/env python3
"""Real staged email action RPCs, exact ACKs and nonblank reason boundaries.

Synthetic Auth/approval fixtures are local only. Every action probe rolls back;
the shared database is read-only and the disposable clone is removed.
"""
import argparse
import datetime
import json
from pathlib import Path

import local_schema_uat as local
import staged_bundle_upgrade_uat as bundle

R, U, ROOT = local.R, local.U, local.ROOT
UID, SID, OTHER, OTHERSID = U.UID, U.SID, U.OTHER, U.OTHERSID
ROLE = "99710000-0000-4000-8000-000000020001"
REASON_PATCH = "20260930235500_operator_reason_whitespace.sql"
WHITESPACE = [chr(code) for code in (9, 10, 11, 12, 13, 32, 133, 160, 5760,
    8192, 8193, 8194, 8195, 8196, 8197, 8198, 8199, 8200, 8201, 8202,
    8232, 8233, 8239, 8287, 12288, 65279)]
REASON_APIS = {
    "public.admin_set_operator_email_mode_v1(text)",
    "public.admin_revoke_email_operator_v1(uuid, text)",
    "public.admin_approve_email_operator_v1(uuid, text, text)",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh release evidence directory required")
    report.mkdir(parents=True, mode=0o700)
    paths = [ROOT / "supabase/migrations" / name for name in bundle.STAGES]
    sources = {path: path.read_bytes() for path in paths}
    evidence = dict(kind="actual_email_admin_action_reason_and_ack_bounds", status="running",
                    started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(), cases=[],
                    shared_source_written=False, provider_called=False, signed_jwt_tested=False,
                    migration_sources={path.name: R.sha(body) for path, body in sources.items()})
    for path, body in sources.items():
        (report / path.name).write_bytes(body)
    (report / "runner.py").write_bytes(Path(__file__).read_bytes())
    (report / "bundle-runner.py").write_bytes(Path(bundle.__file__).read_bytes())
    U.SQL_LOG = report / "queries.log"

    def save():
        R.save(report / "result.json", evidence)

    def record(name, ok, detail):
        evidence["cases"].append(dict(name=name, status="pass" if ok else "failed", detail=detail))
        save()
        print(("PASS " if ok else "FAIL ") + name, flush=True)

    save()
    try:
        with local.isolated(report, evidence, count=154, latest="20260930230000") as db:
            bundle.seed_schema_clone_permission_catalog(db, report, evidence)
            def catalog():
                names = ",".join(R.literal(name) for name in R.SCHEMAS)
                return json.loads(U.psql(db, f"""select jsonb_object_agg(identity,properties) from (
                  select n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')' identity,
                    jsonb_build_object('body',p.prosrc,'volatility',p.provolatile,'owner',p.proowner,
                      'acl',p.proacl,'definer',p.prosecdef,'config',p.proconfig,
                      'result',pg_get_function_result(p.oid),'arguments',pg_get_function_arguments(p.oid)) properties
                  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ({names})
                )s;""").stdout)
            for path, body in sources.items():
                before = catalog() if path.name == REASON_PATCH else None
                result = U.psql(db, body.decode(), False)
                (report / (path.stem + ".stderr.log")).write_text(result.stderr)
                if result.returncode:
                    raise RuntimeError("Staged prerequisite failed: " + path.name)
                if before is not None:
                    after = catalog()
                    R.save(report / "reason-catalog-before.json", before)
                    R.save(report / "reason-catalog-after.json", after)
                    changed = {name: sorted(key for key in before[name] if before[name][key] != after[name][key])
                               for name in before if before[name] != after.get(name)}
                    added = set(after) - set(before)
                    record("reason patch preserves identities/defaults/results/owners/ACLs and unrelated routine bodies",
                        set(before) <= set(after) and set(changed) == REASON_APIS
                        and all(keys == ['body'] for keys in changed.values())
                        and added == {"collect_admin_access.normalized_operator_reason(text)"},
                        dict(changed=changed, added=sorted(added)))
            U.psql(db, f"""insert into public.admin_roles(id,name,description)
                values('{ROLE}','platform_owner','Synthetic action fixture');
              insert into public.admin_permissions(name) values('admin_users.manage'),('admin_users.read'),('audit.read');
              insert into public.admin_role_permissions(role_id,permission_name) select '{ROLE}',name from public.admin_permissions;
              insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
              values('{UID}','authenticated','authenticated','synthetic-owner@collect.example',clock_timestamp(),'{{}}','{{}}'),
                    ('{OTHER}','authenticated','authenticated','synthetic-target@collect.example',clock_timestamp(),'{{}}','{{}}');
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
              values('{UID}','synthetic-owner@collect.example',clock_timestamp()-interval '2 minutes','Synthetic fixture approval');
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
              values('{UID}','{ROLE}','Synthetic fixture grant',clock_timestamp()-interval '1 minute');
              insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
              values('{SID}','{UID}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
                    ('{OTHERSID}','{OTHER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');""")
            target_approval = f"""insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
              values('{OTHER}','synthetic-target@collect.example',clock_timestamp()-interval '2 minutes','Synthetic target approval');"""
            operations = {
                "approve": ("", lambda reason: f"public.admin_approve_email_operator_v1('{OTHER}','synthetic-target@collect.example',{reason})", "22023", "operator_email_approval_invalid", dict(ok=True, status="approved", user_id=OTHER)),
                "revoke": (target_approval, lambda reason: f"public.admin_revoke_email_operator_v1('{OTHER}',{reason})", "22023", "email_revoke_invalid", dict(ok=True, status="revoked", user_id=OTHER)),
                "cutover": ("", lambda reason: f"public.admin_set_operator_email_mode_v1({reason})", "42501", "current_email_operator_required", dict(ok=True, mode="email", replay=False)),
            }
            protected = bundle.data.clone_snapshot(db)
            for name, (prefix, operation, state, message, ack) in operations.items():
                audit_action = {"approve": "admin.email.approved", "revoke": "admin.email.revoked",
                                "cutover": "admin.auth.email_cutover"}[name]
                def probe(reason, uid=UID, sid=SID, role="authenticated", extra="", details=False):
                    auth = U.auth(uid, sid) if role == "authenticated" else "set local role " + role + ";"
                    value = "null" if reason is None else R.literal(reason)
                    effects = f"""reset role;select jsonb_build_object(
                      'audit_reasons',(select coalesce(jsonb_agg(metadata->'reason'),'[]'::jsonb)
                        from public.audit_logs where actor_user_id='{UID}' and action={R.literal(audit_action)}),
                      'target_reason',(select reason from collect_admin_access.email_approvals where user_id='{OTHER}'),
                      'mode',(select mode from collect_admin_access.operator_auth_policy where id));""" if details else ""
                    return U.psql(db, "begin;" + prefix + extra + auth + "select " + operation(value) + ";" + effects + "rollback;", False)

                for reason in ("12345678", "x" * 500, "  Synthetic accountable reason  "):
                    result = probe(reason)
                    observed = json.loads(result.stdout.strip().splitlines()[-1]) if not result.returncode else None
                    record(name + " valid reason returns exact current ACK " + str(len(reason.strip())),
                           result.returncode == 0 and observed == ack, dict(ack=observed, exit_code=result.returncode))
                invalid = [None, "", " " * 8, "\t" * 8, "\n" * 8, "\r\n\t" * 3, "x" * 501]
                invalid += [char * 8 for char in WHITESPACE]
                invalid += ["\u00a0\t1234567\n\ufeff"]
                for index, reason in enumerate(invalid):
                    result = probe(reason)
                    record(name + " invalid reason boundary " + str(index),
                           bool(result.returncode and state + ":" in result.stderr and message in result.stderr),
                           dict(exit_code=result.returncode, intended_error_observed=message in result.stderr,
                                returned_ack=bool(not result.returncode)))
                for reason, normalized in (
                    ("\ufeff\u3000\tSynthetic accountable reason\n\u00a0", "Synthetic accountable reason"),
                    ("  Audit\tinterior\nreason  ", "Audit\tinterior\nreason"),
                ):
                    result = probe(reason, details=True)
                    output = result.stdout.strip().splitlines()
                    observed = json.loads(output[-2]) if not result.returncode else None
                    effects = json.loads(output[-1]) if not result.returncode else None
                    record(name + " records canonical bounded reason while preserving interior whitespace",
                        result.returncode == 0 and observed == ack and effects['audit_reasons'] == [normalized]
                        and (name != "approve" or effects['target_reason'] == normalized)
                        and (name != "revoke" or effects['target_reason'] == "Synthetic target approval")
                        and (name != "cutover" or effects['mode'] == 'email'),
                        dict(ack=observed, effects=effects))
                for role in ("anon", "service_role"):
                    result = probe("Synthetic accountable reason", role=role)
                    record(name + " denies " + role, bool(result.returncode and "42501:" in result.stderr), dict(exit_code=result.returncode))
                result = probe("Synthetic accountable reason", uid=OTHER, sid=OTHERSID)
                record(name + " denies ordinary unapproved member", bool(result.returncode and "42501:" in result.stderr), dict(exit_code=result.returncode))
                result = probe("Synthetic accountable reason", extra=f"delete from public.admin_role_permissions where role_id='{ROLE}' and permission_name='admin_users.manage';")
                record(name + " denies missing manage permission", bool(result.returncode and "42501:" in result.stderr), dict(exit_code=result.returncode))
            helper_private = U.psql(db, """select not exists(
              select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a
              left join pg_roles r on r.oid=a.grantee
              where p.oid='collect_admin_access.normalized_operator_reason(text)'::regprocedure
                and a.privilege_type='EXECUTE' and (a.grantee=0 or r.rolname in('anon','authenticated','service_role')));""").stdout.strip() == 't'
            record("reason helper remains unavailable to every API role and PUBLIC", helper_private, {})
            record("all action probes rollback every synthetic row/control/catalog effect",
                   protected == bundle.data.clone_snapshot(db), {})
            record("all staged inputs remain byte-identical", all(path.read_bytes() == body for path, body in sources.items()), {})
        evidence["status"] = "failed" if any(case["status"] != "pass" for case in evidence["cases"]) else "pass"
    except Exception as error:
        evidence.update(status="failed", failure=str(error))
        raise
    finally:
        U.SQL_LOG = None
        evidence["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()
    if evidence["status"] != "pass":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
