#!/usr/bin/env python3
"""Compare old and candidate Admin notification JSON in one rollback transaction."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CONTAINER = "supabase_db_collect_financial_restore_qa_20260928"
DATABASE = "collect_financial_restore_empty_20260928"
BENCHMARK = ROOT / "scripts/tests/admin_notification_paging_benchmark.sql"
MIGRATION = ROOT / "supabase/migrations/20260929110000_admin_notification_page_before_delivery_counts.sql"
MARKER = "-- BEFORE_RPC_BENCHMARK"


PARITY_SQL = r"""
create temp table old_notification_pages(
  label text primary key, p_search text, p_status text,
  p_limit integer, p_offset integer, p_sort text, doc jsonb not null
);
grant select, insert on pg_temp.old_notification_pages to authenticated;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001",'
  || '"role":"authenticated",'
  || '"session_id":"99830000-0000-4000-8000-000000000001"}',true) \gset
insert into pg_temp.old_notification_pages
select args.*, public.admin_list_notifications(
  args.p_search,args.p_status,args.p_limit,args.p_offset,args.p_sort)
from (values
  ('first-desc',null::text,null::text,25,0,'created_at_desc'),
  ('first-asc',null::text,null::text,25,0,'created_at_asc'),
  ('failed-asc',null::text,'failed',25,0,'created_at_asc'),
  ('deep-desc',null::text,null::text,25,975,'created_at_desc'),
  ('type-search','group_update',null::text,25,0,'created_at_desc'),
  ('public-id-search',(select public_id::text from public.profiles
    where id='99100000-0000-4000-8000-000000000001'),
    null::text,25,0,'created_at_desc'),
  ('no-match','unlikely-type-xyz',null::text,25,0,'created_at_desc'),
  ('unknown-sort',null::text,null::text,25,0,'unknown'),
  ('clamped-limit',null::text,null::text,-1,-10,'created_at_desc'),
  ('expired-offset',null::text,null::text,25,20000,'created_at_desc')
) args(label,p_search,p_status,p_limit,p_offset,p_sort);
reset role;
-- APPLY_CANDIDATE_MIGRATION
do $$ begin
  if has_function_privilege('anon',
       'public.admin_list_notifications(text,text,integer,integer,text)',
       'EXECUTE')
     or not has_function_privilege('authenticated',
       'public.admin_list_notifications(text,text,integer,integer,text)',
       'EXECUTE')
     or (select count(*) from pg_indexes
         where schemaname='public' and tablename='notification_events'
           and indexname in ('notification_events_admin_created_idx',
             'notification_events_admin_status_created_idx')) <> 2 then
    raise exception 'Candidate notification grant/index contract failed';
  end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001",'
  || '"role":"authenticated",'
  || '"session_id":"99830000-0000-4000-8000-000000000001"}',true) \gset
do $$ begin
  if (select count(*) from pg_temp.old_notification_pages) <> 10
     or exists (
       select 1 from pg_temp.old_notification_pages old_page
       where old_page.doc is distinct from public.admin_list_notifications(
         old_page.p_search,old_page.p_status,old_page.p_limit,
         old_page.p_offset,old_page.p_sort)
     ) then
    raise exception 'Notification page JSON changed in candidate migration';
  end if;
end $$;
select label, jsonb_array_length(doc->'rows') as rows,
  (doc->>'total')::bigint as total
from pg_temp.old_notification_pages order by label;
\echo ADMIN_NOTIFICATION_PAGE_PARITY_PASS_10
rollback;
"""


def main() -> None:
    labels = json.loads(subprocess.run(
        ["docker", "inspect", CONTAINER, "--format", "{{json .Config.Labels}}"],
        text=True, capture_output=True, check=True, timeout=20,
    ).stdout)
    if (labels.get("com.supabase.cli.project") !=
            "collect_financial_restore_qa_20260928" or
            labels.get("com.supabase.cli.workdir") !=
            str(ROOT / ".cache/financial-restore-qa-20260928")):
        raise SystemExit("Unrecognized task-owned restore container")
    benchmark = BENCHMARK.read_text()
    if benchmark.count(MARKER) != 1:
        raise SystemExit("Notification fixture marker changed")
    parity = PARITY_SQL.replace("-- APPLY_CANDIDATE_MIGRATION",
                                MIGRATION.read_text())
    script = benchmark.split(MARKER, 1)[0] + parity
    result = subprocess.run(
        ["docker", "exec", "-i", CONTAINER, "psql", "-XqAt", "-v",
         "ON_ERROR_STOP=1", "-v", "bench_events=1000",
         "-U", "supabase_admin", "-d", DATABASE],
        input=script, text=True, capture_output=True, timeout=180, check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"Notification page parity failed: {result.stderr[-1200:]}")
    if ("ADMIN_NOTIFICATION_PAGE_PARITY_PASS_10" not in result.stdout
            or len([line for line in result.stdout.splitlines()
                    if line.count("|") == 2]) != 10):
        raise SystemExit("Notification page parity transcript incomplete")
    print(result.stdout, end="")


if __name__ == "__main__":
    main()
