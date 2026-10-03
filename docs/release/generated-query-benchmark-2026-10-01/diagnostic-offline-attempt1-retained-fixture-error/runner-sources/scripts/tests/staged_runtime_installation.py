#!/usr/bin/env python3
"""Root-owned atomic installation/rehearsal for reviewed offline151–154.

Before COMMIT, compare every original row and catalog object, attribute the four
151 append-only rows to this XID, and validate152's private telemetry boundary.
No URL, alternative database, role or arbitrary changed-table scope is accepted.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("offline", Path(__file__).with_name("local_offline_verification.py"))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
UPGRADES = {
    "20260930200000": (150, "20260930180000", "admin_automation_navigation"),
    "20260930210000": (151, "20260930200000", "shadow_supervisor_runs"),
    "20260930220000": (152, "20260930210000", "runtime_control_authority"),
    "20260930230000": (153, "20260930220000", "group_share_rotation_receipts"),
}
NAV_APPEND = ("public.admin_navigation_items", "collect_security.runtime_control_heads",
              "collect_security.runtime_control_events", "public.app_realtime_events")
SHADOW_TABLES = tuple("collect_security.shadow_supervisor_" + x for x in ("runs", "lease", "samples"))
SHADOW_FUNCTIONS = tuple("collect_security." + x for x in (
    "require_shadow_actor", "guard_shadow_sample", "guard_shadow_run", "shadow_run_json", "require_shadow_health")) + tuple(
    "public." + x + "_collect_shadow_run_v1" for x in ("begin", "sample", "finish", "get")) + ("public.list_collect_shadow_runs_v1",)
AUTH_FUNCTIONS = ("collect_security.runtime_control_actor", "public.admin_list_runtime_control_events_v1")
SHARE_TABLES = ("collect_member_actions.group_share_rotations",)
SHARE_NEW_FUNCTIONS = ("collect_member_actions.guard_group_share_rotation",
                       "collect_member_actions.require_group_share_actor", "public.rotate_group_share_code_v2")
SHARE_CHANGED_FUNCTIONS = ("public.get_group_share_code", "public.rotate_group_share_code")


def catalog_query() -> str:
    names = ",".join(R.literal(x) for x in R.SCHEMAS)
    return f"""with objects(family,object_name,identity,body) as (
      select 'schema',n.nspname::text,n.nspname::text,to_jsonb(n)-array['oid'] from pg_namespace n where n.nspname in ({names})
      union all select 'relation',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname,
        jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'kind',c.relkind)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_index ix on ix.indexrelid=c.oid
        left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace where n.nspname in ({names})
      union all select 'column',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname||':'||a.attname,
        jsonb_build_object('type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
        left join pg_index ix on ix.indexrelid=c.oid left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace
        where n.nspname in ({names}) and a.attnum>0 and not a.attisdropped
      union all select 'routine',n.nspname||'.'||p.proname,n.nspname||'.'||p.proname||':'||pg_get_function_identity_arguments(p.oid),
        jsonb_build_object('owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef,'volatile',p.provolatile,'result',p.prorettype)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ({names})
      union all select 'trigger',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||t.tgname,
        jsonb_build_object('enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
      union all select 'constraint',n.nspname||'.'||cl.relname,n.nspname||'.'||cl.relname||':'||c.conname,to_jsonb(pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=c.connamespace where n.nspname in ({names})
      union all select 'policy',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||p.polname,
        jsonb_build_object('roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ({names})
    ) select * from objects"""


def array(values) -> str:
    return "array[" + ",".join(R.literal(x) for x in values) + "]::text[]"


def transaction(source: str, version: str, *, commit: bool) -> str:
    count, latest, name = UPGRADES[version]
    stripped = re.sub(r"\A\s*begin\s*;", "", source, count=1, flags=re.I)
    if stripped == source or not re.search(r"commit;\s*\Z", stripped, flags=re.I):
        raise RuntimeError("Reviewed canonical explicit transaction required")
    stripped = re.sub(r"commit;\s*\Z", "", stripped, count=1, flags=re.I)
    names = ",".join(R.literal(x) for x in R.SCHEMAS)
    allowed_append = NAV_APPEND if version == "20260930200000" else ()
    allowed_new = {"20260930210000": SHADOW_TABLES + SHADOW_FUNCTIONS,
                   "20260930230000": SHARE_TABLES + SHARE_NEW_FUNCTIONS}.get(version, ())
    allowed_changed = {"20260930220000": AUTH_FUNCTIONS,
                       "20260930230000": SHARE_CHANGED_FUNCTIONS}.get(version, ())
    body = f"""begin isolation level serializable;
    do $$begin if current_user<>'postgres' or current_database()<>'postgres'
      or (select rolsuper from pg_roles where rolname=current_user)
      or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
      or (select count(*) from supabase_migrations.schema_migrations)<>{count}
      or (select max(version) from supabase_migrations.schema_migrations)<>{R.literal(latest)} then
      raise exception 'Exact offline sequential upgrade required';end if;end$$;
    create temp table collect_upgrade_rows(table_name text,rowdata jsonb,n bigint) on commit drop;
    create temp table collect_upgrade_counts(table_name text,n bigint) on commit drop;
    create temp table collect_upgrade_catalog on commit drop as {catalog_query()};
    do $$begin if exists(select 1 from pg_temp.collect_upgrade_catalog group by family,identity having count(*)<>1)
      or exists(select 1 from pg_temp.collect_upgrade_catalog where identity is null or object_name is null) then
      raise exception 'Catalog identity collision';end if;end$$;
    do $$declare t record;begin
      for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ({names}) and c.relkind in ('r','p') loop
        execute format('insert into pg_temp.collect_upgrade_rows select %L,to_jsonb(t),count(*) from %I.%I t group by to_jsonb(t)',t.nspname||'.'||t.relname,t.nspname,t.relname);
        execute format('insert into pg_temp.collect_upgrade_counts select %L,count(*) from %I.%I',t.nspname||'.'||t.relname,t.nspname,t.relname);
      end loop;
    end$$;
    {stripped}
    insert into supabase_migrations.schema_migrations(version,name,statements)
      values({R.literal(version)},{R.literal(name)},array[{R.literal(source)}]);
    create temp table collect_upgrade_catalog_after on commit drop as {catalog_query()};
    do $$declare t record;missing boolean;delta bigint;new_xid bigint;append_count bigint:=0;begin
      for t in select * from pg_temp.collect_upgrade_counts loop
        execute format('select exists(select 1 from pg_temp.collect_upgrade_rows b where b.table_name=%L and b.n>(select count(*) from %s t where to_jsonb(t)=b.rowdata))',t.table_name,t.table_name) into missing;
        if missing then raise exception 'Original row removed or changed in %',t.table_name;end if;
        execute format('select count(*)-%s from %s',t.n,t.table_name) into delta;
        if t.table_name='supabase_migrations.schema_migrations' then
          if delta<>1 then raise exception 'Migration registry delta invalid';end if;
        elsif t.table_name=any({array(allowed_append)}) then
          if delta not in (0,1) then raise exception 'Append delta invalid in %',t.table_name;end if;
          execute format('select count(*) from %s where xmin::text::bigint=pg_current_xact_id()::text::bigint',t.table_name) into new_xid;
          if new_xid<>delta then raise exception 'Unattributed append in %',t.table_name;end if;
          append_count:=append_count+delta;
        elsif delta<>0 then raise exception 'Unexpected row insertion in %',t.table_name;end if;
      end loop;
      if append_count not in (0,4) then raise exception 'Navigation governance append incomplete';end if;
      missing:=false;
      for t in select b.family,b.identity,encode(extensions.digest(b.body::text,'sha256'),'hex') old_hash,
        encode(extensions.digest(a.body::text,'sha256'),'hex') new_hash
        from pg_temp.collect_upgrade_catalog b left join pg_temp.collect_upgrade_catalog_after a using(family,identity)
        where a.identity is null or a.body is distinct from b.body and not (b.family='routine' and b.object_name=any({array(allowed_changed)})) loop
        raise notice 'CATALOG_DIFF|%|%|%|%',t.family,t.identity,t.old_hash,t.new_hash;
        missing:=true;
      end loop;
      if missing then raise exception 'Unexpected original catalog mutation';end if;
      missing:=false;
      for t in select a.family,a.object_name,a.identity from pg_temp.collect_upgrade_catalog_after a left join pg_temp.collect_upgrade_catalog b using(family,identity)
        where b.identity is null and not(a.object_name=any({array(allowed_new)})) loop
        raise notice 'UNEXPECTED_NEW_CATALOG|%|%|%',t.family,t.object_name,t.identity;missing:=true;
      end loop;
      if missing then raise exception 'Unexpected new catalog object';end if;
      if (select count(*) from supabase_migrations.schema_migrations)<>{count+1} then raise exception 'Wrong installed count';end if;
      raise notice 'STAGED_UPGRADE_ROWS_PRESERVED|%|%',(select count(*) from pg_temp.collect_upgrade_counts),append_count;
    end$$;
    """
    if version == "20260930200000":
        body += """do $$begin if not exists(select 1 from public.admin_navigation_items n
          join collect_security.runtime_control_heads h on h.family='admin_navigation_items' and h.identity=jsonb_build_object('key',n.key)
          where n.key='automations' and n.route_path='/admin/automations' and n.required_permission='system_health.read'
            and n.enabled and h.content_sha256=collect_security.runtime_control_hash(to_jsonb(n))) then
          raise exception 'Navigation provision integrity failed';end if;end$$;"""
    if version == "20260930210000":
        body += f"""do $$begin
          if (select count(*) from collect_security.shadow_supervisor_lease)<>1
            or exists(select 1 from collect_security.shadow_supervisor_lease where not id or fence_version<>0 or active_run_id is not null or lease_expires_at is not null)
            or exists(select 1 from collect_security.shadow_supervisor_runs) or exists(select 1 from collect_security.shadow_supervisor_samples) then
            raise exception 'Shadow initial state invalid';end if;
          if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
            where n.nspname||'.'||c.relname=any({array(SHADOW_TABLES)}) and c.relkind='r' and c.relrowsecurity)=3 is not true then
            raise exception 'Shadow RLS missing';end if;
          if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||c.relname=any({array(SHADOW_TABLES)}) and has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')) then
            raise exception 'Shadow API table privilege';end if;
          if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname=any({array(SHADOW_FUNCTIONS)}))<>10 then
            raise exception 'Shadow function set incomplete';end if;
          if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||p.proname=any({array(SHADOW_FUNCTIONS)}) and has_function_privilege(r,p.oid,'EXECUTE') is distinct from (n.nspname='public' and r='authenticated')) then
            raise exception 'Shadow API function privilege';end if;
        end$$;"""
    if version == "20260930230000":
        body += f"""do $$begin
          if exists(select 1 from collect_member_actions.group_share_rotations) then
            raise exception 'Invitation receipts must start empty';end if;
          if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
            where n.nspname||'.'||c.relname=any({array(SHARE_TABLES)}) and c.relkind='r' and c.relrowsecurity)<>1 then
            raise exception 'Invitation receipt RLS missing';end if;
          if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||c.relname=any({array(SHARE_TABLES)}) and has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')) then
            raise exception 'Invitation API table privilege';end if;
          if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname||'.'||p.proname=any({array(SHARE_NEW_FUNCTIONS + SHARE_CHANGED_FUNCTIONS)}))<>5 then
            raise exception 'Invitation function set incomplete';end if;
          if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||p.proname=any({array(SHARE_NEW_FUNCTIONS + SHARE_CHANGED_FUNCTIONS)})
            and has_function_privilege(r,p.oid,'EXECUTE') is distinct from (n.nspname='public' and r='authenticated')) then
            raise exception 'Invitation API function privilege';end if;
          if exists(select 1 from pg_temp.collect_upgrade_catalog b join pg_temp.collect_upgrade_catalog_after a using(family,identity)
            where b.family='routine' and b.object_name=any({array(SHARE_CHANGED_FUNCTIONS)})
            and (b.body-array['source','config','volatile','acl','definer']) is distinct from
                (a.body-array['source','config','volatile','acl','definer'])) then
            raise exception 'Invitation original function owner/result changed';end if;
        end$$;"""
    body += "\n" + ("commit;" if commit else "rollback;") + "\n"
    return body


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--version", choices=tuple(UPGRADES), required=True)
    p.add_argument("--sha256", required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--commit", action="store_true")
    a = p.parse_args()
    count, latest, name = UPGRADES[a.version]
    path = ROOT / "supabase/migrations" / f"{a.version}_{name}.sql"
    if R.sha(path.read_bytes()) != a.sha256:
        p.error("Reviewed source SHA differs")
    output = a.output.resolve()
    if not output.is_relative_to(ROOT / "docs/release"):
        p.error("Fresh release evidence directory required")
    before = R.prepare(output, count, latest)
    source = R.reviewed_source(path, a.sha256, output)
    sql = transaction(source, a.version, commit=a.commit)
    (output / "executed-upgrade.sql").write_text(sql)
    try:
        R.execute(sql, output)
    except Exception as error:
        after = R.snapshot()
        R.save(output / "after-failure.json", after)
        R.save(output / "failure.json", dict(status="failed", message=str(error), baseline_restored=before == after))
        raise
    after = R.snapshot()
    if after["cron_jobs"] != before["cron_jobs"] or after["cron_history"] != before["cron_history"]:
        raise RuntimeError("Scheduler catalog/history changed")
    expected_new = set({"20260930210000": SHADOW_TABLES, "20260930230000": SHARE_TABLES}.get(a.version, ())) if a.commit else set()
    if set(after["tables"]) - set(before["tables"]) != expected_new:
        raise RuntimeError("Unexpected new table set")
    changed = NAV_APPEND if a.commit and a.version == "20260930200000" else ()
    R.finish(output, before, after, unchanged=not a.commit, expected_changed_tables=changed)
    R.guard(count + a.commit, a.version if a.commit else latest)
    result = json.loads((output / "result.json").read_text())
    result.update(upgrade_version=a.version, installed=a.commit, original_rows_preserved_before_commit=True,
                  original_catalog_checked_before_commit=True, new_tables=sorted(expected_new),
                  installer_sha256=R.sha(Path(__file__).read_bytes()))
    R.save(output / "result.json", result)


if __name__ == "__main__":
    main()
