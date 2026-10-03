#!/usr/bin/env python3
"""Actual Admin read RPC checks in a guarded disposable schema-only database.

Reuse the existing no-network schema150 clone/ACL/Auth scaffolding. Never
install this migration or synthetic rows in the source database or hosted DB.
"""
import importlib.util
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("shadow_fixture", ROOT / "scripts/tests/shadow_supervisor_uat.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
fixture.MIGRATION = ROOT / "supabase/migrations/20260930230300_admin_transaction_lifecycle.sql"


def run_cases(db, case, evidence, report, sessions, role):
    evidence["kind"] = "admin_transaction_lifecycle_isolated_schema_only"
    evidence["financial_evidence"] = "synthetic_current_schema_not_provider_authenticity"
    sql = lambda text: fixture.psql(db, text).stdout
    call = lambda text: fixture.call(db, text)
    error = lambda text, state, reason=None, **kw: fixture.expected_error(db, text, state, reason, **kw)
    def check(value):
        assert value, value
        return True
    sql("""insert into public.admin_permissions(name,description) values('payments.read','Synthetic read');
    insert into public.admin_role_permissions(role_id,permission_name) values('%s','payments.read');
    insert into public.collections(id,slug,creator_user_id,title,category)
    values('99720000-0000-4000-8000-000000000010','synthetic-lifecycle','%s','Synthetic lifecycle','Family / friends');
    insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,
      parse_status,received_at_device,receiver_momo_number_hash) values
    ('99720000-0000-4000-8000-000000000101','99720000-0000-4000-8000-000000000010','%s','M-Money','Synthetic A',repeat('1',64),'parsed','2026-09-30T10:00:00Z',repeat('a',64)),
    ('99720000-0000-4000-8000-000000000102','99720000-0000-4000-8000-000000000010','%s','M-Money','Synthetic B',repeat('2',64),'pending','2026-09-30T10:00:00Z',repeat('a',64)),
    ('99720000-0000-4000-8000-000000000103','99720000-0000-4000-8000-000000000010','%s','M-Money','Synthetic C',repeat('3',64),'failed','2026-09-30T09:00:00Z',repeat('a',64));
    insert into public.parsed_payment_events(id,raw_sms_id,collection_id,receiver_user_id,
      is_mobile_money_payment,network,direction,amount_rwf,currency,transaction_id,
      sender_name,allocation_status) values
    ('99720000-0000-4000-8000-000000000111','99720000-0000-4000-8000-000000000101',
      '99720000-0000-4000-8000-000000000010','%s',true,'mtn_momo','incoming',2500,'RWF',
      'SYNTHETIC-A','Synthetic payer','allocated');
    insert into public.payments(id,parsed_event_id,collection_id,receiver_user_id,
      receiver_momo_number_hash,amount_rwf,transaction_id,source,status,provider_network,posted_at)
    values('99720000-0000-4000-8000-000000000121','99720000-0000-4000-8000-000000000111',
      '99720000-0000-4000-8000-000000000010','%s',repeat('a',64),2500,'SYNTHETIC-A',
      'sms_auto','review','mtn_momo',null);""" % (role, fixture.UID, fixture.UID, fixture.UID, fixture.UID, fixture.UID, fixture.UID))
    before = fixture.fingerprint(db)
    evidence["business_before_reads"] = before
    result = call("select public.admin_list_collect_transactions();")
    (report / "observed-list.json").write_text(json.dumps(result, indent=2) + "\n")
    case("three nonempty Rwanda observations use independent states", lambda: check(result["total"] == 3 and len(result["rows"]) == 3 and all(r["country_code"] == "RW" for r in result["rows"])))
    row = next(r for r in result["rows"] if r["reference"] == "SYNTHETIC-A")
    case("allocated observation cannot imply verification or financial posting", lambda: check(row["lifecycle"]["allocation"] == "allocated" and row["lifecycle"]["verification"] == "pending" and row["lifecycle"]["ledger"] == "not_posted" and row["lifecycle"]["notification"] == "not_created"))
    case("failed parsing is distinct from allocation ambiguity", lambda: check(next(r for r in result["rows"] if r["status"] == "failed")["lifecycle"]["allocation"] == "parse_failed"))
    case("pending parser is distinct from pending provider verification", lambda: check(next(r for r in result["rows"] if r["status"] == "pending")["lifecycle"]["allocation"] == "pending_parse"))
    case("page beyond end retains exact total", lambda: check(call("select public.admin_list_collect_transactions(null,null,2,3);") == {"rows": [], "total": 3}))
    asc = call("select public.admin_list_collect_transactions(null,null,3,0,'created_at_asc');")
    case("oldest-first sorting preserved in response", lambda: check(asc["rows"][0]["status"] == "failed"))
    first = call("select public.admin_list_collect_transactions(null,null,1,0);")
    second = call("select public.admin_list_collect_transactions(null,null,1,1);")
    case("equal timestamp pagination has stable nonoverlapping tie-breaker", lambda: check(first["rows"][0]["id"] != second["rows"][0]["id"] and first["rows"][0]["status"] == "pending"))
    case("parse-failed operational filter resolves actual failure state", lambda: check(call("select public.admin_list_collect_transactions(null,'parse_failed');")["total"] == 1))
    for query in ["null,null,0,0", "null,null,101,0", "null,null,25,-1", "null,null,25,100001", "null,null,25,0,'unsafe'", "repeat('a',129),null"]:
        case("invalid query denied " + query, lambda query=query: error("select public.admin_list_collect_transactions("+query+");", "22023", "transaction_query_invalid"))
    for api_role in ["anon", "service_role"]:
        case(api_role + " cannot invoke Admin lifecycle list", lambda api_role=api_role: error("select public.admin_list_collect_transactions();", "42501", role=api_role))
    case("missing Auth session denied", lambda: error("select public.admin_list_collect_transactions();", "42501", sid="99720000-0000-4000-8000-000000010099"))
    def denied_receipt():
        value = fixture.psql(db, "begin;delete from public.admin_role_permissions where role_id='%s' and permission_name='notifications.read';" % role + fixture.auth() + "select public.admin_list_collect_transactions();rollback;").stdout
        response = json.loads(value.strip().splitlines()[-1])
        return check(all(r["lifecycle"]["notification"] == "access_required" for r in response["rows"]))
    case("revoked notification read never exposes receipt existence/state", denied_receipt)
    for title, mutation in [
        ("payment permission removed", "delete from public.admin_role_permissions where role_id='%s' and permission_name='payments.read';" % role),
        ("owner role revoked", "update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='%s';" % fixture.UID),
        ("approval revoked", "update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='%s';" % fixture.UID),
    ]:
        def probe(mutation=mutation):
            result = fixture.psql(db, "begin;" + mutation + fixture.auth() + "select public.admin_list_collect_transactions();rollback;", False)
            return check(result.returncode != 0 and "42501:" in result.stderr)
        case(title + " denies fresh observation", probe)
    after = fixture.fingerprint(db)
    evidence["business_after_reads"] = after
    case("read/denial matrix preserves seven business fingerprints including populated payments", lambda: check(before == after))
    # Seed a real balanced posting through the installed financial RPC using
    # synthetic evidence, rather than fabricating a 'posted' response fixture.
    sql("""begin;select set_config('request.jwt.claims','{"role":"service_role"}',true);
    select public.confirm_provider_payment('99720000-0000-4000-8000-000000000121',
      'mtn_momo','SYNTHETIC-A','CONF-SYNTHETIC-A',repeat('a',64),2500,clock_timestamp(),repeat('b',64));commit;""")
    financial_baseline = fixture.fingerprint(db)
    posted = call("select public.admin_list_collect_transactions('SYNTHETIC-A');")
    (report / "observed-posted-list.json").write_text(json.dumps(posted, indent=2) + "\n")
    case("balanced canonical posting and confirmation produce independent observations", lambda: check(
        posted["rows"][0]["lifecycle"]["verification"] == "confirmation_recorded" and
        posted["rows"][0]["lifecycle"]["ledger"] == "posted" and
        posted["rows"][0]["lifecycle"]["notification"] == "not_created"))
    case("confirmed amount ordering preserves leading financial record", lambda: check(
        call("select public.admin_list_collect_transactions(null,null,3,0,'amount_desc');")["rows"][0]["reference"] == "SYNTHETIC-A"))
    case("posted evidence stays unchanged by Admin list reads", lambda: check(financial_baseline == fixture.fingerprint(db)))
    evidence["posted_business_fingerprints"] = financial_baseline


fixture.run_cases = run_cases
if __name__ == "__main__":
    fixture.main()
