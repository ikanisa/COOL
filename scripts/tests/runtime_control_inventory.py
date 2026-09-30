#!/usr/bin/env python3
"""Read-only inventory of the actual local runtime control/copy contracts.

No setting values, secrets or customer rows are exported. Effective grants,
policies, validation constraints, triggers and routine definitions are captured.
Table grants alone never establish that RLS permits a write.
"""
from __future__ import annotations
import argparse
import datetime as dt
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("offline", ROOT / "scripts/tests/local_offline_verification.py")
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
TABLES = (
    "public.brand_entities", "public.support_channels", "public.payment_entrypoints",
    "public.feature_flags", "public.system_settings", "public.admin_navigation_items",
    "public.admin_queue_specs", "public.admin_queue_filter_options", "public.admin_queue_signals",
    "public.admin_queue_sla_policies", "public.notification_channels", "public.notification_event_types",
    "public.notification_templates", "public.notification_template_versions",
    "public.policy_documents", "public.policy_document_sections", "public.account_request_reason_options",
    "public.collection_type_catalog", "public.collection_purpose_templates", "public.collection_type_country_rules",
    "public.notification_preferences", "collect_hybrid.sms_receipt_policies",
    "collect_hybrid.sms_receipt_member_consents", "collect_security.otp_policy",
    "collect_hybrid.roster_resource_policy",
)
ROUTINES = (
    "get_public_runtime_config", "admin_runtime_config", "get_notification_runtime_config",
    "get_active_policy_document", "get_account_request_reason_options", "admin_list_feature_flags",
    "admin_list_settings", "admin_set_feature_flag", "admin_set_sms_receipt_policy",
    "admin_set_sms_receipt_member_consent", "configure_notification_dispatch_schedule",
    "_notification_dispatch_configuration", "audit_public_runtime_config_change",
    "audit_policy_runtime_change", "record_policy_acceptance", "reserve_roster_resources",
    "reserve_signed_otp_send", "begin_signed_otp_send", "render_notification_template",
)
SOURCE_PATHS = (
    "supabase/migrations/20260704100000_public_runtime_config.sql",
    "supabase/migrations/20260704110000_admin_runtime_metadata.sql",
    "supabase/migrations/20260704120000_policy_documents_account_reasons.sql",
    "supabase/migrations/20260703225455_notification_templates_runtime.sql",
    "supabase/migrations/20260903090000_hybrid_sms_notification_outbox.sql",
    "supabase/migrations/20260929160000_notification_retry_schedule.sql",
    "supabase/migrations/20260930130000_signed_otp_uncertain_recovery.sql",
    "supabase/migrations/20260930140000_roster_resource_integrity.sql",
    "lib/shared/repositories/collect_repository_providers.dart", "lib/admin/core/admin_runtime.dart",
    "lib/admin/core/admin_list_runtime.dart", "lib/admin/core/admin_action_contracts.dart",
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "docs/release") or output.exists():
        parser.error("Fresh repository release output required")
    R.guard(146, "20260930140000")
    before = R.snapshot()
    relations = ",".join(R.literal(name) for name in TABLES)
    routines = ",".join(R.literal(name) for name in ROUTINES)
    body = f"""begin isolation level repeatable read read only;
      select jsonb_build_object('tables',(select jsonb_agg(jsonb_build_object(
        'relation',n.nspname||'.'||c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,
        'columns',(select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
          'not_null',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
          from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
          where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),
        'constraints',(select coalesce(jsonb_agg(jsonb_build_object('name',x.conname,'definition',pg_get_constraintdef(x.oid)) order by x.conname),'[]') from pg_constraint x where x.conrelid=c.oid),
        'policies',(select coalesce(jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'roles',p.polroles,
          'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) order by p.polname),'[]') from pg_policy p where p.polrelid=c.oid),
        'triggers',(select coalesce(jsonb_agg(jsonb_build_object('name',t.tgname,'enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid),
          'function_definition',pg_get_functiondef(t.tgfoid)) order by t.tgname),'[]') from pg_trigger t where t.tgrelid=c.oid and not t.tgisinternal),
        'api_grants',(select jsonb_object_agg(role_name,jsonb_build_object('select',has_table_privilege(role_name,c.oid,'SELECT'),
          'insert',has_table_privilege(role_name,c.oid,'INSERT'),'update',has_table_privilege(role_name,c.oid,'UPDATE'),
          'delete',has_table_privilege(role_name,c.oid,'DELETE'))) from unnest(array['anon','authenticated','service_role']) role_name)
        ) order by n.nspname,c.relname) from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname||'.'||c.relname in ({relations}) and c.relkind='r'),
        'routines',(select jsonb_agg(jsonb_build_object('signature',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),
          'security_definer',p.prosecdef,'definition',pg_get_functiondef(p.oid),
          'api_execute',(select jsonb_object_agg(role_name,has_function_privilege(role_name,p.oid,'EXECUTE')) from unnest(array['anon','authenticated','service_role']) role_name)
          ) order by p.oid::regprocedure::text) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
          where n.nspname in ('public','collect_hybrid','collect_security') and p.proname in ({routines})));
      rollback;"""
    inventory = json.loads(R.FIXTURE.sql(body))
    missing = sorted(set(TABLES) - {item["relation"] for item in inventory["tables"]})
    if missing:
        raise RuntimeError("Declared control tables missing: " + ",".join(missing))
    source_hashes = {path: R.sha((ROOT / path).read_bytes()) for path in SOURCE_PATHS}
    if R.snapshot() != before:
        raise RuntimeError("Read-only inventory observed unexpected local state drift")
    output.mkdir(parents=True, mode=0o700)
    (output / "reviewed-query.sql").write_text(body)
    (output / Path(__file__).name).write_bytes(Path(__file__).read_bytes())
    R.save(output / "inventory.json", inventory)
    no_version_column = [item["relation"] for item in inventory["tables"]
                         if not any(column["name"] in ("version", "revision", "config_version") for column in item["columns"])]
    R.save(output / "validation.json", {
        "status": "pass", "scope": "Read-only146 runtime control inventory; implementation acceptance remains open",
        "captured_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "fixture": R.FIXTURE.PROJECT, "tables": len(inventory["tables"]), "routines": len(inventory["routines"]),
        "source_hashes": source_hashes, "inventory_sha256": R.sha((output / "inventory.json").read_bytes()),
        "query_sha256": R.sha(body.encode()), "database_baseline_unchanged": True,
        "setting_values_exported": False, "provider_calls": 0, "hosted_calls": 0,
        "tables_without_version_column": no_version_column,
        "inference_limits": ["A version column does not prove concurrency/version enforcement.",
                             "API table grants alone do not establish a permitted write; RLS and callers must be tested.",
                             "Operational events, consent evidence and stable local Dart/YAML strings are distinct from mutable operator copy.",
                             "Validation, immutable published copy, accountable audit and final authorization tests remain required forL20."],
    })
    print(json.dumps({"tables": len(inventory["tables"]), "routines": len(inventory["routines"]),
                      "without_version_column": len(no_version_column), "database_unchanged": True}))


if __name__ == "__main__":
    main()
