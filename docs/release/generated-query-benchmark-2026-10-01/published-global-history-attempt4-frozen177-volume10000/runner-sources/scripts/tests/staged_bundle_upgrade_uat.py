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
          "20260930235500_operator_reason_whitespace.sql", "20260930235600_runtime_control_reason_whitespace.sql",
          "20260930235700_sensitive_reason_whitespace.sql", "20261001000100_operational_exception_inbox.sql",
          "20261001000200_admin_gateway_reads.sql", "20261001000300_admin_exception_reads.sql",
          "20261001000400_receipt_supervisor_identity.sql", "20261001000519_safe_unstarted_receipt_cancel.sql",
          "20261001001457_joined_operator_audit.sql", "20261001003338_unattended_operating_policy.sql",
          "20261001004651_receipt_cancel_audit_actor.sql",
          "20261001095000_member_history_global_keyset_indexes.sql",
          "20261001100000_receipt_financial_policy.sql"]
ROLE = "99640000-0000-4000-8000-000000030001"
PRIVATE_TABLES = {
    "collect_admin_access.email_approvals", "collect_admin_access.operator_auth_policy",
    "collect_gateway.admin_requests", "collect_gateway.devices", "collect_gateway.dispatch_arms",
    "collect_gateway.health_observations", "collect_gateway.requests", "collect_gateway.segment_callbacks",
    "collect_hybrid.receipt_business_event_heads", "collect_hybrid.receipt_business_events",
    "collect_hybrid.receipt_monitor_consumers", "collect_hybrid.receipt_monitor_acknowledgements",
    "collect_hybrid.receipt_monitor_observed_events",
    "collect_ops.exceptions", "collect_ops.exception_observations", "collect_ops.exception_actions",
    "collect_supervisor.identities", "collect_supervisor.owner_requests", "collect_supervisor.requests",
    "collect_receipt_actions.revisions", "collect_receipt_actions.cancellations",
    "collect_operator_audit.shadow_events",
    "collect_automation.operating_policy", "collect_automation.policy_requests",
    "collect_receipt_policy.decisions", "collect_receipt_policy.content_evidence",
}
PERMISSION_CATALOG_SOURCE = ROOT / "supabase/migrations/20260815062536_complete_admin_operations_control_plane.sql"
PERMISSION_CATALOG_SHA = "33116a8b778fe7fefdb22e41885796c250c79e6718299a4eae605e9f5b1804f5"
PAYMENT_PERMISSION_SOURCE = ROOT / "supabase/migrations/202605230008_admin_panel.sql"
PAYMENT_PERMISSION_SHA = "cd579d24bc9b092fff80476533e1242bf99439e281931485f6504444a31af783"
SHADOW_LEASE_SOURCE = ROOT / "supabase/migrations/20260930210000_shadow_supervisor_runs.sql"
SHADOW_LEASE_SHA = "cea3af48586bc2f26906e07fe14f001aa629354272c215ee0b9c6e6c980a1424"


