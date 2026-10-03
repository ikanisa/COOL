#!/usr/bin/env python3
"""Generate the additive exact receipt/aggregate correction from proven bodies."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/release/data-correctness-2026-09-30/sql154-positive-history-precision-review/actual-minimum-functions.json"
SOURCE_SHA = "6ec82c3fd45bc71217eab3f1ea7d2cc3da0c1994ea7881d30d5673da6cb7fa9b"
OUTPUT = ROOT / "supabase/migrations/20260930235000_exact_receipt_history_amounts.sql"


def replace_once(body, old, new):
    if body.count(old) != 1:
        raise RuntimeError("Reviewed function anchor changed; do not generate")
    return body.replace(old, new, 1)


def main():
    raw = SOURCE.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA or OUTPUT.exists():
        raise RuntimeError("Exact reviewed source and fresh output required")
    rows = {row["identity"]: row["definition"] for row in json.loads(raw)}
    proposal = rows["propose_payment_reconciliation_v2(uuid,text,text,timestamp with time zone,text)"]
    proposal = replace_once(proposal,
        " fingerprint:=collect_security.reconciliation_fingerprint(payment_row);",
        " perform collect_member_actions.exact_json_amount(payment_row.amount_rwf);\n fingerprint:=collect_security.reconciliation_fingerprint(payment_row);")
    confirmation = rows["confirm_provider_payment(uuid,text,text,text,text,bigint,timestamp with time zone,text)"]
    confirmation = replace_once(confirmation,
        "  perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:' || p_payment_id::text, 0));",
        "  perform collect_member_actions.exact_json_amount(p_amount_rwf);\n\n  perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:' || p_payment_id::text, 0));")
    history = rows["history_page(uuid,text,text,jsonb,integer)"]
    history = replace_once(history, "select count(*)::bigint,", "select collect_member_actions.exact_json_amount(count(*)),")
    history = replace_once(history, "coalesce(sum(amount_rwf), 0)::bigint,",
                          "collect_member_actions.exact_json_amount(coalesce(sum(amount_rwf), 0)),")
    history = replace_once(history, "coalesce(sum(amount_rwf) filter (where own), 0)::bigint,",
                          "collect_member_actions.exact_json_amount(coalesce(sum(amount_rwf) filter (where own), 0)),")
    balances = rows["list_current_member_collection_balances()"]
    balances = replace_once(balances, "'amount_raised_minor', coalesce(balance.confirmed_rwf, 0),",
                           "'amount_raised_minor', collect_member_actions.exact_json_amount(coalesce(balance.confirmed_rwf, 0)),")
    balances = replace_once(balances, "'current_user_balance_minor', coalesce((",
                           "'current_user_balance_minor', collect_member_actions.exact_json_amount(coalesce((")
    balances = replace_once(balances, "sum(member_balance.confirmed_rwf)::bigint", "sum(member_balance.confirmed_rwf)")
    balances = replace_once(balances, "      ), 0)\n    )),", "      ), 0))\n    )),")
    prefix = f"""begin;

-- Source bodies: {SOURCE.relative_to(ROOT)}
-- Source SHA-256: {SOURCE_SHA}
-- Preserve numeric JSON wire shapes, authority/finality/replay semantics and
-- all stored values. Existing unsafe posted rows abort this migration; REVIEW
-- observations remain available for an explicit rejection/correction workflow.
create function collect_member_actions.exact_json_amount(p_amount numeric)
returns bigint language plpgsql immutable security invoker set search_path='' as $$
begin
 if p_amount is null or p_amount<0 or p_amount>9007199254740991
   or p_amount<>trunc(p_amount) then
  raise exception 'financial_amount_not_exact' using errcode='22023';
 end if;
 return p_amount::bigint;
end$$;
revoke all on function collect_member_actions.exact_json_amount(numeric)
 from public,anon,authenticated,service_role;

alter table public.payments add constraint payments_posted_amount_exact_json
 check(status<>'posted' or amount_rwf<=9007199254740991) not valid;
alter table public.payments validate constraint payments_posted_amount_exact_json;

"""
    body = prefix + "\n".join([proposal, confirmation, history, balances]) + "\nnotify pgrst,'reload schema';\ncommit;\n"
    with OUTPUT.open("x") as handle:
        handle.write(body)
    print(json.dumps(dict(path=str(OUTPUT.relative_to(ROOT)), source_sha256=SOURCE_SHA,
                         sha256=hashlib.sha256(OUTPUT.read_bytes()).hexdigest(), function_bodies=4)))


if __name__ == "__main__":
    main()
