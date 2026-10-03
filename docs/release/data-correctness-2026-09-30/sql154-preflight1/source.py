#!/usr/bin/env python3
"""Actual installed154 member APIs in a disposable, schema-only local database.

No source data is copied. No posted payment, provider confirmation, verified
native capability or disabled trigger is manufactured. Positive posted history
ordering consequently remains an explicit acceptance boundary.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import traceback

from local_schema_uat import ROOT, U, isolated, save

ACTOR = "99640000-0000-4000-8000-000000000001"
PEER = "99640000-0000-4000-8000-000000000002"
OUTSIDER = "99640000-0000-4000-8000-000000000003"
SESSION = "99640000-0000-4000-8000-000000010001"
GROUP = "99640000-0000-4000-8000-000000020001"
PUBLIC = "99640000-0000-4000-8000-000000020002"
FOREIGN = "99640000-0000-4000-8000-000000020003"
NO_ROUTE = "99640000-0000-4000-8000-000000020004"
MISSING = "99640000-0000-4000-8000-000000099999"
MAX_EXACT = 9007199254740991
APIS = (
    "public.get_current_member_profile()",
    "public.list_current_user_collections(uuid)",
    "public.list_current_member_recent_intents(uuid)",
    "public.list_current_member_history_page(uuid,text,text,jsonb,integer)",
    "public.list_current_member_collection_balances()",
    "public.create_contribution_intent(uuid,bigint,text)",
    "public.allocate_parsed_payment_event(uuid)",
    "public.post_payment_from_event(uuid,uuid,uuid,text)",
    "public._authenticated_momo_phone_hash(uuid)",
    "collect_member_actions.history_page(uuid,text,text,jsonb,integer)",
    "collect_member_actions.recent_intents(uuid)",
)


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


def scalar(db, sql):
    return json.loads(U.psql(db, sql).stdout.strip().splitlines()[-1])


def definitions(db):
    wanted = ",".join(literal(x) + "::regprocedure" for x in APIS)
    return scalar(db, f"""select jsonb_agg(jsonb_build_object(
      'identity',p.oid::regprocedure::text,'definition',pg_get_functiondef(p.oid),
      'acl',coalesce(p.proacl,acldefault('f',p.proowner))::text)
      order by p.oid::regprocedure::text) from pg_proc p where p.oid in ({wanted});""")


def financial(db):
    # Includes both confirmed balance projections and all delivery surfaces.
    names = ["public.payments", "public.payment_allocations",
             "collect_hybrid.collection_balances", "collect_hybrid.member_balances",
             "collect_hybrid.momo_journal_entries", "public.notification_deliveries",
             "public.notification_delivery_attempts", "collect_hybrid.sms_notification_outbox",
             "collect_hybrid.sms_notification_attempts", "collect_hybrid.sms_operator_heartbeats"]
    unions = []
    for name in names:
        unions.append(f"select {literal(name)} name,count(*) n,encode(extensions.digest("
                      "coalesce(string_agg(to_jsonb(t)::text,E'\\n' order by to_jsonb(t)::text),''),"
                      f"'sha256'),'hex') h from {name} t")
    return scalar(db, "select jsonb_object_agg(name,jsonb_build_object('rows',n,'sha256',h)) "
                  "from (" + " union all ".join(unions) + ") s;")


def seed(db):
    users = [(ACTOR, "250788640123"), (PEER, "250738640123"), (OUTSIDER, "250788640999")]
    sql = "begin;set local statement_timeout='30s';"
    for uid, phone in users:
        sql += f"""insert into auth.users(id,aud,role,phone,phone_confirmed_at,
          raw_app_meta_data,raw_user_meta_data) values('{uid}','authenticated',
          'authenticated','{phone}',now(),'{{}}','{{}}');
          update public.profiles set country_code='RW',currency_code='RWF',
          momo_number='0{phone[3:]}',momo_provider={'\'airtel_money\'' if uid == PEER else '\'mtn_momo\''},
          momo_number_hash=encode(extensions.digest('+{phone}','sha256'),'hex') where id='{uid}';"""
    sql += f"""insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
      values('{SESSION}','{ACTOR}',now(),now(),now()+interval '1 hour','aal1');"""
    for group, owner, title, public in [(GROUP, ACTOR, "Synthetic private data", False),
                                       (PUBLIC, ACTOR, "Synthetic public data", True),
                                       (FOREIGN, OUTSIDER, "Synthetic foreign private", False),
                                       (NO_ROUTE, ACTOR, "Synthetic no receiver", False)]:
        sql += f"""insert into public.collections(id,slug,creator_user_id,title,public_status,
          visibility,created_at) values('{group}','data-uat-{group[-6:]}','{owner}',
          '{title}','{'public_approved' if public else 'private'}',
          '{'public_approved' if public else 'private'}','2026-09-30T08:00:00Z');"""
        if group != NO_ROUTE:
            sql += f"""insert into public.collection_receivers(collection_id,receiver_user_id,
              momo_number,momo_number_hash,network,label) select '{group}','{owner}',momo_number,
              momo_number_hash,momo_provider,'Synthetic receiver' from public.profiles where id='{owner}';"""
    sql += f"""insert into public.collection_members(collection_id,user_id,role,status)
      values('{GROUP}','{ACTOR}','owner','active'),('{GROUP}','{PEER}','member','active');commit;"""
    U.psql(db, sql)


def run(db, evidence, report):
    def case(name, fn):
        try:
            detail = fn()
            evidence["cases"].append(dict(name=name, status="pass", detail=detail))
            print("PASS " + name, flush=True)
        except Exception as error:
            evidence["cases"].append(dict(name=name, status="failed", error=str(error)))
            print("FAIL " + name + ": " + str(error), flush=True)
        save(report / "result.json", evidence)

    def require(ok, detail):
        if not ok:
            raise AssertionError(json.dumps(detail, sort_keys=True))
        return detail

    def call(sql, actor=ACTOR):
        return U.call(db, sql, actor, SESSION)

    def deny(sql, state, reason=None, actor=ACTOR, role="authenticated"):
        return U.expected_error(db, sql, state, reason, actor, SESSION, role)

    def rollback_call(sql, actor=ACTOR):
        result = U.psql(db, "begin;" + U.auth(actor, SESSION) + sql + ";rollback;")
        return json.loads(result.stdout.strip().splitlines()[-1])

    sender = scalar(db, f"select to_jsonb(public._authenticated_momo_phone_hash('{ACTOR}')); ")
    peer_sender = scalar(db, f"select to_jsonb(public._authenticated_momo_phone_hash('{PEER}')); ")
    def intent(amount, group=GROUP, claimed=sender, actor=ACTOR, rollback=False):
        sql = ("select to_jsonb(t) from public.create_contribution_intent("
               f"'{group}',{'null' if amount is None else amount},{literal(claimed) if claimed is not None else 'null'}) t")
        return (rollback_call if rollback else call)(sql, actor)

    baseline = financial(db)
    evidence["financial_before"] = baseline
    evidence["fixture"] = dict(synthetic_identities=3, groups=4, profiles_created_by_actual_auth_trigger=True,
                               source_rows_copied=False, posted_rows_created=0, confirmed_status_fabricated=False,
                               native_capabilities_fabricated=False, triggers_disabled=False)
    case("restored API definitions and ACLs exactly match installed154", lambda: require(
        definitions(db) == evidence["installed_api_definitions"], dict(api_count=len(APIS))))
    case("confirmed full phone identities distinguish equal suffixes", lambda: require(
        sender != peer_sender and len(sender) == len(peer_sender) == 64,
        dict(same_last_three=True, full_identity_hashes_distinct=sender != peer_sender)))
    case("own profile payload uses exact immutable actor and Collect ID", lambda: require(
        (p := call("select public.get_current_member_profile()"))["id"] == ACTOR
        and p["public_id"].isdigit() and len(p["public_id"]) == 6, p))
    case("visible groups exclude foreign and forged IDs and deterministically order ties", lambda: require(
        [x["id"] for x in (rows := call("select public.list_current_user_collections(null)"))]
        == sorted([GROUP, PUBLIC, NO_ROUTE]), dict(groups=rows)))
    for group in (FOREIGN, MISSING):
        case("unreadable exact collection " + group[-6:], lambda group=group: require(
            call(f"select public.list_current_user_collections('{group}')") == [], dict(collection_id=group)))
    case("actual readable empty balances explicitly return zero, not unavailable", lambda: require(
        len(rows := call("select public.list_current_member_collection_balances()")) == 3
        and all(x["balances"] == [dict(currency="RWF", amount_raised_minor=0, current_user_balance_minor=0)]
                and x["supporter_count"] == 0 for x in rows), rows))
    case("nonmember private balances remain absent while public zero is visible", lambda: require(
        [x["collection_id"] for x in (rows := call("select public.list_current_member_collection_balances()", PEER))]
        == sorted([GROUP, PUBLIC]), rows))
    for amount in (None, 0, -1):
        case("invalid nonpositive amount " + str(amount), lambda amount=amount: deny(
            f"select public.create_contribution_intent('{GROUP}',{'null' if amount is None else amount},'{sender}')",
            "P0001", "Contribution amount must be above zero"))
    for group in (FOREIGN, MISSING):
        case("cross-group or forged contribution target " + group[-6:], lambda group=group: deny(
            f"select public.create_contribution_intent('{group}',2000,'{sender}')", "P0001", "Private group membership"))
    case("missing group receiver refuses contribution", lambda: deny(
        f"select public.create_contribution_intent('{NO_ROUTE}',2000,'{sender}')", "P0001", "no active receiver"))
    for claimed in (None, "", peer_sender, "f" * 64):
        case("forged or absent payer hash " + str(claimed)[:8], lambda claimed=claimed: deny(
            f"select public.create_contribution_intent('{GROUP}',2000,{literal(claimed) if claimed is not None else 'null'})",
            "P0001", "identity verification failed"))
    first = intent(2000)
    case("contribution receipt binds amount collection payer route and pending lifetime", lambda: require(
        first["collection_id"] == GROUP and first["expected_amount_rwf"] == 2000
        and first["sender_phone_hash"] == sender and first["network"] == "mtn_momo"
        and first["status"] == "pending" and first["created_at"] < first["expires_at"], first))
    case("identical live contribution request reuses exact intent", lambda: require(
        (same := intent(2000))["id"] == first["id"], same))
    for amount in (1, MAX_EXACT):
        case("exact JSON amount boundary " + str(amount), lambda amount=amount: require(
            (receipt := intent(amount, rollback=True))["expected_amount_rwf"] == amount, receipt))
    for amount in (MAX_EXACT + 1, 9223372036854775807):
        # Expected strict rejection is the acceptance requirement. The actual
        # accepted receipt is retained as a failing case without persisting it.
        def unsafe(amount=amount):
            receipt = intent(amount, rollback=True)
            raise AssertionError(json.dumps(dict(defect="server accepts amount outside exact JSON integer range",
                                                 requested_amount=amount, actual_receipt=receipt)))
        case("unsafe JSON amount rejected " + str(amount), unsafe)
    case("signed bigint overflow is rejected by actual parameter type", lambda: deny(
        f"select public.create_contribution_intent('{GROUP}',9223372036854775808,'{sender}')", "22003"))
    # The real API, rather than an insert with triggers disabled, creates61
    # simultaneous pending requests. One existing2000 request makes62 total.
    bulk = call(f"""select jsonb_agg(to_jsonb(t)) from generate_series(1,61)n
      cross join lateral public.create_contribution_intent('{GROUP}',10000+n,'{sender}')t""")
    case("61 real contribution calls preserve distinct request and collection bindings", lambda: require(
        len(bulk) == len({x["id"] for x in bulk}) == 61
        and {x["expected_amount_rwf"] for x in bulk} == set(range(10001, 10062))
        and all(x["collection_id"] == GROUP and x["sender_phone_hash"] == sender for x in bulk),
        dict(receipts=bulk)))
    recent = call("select public.list_current_member_recent_intents(null)")
    expected = scalar(db, f"select jsonb_agg(id::text order by created_at desc,id) from (select id,created_at "
                      f"from public.payment_intents where contributor_user_id='{ACTOR}' order by created_at desc,id limit50)s;".replace("limit50", "limit 50"))
    case("recent50 window has exact full62 pending count and deterministic ties", lambda: require(
        len(recent["items"]) == 50 and recent["pending_count"] == 62
        and [x["id"] for x in recent["items"]] == expected, recent))
    case("exact old intent outside50 remains request-bound with full pending count", lambda: require(
        len(rows := call(f"select public.list_current_member_recent_intents('{first['id']}')")["items"]) == 1
        and rows[0]["id"] == first["id"] and rows[0]["collection_id"] == GROUP,
        dict(items=rows)))
    case("foreign exact intent cannot leak even to another active member", lambda: require(
        (doc := call(f"select public.list_current_member_recent_intents('{first['id']}')", PEER))
        == dict(items=[], pending_count=0), doc))
    case("forged intent preserves own full pending count without creating a row", lambda: require(
        (doc := call(f"select public.list_current_member_recent_intents('{MISSING}')"))
        == dict(items=[], pending_count=62), doc))
    expire = bulk[0]["id"]
    U.psql(db, f"update public.payment_intents set expires_at=now()-interval '1 second' where id='{expire}';")
    case("expired pending request reports expired and reduces exact full count", lambda: require(
        (doc := call(f"select public.list_current_member_recent_intents('{expire}')"))["pending_count"] == 61
        and doc["items"][0]["status"] == "expired", doc))
    for sort in ("newest", "oldest", "highest", "lowest"):
        case("history empty exact totals and valid sort " + sort, lambda sort=sort: require(
            (doc := call(f"select public.list_current_member_history_page('{GROUP}','','{sort}',null,2)"))["items"] == []
            and doc["total_count"] == 0 and doc["totals"] == {} and doc["own_totals"] == {}
            and doc["own_collection_ids"] == [] and doc["next_cursor"] is None, doc))
    for args in ("null,'','newest',null,0", "null,'','newest',null,101",
                 "null,'','forged',null,20", "null,repeat('x',81),'newest',null,20",
                 "null,'','newest','[]',20", "null,'','newest','{\"revision\":\"forged\"}',20"):
        case("invalid history query " + args, lambda args=args: deny(
            f"select public.list_current_member_history_page({args})", "22023"))
    empty = call("select public.list_current_member_history_page(null,'','newest',null,2)")
    cursor = json.dumps(dict(revision=empty["revision"], after="momo:" + MISSING))
    case("forged cursor anchor rejected even with current exact revision", lambda: deny(
        f"select public.list_current_member_history_page(null,'','newest',{literal(cursor)},2)", "P0001", "History changed"))
    for sql in ("select public.list_current_member_history_page()", "select public.list_current_member_recent_intents()",
                "select public.list_current_member_collection_balances()", "select public.list_current_user_collections()",
                f"select public.create_contribution_intent('{GROUP}',2000,'{sender}')"):
        case("anonymous SQL role denies " + sql.split("(")[0], lambda sql=sql: deny(sql, "42501", role="anon"))
    case("authenticated role cannot forge profile Collect identity", lambda: deny(
        f"update public.profiles set public_id='999998' where id='{ACTOR}'", "42501"))
    case("financial rows balances journal and delivery fingerprints unchanged", lambda: require(
        (after := financial(db)) == baseline, dict(before=baseline, after=after)))
    evidence["financial_after"] = financial(db)
    evidence["remaining_acceptance"] = [
        "Posted history positive sorting/ties/filter matched counts/full money totals require an authentic posting fixture; no posted or provider-confirmed state was manufactured.",
        "No current API provides recent-intent paging; actual API is a bounded50 window with complete count and request-bound exact-ID lookup, both exercised.",
        "Positive native-SMS candidate posting needs verified native capability; no native/provider attestation was fabricated.",
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    report = Path(args.output).resolve()
    if report.exists():
        raise RuntimeError("Fresh evidence directory required")
    report.mkdir(parents=True)
    evidence = dict(kind="installed154_schema_only_member_data_uat", status="running", cases=[],
                    started_at=dt.datetime.now(dt.timezone.utc).isoformat(), source_database_written=False,
                    hosted_called=False, provider_called=False, current_server_acceptance=False)
    inputs = [Path(__file__).resolve(), ROOT / "scripts/tests/local_schema_uat.py",
              ROOT / "scripts/tests/local_offline_verification.py", ROOT / "scripts/tests/shadow_supervisor_uat.py"]
    evidence["source_inputs"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    U.SQL_LOG = report / "queries.log"
    try:
        evidence["installed_api_definitions"] = definitions("postgres")
        save(report / "installed-api-definitions.json", evidence["installed_api_definitions"])
        with isolated(report, evidence, count=154, latest="20260930230000") as db:
            seed(db)
            run(db, evidence, report)
        evidence["status"] = "failed" if any(x["status"] == "failed" for x in evidence["cases"]) else "pass_scoped"
    except Exception as error:
        evidence.update(status="failed", failure=str(error), traceback=traceback.format_exc())
    finally:
        U.SQL_LOG = None
        evidence["completed_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        evidence["source_inputs_unchanged"] = all(hashlib.sha256((ROOT / p).read_bytes()).hexdigest() == h
                                                for p, h in evidence["source_inputs"].items())
        save(report / "result.json", evidence)
    print(json.dumps({k: evidence.get(k) for k in ("status", "failure", "all_source_tables_catalog_cron_preserved", "isolated_database_removed")}))
    return 1 if evidence["status"] == "failed" else 0


if __name__ == "__main__":
    raise SystemExit(main())