def seed_schema_clone_permission_catalog(db, report, evidence):
    """Restore migration-seeded reference rows omitted by a schema-only clone.

    This deliberately grants no actor role or permission and reads no source
    rows. It executes the exact two-row notification catalog insert and the
    original payments.read row from pinned baseline migrations before newer
    navigation foreign keys are installed.
    """
    body = PERMISSION_CATALOG_SOURCE.read_bytes()
    if R.sha(body) != PERMISSION_CATALOG_SHA:
        raise RuntimeError("Reviewed baseline permission catalog source changed")
    anchor = "insert into public.admin_permissions (name, description)\nvalues\n"
    end = "on conflict (name) do update set description = excluded.description;"
    text = body.decode()
    if text.count(anchor) != 1 or text.count(end) != 1:
        raise RuntimeError("Exact baseline permission seed boundaries changed")
    seed = text[text.index(anchor):text.index(end) + len(end)]
    expected = """insert into public.admin_permissions (name, description)
values
  ('notifications.read', 'Read notification event and delivery health'),
  ('notifications.manage', 'Retry failed notification deliveries with a reason')
on conflict (name) do update set description = excluded.description;"""
    if seed != expected:
        raise RuntimeError("Reviewed baseline permission seed contents changed")
    (report / PERMISSION_CATALOG_SOURCE.name).write_bytes(body)
    (report / "schema-clone-reference-permission-seed.sql").write_text(seed)
    U.psql(db, seed)
    payment_body = PAYMENT_PERMISSION_SOURCE.read_bytes()
    payment_row = "  ('payments.read', 'Read payments'),"
    payment_text = payment_body.decode()
    if R.sha(payment_body) != PAYMENT_PERMISSION_SHA or payment_text.count(payment_row) != 1:
        raise RuntimeError("Reviewed original payment permission source changed")
    permission_insert = payment_text.index("insert into admin_permissions (name, description)\nvalues\n")
    permission_end = payment_text.index("on conflict (name) do update set description = excluded.description;", permission_insert)
    if payment_row not in payment_text[permission_insert:permission_end]:
        raise RuntimeError("Original payments.read row is not in its permission catalog insert")
    payment_seed = "insert into public.admin_permissions(name,description) values\n" + payment_row.rstrip(",") + "\non conflict(name) do update set description=excluded.description;"
    (report / PAYMENT_PERMISSION_SOURCE.name).write_bytes(payment_body)
    (report / "schema-clone-reference-payment-seed.sql").write_text(payment_seed)
    U.psql(db, payment_seed)
    evidence["schema_clone_reference_catalog"] = dict(
        source=PERMISSION_CATALOG_SOURCE.name, source_sha256=R.sha(body),
        seed_sha256=R.sha(seed.encode()), rows=["notifications.read", "notifications.manage", "payments.read"],
        payment_source=PAYMENT_PERMISSION_SOURCE.name, payment_source_sha256=R.sha(payment_body),
        payment_seed_sha256=R.sha(payment_seed.encode()),
        source_rows_copied=False, actor_authority_granted=False)
    if PERMISSION_CATALOG_SOURCE.read_bytes() != body or PAYMENT_PERMISSION_SOURCE.read_bytes() != payment_body:
        raise RuntimeError("Baseline permission catalog source drifted during seeding")


