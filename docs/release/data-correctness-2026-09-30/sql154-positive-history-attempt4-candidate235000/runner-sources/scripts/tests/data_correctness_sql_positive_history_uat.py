#!/usr/bin/env python3
"""Synthetic reconciliation mechanics and positive member history in a clone.

Only REVIEW inputs are seeded. The actual authenticated maker/checker APIs and
service finalizer run with all production triggers intact. Synthetic evidence
digests are deliberately not provider, native/device, signed-JWT or settlement
acceptance. The shared database is read-only; the unique clone is always removed.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import time
import traceback

import data_correctness_sql_uat as D
from local_schema_uat import ROOT, R, U, isolated, save

MAKER = "99640000-0000-4000-8000-000000000004"
CHECKER = "99640000-0000-4000-8000-000000000005"
MAKER_SID = "99640000-0000-4000-8000-000000010004"
CHECKER_SID = "99640000-0000-4000-8000-000000010005"
OUTSIDER_SID = "99640000-0000-4000-8000-000000010003"
PRECISION_GROUP = "99640000-0000-4000-8000-000000020005"
ROLE = "99640000-0000-4000-8000-000000030001"
PATCH_SHA = "0ca10f9a069c83f12bc1c1f4529cac2d31579e6132d98382fb57921585b790ba"
RECEIPT_PATCH = ROOT / "supabase/migrations/20260930235000_exact_receipt_history_amounts.sql"
RECEIPT_PATCH_SHA = "c3ae5ed350da19b30158d9d13e51c5ae9c02256eb7b09f36b47ca5de02630a04"
EXACT_HELPER = "collect_member_actions.exact_json_amount(numeric)"
RECEIPT_BODIES = (
    "public.propose_payment_reconciliation_v2(uuid,text,text,timestamp with time zone,text)",
    "public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamp with time zone,text)",
    "collect_member_actions.history_page(uuid,text,text,jsonb,integer)",
    "public.list_current_member_collection_balances()",
)
CATALOG_SOURCE = ROOT / "supabase/migrations/20260703225455_notification_templates_runtime.sql"
PIPELINE = (
    "public.propose_payment_reconciliation_v2(uuid,text,text,timestamp with time zone,text)",
    "public.approve_payment_reconciliation_v2(uuid,text)",
    "public.finalize_approved_reconciliation_v2(uuid)",
    "collect_security.reconciliation_actor_current(uuid,uuid)",
    "collect_security.require_reconciliation_actor()",
)


def actor(uid, sid, aal="aal2"):
    claims = json.dumps(dict(sub=uid, session_id=sid, role="authenticated", aal=aal))
    return "set local role authenticated;select set_config('request.jwt.claims'," + D.literal(claims) + ",true);"


def service():
    return "set local role service_role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);"


def api_definitions(db):
    wanted = ",".join(D.literal(x) + "::regprocedure" for x in PIPELINE + D.APIS)
    return D.scalar(db, f"""select jsonb_agg(jsonb_build_object(
      'identity',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),
      'volatile',p.provolatile,'strict',p.proisstrict,'parallel',p.proparallel,
      'leakproof',p.proleakproof,'language',l.lanname,'result',pg_get_function_result(p.oid),
      'defaults',pg_get_expr(p.proargdefaults,0),
      'api_privileges',(select jsonb_agg(jsonb_build_object('role',coalesce(r.rolname,'PUBLIC'),
        'privilege',x.privilege_type,'grantable',x.is_grantable)
        order by coalesce(r.rolname,'PUBLIC'),x.privilege_type,x.is_grantable)
        from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
        left join pg_roles r on r.oid=x.grantee
        where x.grantee=0 or r.rolname in ('anon','authenticated','service_role')))
      order by p.oid::regprocedure::text) from pg_proc p join pg_language l on l.oid=p.prolang
      where p.oid in ({wanted});""")


def catalog(db):
    """Whole application catalog, normalized only for no-owner restore.

    ACL owner entries are named OWNER; PUBLIC and the three application API
    roles remain explicit, matching the clone helper's reviewed ACL restoration.
    Internal platform-role grants are not inferred from that restoration.
    Function attributes/defaults/source, policies, columns, views, indices and
    triggers remain explicit. Restored owner equality is not asserted.
    """
    names = ",".join(D.literal(name) for name in R.SCHEMAS)
    return D.scalar(db, f"""with acl as (
      select p.oid,'routine' family,coalesce(p.proacl,acldefault('f',p.proowner)) a,p.proowner owner
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ({names})
      union all select c.oid,'relation',coalesce(c.relacl,acldefault(case when c.relkind='S' then 'S'::\"char\" else 'r'::\"char\" end,c.relowner)),c.relowner
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
      union all select n.oid,'schema',coalesce(n.nspacl,acldefault('n',n.nspowner)),n.nspowner
        from pg_namespace n where n.nspname in ({names})
    ), privileges as (
      select a.oid,a.family,jsonb_agg(jsonb_build_object(
        'grantee',case when x.grantee=0 then 'PUBLIC' when x.grantee=a.owner then 'OWNER' else r.rolname end,
        'grantor',case when x.grantor=a.owner then 'OWNER' else g.rolname end,
        'privilege',x.privilege_type,'grantable',x.is_grantable)
        order by case when x.grantee=0 then 'PUBLIC' when x.grantee=a.owner then 'OWNER' else r.rolname end,
        case when x.grantor=a.owner then 'OWNER' else g.rolname end,x.privilege_type,x.is_grantable) value
      from acl a cross join lateral aclexplode(a.a) x
      left join pg_roles r on r.oid=x.grantee left join pg_roles g on g.oid=x.grantor
      where x.grantee=0 or x.grantee=a.owner or r.rolname in ('anon','authenticated','service_role') group by a.oid,a.family
    ), controls as (
      select 'routine:'||format('%I.%I(%s)',n.nspname,p.proname,replace(oidvectortypes(p.proargtypes),', ',',')) key,jsonb_build_object(
        'source',p.prosrc,'binary',p.probin,'arguments',pg_get_function_arguments(p.oid),
        'result',pg_get_function_result(p.oid),'defaults',pg_get_expr(p.proargdefaults,0),
        'language',l.lanname,'volatile',p.provolatile,'strict',p.proisstrict,
        'parallel',p.proparallel,'leakproof',p.proleakproof,'definer',p.prosecdef,
        'config',p.proconfig,'kind',p.prokind,'cost',p.procost,'rows',p.prorows,
        'acl',(select value from privileges x where x.family='routine' and x.oid=p.oid)) value
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang where n.nspname in ({names})
      union all select 'schema:'||n.nspname,jsonb_build_object('acl',(select value from privileges x where x.family='schema' and x.oid=n.oid))
        from pg_namespace n where n.nspname in ({names})
      union all select 'relation:'||n.nspname||'.'||c.relname,jsonb_build_object(
        'kind',c.relkind,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,
        'view',case when c.relkind in ('v','m') then pg_get_viewdef(c.oid,true) end,
        'acl',(select value from privileges x where x.family='relation' and x.oid=c.oid))
        from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
      union all select 'column:'||c.oid::regclass::text||'.'||a.attname,jsonb_build_object(
        'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'identity',a.attidentity,
        'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid),'acl',a.attacl)
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace
        left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where n.nspname in ({names}) and a.attnum>0 and not a.attisdropped
      union all select 'constraint:'||c.conrelid::regclass::text||'.'||c.conname,jsonb_build_object(
        'definition',pg_get_constraintdef(c.oid),'validated',c.convalidated,'deferrable',c.condeferrable,'deferred',c.condeferred)
        from pg_constraint c join pg_namespace n on n.oid=c.connamespace where n.nspname in ({names})
      union all select 'trigger:'||t.tgrelid::regclass::text||'.'||t.tgname,jsonb_build_object(
        'definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled)
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
      union all select 'policy:'||p.polrelid::regclass::text||'.'||p.polname,jsonb_build_object(
        'roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
      union all select 'index:'||i.indexrelid::regclass::text,jsonb_build_object(
        'definition',pg_get_indexdef(i.indexrelid),'valid',i.indisvalid,'ready',i.indisready)
        from pg_index i join pg_class c on c.oid=i.indrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
    ) select jsonb_object_agg(key,value) from controls;""")


def reviewed_receipt_patch():
    source = RECEIPT_PATCH.read_bytes()
    if hashlib.sha256(source).hexdigest() != RECEIPT_PATCH_SHA:
        raise RuntimeError("Reviewed exact235000 receipt patch changed")
    return source.decode()


def approve_api_sql(row):
    # This is the identical actual public maker/checker route used by posting,
    # stopped before the finalizer so a pre-patch approved REVIEW can be tested.
    return post_api_sql(row).split(service(), 1)[0]


def seed_authority(db):
    email_mode = D.scalar(db, "select to_jsonb(to_regclass('collect_admin_access.email_approvals') is not null);")
    sql = "begin;"
    for uid, phone, sid in [(MAKER, "250788640004", MAKER_SID), (CHECKER, "250788640005", CHECKER_SID)]:
        sql += f"""insert into auth.users(id,aud,role,phone,phone_confirmed_at,
          raw_app_meta_data,raw_user_meta_data) values('{uid}','authenticated','authenticated',
          '{phone}',now(),'{{}}','{{}}');
          update public.profiles set country_code='RW',currency_code='RWF' where id='{uid}';"""
        if email_mode:
            email = "synthetic-maker@collect.example" if uid == MAKER else "synthetic-checker@collect.example"
            sql += f"""update auth.users set email='{email}',email_confirmed_at=now() where id='{uid}';
              insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
                values('{uid}','{email}',now()-interval '2 minutes','Synthetic mechanical operator approval');"""
        else:
            sql += f"""insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
                values('{uid}','+{phone}',now()-interval '2 minutes','Synthetic mechanical fixture operator');"""
    # Catalog contents are not copied from the source database. These are the
    # genuine source role/permission names used by require_reconciliation_actor.
    permissions = ['payments.allocate', 'admin_users.manage'] if email_mode else ['payments.allocate']
    permission_array = 'array[' + ','.join(D.literal(name) for name in permissions) + ']'
    sql += f"""insert into public.admin_roles(id,name,description) values('{ROLE}','platform_owner','Synthetic mechanical fixture');
      insert into public.admin_permissions(name) select name from unnest({permission_array})name on conflict(name) do nothing;
      insert into public.admin_role_permissions(role_id,permission_name) select '{ROLE}',name from unnest({permission_array})name;
      insert into public.admin_user_roles(user_id,role_id,reason,created_at)
        values('{MAKER}','{ROLE}','Synthetic mechanical fixture',now()-interval '1 minute'),
              ('{CHECKER}','{ROLE}','Synthetic mechanical fixture',now()-interval '1 minute');
      insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
        ('{MAKER_SID}','{MAKER}',now(),now(),now()+interval '1 hour','aal2'),
        ('{CHECKER_SID}','{CHECKER}',now(),now(),now()+interval '1 hour','aal2'),
        ('{OUTSIDER_SID}','{D.OUTSIDER}',now(),now(),now()+interval '1 hour','aal1');
      insert into public.collections(id,slug,creator_user_id,title,visibility,public_status)
        values('{PRECISION_GROUP}','data-precision-synthetic','{D.OUTSIDER}',
          'Synthetic private precision group','private','private');
      insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
        select '{PRECISION_GROUP}',id,momo_number,momo_number_hash,momo_provider,'Synthetic receiver'
        from public.profiles where id='{D.OUTSIDER}';commit;"""
    U.psql(db, sql)
    return dict(operator_provider="email" if email_mode else "dated_whatsapp",
        grants_and_approvals_before_fresh_aal2_sessions=True,
        email_delivery_or_signed_jwt_tested=False, member_phone_momo_identity_preserved=True)


def seed_notification_catalog(db):
    # A schema-only clone has no migration seed rows. Restore only the exact
    # source-defined foundation required by the production confirmation trigger;
    # do not turn off that trigger or copy source database catalog contents.
    source = CATALOG_SOURCE.read_text()
    for snippet in ("'collect_group_updates'", "'contribution.confirmed.default'",
                    "'contribution_confirmed', 'contribution_confirmations', 'Contribution confirmed'",
                    "'{{amount}} has been confirmed for {{group}}.'", "'2026-07-04'"):
        if snippet not in source:
            raise RuntimeError("Reviewed notification seed source changed")
    U.psql(db, """begin;
      insert into public.notification_channels(key,label,description,platform,display_order,enabled)
        values('collect_group_updates','Collect group updates',
          'Contribution confirmations, payment reminders, group updates, and security notices.','all',10,true);
      insert into public.notification_event_types(key,preference_key,label,description,default_channel_key,display_order,enabled)
        values('contribution_confirmed','contribution_confirmations','Contribution confirmed',
          'A contribution has been matched and posted.','collect_group_updates',10,true);
      insert into public.notification_templates(key,event_type_key,locale,enabled)
        values('contribution.confirmed.default','contribution_confirmed','en',true);
      insert into public.notification_template_versions(template_key,version,title_template,body_template,status,effective_at,published_at)
        values('contribution.confirmed.default','2026-07-04','Contribution confirmed',
          '{{amount}} has been confirmed for {{group}}.','published','2026-07-04 00:00:00+00','2026-07-04 00:00:00+00');commit;""")


def financial(db):
    result = D.financial(db)
    for name in ("public.ledger_entries", "public.payment_provider_confirmations", "public.provider_finality_requests",
                 "collect_hybrid.momo_journal_lines", "collect_hybrid.momo_balance_snapshots",
                 "public.notification_events", "collect_security.reconciliation_reviews", "public.audit_logs"):
        result[name] = D.scalar(db, "select jsonb_build_object('rows',count(*),'sha256',"
            "encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),"
            f"'sha256'),'hex')) from {name} t;")
    for name in ("collect_ops.exceptions", "collect_ops.exception_observations", "collect_ops.exception_actions",
                 "collect_hybrid.receipt_business_event_heads", "collect_hybrid.receipt_business_events"):
        if D.scalar(db, "select to_jsonb(to_regclass(" + D.literal(name) + ") is not null);"):
            result[name] = D.scalar(db, "select jsonb_build_object('rows',count(*),'sha256',"
                "encode(extensions.digest(coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),"
                f"'sha256'),'hex')) from {name} t;")
    return result


def fixture_rows():
    result = []
    for i in range(65):
        result.append(dict(id=f"99640000-0000-4000-8000-{40001+i:012d}", group=D.GROUP,
            contributor=D.ACTOR if i % 3 == 0 else D.PEER, amount=[1, 2, 2, 5][i % 4],
            date="2026-09-28T12:00:00+00:00" if i % 2 == 0 else "2026-09-29T12:00:00+00:00",
            transaction=f"SYNTH-MECHANICAL-{i:03d}", anonymity="public_id", visible=True))
    result += [
        dict(id="99640000-0000-4000-8000-000000040066", group=D.PUBLIC, contributor=None,
             amount=3, date="2026-09-29T12:00:00+00:00", transaction="SYNTH-PUBLIC-ANONYMOUS", anonymity="anonymous", visible=True),
        dict(id="99640000-0000-4000-8000-000000040067", group=D.FOREIGN, contributor=D.ACTOR,
             amount=7, date="2026-09-28T12:00:00+00:00", transaction="SYNTH-OWN-UNREADABLE", anonymity="anonymous", visible=True),
        dict(id="99640000-0000-4000-8000-000000040068", group=D.FOREIGN, contributor=D.OUTSIDER,
             amount=11, date="2026-09-28T12:00:00+00:00", transaction="SYNTH-HIDDEN-PRIVATE", anonymity="anonymous", visible=False),
        dict(id="99640000-0000-4000-8000-000000040069", group=PRECISION_GROUP, contributor=D.OUTSIDER,
             amount=D.MAX_EXACT, date="2026-09-29T12:00:00+00:00", transaction="SYNTH-EXACT-MAX", anonymity="public_id", visible=False),
    ]
    # The entire actor-visible sum is exactly the interoperable boundary.
    result[64]["amount"] = D.MAX_EXACT - sum(r["amount"] for r in result if r["visible"] and r is not result[64])
    return result


def review_input_sql(row):
    contributor = "null" if row["contributor"] is None else D.literal(row["contributor"]) + "::uuid"
    public_id = "null" if row["contributor"] is None else f"(select public_id from public.profiles where id={contributor})"
    return f"""insert into public.payments(id,collection_id,contributor_user_id,receiver_user_id,
      receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,
      anonymity_choice,contributor_public_id,posted_at,payment_intent_id,parsed_event_id)
      values('{row['id']}','{row['group']}',{contributor},
      (select creator_user_id from public.collections where id='{row['group']}'),
      (select momo_number_hash from public.profiles where id=(select creator_user_id from public.collections where id='{row['group']}')),
      {row['amount']},{D.literal(row['transaction'])},'mtn_momo','manual_admin','review',
      '{row['anonymity']}',{public_id},null,null,null);"""


def post_api_sql(row):
    digest = hashlib.sha256(("SYNTHETIC-MECHANICAL-NOT-PROVIDER:" + row["id"]).encode()).hexdigest()
    return actor(MAKER, MAKER_SID) + f"""
      select public.propose_payment_reconciliation_v2('{row['id']}','{digest}',
        'SYNTHETIC-MECHANICAL-{row['id'][-12:]}','{row['date']}',
        'Synthetic local mechanics input; no independent provider evidence') as review_id \\gset
      reset role;""" + actor(CHECKER, CHECKER_SID) + """
      select public.approve_payment_reconciliation_v2(:'review_id',
        'Synthetic independent checker mechanics; no provider acceptance') as approved \\gset
      reset role;""" + service() + "select public.finalize_approved_reconciliation_v2(:'review_id');reset role;"


def require(ok, detail):
    if not ok:
        raise AssertionError(json.dumps(detail, sort_keys=True))
    return detail


def record_case(report, evidence, name, fn):
    try:
        detail = fn()
        evidence["cases"].append(dict(name=name, status="pass", detail=detail))
        print("PASS " + name, flush=True)
    except Exception as error:
        evidence["cases"].append(dict(name=name, status="failed", error=str(error)))
        print("FAIL " + name + ": " + str(error), flush=True)
    save(report / "result.json", evidence)


def receipt_catalog_check(before, after):
    added = set(after) - set(before)
    removed = set(before) - set(after)
    changed = {key for key in before.keys() & after.keys() if before[key] != after[key]}
    wanted = {"routine:" + identity for identity in RECEIPT_BODIES}
    require(added == {"routine:" + EXACT_HELPER, "constraint:payments.payments_posted_amount_exact_json"}
        and not removed and changed == wanted,
        dict(added=sorted(added), removed=sorted(removed), changed=sorted(changed), expected_changed=sorted(wanted)))
    for key in wanted:
        old, new = dict(before[key]), dict(after[key])
        source, changed_source = old.pop("source"), new.pop("source")
        require(old == new, dict(identity=key, all_attributes_and_acls_preserved=old == new))
        if key == "routine:" + RECEIPT_BODIES[0]:
            source = source.replace("fingerprint:=collect_security.reconciliation_fingerprint(payment_row);",
                "perform collect_member_actions.exact_json_amount(payment_row.amount_rwf);\n fingerprint:=collect_security.reconciliation_fingerprint(payment_row);")
        elif key == "routine:" + RECEIPT_BODIES[1]:
            source = source.replace("perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:' || p_payment_id::text, 0));",
                "perform collect_member_actions.exact_json_amount(p_amount_rwf);\n\n  perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:' || p_payment_id::text, 0));", 1)
        elif key == "routine:" + RECEIPT_BODIES[2]:
            for expression in ("count(*)", "coalesce(sum(amount_rwf), 0)", "coalesce(sum(amount_rwf) filter (where own), 0)"):
                source = source.replace(expression + "::bigint", "collect_member_actions.exact_json_amount(" + expression + ")")
        else:
            source = source.replace("'amount_raised_minor', coalesce(balance.confirmed_rwf, 0)",
                "'amount_raised_minor', collect_member_actions.exact_json_amount(coalesce(balance.confirmed_rwf, 0))")
            source = source.replace("'current_user_balance_minor', coalesce((", "'current_user_balance_minor', collect_member_actions.exact_json_amount(coalesce((")
            source = source.replace("sum(member_balance.confirmed_rwf)::bigint", "sum(member_balance.confirmed_rwf)")
            source = source.replace("      ), 0)\n", "      ), 0))\n")
        require(re.sub(r"\s+", " ", source).strip() == re.sub(r"\s+", " ", changed_source).strip(),
            dict(identity=key, body_changes_limited_to_reviewed_exact_guards=True))
    helper = after["routine:" + EXACT_HELPER]
    require(helper["volatile"] == "i" and helper["definer"] is False and helper["language"] == "plpgsql"
        and helper["arguments"] == "p_amount numeric" and helper["result"] == "bigint"
        and helper["config"] == ['search_path=""']
        and all(x["grantee"] == "OWNER" for x in helper["acl"] or []), dict(actual_helper=helper))
    require(after["constraint:payments.payments_posted_amount_exact_json"]["validated"] is True,
        dict(validated_posted_constraint=True))
    return dict(all_catalog_entries_before=len(before), all_catalog_entries_after=len(after),
        only_four_reviewed_bodies_changed=sorted(wanted), signatures_defaults_acls_attributes_preserved=True,
        only_private_helper_and_validated_posted_constraint_added=True, owner_restore_normalization_explicit=True)


def unsafe_row(number, amount):
    return dict(id=f"99640000-0000-4000-8000-{number:012d}", group=PRECISION_GROUP,
        contributor=D.OUTSIDER, amount=amount, date="2026-09-29T12:00:00+00:00",
        transaction=f"SYNTH-UNSAFE-{number}", anonymity="public_id")


def unsafe_predecessor(report, evidence):
    """A separate clone retains one genuinely posted unsafe pre-migration row.

    The old public reconciliation APIs create it with every production trigger.
    Its failed migration must roll back catalog and rows atomically. Nothing is
    deleted or reclassified to make a migration pass; the entire clone is dropped.
    """
    child = report / "unsafe-predecessor"
    child.mkdir(mode=0o700)
    proof = dict(kind="synthetic_genuine_unsafe_posted_predecessor_atomic_migration_abort", status="running", cases=[])
    try:
        with isolated(child, proof, count=154, latest="20260930230000") as db:
            U.psql(db, D.CANDIDATE.read_text())
            D.seed(db)
            seed_authority(db)
            seed_notification_catalog(db)
            row = unsafe_row(48890, D.MAX_EXACT + 1)
            ack = D.scalar(db, "begin;" + review_input_sql(row) + post_api_sql(row) + "commit;")
            require(ack["payment_status"] == "posted" and ack["replayed"] is False,
                dict(actual_public_api_receipt=ack))
            before = D.clone_snapshot(db)
            before_catalog = catalog(db)
            result = U.psql(db, reviewed_receipt_patch(), False)
            (child / "migration.stdout.log").write_text(result.stdout)
            (child / "migration.stderr.log").write_text(result.stderr)
            detail = dict(payment_input=row, actual_finalizer_receipt=ack,
                sql_error=result.stderr[-3000:], catalog_unchanged=before_catalog == catalog(db),
                rows_and_controls_unchanged=before == D.clone_snapshot(db),
                genuine_prepatch_api_posting=True, provider_truth=False, unsafe_status_directly_written=False,
                production_triggers_preserved=True)
            proof["actual_proof"] = detail
            save(child / "before.json", before)
            require(result.returncode != 0 and '23514:' in result.stderr
                and 'payments_posted_amount_exact_json' in result.stderr
                and detail["catalog_unchanged"] and detail["rows_and_controls_unchanged"], detail)
            proof["status"] = "pass_scoped"
    except Exception as error:
        proof.update(status="failed", failure=str(error), traceback=traceback.format_exc())
    finally:
        save(child / "result.json", proof)
    evidence["unsafe_predecessor"] = dict(path=str(child.relative_to(ROOT)),
        result_sha256=hashlib.sha256((child / "result.json").read_bytes()).hexdigest(),
        status=proof["status"], isolated_database_removed=proof.get("isolated_database_removed"),
        all_source_tables_catalog_cron_preserved=proof.get("all_source_tables_catalog_cron_preserved"),
        recorder_sources_unchanged=proof.get("recorder_sources_unchanged"), source_rows_copied=False)
    return require(proof["status"] == "pass_scoped", evidence["unsafe_predecessor"])


def run(db, report, evidence, mode, stages):
    def case(name, fn):
        record_case(report, evidence, name, fn)

    installed = api_definitions("postgres")
    cloned = api_definitions(db)
    save(report / "installed-api-definitions.json", installed)
    save(report / "clone-before-patch-api-definitions.json", cloned)
    case("schema clone preserves actual API bodies attributes and application ACLs", lambda: require(installed == cloned, dict(equal=installed == cloned)))
    source_catalog, cloned_catalog = catalog("postgres"), catalog(db)
    save(report / "installed-full-normalized-catalog.json", source_catalog)
    save(report / "clone-before-patch-full-normalized-catalog.json", cloned_catalog)
    case("schema clone preserves exhaustive normalized catalog and every application API ACL", lambda: require(
        source_catalog == cloned_catalog, dict(equal=source_catalog == cloned_catalog,
            source_count=len(source_catalog), clone_count=len(cloned_catalog),
            changed=[key for key in source_catalog.keys() & cloned_catalog.keys() if source_catalog[key] != cloned_catalog[key]][:30],
            source_only=sorted(source_catalog.keys()-cloned_catalog.keys()), clone_only=sorted(cloned_catalog.keys()-source_catalog.keys()),
            normalization="No-owner restore; OWNER ACL identities normalized; PUBLIC/anon/authenticated/service_role ACLs compared; internal platform-role grants not certified")))
    if stages:
        import staged_bundle_upgrade_uat as B
        B.seed_schema_clone_permission_catalog(db, report, evidence)
        for path, body in stages:
            if path.name >= D.CANDIDATE.name:
                break
            U.psql(db, body.decode())
    patch = D.CANDIDATE.read_bytes()
    if hashlib.sha256(patch).hexdigest() != PATCH_SHA:
        raise RuntimeError("Reviewed exact234000 patch changed")
    U.psql(db, patch.decode())
    evidence["candidate"] = dict(path=str(D.CANDIDATE.relative_to(ROOT)), sha256=PATCH_SHA,
        installed_in_shared_database=False, applied_only_to_disposable_clone=True)
    save(report / "clone-after-patch-api-definitions.json", api_definitions(db))
    D.seed(db)
    evidence["operator_fixture_authority"] = seed_authority(db)
    if mode == "full-current":
        ack = D.scalar(db, "begin;" + actor(MAKER,MAKER_SID) +
            "select public.admin_set_operator_email_mode_v1('Synthetic mechanical fixture email cutover');commit;")
        case("actual approved fresh email operator performs genuine public email cutover", lambda: require(
            ack == dict(ok=True, mode='email', replay=False), dict(actual_api_ack=ack,
                direct_policy_override=False, signed_jwt_or_email_delivery_tested=False)))
    seed_notification_catalog(db)
    evidence['fixture_catalog_source'] = dict(path=str(CATALOG_SOURCE.relative_to(ROOT)),
        sha256=hashlib.sha256(CATALOG_SOURCE.read_bytes()).hexdigest(), seed='Only exact contribution-confirmed source catalog rows',
        source_database_rows_copied=False, production_triggers_preserved=True)
    if mode != "baseline234":
        previously_approved = []
        for number, amount in ((48801, D.MAX_EXACT + 1), (48802, 9223372036854775807)):
            row = unsafe_row(number, amount)
            review_id = D.scalar(db, "begin;" + review_input_sql(row) + approve_api_sql(row) +
                "select to_jsonb(id) from collect_security.reconciliation_reviews where payment_id=" + D.literal(row["id"]) + ";commit;")
            previously_approved.append(dict(input=row, review_id=review_id))
        before_catalog = catalog(db)
        before_rows = D.clone_snapshot(db)["tables"]
        U.psql(db, reviewed_receipt_patch())
        after_catalog = catalog(db)
        save(report / "clone-before235-full-catalog.json", before_catalog)
        save(report / "clone-after235-full-catalog.json", after_catalog)
        evidence["receipt_candidate"] = dict(path=str(RECEIPT_PATCH.relative_to(ROOT)), sha256=RECEIPT_PATCH_SHA,
            installed_in_shared_database=False, applied_only_to_disposable_clone=True)
        case("exact235 preserves all catalog contracts except reviewed four bodies and private bounds", lambda:
            receipt_catalog_check(before_catalog, after_catalog))
        case("exact235 retains legitimate and unsafe REVIEW observations without row rewriting", lambda: require(
            before_rows == D.clone_snapshot(db)["tables"], dict(all_table_rows_preserved=True, unsafe_review_observations_retained=True)))
        for approved in previously_approved:
            def canonical_denied(approved=approved):
                before = D.clone_snapshot(db)
                result = U.psql(db, "begin;" + service() +
                    "select public.finalize_approved_reconciliation_v2(" + D.literal(approved["review_id"]) + ");commit;", False)
                return require(result.returncode != 0 and '22023:' in result.stderr
                    and 'financial_amount_not_exact' in result.stderr and before == D.clone_snapshot(db),
                    dict(amount=approved["input"]["amount"], actual_service_public_finalizer=True,
                        exact_denial_before_financial_mutation=True, all_rows_and_controls_preserved=before == D.clone_snapshot(db),
                        sql_error=result.stderr[-3000:]))
            case("canonical confirmation rejects previously approved unsafe amount " + str(approved["input"]["amount"]), canonical_denied)
        for amount in ("0", "1", str(D.MAX_EXACT)):
            case("private exact helper owner arithmetic preserves " + amount, lambda amount=amount: require(
                D.scalar(db, "select to_jsonb(collect_member_actions.exact_json_amount(" + amount + "::numeric));") == int(amount),
                dict(amount=amount, exact_integer=True)))
        for amount in ("null", "-1", "0.5", str(D.MAX_EXACT+1), "'NaN'", "'Infinity'", "'-Infinity'"):
            case("private exact helper refuses nonexact arithmetic " + amount, lambda amount=amount: require(
                (result := U.psql(db, "select collect_member_actions.exact_json_amount(" + amount + "::numeric);", False)).returncode != 0
                and '22023:' in result.stderr and 'financial_amount_not_exact' in result.stderr,
                dict(sql_error=result.stderr[-1500:], amount=amount)))
        for role in ("anon", "authenticated", "service_role"):
            case("private exact helper is inaccessible to direct API role " + role, lambda role=role: U.expected_error(db,
                "select collect_member_actions.exact_json_amount(1::numeric)", "42501", role=role))
        if stages:
            for path, body in stages:
                if path.name > RECEIPT_PATCH.name:
                    U.psql(db, body.decode())
            evidence["full_current_stage_sha256"] = {path.name: hashlib.sha256(body).hexdigest() for path, body in stages}
    rows = fixture_rows()
    U.psql(db, "begin;" + "".join(review_input_sql(row) for row in rows) + "commit;")
    before_posting = financial(db)
    receipts = []
    for row in rows:
        ack = D.scalar(db, "begin;" + post_api_sql(row) + "commit;")
        if ack.get("payment_status") != "posted" or ack.get("replayed") is not False:
            raise AssertionError("Production finalizer did not post synthetic fixture: " + json.dumps(ack))
        receipts.append(dict(input=row, receipt=ack))
    save(report / "synthetic-reconciliation-receipts.json", receipts)
    # A review-only candidate must never appear among confirmed history rows.
    unposted = dict(id="99640000-0000-4000-8000-000000040070", group=D.GROUP,
                   contributor=D.ACTOR, amount=13, transaction="SYNTH-NOT-CONFIRMED", anonymity="public_id")
    U.psql(db, "begin;" + review_input_sql(unposted) + "commit;")
    public_ids = D.scalar(db, "select jsonb_object_agg(id::text,public_id) from public.profiles;")
    for row in rows:
        row["own"] = row["contributor"] == D.ACTOR
        row["label"] = "You" if row["own"] else "Collect ID " + str(public_ids[row["contributor"]]) if row["anonymity"] == "public_id" else "Anonymous supporter"
        row["readable"] = row["group"] in (D.GROUP, D.PUBLIC, D.NO_ROUTE)
        row["title"] = {D.GROUP: "Synthetic private data", D.PUBLIC: "Synthetic public data", D.FOREIGN: "Synthetic foreign private", PRECISION_GROUP: "Synthetic private precision group"}[row["group"]]
    case("69 genuine reviewed synthetic postings retain confirmed journal and balance triggers", lambda: require(
        len(receipts) == 69 and (actual := D.scalar(db, """select jsonb_build_object(
          'posted',(select count(*) from public.payments where status='posted'),
          'confirmations',(select count(*) from public.payment_provider_confirmations),
          'ledger',(select count(*) from public.ledger_entries),
          'journal',(select count(*) from collect_hybrid.momo_journal_entries),
          'unbalanced',(select count(*) from collect_hybrid.momo_journal_entries e where
             (select sum(case when direction='debit' then amount_rwf else -amount_rwf end)
                from collect_hybrid.momo_journal_lines l where l.journal_entry_id=e.id)<>0));""")) ==
        dict(posted=69, confirmations=69, ledger=138, journal=69, unbalanced=0),
        dict(actual=actual, fixture_provenance="SYNTHETIC mechanical review inputs via genuine public API/trigger route")))
    if mode == "full-current":
        operational = D.scalar(db, """select jsonb_build_object(
          'source_payment_count',(select count(*) from collect_ops.exceptions where source_kind='payment'),
          'observation_count',(select count(*) from collect_ops.exception_observations),
          'action_count',(select count(*) from collect_ops.exception_actions),
          'posted_resolved_count',(select count(*) from collect_ops.exceptions e join public.payments p on p.id=e.source_id
            where e.source_kind='payment' and e.reason_code='VERIFICATION_PENDING' and p.status='posted' and not e.active and e.revision>=2),
          'posted_active_count',(select count(*) from collect_ops.exceptions e join public.payments p on p.id=e.source_id
            where e.source_kind='payment' and p.status='posted' and e.active),
          'unposted_pending_count',(select count(*) from collect_ops.exceptions e join public.payments p on p.id=e.source_id
            where e.source_kind='payment' and e.reason_code='VERIFICATION_PENDING' and p.transaction_id='SYNTH-NOT-CONFIRMED' and e.active),
          'payment_trigger_enabled',(select tgenabled='O' from pg_trigger where tgrelid='public.payments'::regclass and tgname='zzzz_operational_payment'),
          'unposted_financial_rows',(select count(*) from public.payments where status='posted' and posted_at is null));""")
        save(report / "actual-operational-capture-state.json", operational)
        case("current Ops capture triggers preserve genuine posted financial mechanics", lambda: require(
            operational["payment_trigger_enabled"] and operational["action_count"] == 0
            and operational["posted_resolved_count"] == 69 and operational["posted_active_count"] == 0
            and operational["unposted_pending_count"] == 1
            and operational["unposted_financial_rows"] == 0,
            dict(actual=operational, operational_policy_override=False, actual_posting_count=69,
                operational_capture_rwanda_sms_scope_retained=True)))
    evidence["financial_before_legitimate_posting"] = before_posting
    baseline = financial(db)
    save(report / "financial-after-fixture-before-reads.json", baseline)
    case("synthetic posting is a deliberate financial change, not provider settlement evidence", lambda: require(
        baseline != before_posting, dict(financial_changed=True, provider_called=False, independent_provider_truth=False)))

    def history(group=None, query="", sort="newest", cursor=None, limit=7, uid=D.ACTOR, sid=D.SESSION):
        text = f"select public.list_current_member_history_page({'null' if group is None else D.literal(group)+'::uuid'}," + \
               f"{D.literal(query)},{D.literal(sort)},{'null' if cursor is None else D.literal(json.dumps(cursor))+'::jsonb'},{limit});"
        return U.call(db, text, uid, sid)

    def matched(group=None, query=""):
        q = query.lower().strip()
        return [r for r in rows if r["visible"] and (group is None or r["group"] == group)
                and (not q or q in r["label"].lower() or (r["own"] and q in r["transaction"].lower())
                     or (r["readable"] and q in r["title"].lower()))]

    def expected_order(items, sort):
        def key(row):
            timestamp = dt.datetime.fromisoformat(row["date"]).timestamp()
            if sort == "oldest":
                return (timestamp, row["id"])
            if sort == "highest":
                return (-row["amount"], -timestamp, row["id"])
            if sort == "lowest":
                return (row["amount"], -timestamp, row["id"])
            return (-timestamp, row["id"])
        return sorted(items, key=key)

    exported_pages = []
    def walk(group=None, query="", sort="newest", limit=7):
        wanted = expected_order(matched(group, query), sort)
        ids = ["momo:" + row["id"] for row in wanted]
        amount = sum(row["amount"] for row in wanted)
        own_amount = sum(row["amount"] for row in wanted if row["own"])
        own_groups = sorted(set(row["group"] for row in wanted if row["own"]))
        cursor, revision, seen, windows = None, None, [], 0
        while True:
            started = time.monotonic()
            page = history(group, query, sort, cursor, limit)
            windows += 1
            offset = len(seen)
            got = [row["payment_id"] for row in page["items"]]
            require(got == ids[offset:offset+limit] and page["total_count"] == len(wanted)
                    and page["totals"] == (dict(RWF=amount) if wanted else {})
                    and page["own_totals"] == (dict(RWF=own_amount) if wanted else {})
                    and page["own_collection_ids"] == own_groups
                    and (revision is None or revision == page["revision"]),
                    dict(expected=ids[offset:offset+limit], actual=page, expected_total=amount, expected_own=own_amount))
            for wire, expected in zip(page["items"], wanted[offset:offset+limit]):
                require(wire["collection_id"] == expected["group"] and wire["amount_minor"] == expected["amount"]
                        and wire["is_current_user_contribution"] == expected["own"]
                        and wire["supporter_label"] == expected["label"]
                        and wire["transaction_id"] == (expected["transaction"] if expected["own"] else None)
                        and dt.datetime.fromisoformat(wire["posted_at"]) == dt.datetime.fromisoformat(expected["date"]),
                        dict(actual=wire, expected=expected))
            exported_pages.append(dict(query=dict(collection_id=group, search=query, sort=sort), limit=limit,
                requested_cursor=cursor, response=page, seconds=round(time.monotonic()-started, 6)))
            revision = page["revision"]
            seen += got
            cursor = page["next_cursor"]
            if len(seen) < len(wanted):
                require(cursor == dict(revision=revision, after=seen[-1]), dict(cursor=cursor, expected_after=seen[-1]))
            else:
                require(cursor is None, dict(cursor=cursor, loaded=len(seen)))
                break
            require(windows <= len(wanted)+1, dict(windows=windows))
        require(seen == ids and len(set(seen)) == len(seen), dict(expected=ids, actual=seen))
        return dict(total_count=len(wanted), total_amount=amount, own_amount=own_amount, windows=windows,
                    limit=limit, exact_id_order=seen, full_aggregate_not_page_sum=True)

    for sort in ("newest", "oldest", "highest", "lowest"):
        case("full nonzero history typed tie order and complete pagination " + sort,
             lambda sort=sort: walk(sort=sort))
        case("group-scoped history full count/totals tie order " + sort,
             lambda sort=sort: walk(group=D.GROUP, sort=sort, limit=2))
    for query in ("You", "  yOu  ", "Collect ID " + str(public_ids[D.PEER]), "Anonymous supporter",
                  "synthetic private data", "Synthetic public data", "SYNTH-OWN-UNREADABLE",
                  "SYNTH-MECHANICAL-001", "SYNTH-HIDDEN-PRIVATE", "Synthetic foreign private",
                  "SYNTH-NOT-CONFIRMED", "%' OR true --"):
        case("matched history filters exact complete count/sums/privacy " + query, lambda query=query: walk(query=query))
    for group in (D.FOREIGN, D.PUBLIC, D.NO_ROUTE, D.MISSING):
        case("history exact ownership selected group " + group, lambda group=group: walk(group=group))
    case("known zero history totals differ from nonzero and inaccessible group", lambda: require(
        history(D.NO_ROUTE)["totals"] == {} and history(D.GROUP)["totals"]["RWF"] > 0,
        dict(zero=history(D.NO_ROUTE), unavailable=history(D.MISSING))))
    first = history(limit=2)
    for cursor, name in [
        (dict(revision="0"*32, after=first["items"][-1]["payment_id"]), "stale revision"),
        (dict(revision=first["revision"], after="momo:"+D.MISSING), "forged anchor"),
        (dict(revision=first["revision"], after="momo:"+rows[67]["id"]), "foreign hidden anchor"),
    ]:
        def denied_cursor(cursor=cursor):
            return U.expected_error(db, "select public.list_current_member_history_page(null,'','newest'," +
                D.literal(json.dumps(cursor)) + "::jsonb,2)", "P0001", uid=D.ACTOR, sid=D.SESSION)
        case("actual history rejects " + name, denied_cursor)
    case("changed filter rejects borrowed continuation revision", lambda: U.expected_error(db,
        "select public.list_current_member_history_page(null,'You','newest',"+
        D.literal(json.dumps(first["next_cursor"]))+"::jsonb,2)", "P0001", uid=D.ACTOR, sid=D.SESSION))

    balances = U.call(db, "select public.list_current_member_collection_balances()", D.ACTOR, D.SESSION)
    by_group = {r["collection_id"]: r for r in balances}
    case("nonzero balance projections are complete sums, supporters unknown distinct from zero", lambda: require(
        by_group[D.GROUP]["balances"] == [dict(currency="RWF", amount_raised_minor=sum(r["amount"] for r in rows if r["group"] == D.GROUP),
                current_user_balance_minor=sum(r["amount"] for r in rows if r["group"] == D.GROUP and r["own"]))]
        and by_group[D.GROUP]["supporter_count"] == 2
        and by_group[D.PUBLIC]["supporter_count"] is None
        and by_group[D.NO_ROUTE]["supporter_count"] == 0
        and by_group[D.NO_ROUTE]["balances"] == [dict(currency='RWF',amount_raised_minor=0,current_user_balance_minor=0)]
        and D.FOREIGN not in by_group and PRECISION_GROUP not in by_group,
        dict(actual=balances)))
    max_page = history(PRECISION_GROUP, limit=100, uid=D.OUTSIDER, sid=OUTSIDER_SID)
    exported_pages.append(dict(query=dict(collection_id=PRECISION_GROUP, search="", sort="newest"),
        limit=100, requested_cursor=None, response=max_page))
    case("genuine max-exact individual payment and max-exact aggregate JSON receipt", lambda: require(
        max_page["total_count"] == 1 and max_page["items"][0]["amount_minor"] == D.MAX_EXACT
        and max_page["totals"] == dict(RWF=D.MAX_EXACT) and max_page["own_totals"] == dict(RWF=D.MAX_EXACT),
        dict(actual=max_page)))
    case("genuine minimum positive payment remains exact", lambda: require(
        any(r["amount"] == 1 for r in matched()), dict(minimum=min(r["amount"] for r in matched()))))
    save(report / "actual-member-history-pages.json", exported_pages)
    save(report / "actual-member-balances.json", balances)
    plans = []
    for sort in ('newest','oldest','highest','lowest'):
        for query in ('','You'):
            # set_config emits a claim JSON before EXPLAIN's multiline array;
            # suppress only that fixture output with psql's gset, not execution.
            auth_sql = U.auth(D.ACTOR,D.SESSION).replace(',true);', ',true) as claims \\gset\n')
            plan = json.loads(U.psql(db, 'begin;'+auth_sql+
                "explain(analyze,buffers,format json) select public.list_current_member_history_page(null,"+
                D.literal(query)+','+D.literal(sort)+',null,7);commit;').stdout)
            plans.append(dict(sort=sort,query=query,limit=7,plan=plan,
                limitation='Wrapper plan measures real SQL execution on69 synthetic posted rows; it does not expose nested function plan or certify production scale.'))
    save(report/'actual-history-wrapper-plans.json', plans)
    case('actual positive history SQL wrapper execution measurements all four sorts and own filter', lambda: require(
        len(plans)==8 and all(p['plan'][0]['Execution Time']>=0 for p in plans),
        dict(measurements=[dict(sort=p['sort'],query=p['query'],server_execution_ms=p['plan'][0]['Execution Time']) for p in plans],
             production_scale_acceptance=False,nested_query_plan_certified=False)))
    case("all history/query/balance reads preserve legitimate financial fingerprints", lambda: require(
        (after := financial(db)) == baseline, dict(before=baseline, after=after)))

    # These probes are complete genuine reconciliation workflows in a single
    # transaction, then rollback. A rejected assertion is retained as evidence
    # of an actual exposed bound gap; it never becomes settlement acceptance.
    for amount in (0, -1, D.MAX_EXACT + 1, 9223372036854775807):
        row = dict(id="99640000-0000-4000-8000-000000049901", group=PRECISION_GROUP,
            contributor=D.OUTSIDER, amount=amount, date="2026-09-29T12:00:00+00:00",
            transaction="SYNTH-UNSAFE-PRECISION", anonymity="public_id")
        def boundary(row=row, amount=amount):
            before = D.clone_snapshot(db)
            r = U.psql(db, "begin;"+review_input_sql(row)+post_api_sql(row)+
                actor(D.OUTSIDER,OUTSIDER_SID,"aal1")+
                f"select public.list_current_member_history_page('{PRECISION_GROUP}','','newest',null,2);rollback;", False)
            require(before == D.clone_snapshot(db), dict(all_rows_and_controls_preserved=True))
            actual = None
            if r.returncode == 0:
                actual = json.loads(r.stdout.strip().splitlines()[-1])
            bound_denial = r.returncode != 0 and (
                (amount <= 0 and '23514:' in r.stderr) or
                (amount > D.MAX_EXACT and ('23514:' in r.stderr or '22023:' in r.stderr) and 'exact' in r.stderr))
            detail = dict(amount=amount, rejected=r.returncode != 0, exact_bound_denial=bound_denial, actual_response=actual,
                sql_error=r.stderr[-2500:] if r.returncode else None, rolled_back=True,
                only_synthetic_mechanical_inputs=True)
            evidence.setdefault("precision_boundary_observations", []).append(detail)
            return require(bound_denial, detail)
        case("review input plus genuine finalizer refuses nonexact money " + str(amount), boundary)
    extra = dict(id="99640000-0000-4000-8000-000000049902", group=D.GROUP, contributor=D.ACTOR,
        amount=1, date="2026-09-29T12:00:00+00:00", transaction="SYNTH-AGGREGATE-OVERFLOW", anonymity="public_id")
    def aggregate_boundary():
        before = D.clone_snapshot(db)
        r = U.psql(db, "begin;"+review_input_sql(extra)+post_api_sql(extra)+
            actor(D.ACTOR,D.SESSION,"aal1")+"select public.list_current_member_history_page(null,'','newest',null,2);rollback;", False)
        require(before == D.clone_snapshot(db), dict(all_rows_and_controls_preserved=True))
        page = None if r.returncode else json.loads(r.stdout.strip().splitlines()[-1])
        detail = dict(rejected=r.returncode != 0, actual_response=page, rolled_back=True,
            sql_error=r.stderr[-2500:] if r.returncode else None)
        evidence["aggregate_boundary_observation"] = detail
        return require((r.returncode != 0 and '22023:' in r.stderr and 'exact' in r.stderr)
            or (page is not None and page["totals"]["RWF"] <= D.MAX_EXACT), detail)
    case("history server does not publish nonexact aggregate JSON", aggregate_boundary)
    if mode != "baseline234":
        for number, group, amount, uid, sid, sql, description in (
            (49903, D.GROUP, 11, D.ACTOR, D.SESSION, "select public.list_current_member_collection_balances();", "visible collection full confirmed aggregate"),
            (49904, PRECISION_GROUP, 1, D.OUTSIDER, OUTSIDER_SID, "select public.list_current_member_collection_balances();", "own and group confirmed aggregate"),
            (49905, PRECISION_GROUP, 1, D.OUTSIDER, OUTSIDER_SID,
             f"select public.list_current_member_history_page('{PRECISION_GROUP}','','newest',null,2);", "own and group history aggregate"),
        ):
            row = unsafe_row(number, amount)
            row.update(group=group, contributor=uid)
            def summary_denied(row=row, uid=uid, sid=sid, sql=sql, description=description):
                before = D.clone_snapshot(db)
                result = U.psql(db, "begin;" + review_input_sql(row) + post_api_sql(row) + actor(uid,sid,"aal1") + sql + "rollback;", False)
                return require(result.returncode != 0 and '22023:' in result.stderr
                    and 'financial_amount_not_exact' in result.stderr and before == D.clone_snapshot(db),
                    dict(description=description, each_individual_amount_exact=True,
                        expected_full_aggregate=D.MAX_EXACT+1, actual_sql_error=result.stderr[-3000:],
                        all_rows_controls_and_operational_capture_preserved=before == D.clone_snapshot(db)))
            case("server rejects nonexact " + description + " before JSON", summary_denied)
    evidence["financial_after"] = financial(db)
    case("precision probes rollback all financial changes and controls", lambda: require(
        evidence["financial_after"] == baseline, dict(equal=True)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--mode", choices=("baseline234", "candidate235", "full-current"), default="candidate235")
    parser.add_argument("--reviewed-stages", type=Path,
        help="Terminal root13-stage result.json; required only for full-current mode")
    args = parser.parse_args()
    report = Path(args.output).resolve()
    if report.exists():
        raise RuntimeError("Fresh evidence directory required")
    report.mkdir(parents=True)
    inputs = [Path(__file__).resolve(), Path(D.__file__).resolve(), ROOT / "scripts/tests/local_schema_uat.py",
        ROOT / "scripts/tests/local_offline_verification.py", ROOT / "scripts/tests/shadow_supervisor_uat.py", D.CANDIDATE, CATALOG_SOURCE]
    if hashlib.sha256(D.CANDIDATE.read_bytes()).hexdigest() != PATCH_SHA:
        raise RuntimeError("Reviewed exact234000 patch changed")
    stages = []
    reviewed = None
    if args.mode != "baseline234":
        reviewed_receipt_patch()
        inputs.append(RECEIPT_PATCH)
    if args.mode == "full-current":
        import staged_bundle_upgrade_uat as B
        if args.reviewed_stages is None:
            parser.error("full-current requires the terminal root-reviewed stage result")
        review_path = args.reviewed_stages.resolve()
        if not review_path.is_relative_to(ROOT / "docs/release"):
            parser.error("Root-reviewed release packet required")
        reviewed = json.loads(review_path.read_bytes())
        expected = {name: hashlib.sha256((ROOT/"supabase/migrations"/name).read_bytes()).hexdigest() for name in B.STAGES}
        if reviewed.get("status") != "pass" or expected != reviewed.get("source_migration_sha256") \
            or not reviewed.get("all_source_tables_catalog_cron_preserved") \
            or not reviewed.get("isolated_database_removed") or len(expected) != 13:
            raise RuntimeError("Terminal exact root13-stage preserved-source proof required")
        stages = [(ROOT/"supabase/migrations"/name, (ROOT/"supabase/migrations"/name).read_bytes()) for name in B.STAGES]
        inputs += [Path(B.__file__).resolve(), B.PERMISSION_CATALOG_SOURCE, review_path] + [path for path,body in stages]
        stage_dir = report/"reviewed-stage-sources"
        stage_dir.mkdir(mode=0o700)
        for path, body in stages:
            (stage_dir/path.name).write_bytes(body)
    evidence = dict(kind="installed154_plus_exact234000_synthetic_positive_history_mechanics", mode=args.mode, status="running", cases=[],
        started_at=dt.datetime.now(dt.timezone.utc).isoformat(), source_database_written=False,
        hosted_called=False, provider_called=False, current_server_acceptance=False,
        signed_jwt_tested=False, native_device_attestation_tested=False, independent_provider_truth=False,
        source_inputs={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
    if reviewed is not None:
        evidence["reviewed_stage_packet"] = dict(path=str(review_path.relative_to(ROOT)),
            sha256=hashlib.sha256(review_path.read_bytes()).hexdigest(), source_migration_sha256=expected)
    captured = report / "runner-sources"
    captured.mkdir(mode=0o700)
    for path in inputs:
        relative = path.relative_to(ROOT)
        body = path.read_bytes()
        if hashlib.sha256(body).hexdigest() != evidence["source_inputs"][str(relative)]:
            raise RuntimeError("Runner input changed during immutable capture")
        target = captured / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    U.SQL_LOG = report / "queries.log"
    try:
        if args.mode != "baseline234":
            record_case(report, evidence, "exact235 aborts atomically on genuine unsafe POSTED predecessor", lambda:
                unsafe_predecessor(report, evidence))
        with isolated(report, evidence, count=154, latest="20260930230000") as db:
            run(db, report, evidence, args.mode, stages)
        evidence["status"] = "failed" if any(c["status"] == "failed" for c in evidence["cases"]) else "pass_scoped"
    except Exception as error:
        evidence.update(status="failed", failure=str(error), traceback=traceback.format_exc())
    finally:
        U.SQL_LOG = None
        evidence["completed_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        evidence["source_inputs_unchanged"] = all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest() == h
            for p,h in evidence["source_inputs"].items())
        evidence["artifact_sha256"] = {p.name:hashlib.sha256(p.read_bytes()).hexdigest()
            for name in ("actual-member-history-pages.json","actual-member-balances.json",
                         "synthetic-reconciliation-receipts.json","financial-after-fixture-before-reads.json",
                         "actual-history-wrapper-plans.json")
            if (p:=report/name).is_file()}
        evidence["remaining_acceptance"] = ["Current installed/hosted server alignment is not inferred from a patched disposable154 clone.",
            "Synthetic reconciled inputs prove local mechanics; independent provider/native/device/settlement acceptance remains separate."]
        save(report / "result.json", evidence)
    print(json.dumps({k:evidence.get(k) for k in ("status","failure","all_source_tables_catalog_cron_preserved","isolated_database_removed")}))
    return int(evidence["status"] == "failed")


if __name__ == "__main__":
    raise SystemExit(main())
