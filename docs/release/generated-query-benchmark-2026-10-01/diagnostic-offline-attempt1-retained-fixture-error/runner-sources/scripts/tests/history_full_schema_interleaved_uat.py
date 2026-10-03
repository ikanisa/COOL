#!/usr/bin/env python3
"""Test history cursors across committed changes in an isolated DB clone.

The fixture uses synthetic posted rows without provider or ledger evidence.
It tests read visibility only and drops its task-owned clone on every exit.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = ROOT / ".cache/financial-qa-20260928/historical-upgraded.dump"
ARCHIVE_SHA256 = "c84940178f575ea8b0b1e9fa61f63246f7a306981b772587787bbb9719fd02a3"
CONTAINER = "supabase_db_collect_financial_restore_qa_20260928"
SOURCE_DB = "collect_financial_restore_empty_20260928"
TEST_DB = "collect_history_interleaved_qa_20260929"
ACTOR = "99100000-0000-4000-8000-000000000001"
VIEWER = "99100000-0000-4000-8000-000000000004"
COLLECTION = "99300000-0000-4000-8000-000000000010"
NEW_PAYMENT = "99600000-0000-4000-8000-000000000099"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def command(*args: str, input_text: str | None = None,
            ok: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, input=input_text, text=True,
                            capture_output=True, timeout=120, check=False)
    if ok and result.returncode != 0:
        raise AssertionError(f"{args[0]} {args[1]} exited {result.returncode}: "
                             f"{result.stderr.strip()[:600]}")
    return result


def sql(database: str, script: str, ok: bool = True,
        user: str = "postgres") -> subprocess.CompletedProcess[str]:
    return command("docker", "exec", "-i", CONTAINER, "psql", "-XqAt",
                   "-v", "ON_ERROR_STOP=1", "-U", user, "-d", database,
                   input_text=script, ok=ok)


def scalar(database: str, query: str) -> str:
    rows = sql(database, query).stdout.strip().splitlines()
    require(len(rows) == 1, f"Expected one result row, got {len(rows)}")
    return rows[0]


def quoted(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def history(user: str, cursor: dict[str, str] | None = None,
            ok: bool = True) -> dict[str, object] | subprocess.CompletedProcess[str]:
    cursor_sql = "null::jsonb" if cursor is None else quoted(json.dumps(cursor)) + "::jsonb"
    script = f"""
begin;
set local role authenticated;
set local request.jwt.claims = '{{"sub":"{user}","role":"authenticated"}}';
select public.list_current_member_history_page(
  {quoted(COLLECTION)}::uuid, '', 'newest', {cursor_sql}, 20);
rollback;
"""
    result = sql(TEST_DB, script, ok=ok)
    if not ok:
        return result
    rows = result.stdout.strip().splitlines()
    require(len(rows) == 1, "History RPC must return exactly one JSON row")
    return json.loads(rows[0])


def expect_refresh(user: str, cursor: dict[str, str]) -> None:
    result = history(user, cursor, ok=False)
    require(isinstance(result, subprocess.CompletedProcess), "Expected SQL error")
    require(result.returncode != 0 and
            "History changed. Refresh before loading more." in result.stderr,
            "Stale history cursor did not fail closed")


def fixture_sql() -> str:
    return f"""
begin;
set local statement_timeout = '120s';
do $$ begin
  if current_database() <> '{TEST_DB}'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.payments) <> 2
     or exists (select 1 from pg_trigger
       where tgrelid = 'public.payments'::regclass
         and not tgisinternal and tgenabled <> 'O') then
    raise exception 'Exact task-owned restored clone required';
  end if;
