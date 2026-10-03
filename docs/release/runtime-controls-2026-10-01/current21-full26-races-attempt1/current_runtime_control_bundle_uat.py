#!/usr/bin/env python3
"""Actual current runtime-control RPCs for all26 families in an offline clone.

The ordinary-owner shared154 database is read only. Synthetic Auth, control
and roster fixtures are created only in a disposable schema/ACL clone. No
provider, signed JWT, device capability, delivery or posted money is fabricated.
"""
from __future__ import annotations

import argparse
from collections import Counter
import datetime as dt
import json
from pathlib import Path
import re

import data_correctness_sql_uat as data
import local_schema_uat as local
import staged_bundle_upgrade_uat as bundle

ROOT, R, U = local.ROOT, local.R, local.U
SPEC_SOURCE = ROOT / "supabase/migrations/20260930150000_runtime_control_governance.sql"
UID = "99790000-0000-4000-8000-000000000001"
OTHER = "99790000-0000-4000-8000-000000000002"
SID = "99790000-0000-4000-8000-000000010001"
OTHERSID = "99790000-0000-4000-8000-000000010002"
ROLE = "99790000-0000-4000-8000-000000020001"
GROUP = "99790000-0000-4000-8000-000000030001"
MEMBER = "99790000-0000-4000-8000-000000040001"
FILTER = "99790000-0000-4000-8000-000000050001"
SIGNAL = "99790000-0000-4000-8000-000000050002"
POLICY = "99790000-0000-4000-8000-000000060001"
SECTION = "99790000-0000-4000-8000-000000060002"
VERSION = "99790000-0000-4000-8000-000000070001"
KEY = "qa_runtime_current"
REASON = "Synthetic accountable runtime edit"


def j(value):
    return R.literal(json.dumps(value, ensure_ascii=False, separators=(",", ":"))) + "::jsonb"


def specs_from_source(body):
    match = re.search(r"select '(\{.*\})'::jsonb -> p_family", body.decode())
    if match is None:
        raise RuntimeError("Exact embedded runtime-control registry required")
    return json.loads(match.group(1).replace("''", "'"))


def fixtures():
    # Ordering follows actual FK and publication-parent dependencies. Existing
    # singleton/reference rows are updated through their reviewed owner path.
    return {
        "brand_entities": dict(key=KEY, display_name="Synthetic brand", legal_name="Synthetic legal entity", public_url="https://collect.example"),
        "support_channels": dict(key=KEY, channel_type="email", label="Synthetic support", value="synthetic@collect.example"),
        "payment_entrypoints": dict(key=KEY, country_code="RW", currency="RWF", network="mtn_momo", label="Synthetic payment", code="*182*8*1*41258*2000#", metadata={"amount_rwf": 2000}),
        "feature_flags": dict(key=KEY, enabled=False),
        "system_settings": dict(key=KEY, value={"display": "Synthetic content"}, description="Synthetic setting"),
        "admin_navigation_items": dict(key=KEY, label="Synthetic navigation", icon_key="home", route_path="/admin/home", required_permission="settings.read"),
        "admin_queue_specs": dict(rpc_name="admin_list_qa_runtime_current", title="Synthetic queue", subtitle="Synthetic subtitle", required_permission="settings.read"),
        "admin_queue_filter_options": dict(id=FILTER, rpc_name="admin_list_qa_runtime_current", filter_kind="status", value="all", label="Synthetic filter"),
        "admin_queue_signals": dict(id=SIGNAL, rpc_name="admin_list_qa_runtime_current", signal_kind="priority", icon_key="home", label="Synthetic signal"),
        "admin_queue_sla_policies": dict(queue_key=KEY, target="Synthetic target", owner="Synthetic owner", escalation="Synthetic escalation"),
        "notification_preferences": dict(user_id=UID, payment_reminders=False),
        "notification_channels": dict(key=KEY, label="Synthetic channel", description="Synthetic description"),
        "notification_event_types": dict(key="security_notice", preference_key="security_notices", label="Synthetic event", description="Synthetic description", default_channel_key=KEY),
        "notification_templates": dict(key=KEY, event_type_key="security_notice", locale="en"),
        "notification_template_versions": dict(id=VERSION, template_key=KEY, version="qa-current-a", title_template="Synthetic notice", body_template="Synthetic body {{group_name}}"),
        "policy_documents": dict(id=POLICY, kind="terms", version="qa-current-a", title="Synthetic policy"),
        "policy_document_sections": dict(id=SECTION, policy_document_id=POLICY, section_key="qa", title="Synthetic section", body="Synthetic policy body"),
        "account_request_reason_options": dict(request_type="account_deletion", locale="en", key=KEY, label="Synthetic reason"),
        "collection_type_catalog": dict(key="ikimina", label="Synthetic type", short_purpose="Synthetic purpose", icon_key="groups", default_category_subtype=KEY, default_purpose_template_key=KEY),
        "collection_category_subtypes": dict(collection_type_key="ikimina", key=KEY, label="Synthetic subtype"),
        "collection_purpose_templates": dict(collection_type_key="ikimina", key=KEY, label="Synthetic purpose"),
        "collection_type_country_rules": dict(collection_type_key="ikimina", country_code="RW", enabled=True),
        "sms_receipt_policies": dict(collection_id=GROUP, enabled=False, reason="Synthetic fixture policy", updated_by=UID),
        "sms_receipt_member_consents": dict(member_record_id=MEMBER, enabled=False, capture_method="written", reason="Synthetic fixture consent", recorded_by=UID),
        "otp_policy": dict(singleton=True, global_hourly_limit=100, global_daily_limit=1000, enabled=False),
        "roster_resource_policy": dict(id=True, actor_daily_requests=10, actor_daily_bytes=10485760, actor_active=2, global_daily_requests=100, global_daily_bytes=104857600, global_active=10, actor_daily_cost_units=100, global_daily_cost_units=1000, ai_attempt_cost_units=1, version=1),
    }


