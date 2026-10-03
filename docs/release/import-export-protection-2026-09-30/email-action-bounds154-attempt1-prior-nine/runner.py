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
            for path, body in sources.items():
                result = U.psql(db, body.decode(), False)
                (report / (path.stem + ".stderr.log")).write_text(result.stderr)
                if result.returncode:
                    raise RuntimeError("Staged prerequisite failed: " + path.name)
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
            for name, (prefix, operation, state, message, ack) in operations.items():
                def probe(reason, uid=UID, sid=SID, role="authenticated", extra=""):
                    auth = U.auth(uid, sid) if role == "authenticated" else "set local role " + role + ";"
                    value = "null" if reason is None else R.literal(reason)
                    return U.psql(db, "begin;" + prefix + extra + auth + "select " + operation(value) + ";rollback;", False)

                for reason in ("12345678", "x" * 500, "  Synthetic accountable reason  "):
                    result = probe(reason)
                    observed = json.loads(result.stdout.strip().splitlines()[-1]) if not result.returncode else None
                    record(name + " valid reason returns exact current ACK " + str(len(reason.strip())),
                           result.returncode == 0 and observed == ack, dict(ack=observed, exit_code=result.returncode))
                for index, reason in enumerate((None, "", " " * 8, "\t" * 8, "\n" * 8, "\r\n\t" * 3, "x" * 501)):
                    result = probe(reason)
                    record(name + " invalid reason boundary " + str(index),
                           bool(result.returncode and state + ":" in result.stderr and message in result.stderr),
                           dict(exit_code=result.returncode, intended_error_observed=message in result.stderr,
                                returned_ack=bool(not result.returncode)))
                for role in ("anon", "service_role"):
                    result = probe("Synthetic accountable reason", role=role)
                    record(name + " denies " + role, bool(result.returncode and "42501:" in result.stderr), dict(exit_code=result.returncode))
                result = probe("Synthetic accountable reason", uid=OTHER, sid=OTHERSID)
                record(name + " denies ordinary unapproved member", bool(result.returncode and "42501:" in result.stderr), dict(exit_code=result.returncode))
                result = probe("Synthetic accountable reason", extra=f"delete from public.admin_role_permissions where role_id='{ROLE}' and permission_name='admin_users.manage';")
                record(name + " denies missing manage permission", bool(result.returncode and "42501:" in result.stderr), dict(exit_code=result.returncode))
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
