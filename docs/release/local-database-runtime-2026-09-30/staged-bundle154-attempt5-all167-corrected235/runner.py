#!/usr/bin/env python3
"""Reviewed staged-source integration on a populated synthetic schema154 clone.

This is an upgrade subset, not a complete clean replay or a hosted migration registry.
All shared data and scheduling controls are read only; no network/provider work.
"""
import argparse
import datetime
import json
from pathlib import Path

import data_correctness_sql_uat as data
import local_schema_uat as local

R, U, ROOT = local.R, local.U, local.ROOT
STAGES = ["20260930211605_android_gateway_identity.sql", "20260930213000_operator_email_auth.sql",
          "20260930220527_operator_email_cutover_guard.sql", "20260930230100_receipt_backlog_events.sql",
          "20260930230200_admin_receipt_overview.sql", "20260930230300_admin_transaction_lifecycle.sql",
          "20260930230400_admin_investigation.sql", "20260930233000_sensitive_admin_authority.sql",
          "20260930234000_exact_request_amounts.sql", "20260930235000_exact_receipt_history_amounts.sql",
          "20260930235500_operator_reason_whitespace.sql", "20261001000100_operational_exception_inbox.sql",
          "20261001000200_admin_gateway_reads.sql"]
ROLE = "99640000-0000-4000-8000-000000030001"
PRIVATE_TABLES = {
    "collect_admin_access.email_approvals", "collect_admin_access.operator_auth_policy",
    "collect_gateway.admin_requests", "collect_gateway.devices", "collect_gateway.dispatch_arms",
    "collect_gateway.health_observations", "collect_gateway.requests", "collect_gateway.segment_callbacks",
    "collect_hybrid.receipt_business_event_heads", "collect_hybrid.receipt_business_events",
    "collect_hybrid.receipt_monitor_consumers", "collect_hybrid.receipt_monitor_acknowledgements",
    "collect_hybrid.receipt_monitor_observed_events",
    "collect_ops.exceptions", "collect_ops.exception_observations", "collect_ops.exception_actions",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = args.output.resolve()
    if report.exists() or not report.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh release evidence directory required")
    report.mkdir(parents=True, mode=0o700)
    bodies = {ROOT / "supabase/migrations" / name: (ROOT / "supabase/migrations" / name).read_bytes() for name in STAGES}
    evidence = dict(kind="populated_synthetic154_reviewed_staged_bundle", status="running", cases=[],
        started_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        source_migration_sha256={path.name: R.sha(body) for path, body in bodies.items()},
        shared_source_written=False, source_rows_copied=False, provider_called=False,
        clean_replay_tested=False, hosted_registry_tested=False, confirmed_status_fabricated=False,
        signed_jwt_tested=False, carrier_or_native_attestation_tested=False)
    for path, body in bodies.items():
        (report / path.name).write_bytes(body)
    (report / "runner.py").write_bytes(Path(__file__).read_bytes())
    (report / "data-fixture-runner.py").write_bytes(Path(data.__file__).read_bytes())
    U.SQL_LOG = report / "queries.log"
    U.CONCURRENCY_LOG = report / "concurrency.log"

    def save():
        R.save(report / "result.json", evidence)

    def check(value):
        assert value, value
        return True

    def case(name, action):
        try:
            result = action()
        except Exception as error:
            evidence["cases"].append(dict(name=name, status="failed", detail=str(error)))
            save()
            raise
        evidence["cases"].append(dict(name=name, status="pass", detail=result))
        save()
        print("PASS " + name, flush=True)

    save()
    try:
        with local.isolated(report, evidence, count=154, latest="20260930230000") as db:
            sql = lambda body: U.psql(db, body).stdout.strip()
            installed = set(json.loads(U.psql("postgres", "select to_jsonb(array_agg(version order by version)) from supabase_migrations.schema_migrations;").stdout))
            def actual_staged_names():
                return {path.name for path in (ROOT / "supabase/migrations").glob("*.sql")
                        if path.name.split("_", 1)[0] not in installed}
            case("reviewed stage manifest covers every current uninstalled source version", lambda: check(
                actual_staged_names() == set(STAGES)))
            data.seed(db)
            sender = data.scalar(db, f"select to_jsonb(public._authenticated_momo_phone_hash('{data.ACTOR}'));")
            intent = lambda amount: U.call(db, f"select to_jsonb(t) from public.create_contribution_intent('{data.GROUP}',{amount},'{sender}')t", data.ACTOR, data.SESSION)
            first, second = intent(137), intent(271)
            case("nonempty pending requests are created through actual member RPC", lambda: check(first["id"] != second["id"] and first["status"] == second["status"] == "pending"))
            protected = data.financial(db)
            request_before = json.loads(sql(f"select jsonb_agg(to_jsonb(t) order by id) from public.payment_intents t where contributor_user_id='{data.ACTOR}';"))
            for path, body in bodies.items():
                result = U.psql(db, body.decode(), False)
                (report / (path.stem + ".stdout.log")).write_text(result.stdout)
                (report / (path.stem + ".stderr.log")).write_text(result.stderr)
                case(path.name + " applies as ordinary clone owner", lambda result=result: check(result.returncode == 0))
                case(path.name + " preserves financial rows and exact pending requests", lambda: check(
                    protected == data.financial(db) and request_before == json.loads(sql(f"select jsonb_agg(to_jsonb(t) order by id) from public.payment_intents t where contributor_user_id='{data.ACTOR}';"))))
            sql(f"""insert into public.admin_roles(id,name,description) values('{ROLE}','platform_owner','Synthetic staged owner');
              insert into public.admin_permissions(name,description) select name,'Synthetic' from unnest(array[
                'payments.read','collections.read','notifications.read','notifications.manage','system_health.read',
                'audit.read','admin_users.read','admin_users.manage','payments.allocate','sms.metadata.read',
                'sms.raw.reveal','users.read','overview.read','settings.read','settings.manage','collections.moderate'])name;
              insert into public.admin_role_permissions(role_id,permission_name) select '{ROLE}',name from public.admin_permissions;
              update auth.users set email='synthetic-staged@collect.example',email_confirmed_at=clock_timestamp() where id='{data.ACTOR}';
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
              values('{data.ACTOR}','synthetic-staged@collect.example',clock_timestamp()-interval '2 minutes','Synthetic integration approval');
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
              values('{data.ACTOR}','{ROLE}','Synthetic integration grant',clock_timestamp()-interval '1 minute');""")
            call = lambda body: U.call(db, body, data.ACTOR, data.SESSION)
            case("combined email/security policy admits current masked operator approval read", lambda: check(
                (approval := call(f"select public.admin_get_operator_approval_v1('{data.ACTOR}')"))["provider"] == "email"
                and approval["admin_access"] is True and "synthetic-staged@collect.example" not in json.dumps(approval)))
            case("combined receipt Overview query executes against actual staged columns", lambda: check(
                call("select public.admin_receipt_overview_v1()")['contract_version'] == 1))
            case("combined transaction list executes without receipt/provider data", lambda: check(
                call("select public.admin_list_collect_transactions()") == {"rows": [], "total": 0}))
            case("existing pending contribution replay survives full staged bundle", lambda: check(intent(137) == first))
            case("exact request guard still rejects oversized amount after all stages", lambda: U.expected_error(db,
                f"select public.create_contribution_intent('{data.GROUP}',9007199254740992,'{sender}')", "22023", "contribution_amount_not_exact", data.ACTOR, data.SESSION))
            private = json.loads(sql("""select jsonb_agg(jsonb_build_object('table',c.oid::regclass::text,'rls',c.relrowsecurity,
                'no_api_dml',not exists(select 1 from unnest(array['anon','authenticated','service_role'])r
                  where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')))
                order by c.oid::regclass::text) from pg_class c where c.relkind='r' and
                (c.relnamespace in('collect_gateway'::regnamespace,'collect_ops'::regnamespace) or c.oid in(
                  'collect_admin_access.email_approvals'::regclass,'collect_admin_access.operator_auth_policy'::regclass,
                  'collect_hybrid.receipt_business_event_heads'::regclass,'collect_hybrid.receipt_business_events'::regclass,
                  'collect_hybrid.receipt_monitor_consumers'::regclass,'collect_hybrid.receipt_monitor_acknowledgements'::regclass,
                  'collect_hybrid.receipt_monitor_observed_events'::regclass));"""))
            R.save(report / "new-private-table-acl.json", private)
            case("all16 exact private Gateway/email/receipt/exception tables have RLS and no direct API DML", lambda: check(
                {row["table"] for row in private} == PRIVATE_TABLES
                and all(row["rls"] and row["no_api_dml"] for row in private)))
            case("current read smoke probes leave synthetic financial fingerprints unchanged", lambda: check(protected == data.financial(db)))
            case("all reviewed staged sources remain byte-identical", lambda: check(all(path.read_bytes() == body for path, body in bodies.items())))
            case("no unreviewed source migration appears during full staged integration", lambda: check(
                actual_staged_names() == set(STAGES)))
        evidence["status"] = "pass"
    except Exception as error:
        evidence.update(status="failed", failure=str(error))
        raise
    finally:
        U.SQL_LOG = None
        U.CONCURRENCY_LOG = None
        evidence["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        save()


if __name__ == "__main__":
    main()