def patches():
    result = {name: {"label": "Updated synthetic label"} for name in (
        "support_channels", "payment_entrypoints", "admin_navigation_items", "admin_queue_filter_options", "admin_queue_signals", "notification_channels", "notification_event_types", "account_request_reason_options", "collection_type_catalog", "collection_category_subtypes", "collection_purpose_templates")}
    result.update({
        "brand_entities": {"display_name": "Updated synthetic brand"},
        "feature_flags": {"enabled": True}, "system_settings": {"value": {"display": "Updated synthetic content"}},
        "admin_queue_specs": {"title": "Updated synthetic queue"}, "admin_queue_sla_policies": {"target": "Updated synthetic target"},
        "notification_preferences": {"payment_reminders": True}, "notification_templates": {"enabled": False},
        "notification_template_versions": {"title_template": "Updated synthetic notice"},
        "policy_documents": {"title": "Updated synthetic policy"}, "policy_document_sections": {"body": "Updated synthetic body"},
        "collection_type_country_rules": {"enabled": False}, "sms_receipt_policies": {"enabled": True},
        "sms_receipt_member_consents": {"enabled": True}, "otp_policy": {"global_hourly_limit": 101},
        "roster_resource_policy": {"actor_daily_requests": 11},
    })
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--bundle-proof", required=True, type=Path)
    parser.add_argument("--reason-candidate", type=Path,
                        help="Apply the reviewed single-body reason correction after the accepted bundle")
    args = parser.parse_args()
    report = args.output.resolve()
    proof_path = args.bundle_proof.resolve()
    if report.exists() or not report.is_relative_to(ROOT / "docs/release") or not proof_path.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh local release output and accepted local bundle proof required")
    stage_paths = [ROOT / "supabase/migrations" / name for name in bundle.STAGES]
    sources = {path: path.read_bytes() for path in stage_paths}
    proof = json.loads(proof_path.read_text())
    if proof.get("status") != "pass" or proof.get("source_migration_sha256") != {p.name: R.sha(b) for p, b in sources.items()}:
        raise RuntimeError("Accepted bundle source mismatch")
    if not all(proof.get(k) for k in ("all_source_tables_catalog_cron_preserved", "isolated_database_removed", "recorder_sources_unchanged")):
        raise RuntimeError("Bundle preservation proof incomplete")
    specs = specs_from_source(SPEC_SOURCE.read_bytes())
    rows, edits = fixtures(), patches()
    if len(specs) != 26 or set(specs) != set(rows) or set(specs) != set(edits):
        raise RuntimeError("Explicit full26-family fixture and edit coverage required")
    report.mkdir(mode=0o700, parents=True)
    candidate = args.reason_candidate.resolve() if args.reason_candidate else None
    if candidate and (candidate.name != '20260930235600_runtime_control_reason_whitespace.sql'
                      or not candidate.is_relative_to(ROOT)):
        raise RuntimeError('Reviewed repository runtime-reason candidate required')
    tracked = sources | {SPEC_SOURCE: SPEC_SOURCE.read_bytes(), Path(__file__): Path(__file__).read_bytes(), Path(data.__file__): Path(data.__file__).read_bytes(), Path(bundle.__file__): Path(bundle.__file__).read_bytes()}
    if candidate:
        tracked[candidate] = candidate.read_bytes()
    for path, body in tracked.items():
        (report / path.name).write_bytes(body)
    (report / "bundle-proof.json").write_bytes(proof_path.read_bytes())
    evidence = dict(kind="current_full26_runtime_control_rpc_acceptance", status="running", started_at=dt.datetime.now(dt.timezone.utc).isoformat(), cases=[], source_rows_copied=False, shared_source_written=False, triggers_disabled=False, provider_called=False, signed_jwt_tested=False, full_client_consumer_acceptance=False, actual_blocking_races=0, families=sorted(specs), migration_sources={p.name: R.sha(b) for p,b in sources.items()}, bundle_proof_sha256=R.sha(proof_path.read_bytes()), reason_candidate_sha256=R.sha(tracked[candidate]) if candidate else None)
    U.SQL_LOG = report / "queries.log"

    def save():
        R.save(report / "result.json", evidence)

    def require(ok, detail):
        if not ok:
            raise AssertionError(json.dumps(detail, ensure_ascii=False))
        return detail

    def case(name, fn):
        try:
            detail = fn()
            evidence["cases"].append(dict(name=name, status="pass", detail=detail))
            print("PASS " + name, flush=True)
        except Exception as error:
            evidence["cases"].append(dict(name=name, status="failed", error=str(error)))
            print("FAIL " + name + ": " + str(error), flush=True)
        save()

    save()
    try:
        with local.isolated(report, evidence, count=154, latest="20260930230000") as db:
            bundle.seed_schema_clone_permission_catalog(db, report, evidence)
            for path, body in sources.items():
                result = U.psql(db, body.decode(), False)
                (report / (path.stem + ".stderr.log")).write_text(result.stderr)
                if result.returncode:
                    raise RuntimeError("Stage failed: " + path.name)
            if candidate:
                def catalog():
                    names = ','.join(R.literal(name) for name in R.SCHEMAS)
                    return data.scalar(db, f"""select jsonb_object_agg(identity,properties) from(
                      select n.nspname||'.'||p.proname||'('||oidvectortypes(p.proargtypes)||')' identity,
                        jsonb_build_object('body',p.prosrc,'volatility',p.provolatile,'owner',p.proowner,
                          'acl',p.proacl,'definer',p.prosecdef,'config',p.proconfig,
                          'result',pg_get_function_result(p.oid),'arguments',pg_get_function_arguments(p.oid),
                          'strict',p.proisstrict,'parallel',p.proparallel,'leakproof',p.proleakproof) properties
                      from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in({names})
                    )s;""")
                before_catalog = catalog()
                result = U.psql(db, tracked[candidate].decode(), False)
                (report / 'reason-candidate.stderr.log').write_text(result.stderr)
                if result.returncode:
                    raise RuntimeError('Runtime reason candidate apply failed')
                after_catalog = catalog()
                R.save(report / 'reason-catalog-before.json', before_catalog)
                R.save(report / 'reason-catalog-after.json', after_catalog)
                changed = {name:sorted(k for k in before_catalog[name] if before_catalog[name][k]!=after_catalog[name][k])
                           for name in before_catalog if before_catalog[name]!=after_catalog.get(name)}
                case('reason candidate changes only the updater body and preserves every signature/default/result/owner/ACL/attribute/unrelated routine',
                     lambda: require(set(before_catalog)==set(after_catalog)
                       and changed=={'public.admin_update_runtime_control_v1(text, jsonb, jsonb, bigint, text)':['body']}, changed))
            actual = data.scalar(db, "select jsonb_object_agg(family,collect_security.runtime_control_spec(family)) from unnest(" + "array[" + ",".join(R.literal(f) for f in specs) + "])family;")
            require(actual == specs, dict(runtime_registry_matches_source=actual == specs))
            permissions = sorted({"audit.read"} | {s[k] for s in specs.values() for k in ("permission", "read_permission", "additional_permission") if k in s})
            U.psql(db, f"""insert into public.admin_roles(id,name,description) values('{ROLE}','platform_owner','Synthetic full runtime fixture');
              insert into public.admin_permissions(name) select name from unnest(array[{','.join(R.literal(p) for p in permissions)}])name on conflict(name) do nothing;
              insert into public.admin_role_permissions(role_id,permission_name) select '{ROLE}',name from public.admin_permissions;
              insert into auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
              values('{UID}','authenticated','authenticated','synthetic-runtime@collect.example',clock_timestamp(),'{{}}','{{}}'),
                    ('{OTHER}','authenticated','authenticated','synthetic-runtime-member@collect.example',clock_timestamp(),'{{}}','{{}}');
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
              values('{UID}','synthetic-runtime@collect.example',clock_timestamp()-interval '2 minutes','Synthetic runtime approval');
              insert into public.admin_user_roles(user_id,role_id,reason,created_at)
              values('{UID}','{ROLE}','Synthetic runtime role',clock_timestamp()-interval '1 minute');
              insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
              values('{SID}','{UID}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
                    ('{OTHERSID}','{OTHER}',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
              insert into public.collections(id,slug,creator_user_id,title,collection_type) values('{GROUP}','qa-runtime-current','{UID}','Synthetic runtime group','ikimina');
              insert into collect_hybrid.member_records(id,collect_id,origin,created_by) values('{MEMBER}','971901','admin_assisted','{UID}');
              insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number) values('{MEMBER}','Synthetic Runtime Member','Synthetic Runtime Member','+250788979001');""")
            for family, row in rows.items():
                relation = specs[family]["relation"]
                identity = {key: row[key] for key in specs[family]["identity"]}
                columns = ",".join(row)
                values = ",".join(f"(jsonb_populate_record(null::{relation},{j(row)})).{column}" for column in row)
                existing = data.scalar(db, f"select to_jsonb(exists(select 1 from {relation} t where to_jsonb(t) @> {j(identity)}));")
                if existing:
                    assignments = ",".join(f"{key}=(jsonb_populate_record(null::{relation},{j(row)})).{key}" for key in row if key not in identity)
                    U.psql(db, f"update {relation} t set {assignments} where to_jsonb(t) @> {j(identity)};")
                else:
                    U.psql(db, f"insert into {relation} ({columns}) select {values};")
            finance = data.financial(db)

            def rpc(sql, uid=UID, sid=SID, role="authenticated", extra="", rollback=True):
                auth = U.auth(uid, sid) if role == "authenticated" else "set local role " + role + ";"
                result = U.psql(db, "begin;" + extra + auth + "select " + sql + ";" + ("rollback;" if rollback else "commit;"), False)
                return result, json.loads(result.stdout.strip().splitlines()[-1]) if not result.returncode else None

            def denied(sql, state="42501", message=None, **options):
                result, value = rpc(sql, **options)
                return require(result.returncode and state + ":" in result.stderr and (message is None or message in result.stderr), dict(exit_code=result.returncode, intended_error=message, returned_success=value is not None, stderr=result.stderr[-500:]))

            for family, row in rows.items():
                spec = specs[family]
                identity = {key: row[key] for key in spec["identity"]}
                get = f"public.admin_get_runtime_control_v1({R.literal(family)},{j(identity)})"
                before_result, before = rpc(get)
                require(before_result.returncode == 0, dict(family=family, stderr=before_result.stderr))
                revision = before["revision"]
                update = lambda patch=edits[family], rev=revision, reason=REASON: f"public.admin_update_runtime_control_v1({R.literal(family)},{j(identity)},{j(patch)},{rev},{R.literal(reason) if reason is not None else 'null'})"
                case(family + " exact getter is bound and omits accountable/private fields", lambda before=before, family=family, identity=identity: require(
                    set(before) == {"contract_version","ok","family","identity","revision","exists","value","redacted","content_sha256"}
                    and before["contract_version"] == 1 and before["ok"] is True and before["family"] == family and before["identity"] == identity and before["exists"] is True and before["revision"] >= 1
                    and not ({"updated_by","updated_reason","reason","recorded_by"} & set(before["value"])), before))
                case(family + " direct API DML is unavailable", lambda spec=spec: require(data.scalar(db,
                    "select to_jsonb(not exists(select 1 from unnest(array['anon','authenticated','service_role'])r where has_table_privilege(r," + R.literal(spec['relation']) + ",'INSERT,UPDATE,DELETE,TRUNCATE')));"), {}))
                case(family + " accountable write advances exact revision and hash", lambda update=update, family=family, identity=identity, revision=revision: require(
                    (lambda value: value is not None and set(value)=={"contract_version","ok","family","identity","previous_revision","revision","changed","updated_at","content_sha256"} and value["ok"] is True and value["contract_version"]==1 and value["family"]==family and value["identity"]==identity and value["previous_revision"]==revision and value["revision"]==revision+1 and value["changed"] is True and re.fullmatch('[a-f0-9]{64}',value['content_sha256']))(rpc(update())[1]), dict(family=family)))
                result, ack = rpc(update(), rollback=False)
                require(result.returncode == 0, dict(family=family, stderr=result.stderr))
                event = data.scalar(db, f"select to_jsonb(t) from collect_security.runtime_control_events t where family={R.literal(family)} and identity_sha256=collect_security.runtime_control_hash({j(identity)}) and revision={revision+1};")
                case(family + " exact current actor/session and reason hash are audited", lambda event=event, ack=ack, revision=revision, family=family: require(
                    event['actor_id']==UID and event['session_id']==SID and event['authority']=='live_operator' and event['operation']=='update' and event['previous_revision']==revision and event['revision']==revision+1 and event['reason_sha256']==R.sha(REASON.encode()) and event['reason_characters']==len(REASON) and event['changed_fields']
                    and (event['new_sha256']==ack['content_sha256'] if family!='notification_preferences' else event['redacted'] and event['old_sha256'] is None and event['new_sha256'] is None), event))
                case(family + " identical edit is a no-op without audit growth", lambda update=update, family=family, revision=revision: require(
                    (lambda value: value is not None and value['changed'] is False and value['previous_revision']==revision+1 and value['revision']==revision+1)(rpc(update(rev=revision+1))[1])
                    and data.scalar(db,f"select to_jsonb(count(*)=1) from collect_security.runtime_control_events where family={R.literal(family)} and actor_id='{UID}';"), {}))
                case(family + " stale version is rejected even for unchanged content", lambda update=update: denied(update(), "40001", "runtime_control_conflict"))
                for role in ("anon", "service_role"):
                    case(family + " denies " + role + " getter", lambda get=get, role=role: denied(get, role=role))
                    case(family + " denies " + role + " writer", lambda update=update, revision=revision, role=role: denied(update(rev=revision+1), role=role))
                if not spec.get('user_owned'):
                    case(family + " ordinary member cannot read operator controls", lambda get=get: denied(get, uid=OTHER, sid=OTHERSID))
                    case(family + " ordinary member cannot write operator controls", lambda update=update, revision=revision: denied(update(rev=revision+1), uid=OTHER, sid=OTHERSID))
                    for permission in (spec['permission'],spec.get('additional_permission')):
                        if permission:
                            extra=f"delete from public.admin_role_permissions where role_id='{ROLE}' and permission_name={R.literal(permission)};"
                            case(family + " write denies missing " + permission, lambda update=update, revision=revision, extra=extra: denied(update(rev=revision+1), extra=extra))
                    extra=f"delete from public.admin_role_permissions where role_id='{ROLE}' and permission_name={R.literal(spec['read_permission'])};"
                    case(family + " read denies missing specific permission", lambda get=get, extra=extra: denied(get, extra=extra))
                else:
                    case(family + " member cannot read another user preferences", lambda get=get: denied(get, uid=OTHER, sid=OTHERSID))
                    case(family + " member cannot change another user preferences", lambda update=update, revision=revision: denied(update(rev=revision+1), uid=OTHER, sid=OTHERSID))
                for label, extra in (
                    ('expired session',f"update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='{SID}';"),
                    ('revoked email approval',f"update collect_admin_access.email_approvals set revoked_at=clock_timestamp() where user_id='{UID}';"),
                    ('revoked role',f"update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='{UID}';"),
                ):
                    if spec.get('user_owned') and label!='expired session':
                        continue
                    case(family + " denies " + label, lambda update=update, revision=revision, extra=extra: denied(update(rev=revision+1), extra=extra))
                case(family + " unknown patch cannot forge actor identity", lambda update=update, revision=revision: denied(update({'updated_by':OTHER},revision+1),'22023','runtime_control_patch_invalid'))
                field=next(iter(edits[family]));typ=spec['types'][field]
                wrong = 'true' if typ=='boolean' else True if typ!='jsonb' else {'api_key':'synthetic forbidden field'}
                message='runtime_control_sensitive_field' if typ=='jsonb' else 'runtime_control_invalid'
                case(family + " malformed typed value is rejected", lambda update=update, revision=revision, field=field, wrong=wrong, message=message: denied(update({field:wrong},revision+1),'22023',message))
                # Revert the edited field within a rolled-back probe, so a bad
                # reason cannot pass merely because the submitted edit is a no-op.
                revert = {field: row.get(field, True)}
                invalid = [('empty', ''),('ordinary whitespace',' '*8),('Unicode whitespace','\u00a0'*8),('Unicode padding','\u00a0'+'1234567'+'\u00a0'),('too long','x'*501)]
                invalid += [('whitespace codepoint '+str(code),chr(code)*8) for code in (
                    9,10,11,12,13,32,133,160,5760,8192,8193,8194,8195,8196,8197,8198,8199,8200,8201,8202,8232,8233,8239,8287,12288,65279)]
                for label, reason in invalid:
                    case(family + " rejects " + label + " reason before changing content", lambda update=update, revision=revision, reason=reason, revert=revert: denied(update(revert,revision+1,reason),'22023','runtime_control_revision_reason_required'))
                canonical = 'Audit\tinterior\nreason'
                padded = '\ufeff\u3000\t'+canonical+'\n\u00a0'
                result = U.psql(db,'begin;'+U.auth(UID,SID)+'select '+update(revert,revision+1,padded)+f";reset role;select jsonb_build_object('reason_sha256',reason_sha256,'reason_characters',reason_characters) from collect_security.runtime_control_events where family={R.literal(family)} and identity_sha256=collect_security.runtime_control_hash({j(identity)}) and revision={revision+2};rollback;",False)
                observed = json.loads(result.stdout.strip().splitlines()[-1]) if not result.returncode else None
                case(family+' trims Unicode edges before audit hashing while preserving interior whitespace',
                    lambda observed=observed,result=result: require(result.returncode==0 and observed==dict(reason_sha256=R.sha(canonical.encode()),reason_characters=len(canonical)),dict(observed=observed,exit_code=result.returncode,stderr=result.stderr[-500:])))
            case("every financial and delivery family remains unchanged", lambda: require(finance==data.financial(db), {}))
            case("private governance history has no API DML or raw reason", lambda: require(data.scalar(db,
                "select to_jsonb(not exists(select 1 from unnest(array['anon','authenticated','service_role'])r cross join unnest(array['collect_security.runtime_control_heads','collect_security.runtime_control_events'])t where has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')) and not exists(select 1 from collect_security.runtime_control_events where to_jsonb(runtime_control_events)::text like '%"+REASON+"%'));"), {}))
            case("all source bytes remain unchanged", lambda: require(all(path.read_bytes()==body for path,body in tracked.items()), {}))
        evidence['status']='pass' if all(c['status']=='pass' for c in evidence['cases']) else 'failed'
    except Exception as error:
        evidence.update(status='failed',failure=str(error))
        raise
    finally:
        U.SQL_LOG=None
        evidence['completed_at']=dt.datetime.now(dt.timezone.utc).isoformat()
        evidence['case_statuses']=dict(Counter(c['status'] for c in evidence['cases']))
        save()
    if evidence['status']!='pass':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
