#!/usr/bin/env python3
"""Current-bundle cancellation through a real maker/checker posting pipeline.

Only synthetic review inputs, roster consent and identities are seeded in a
disposable schema/ACL clone. Production posting/enqueue/cancellation triggers
remain enabled. No external provider or carrier is contacted or shared source
written. Synthetic reconciliation evidence does not attest provider acceptance.
"""
import argparse
import datetime
import json
from pathlib import Path

import data_correctness_sql_positive_history_uat as posting
import data_correctness_sql_uat as data
import local_schema_uat as local
import staged_bundle_upgrade_uat as bundle

ROOT, R, U = local.ROOT, local.R, local.U
MEMBER = "99780000-0000-4000-8000-000000040001"
PAYMENT = "99780000-0000-4000-8000-000000050001"
REQUEST = "99780000-0000-4000-8000-000000060001"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--bundle-proof", type=Path, required=True)
    args = parser.parse_args()
    report, proof_path = args.output.resolve(), args.bundle_proof.resolve()
    if report.exists() or not report.is_relative_to(ROOT / "docs/release") or not proof_path.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh local release output and accepted bundle proof required")
    stages = {ROOT / "supabase/migrations" / name: (ROOT / "supabase/migrations" / name).read_bytes() for name in bundle.STAGES}
    proof = json.loads(proof_path.read_text())
    if proof.get("status") != "pass" or proof.get("source_migration_sha256") != {p.name: R.sha(b) for p, b in stages.items()}:
        raise RuntimeError("Exact current accepted staged proof required")
    if not all(proof.get(k) for k in ("all_source_tables_catalog_cron_preserved", "isolated_database_removed", "recorder_sources_unchanged")):
        raise RuntimeError("Incomplete bundle preservation proof")
    tracked = stages | {p: p.read_bytes() for p in (Path(__file__), Path(posting.__file__), Path(data.__file__), Path(bundle.__file__), posting.CATALOG_SOURCE)}
    inventory = {p.name: R.sha(p.read_bytes()) for p in sorted((ROOT / "supabase/migrations").glob("*.sql"))}
    report.mkdir(mode=0o700, parents=True)
    for path, body in tracked.items(): (report / path.name).write_bytes(body)
    (report / "bundle-proof.json").write_bytes(proof_path.read_bytes())
    R.save(report / "source-migration-inventory.json", inventory)
    evidence = dict(kind="current_bundle_actual_posted_receipt_cancellation", status="running", cases=[],
        source_rows_copied=False, shared_source_written=False, provider_called=False, carrier_called=False,
        independent_provider_evidence=False, signed_jwt_tested=False, triggers_disabled=False,
        synthetic_review_evidence=True, actual_maker_checker_service_finalizer=True,
        source_migration_sha256={p.name: R.sha(b) for p, b in stages.items()},
        bundle_proof_sha256=R.sha(proof_path.read_bytes()), started_at=datetime.datetime.now(datetime.timezone.utc).isoformat())
    U.SQL_LOG, U.CONCURRENCY_LOG = report / "queries.log", report / "concurrency.log"
    def save(): R.save(report / "result.json", evidence)
    def require(ok, detail):
        if not ok: raise AssertionError(json.dumps(detail))
        return detail
    def case(name, action):
        try: detail = action()
        except Exception as error:
            evidence["cases"].append(dict(name=name, status="failed", error=str(error))); save(); raise
        evidence["cases"].append(dict(name=name, status="pass", detail=detail)); save(); print("PASS " + name, flush=True)
    save()
    try:
        with local.isolated(report, evidence, count=154, latest="20260930230000") as db:
            installed = set(data.scalar("postgres", "select to_jsonb(array_agg(version order by version))from supabase_migrations.schema_migrations;"))
            actual = {p.name for p in (ROOT / "supabase/migrations").glob("*.sql") if p.name.split("_", 1)[0] not in installed}
            require(actual == set(bundle.STAGES), dict(unreviewed=sorted(actual-set(bundle.STAGES)), missing=sorted(set(bundle.STAGES)-actual)))
            bundle.seed_schema_clone_permission_catalog(db, report, evidence)
            for path, body in stages.items(): U.psql(db, body.decode())
            data.seed(db)
            posting.seed_authority(db)
            posting.seed_notification_catalog(db)
            U.psql(db, f"""begin;
              insert into public.admin_permissions(name)select name from unnest(array[
                'payments.read','notifications.read','notifications.manage','system_health.read','audit.read'])name on conflict(name)do nothing;
              insert into public.admin_role_permissions(role_id,permission_name)
                select '{posting.ROLE}',name from public.admin_permissions on conflict do nothing;
              update auth.users set email='synthetic-receipt@collect.example',email_confirmed_at=clock_timestamp()where id='{data.ACTOR}';
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
                values('{data.ACTOR}','synthetic-receipt@collect.example',clock_timestamp()-interval '2 minutes','Synthetic operator approval');
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
                values('{data.ACTOR}','{posting.ROLE}','Synthetic receipt operator',clock_timestamp()-interval '1 minute');
              insert into collect_hybrid.member_records(id,collect_id,origin,created_by)
                values('{MEMBER}','978401','admin_assisted','{data.ACTOR}');
              insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
                values('{MEMBER}','Synthetic roster member','SYNTHETIC ROSTER MEMBER','+250788978401');
              insert into public.collection_members(collection_id,member_record_id,role,status)
                values('{data.GROUP}','{MEMBER}','member','active');
              insert into public.feature_flags(key,enabled,description)values('hybrid_sms_notifications',false,'Synthetic hard dispatch pause');
              insert into collect_hybrid.sms_receipt_policies(collection_id,enabled,reason,updated_by)
                values('{data.GROUP}',true,'Synthetic explicit receipt policy','{data.ACTOR}');
              insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by)
                values('{MEMBER}',true,'written','Synthetic explicit roster consent','{data.ACTOR}');commit;""")
            U.call(db, "select public.admin_set_operator_email_mode_v1('Synthetic current cancellation email cutover')", posting.MAKER, posting.MAKER_SID)
            row = dict(id=PAYMENT, group=data.GROUP, contributor=None, amount=100,
                date="2026-09-30T12:00:00+00:00", transaction="SYNTH-CURRENT-RECEIPT-978401", anonymity="anonymous")
            review = posting.review_input_sql(row)
            require(review.count("insert into public.payments(id,") == review.count("values('") == 1, {})
            review = review.replace("insert into public.payments(id,", "insert into public.payments(member_record_id,id,", 1)
            review = review.replace("values('", "values('" + MEMBER + "','", 1)
            (report / "synthetic-review-input.sql").write_text(review)
            U.psql(db, review)
            acknowledgement = U.psql(db, "begin;" + posting.post_api_sql(row) + "commit;").stdout
            (report / "actual-posting-acknowledgement.log").write_text(acknowledgement)
            scalar = lambda body: data.scalar(db, body)
            call = lambda body: U.call(db, "select " + body, data.ACTOR, data.SESSION)
            job = scalar(f"select to_jsonb(o)from collect_hybrid.sms_notification_outbox o where payment_id='{PAYMENT}';")
            case("actual maker/checker/finalizer creates exactly one paused pristine primary receipt", lambda: require(
                job is not None and job["state"] == "queued" and job["member_record_id"] == MEMBER
                and job["amount_rwf"] == 100 and job["attempt_count"] == job["fence_version"] == 0,
                dict(payment_id=PAYMENT, outbox_id=job["id"], actual_triggers_enabled=True)))
            outbox = job["id"]
            inspect = f"public.admin_inspect_unstarted_receipt_v1('{outbox}')"
            before_view = call(inspect)
            case("current positive inspection binds exact eligible Rwanda source and physical revision", lambda: require(
                before_view["status"] == "available" and before_view["receipt"]["can_cancel"]
                and before_view["receipt"]["reason_code"] == "eligible" and before_view["receipt"]["revision"] == 1, before_view))
            def protected():
                result = posting.financial(db)
                for key in ("collect_hybrid.sms_notification_outbox", "public.audit_logs",
                    "collect_hybrid.receipt_business_event_heads", "collect_hybrid.receipt_business_events",
                    "collect_ops.exceptions", "collect_ops.exception_observations"):
                    result.pop(key, None)
                result["immutable_primary_payload"] = scalar("select jsonb_build_object('rows',count(*),'sha256',"
                    "encode(extensions.digest(coalesce(string_agg((to_jsonb(o)-array['state','suppression_reason','updated_at'])::text,E'\\n'order by id),''),'sha256'),'hex'))"
                    "from collect_hybrid.sms_notification_outbox o;")
                return result
            def controls():
                return {name: scalar("select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),'[]'::jsonb)from " + name + " t;")
                    for name in ("collect_ops.exceptions", "collect_ops.exception_observations",
                        "collect_hybrid.receipt_business_events", "collect_hybrid.receipt_business_event_heads")}
            def appended(before, after):
                old = {json.dumps(row, sort_keys=True) for row in before}
                new = {json.dumps(row, sort_keys=True) for row in after}
                require(old <= new and len(after) == len(before) + 1, dict(old_rows=len(before), new_rows=len(after)))
                return next(row for row in after if json.dumps(row, sort_keys=True) not in old)
            financial = protected()
            control_before = controls()
            R.save(report / "financial-before-cancellation.json", financial)
            R.save(report / "controls-before-cancellation.json", control_before)
            cancel = f"public.admin_cancel_unstarted_receipt_v1('{REQUEST}','{outbox}',1,'operator_cancelled')"
            receipt = call(cancel)
            R.save(report / "actual-cancellation-receipt.json", receipt)
            case("current cancellation returns request-bound nonfinancial nonsend revision acknowledgement", lambda: require(
                receipt["request_id"] == REQUEST and receipt["outbox_id"] == outbox
                and receipt["expected_revision"] == 1 and receipt["revision"] == 2
                and receipt["state_before"] == "queued" and receipt["state_after"] == "suppressed"
                and receipt["primary_receipt_retained"] is True
                and all(receipt[k] is False for k in ("financial_action", "send_action", "provider_delivery_verified")), receipt))
            financial_after, control_after = protected(), controls()
            R.save(report / "financial-after-cancellation.json", financial_after)
            R.save(report / "controls-after-cancellation.json", control_after)
            case("cancellation preserves financial, provider-fixture, payload and transport evidence", lambda: require(
                financial_after == financial, dict(changed_families=[k for k in financial if financial[k] != financial_after.get(k)])))
            exception = appended(control_before["collect_ops.exceptions"], control_after["collect_ops.exceptions"])
            observation = appended(control_before["collect_ops.exception_observations"], control_after["collect_ops.exception_observations"])
            case("actual operational trigger appends exactly the source-bound suppression observation", lambda: require(
                exception["source_kind"] == "receipt" and exception["source_id"] == outbox
                and exception["reason_code"] == "RECEIPT_SUPPRESSED" and exception["active"] is True
                and exception["revision"] == 1 and observation["exception_id"] == exception["id"]
                and observation["revision"] == 1 and observation["active"] is True
                and observation["source_sha256"] == exception["source_sha256"]
                and observation["observed_at"] == exception["last_changed_at"],
                dict(prior_rows_retained=True, new_exception_count=1, new_observation_count=1)))
            event = appended(control_before["collect_hybrid.receipt_business_events"], control_after["collect_hybrid.receipt_business_events"])
            heads = lambda rows: {(r["source_kind"],r["source_id"]):r for r in rows}
            before_heads, after_heads = heads(control_before["collect_hybrid.receipt_business_event_heads"]), heads(control_after["collect_hybrid.receipt_business_event_heads"])
            identity = ("receipt",outbox)
            case("actual receipt trigger appends one suppression event and advances only its source-local head", lambda: require(
                event["event_kind"] == "receipt_suppressed" and event["source_state"] == "suppressed"
                and event["source_kind"] == "receipt" and event["source_id"] == event["outbox_id"] == outbox
                and event["payment_id"] == PAYMENT and event["member_record_id"] == MEMBER
                and event["source_version"] == after_heads[identity]["version"] == before_heads[identity]["version"] + 1
                and set(before_heads) == set(after_heads)
                and all(after_heads[k] == row for k,row in before_heads.items() if k != identity),
                dict(prior_events_retained=True, appended_events=1, unrelated_heads_unchanged=True)))
            audits = scalar(f"select coalesce(jsonb_agg(to_jsonb(a)order by id),'[]'::jsonb)from public.audit_logs a where action='notification.sms.cancelled_unstarted'and entity_id='{outbox}';")
            case("stored cancellation audit attributes exact actor entity request reason and revisions", lambda: require(
                len(audits) == 1 and audits[0]["actor_user_id"] == data.ACTOR
                and audits[0]["metadata"]["request_id"] == REQUEST
                and audits[0]["metadata"]["expected_revision"] == 1 and audits[0]["metadata"]["revision"] == 2
                and audits[0]["metadata"]["reason_code"] == "operator_cancelled"
                and audits[0]["metadata"]["financial_action"] is False and audits[0]["metadata"]["send_action"] is False, {}))
            lookup = call(f"public.admin_get_unstarted_receipt_action_v1('{REQUEST}')")
            case("durable current lookup returns the exact acknowledgement", lambda: require(lookup["status"] == "recorded" and lookup["receipt"] == receipt, {}))
            case("original replay returns identical acknowledgement without duplicate audit", lambda: require(call(cancel) == receipt
                and audits == scalar(f"select coalesce(jsonb_agg(to_jsonb(a)order by id),'[]'::jsonb)from public.audit_logs a where action='notification.sms.cancelled_unstarted'and entity_id='{outbox}';")
                and protected() == financial, {}))
            after_view = call(inspect)
            case("cancelled primary remains retained and terminally ineligible", lambda: require(
                after_view["receipt"]["state"] == "suppressed" and after_view["receipt"]["revision"] == 2
                and after_view["receipt"]["can_cancel"] is False and after_view["receipt"]["reason_code"] == "already_cancelled", {}))
            page = call(f"public.admin_get_operator_entity_audit_v1('receipt','{outbox}')")
            rows = [r for r in page["rows"] if r["action"] == "notification.sms.cancelled_unstarted"]
            case("joined current audit exposes one exact redacted attributed cancellation event", lambda: require(
                page["status"] == "available" and len(rows) == 1 and rows[0]["actor_id"] == data.ACTOR
                and rows[0]["request_id"] == REQUEST and rows[0]["revision"] == 2
                and set(rows[0]) == {"event_id","source","action","recorded_at","actor_id","request_id","revision","fence_version","reason_code"}, page))
            R.save(report / "actual-joined-audit.json", page)
            case("hard dispatch pause remains enabled with zero carrier attempts", lambda: require(
                scalar("select to_jsonb(not enabled)from public.feature_flags where key='hybrid_sms_notifications';") is True
                and scalar("select to_jsonb(count(*))from collect_hybrid.sms_notification_attempts;") == 0, {}))
            case("all captured source files remain byte-identical", lambda: require(all(p.read_bytes() == body for p, body in tracked.items()), {}))
            case("complete migration source set remains unchanged", lambda: require(inventory == {p.name:R.sha(p.read_bytes())for p in sorted((ROOT/"supabase/migrations").glob("*.sql"))}, {}))
        evidence["status"] = "pass"
    except Exception as error: evidence.update(status="failed", failure=str(error)); raise
    finally:
        U.SQL_LOG = U.CONCURRENCY_LOG = None
        evidence["completed_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat(); save()


if __name__ == "__main__": main()