end $$;
insert into auth.users(
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '{VIEWER}', 'authenticated', 'authenticated', '250788991004', now(), '{{}}', '{{}}'
);
insert into public.collection_members(collection_id, user_id, role, status)
values ('{COLLECTION}', '{VIEWER}', 'member', 'active');
alter table public.payments disable trigger user;
insert into public.payments(
  id, collection_id, contributor_user_id, receiver_user_id,
  receiver_momo_number_hash, amount_rwf, currency, transaction_id,
  source, status, anonymity_choice, provider_network, posted_at
)
select ('99600000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '{COLLECTION}'::uuid, '{ACTOR}'::uuid, '{ACTOR}'::uuid,
  profile.momo_number_hash, 1000 + n, 'RWF', 'SYNTH-INTERLEAVED-' || n,
  'import', 'posted', 'anonymous', 'mtn_momo',
  now() - make_interval(secs => n)
from generate_series(1, 55) n
cross join public.profiles profile where profile.id = '{ACTOR}'::uuid;
alter table public.payments enable trigger user;
commit;
"""


def post_sql() -> str:
    return f"""
begin;
alter table public.payments disable trigger user;
insert into public.payments(
  id, collection_id, contributor_user_id, receiver_user_id,
  receiver_momo_number_hash, amount_rwf, currency, transaction_id,
  source, status, anonymity_choice, provider_network, posted_at
)
select '{NEW_PAYMENT}'::uuid, '{COLLECTION}'::uuid,
  '{ACTOR}'::uuid, '{ACTOR}'::uuid, profile.momo_number_hash,
  7777, 'RWF', 'SYNTH-INTERLEAVED-NEW', 'import', 'posted',
  'anonymous', 'mtn_momo', now()
from public.profiles profile where profile.id = '{ACTOR}'::uuid;
alter table public.payments enable trigger user;
commit;
"""


def main() -> None:
    labels = json.loads(command("docker", "inspect", CONTAINER,
                                "--format", "{{json .Config.Labels}}").stdout)
    require(labels.get("com.supabase.cli.project") ==
            "collect_financial_restore_qa_20260928" and
            labels.get("com.supabase.cli.workdir") ==
            str(ROOT / ".cache/financial-restore-qa-20260928"),
            "Refusing unrecognized Docker container")
    require(scalar(SOURCE_DB, "select count(*) from supabase_migrations.schema_migrations")
            == "133", "Restored source migration count changed")
    archive = ARCHIVE.read_bytes()
    require(hashlib.sha256(archive).hexdigest() == ARCHIVE_SHA256,
            "Synthetic archive hash changed")
    require(scalar("postgres", f"select count(*) from pg_database where datname='{TEST_DB}'")
            == "0", "Task-owned test database already exists; inspect before retry")

    created = False
    source_locked = False
    report: dict[str, object] | None = None
    try:
        # pg_cron keeps a scheduler connection in the source database. Prevent
        # reconnects, terminate that one task-owned session, then clone.
        sql("postgres", f"alter database {SOURCE_DB} allow_connections false;",
            user="supabase_admin")
        source_locked = True
        sql("postgres", f"select pg_terminate_backend(pid) from pg_stat_activity "
            f"where datname='{SOURCE_DB}' and backend_type='pg_cron launcher';",
            user="supabase_admin")
        sql("postgres", f"create database {TEST_DB} template {SOURCE_DB};",
            user="supabase_admin")
        created = True
        sql("postgres", f"alter database {SOURCE_DB} allow_connections true;",
            user="supabase_admin")
        source_locked = False
        sql(TEST_DB, fixture_sql())
        require(scalar(TEST_DB,
                       "select count(*) from pg_proc where provolatile='s' and oid in ("
                       "'collect_member_actions.history_page(uuid,text,text,jsonb,integer)'"
                       "::regprocedure,"
                       "'public.list_current_member_history_page(uuid,text,text,jsonb,integer)'"
                       "::regprocedure)") == "2",
                "History RPC and public wrapper must share one stable query snapshot")
        require(scalar(TEST_DB, "select count(*) from public.payments where status='posted'")
                == "56", "Synthetic post fixture count incorrect")
        require(scalar(TEST_DB,
                       "select count(*) from pg_trigger where tgrelid='public.payments'::regclass "
                       "and not tgisinternal and tgenabled <> 'O'") == "0",
                "Payment triggers left disabled")

        first = history(VIEWER)
        require(isinstance(first, dict), "Missing first page")
        require(first["total_count"] == 56 and len(first["items"]) == 20 and
                first["own_totals"]["RWF"] == 0 and first["next_cursor"],
                "Initial viewer page or totals incorrect")
        require(all(item["transaction_id"] is None and
                    item["is_current_user_contribution"] is False
                    for item in first["items"]), "Private peer details leaked")
        baseline_amount = first["totals"]["RWF"]
        second = history(VIEWER, first["next_cursor"])
        require(isinstance(second, dict) and len(second["items"]) == 20 and
                {item["payment_id"] for item in first["items"]}.isdisjoint(
                    {item["payment_id"] for item in second["items"]}),
                "Stable cursor did not return the next distinct page")

        sql(TEST_DB, post_sql())
        expect_refresh(VIEWER, first["next_cursor"])
        posted = history(VIEWER)
        require(isinstance(posted, dict) and posted["total_count"] == 57 and
                posted["totals"]["RWF"] == baseline_amount + 7777 and
                posted["revision"] != first["revision"],
                "Committed post did not refresh count, total and revision")

        sql(TEST_DB, f"""
begin;
alter table public.payments disable trigger user;
update public.payments set status='reversed', posted_at=null
where id='{NEW_PAYMENT}'::uuid and status='posted';
alter table public.payments enable trigger user;
commit;
""")
        expect_refresh(VIEWER, posted["next_cursor"])
        reversed_page = history(VIEWER)
        require(isinstance(reversed_page, dict) and
                reversed_page["total_count"] == 56 and
                reversed_page["totals"]["RWF"] == baseline_amount and
                reversed_page["revision"] != posted["revision"],
                "Committed reversal did not refresh count, total and revision")

        sql(TEST_DB, f"update public.collection_members set status='removed' "
            f"where collection_id='{COLLECTION}'::uuid "
            f"and user_id='{VIEWER}'::uuid and status='active';")
        expect_refresh(VIEWER, reversed_page["next_cursor"])
        removed = history(VIEWER)
        require(isinstance(removed, dict) and removed["total_count"] == 0 and
                removed["items"] == [] and removed["totals"] == {} and
                removed["revision"] != reversed_page["revision"],
                "Membership revocation did not remove private group history")
        owner = history(ACTOR)
        require(isinstance(owner, dict) and owner["total_count"] == 56 and
                owner["own_totals"]["RWF"] == baseline_amount,
                "Viewer revocation unexpectedly changed owner history")
        report = {
            "status": "pass_synthetic_interleaved_history_not_production_uat",
            "scope": "isolated 133-migration PostgreSQL 17.6 clone of verified task-owned restore",
            "synthetic_source_archive_sha256": ARCHIVE_SHA256,
            "page_limit": 20,
            "initial_posted_count": 56,
            "post_refresh_count": 57,
            "reversal_refresh_count": 56,
            "revoked_viewer_count": 0,
            "distinct_second_page": True,
            "stale_cursor_rejected_after_post_reversal_revocation": True,
            "viewer_peer_details_masked": True,
            "limitations": [
                "synthetic rows have no provider or ledger evidence",
                "commits are interleaved between RPC calls, not during one RPC",
                "no hosted readback, signed app, or real provider reversal",
            ],
        }
    finally:
        if source_locked:
            sql("postgres", f"alter database {SOURCE_DB} allow_connections true;",
                user="supabase_admin")
        if created:
            sql("postgres", f"drop database {TEST_DB} with (force);",
                user="supabase_admin")
    require(report is not None, "Test report missing after cleanup")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