def seed_baseline_shadow_lease(db, report, evidence):
    """Restore the exact installed migration's empty control singleton."""
    body = SHADOW_LEASE_SOURCE.read_bytes()
    seed = "insert into collect_security.shadow_supervisor_lease(id) values(true);"
    if R.sha(body) != SHADOW_LEASE_SHA or body.decode().count(seed) != 1:
        raise RuntimeError("Reviewed baseline shadow lease initializer changed")
    installed = U.psql("postgres", "select statements[1] from supabase_migrations.schema_migrations where version='20260930210000';").stdout
    if body.decode().rstrip() != installed.rstrip():
        raise RuntimeError("Baseline shadow lease source differs from installed migration")
    (report / SHADOW_LEASE_SOURCE.name).write_bytes(body)
    (report / "schema-clone-shadow-lease-seed.sql").write_text(seed + "\n")
    U.psql(db, seed)
    evidence["schema_clone_shadow_lease"] = dict(source=SHADOW_LEASE_SOURCE.name,
        source_sha256=R.sha(body), installed_normalized_parity=True, seed_sha256=R.sha(seed.encode()),
        source_rows_copied=False, actor_authority_granted=False, synthetic_control_singleton=True)
    if SHADOW_LEASE_SOURCE.read_bytes() != body:
        raise RuntimeError("Baseline shadow lease source drifted during seeding")


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
        # Inventory before the expensive clone. A peer source arrival must be
        # reviewed explicitly, and its actual name belongs in a failed packet.
        R.guard(154, "20260930230000")
        installed = set(json.loads(U.psql("postgres", "select to_jsonb(array_agg(version order by version)) from supabase_migrations.schema_migrations;").stdout))
        def actual_staged_names():
            return {path.name for path in (ROOT / "supabase/migrations").glob("*.sql")
                    if path.name.split("_", 1)[0] not in installed}
        def complete_manifest():
            actual = actual_staged_names()
            if actual != set(STAGES):
                raise RuntimeError("Unreviewed or missing staged source: " + json.dumps(dict(
                    unreviewed=sorted(actual-set(STAGES)), missing=sorted(set(STAGES)-actual))))
            return dict(staged_count=len(actual), every_uninstalled_source_reviewed=True)
        case("reviewed stage manifest covers every current uninstalled source version", complete_manifest)
        with local.isolated(report, evidence, count=154, latest="20260930230000") as db:
            sql = lambda body: U.psql(db, body).stdout.strip()
            case("schema-only clone restores exact baseline notification/payment permission catalog without actor grants",
                 lambda: seed_schema_clone_permission_catalog(db, report, evidence))
            data.seed(db)
            sender = data.scalar(db, f"select to_jsonb(public._authenticated_momo_phone_hash('{data.ACTOR}'));")
            intent = lambda amount: U.call(db, f"select to_jsonb(t) from public.create_contribution_intent('{data.GROUP}',{amount},'{sender}')t", data.ACTOR, data.SESSION)
            first, second = intent(137), intent(271)
            case("nonempty pending requests are created through actual member RPC", lambda: check(first["id"] != second["id"] and first["status"] == second["status"] == "pending"))
            protected = data.financial(db)
            request_before = json.loads(sql(f"select jsonb_agg(to_jsonb(t) order by id) from public.payment_intents t where contributor_user_id='{data.ACTOR}';"))
            for path, body in bodies.items():
                attribution = path.name == "20261001004651_receipt_cancel_audit_actor.sql"
                routine = "'public.admin_cancel_unstarted_receipt_v1(uuid,uuid,bigint,text)'::regprocedure"
                if attribution:
                    definition_before = U.psql(db, "select pg_get_functiondef(" + routine + ");").stdout
                    attributes_before = sql("select jsonb_build_object('oid',oid,'volatility',provolatile,"
                        "'security_definer',prosecdef,'configuration',proconfig,'acl',proacl)"
                        "from pg_proc where oid=" + routine + ";")
                    (report / "before-cancellation-audit-function.sql").write_text(definition_before)
                result = U.psql(db, body.decode(), False)
                (report / (path.stem + ".stdout.log")).write_text(result.stdout)
                (report / (path.stem + ".stderr.log")).write_text(result.stderr)
                case(path.name + " applies as ordinary clone owner", lambda result=result: check(result.returncode == 0))
                case(path.name + " preserves financial rows and exact pending requests", lambda: check(
                    protected == data.financial(db) and request_before == json.loads(sql(f"select jsonb_agg(to_jsonb(t) order by id) from public.payment_intents t where contributor_user_id='{data.ACTOR}';"))))
                if attribution:
                    definition_after = U.psql(db, "select pg_get_functiondef(" + routine + ");").stdout
                    (report / "after-cancellation-audit-function.sql").write_text(definition_after)
                    needle = "'reason_code',p_reason_code,'financial_action',false,'send_action',false),null);"
                    case("combined cancellation changes only the public audit actor argument", lambda: check(
                        definition_before.count(needle) == 1
                        and definition_after == definition_before.replace(needle, needle.replace(',null);', ',auth.uid());'))))
                    case("combined cancellation retains its exact OID, authority attributes, configuration and grants", lambda: check(
                        attributes_before == sql("select jsonb_build_object('oid',oid,'volatility',provolatile,"
                            "'security_definer',prosecdef,'configuration',proconfig,'acl',proacl)"
                            "from pg_proc where oid=" + routine + ";")))
            sql(f"""insert into public.admin_roles(id,name,description) values('{ROLE}','platform_owner','Synthetic staged owner');
              insert into public.admin_permissions(name,description) select name,'Synthetic' from unnest(array[
                'payments.read','collections.read','notifications.read','notifications.manage','system_health.read',
                'audit.read','admin_users.read','admin_users.manage','payments.allocate','sms.metadata.read',
                'sms.raw.reveal','users.read','overview.read','settings.read','settings.manage','collections.moderate'])name
                on conflict(name) do nothing;
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
            case("combined receipt content policy preserves non-dispatch member-only v2 scope", lambda: check(
                (receipt := call("select public.admin_receipt_content_policy_v1()"))["contract_version"] == 1
                and receipt["scope"] == "rw_receipt_content_policy"
                and receipt["content_policy_version"] == 2
                and receipt["collection_configuration_version"] == 1
                and receipt["default_language"] == "rw"
                and receipt["explicit_languages"] == ["rw", "en", "fr"]
                and receipt["balance_disclosure"] == "member_only"
                and receipt["dispatch_authority_created"] is False
                and receipt["provider_settlement_verified"] is False
                and receipt["historical_auto_catchup"] is False
                and receipt["correction_or_resend"] is False))
            case("combined receipt Overview query executes against actual staged columns", lambda: check(
                call("select public.admin_receipt_overview_v1()")['contract_version'] == 1))
            case("combined transaction list executes without receipt/provider data", lambda: check(
                call("select public.admin_list_collect_transactions()") == {"rows": [], "total": 0}))
            case("combined Gateway read returns an authorized redacted empty page", lambda: check(
                (page := call("select public.admin_list_gateway_devices_v1()"))["contract_version"] == 1
                and page["scope"] == "platform_global" and page["rows"] == []
                and page["total"] == 0 and page["next_cursor"] is None))
            case("combined Gateway absent owner request remains unknown", lambda: check(
                (receipt := call(f"select public.admin_get_gateway_owner_request_v1('{data.MISSING}')"))["outcome"] == "unknown"
                and receipt["request_id"] == data.MISSING and receipt["identity"] is None
                and receipt["receipt"] is None))
            case("combined exception inbox reads without fabricated source completeness", lambda: check(
                (page := call("select public.admin_list_operational_exceptions_v1()"))["contract_version"] == 1
                and page["rows"] == [] and page["source_scan_complete"] is False
                and page["escalation_delivery_verified"] is False))
            case("combined exception v2 reads return bounded fresh redacted empty scope", lambda: check(
                (page := call("select public.admin_list_operational_exceptions_v2()"))["contract_version"] == 2
                and page["scope"] == "platform_global" and page["rows"] == []
                and page["next_cursor"] is None and page["checked_at"]
                and page["sample_valid_until"] and page["source_scan_complete"] is False
                and page["escalation_delivery_verified"] is False))
            case("combined exception owner request remains unrecorded without fabricated action", lambda: check(
                (receipt := call(f"select public.admin_get_operational_exception_action_v2('{data.MISSING}')"))["contract_version"] == 2
                and receipt["status"] == "not_recorded" and receipt["request_id"] == data.MISSING
                and receipt["receipt"] is None))
            case("combined shadow supervisor request remains unrecorded without fabricated identity", lambda: check(
                (receipt := call(f"select public.admin_get_receipt_supervisor_owner_request_v1('{data.MISSING}')"))["contract_version"] == 1
                and receipt["status"] == "not_recorded" and receipt["request_id"] == data.MISSING
                and receipt["receipt"] is None))
            case("combined absent unstarted receipt remains unavailable without fabricated cancellation", lambda: check(
                (receipt := call(f"select public.admin_inspect_unstarted_receipt_v1('{data.MISSING}')"))["contract_version"] == 1
                and receipt["scope"] == "rw_receipt_manual_cancel" and receipt["outbox_id"] == data.MISSING
                and receipt["status"] == "unavailable" and receipt["receipt"] is None))
            case("combined receipt cancellation owner request remains unrecorded", lambda: check(
                (receipt := call(f"select public.admin_get_unstarted_receipt_action_v1('{data.MISSING}')"))["contract_version"] == 1
                and receipt["scope"] == "rw_receipt_manual_cancel" and receipt["request_id"] == data.MISSING
                and receipt["status"] == "not_recorded" and receipt["receipt"] is None))
            for kind in ("shadow_run", "gateway_device", "exception", "supervisor_identity", "receipt"):
                case("combined absent joined operator audit " + kind + " is unavailable and redacted", lambda kind=kind: check(
                    (receipt := call(f"select public.admin_get_operator_entity_audit_v1('{kind}','{data.MISSING}')"))["contract_version"] == 1
                    and receipt["scope"] == "rw_operator_entity_audit" and receipt["entity_kind"] == kind
                    and receipt["entity_id"] == data.MISSING and receipt["status"] == "unavailable"
                    and receipt["rows"] == [] and receipt["next_cursor"] is None
                    and receipt["history_complete"] is False and receipt["historical_shadow_audit_backfilled"] is False
                    and receipt["financial_action"] is False and receipt["send_action"] is False))
            case("schema-only shadow control singleton restores its exact installed baseline initializer", lambda:
                 seed_baseline_shadow_lease(db, report, evidence))
            shadow = call("select public.begin_collect_shadow_run_v1('99640000-0000-4000-8000-000000099001')")
            case("real shadow start survives the joined audit trigger", lambda: check(
                shadow["outcome"] == "started" and shadow["run"]["status"] == "running"))
            run_id, fence = shadow["run"]["run_id"], shadow["run"]["fence_version"]
            sample = call(f"select public.sample_collect_shadow_run_v1('{run_id}',{fence})")
            case("real shadow sampling survives the joined audit trigger", lambda: check(
                sample["outcome"] == "sampled" and sample["replayed"] is False))
            finished = call(f"select public.finish_collect_shadow_run_v1('{run_id}',{fence})")
            case("real shadow completion survives the joined audit trigger", lambda: check(
                finished["outcome"] == "completed"))
            page = call(f"select public.admin_get_operator_entity_audit_v1('shadow_run','{run_id}')")
            case("joined operator audit retains all three actual lifecycle events with bounded redacted rows", lambda: check(
                page["status"] == "available" and page["history_complete"] is False
                and [row["action"] for row in page["rows"]] == ["shadow.completed", "shadow.sampled", "shadow.started"]
                and all(row["actor_id"] == data.ACTOR and row["request_id"] == shadow["run"]["request_id"]
                    and set(row) == {"event_id","source","action","recorded_at","actor_id","request_id","revision","fence_version","reason_code"}
                    for row in page["rows"])))
            policy = call("select public.admin_get_unattended_operating_policy_v1()")
            case("combined unattended preparation defaults remain paused without dispatch or fabricated limits", lambda: check(
                policy["revision"] == 1 and policy["configured_mode"] == policy["effective_mode"] == "Paused"
                and policy["emergency_stop"] is True and policy["limits"]["enforcement"] is False
                and policy["execution"]["unattended_dispatch_available"] is False
                and policy["schedule"]["configuration_available"] is False
                and all(value is None for value in policy["approvals"].values())))
            request_id = "99640000-0000-4000-8000-000000099002"
            configure = f"select public.admin_configure_unattended_operating_policy_v1('{request_id}',1,'Shadow',false,'operator_clear_future_stop')"
            configured = call(configure)
            case("actual combined preparation policy change records an exact non-dispatch acknowledgement", lambda: check(
                configured["request_id"] == request_id and configured["policy_id"] == policy["policy_id"]
                and configured["expected_revision"] == 1 and configured["revision"] == 2
                and configured["changed"] is True and configured["mode_before"] == "Paused"
                and configured["mode_after"] == "Shadow" and configured["emergency_stop_after"] is False
                and all(configured[k] is False for k in ("unattended_dispatch_available", "financial_action", "send_action",
                    "approval_granted", "schedule_changed", "assisted_dispatch_changed", "signed_shadow_observation_changed", "carrier_work_changed"))))
            policy_audits = json.loads(sql("select jsonb_agg(jsonb_build_object('actor',actor_user_id,'entity_id',entity_id,'metadata',metadata)) "
                "from public.audit_logs where action='automation.operating_policy.configured' and metadata->>'request_id'=" + R.literal(request_id)))
            case("combined preparation policy stores the exact current actor and request-bound audit", lambda: check(
                len(policy_audits) == 1 and policy_audits[0]["actor"] == data.ACTOR
                and policy_audits[0]["entity_id"] == policy["policy_id"]
                and policy_audits[0]["metadata"]["request_id"] == request_id
                and policy_audits[0]["metadata"]["expected_revision"] == 1
                and policy_audits[0]["metadata"]["revision"] == 2
                and all(policy_audits[0]["metadata"][k] is False for k in ("financial_action","send_action","approval_granted","schedule_changed"))))
            case("combined preparation policy request replays the exact durable acknowledgement", lambda: check(call(configure) == configured))
            case("combined preparation policy request recovery reads the exact recorded acknowledgement", lambda: check(
                (read := call(f"select public.admin_get_unattended_policy_request_v1('{request_id}')"))["status"] == "recorded"
                and read["request_id"] == request_id and read["receipt"] == configured))
            for mode in ("Live-limited", "Live"):
                case("combined preparation refuses unavailable " + mode + " authority", lambda mode=mode: U.expected_error(db,
                    f"select public.admin_configure_unattended_operating_policy_v1('99640000-0000-4000-8000-000000099003',2,'{mode}',false,'operator_reviewed_configuration')",
                    "55000", "OPERATING_POLICY_LIVE_AUTHORITY_PENDING", data.ACTOR, data.SESSION))
            case("existing pending contribution replay survives full staged bundle", lambda: check(intent(137) == first))
            case("exact request guard still rejects oversized amount after all stages", lambda: U.expected_error(db,
                f"select public.create_contribution_intent('{data.GROUP}',9007199254740992,'{sender}')", "22023", "contribution_amount_not_exact", data.ACTOR, data.SESSION))
            private = json.loads(sql("""select jsonb_agg(jsonb_build_object('table',c.oid::regclass::text,'rls',c.relrowsecurity,
                'no_api_dml',not exists(select 1 from unnest(array['anon','authenticated','service_role'])r
                  where has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')))
                order by c.oid::regclass::text) from pg_class c where c.relkind='r' and
                (c.relnamespace in('collect_gateway'::regnamespace,'collect_ops'::regnamespace,'collect_supervisor'::regnamespace,'collect_receipt_actions'::regnamespace,'collect_operator_audit'::regnamespace,'collect_automation'::regnamespace,'collect_receipt_policy'::regnamespace) or c.oid in(
                  'collect_admin_access.email_approvals'::regclass,'collect_admin_access.operator_auth_policy'::regclass,
                  'collect_hybrid.receipt_business_event_heads'::regclass,'collect_hybrid.receipt_business_events'::regclass,
                  'collect_hybrid.receipt_monitor_consumers'::regclass,'collect_hybrid.receipt_monitor_acknowledgements'::regclass,
                  'collect_hybrid.receipt_monitor_observed_events'::regclass));"""))
            R.save(report / "new-private-table-acl.json", private)
            case(f"all{len(PRIVATE_TABLES)} exact private Gateway/email/receipt/exception/supervisor tables have RLS and no direct API DML", lambda: check(
                {row["table"] for row in private} == PRIVATE_TABLES
                and all(row["rls"] and row["no_api_dml"] for row in private)))
            case("current read smoke probes leave synthetic financial fingerprints unchanged", lambda: check(protected == data.financial(db)))
            case("all reviewed staged sources remain byte-identical", lambda: check(all(path.read_bytes() == body for path, body in bodies.items())))
            case("no unreviewed source migration appears during full staged integration", complete_manifest)
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
