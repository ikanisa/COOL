#!/usr/bin/env bash
set -euo pipefail

# Disposable PostgreSQL schema exercise of the additive payer migration.
# Full Supabase migration replay and linked-provider evidence remain separate.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="collect-payer-identity-$$"
IMAGE_ID="$(docker image ls -q postgres:17 | head -n 1)"
test -n "$IMAGE_ID"
docker image inspect "$IMAGE_ID" >/dev/null
docker run --pull=never --rm -d --network none --name "$NAME" \
  -e POSTGRES_PASSWORD=local_payer_test "$IMAGE_ID" >/dev/null
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
for attempt in $(seq 1 120); do
  if docker exec "$NAME" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 0.25
done
docker exec "$NAME" pg_isready -U postgres >/dev/null
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres \
  < "$ROOT/scripts/tests/payer_identity_sql_scratch.sql"
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres \
  < "$ROOT/supabase/migrations/20260928170000_confirmed_momo_payer_posting.sql"
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', message; end if;
end;
$$;
create function pg_temp.assert_denied(statement text, message text) returns void
language plpgsql as $$
begin
  begin
    execute statement;
  exception when check_violation then
    return;
  end;
  raise exception 'FAIL: %', message;
end;
$$;
select pg_temp.assert_true(
  (select status = 'pending' from public.payment_intents
   where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'),
  'confirmed payer intent remains pending');
select pg_temp.assert_true(
  (select status = 'cancelled' from public.payment_intents
   where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1'),
  'unverified pending payer intent is cancelled');
select pg_temp.assert_true(
  (select count(*) = 2 from collect_hybrid.payer_identity_reconciliation
   where review_status = 'open'),
  'bad review and historical posted rows are inventoried');
select pg_temp.assert_true(
  (select status = 'posted' from public.payments
   where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3'),
  'historical posted payment is preserved');
select pg_temp.assert_denied(
  $$update public.payments set status = 'posted'
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'$$,
  'unverified matched payment cannot post');
select pg_temp.assert_denied(
  $$update public.payments set payment_intent_id = null
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'$$,
  'review payment cannot drop its intent to bypass the guard');
select pg_temp.assert_denied(
  $$update public.payments set collection_id =
      'dddddddd-dddd-4ddd-8ddd-ddddddddddd1'
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3'$$,
  'historical posted intent attribution cannot move to another group');
insert into public.payments(
  id,collection_id,contributor_user_id,status
) values (
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd2',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','posted'
);
select pg_temp.assert_denied(
  $$update public.payments set payment_intent_id =
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
    where id = 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2'$$,
  'already posted standalone payment cannot acquire an intent');
update public.payments set status = 'posted'
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
select pg_temp.assert_true(
  (select status = 'posted' from public.payments
   where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2'),
  'confirmed Auth phone and matching SMS payer can post');
update auth.users set phone_confirmed_at = null
where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
select pg_temp.assert_true(
  public._authenticated_momo_phone_hash('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1') is null,
  'unconfirmed Auth phone cannot produce payer hash');
select pg_temp.assert_denied(
  $$insert into public.payments(
      id,payment_intent_id,parsed_event_id,collection_id,contributor_user_id,status
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa9',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'cccccccc-cccc-4ccc-8ccc-ccccccccccc1',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1','posted')$$,
  'new intent-backed posting fails after Auth phone loses confirmation');
select 'PAYER_IDENTITY_SQL_SCRATCH_PASS';
SQL
