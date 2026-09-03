#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DB_CONTAINER="${SUPABASE_LOCAL_DB_CONTAINER:-supabase_db_collect}"
DB_NAME="${COLLECT_UAT_DATABASE:-}"
if [[ "$DB_CONTAINER" != 'supabase_db_collect' || "$DB_NAME" != 'collect_uat_20260902' ]]; then
  printf '[concurrent-join-uat][FAIL] Explicit disposable Collect UAT database required.\n' >&2
  exit 1
fi
OWNER_ID="10000000-0000-4000-8000-000000000901"
MEMBER_ID="10000000-0000-4000-8000-000000000902"
COLLECTION_ID="20000000-0000-4000-8000-000000000901"
SHARE_CODE="30000000-0000-4000-8000-000000000901"
EVIDENCE_DIR="${CONCURRENT_JOIN_EVIDENCE_DIR:-$ROOT_DIR/.cache/local_concurrent_join_uat/$(date -u +%Y%m%dT%H%M%SZ)}"

if ! docker inspect "$DB_CONTAINER" >/dev/null 2>&1; then
  printf '[concurrent-join-uat][FAIL] Local Supabase database container is unavailable: %s\n' "$DB_CONTAINER" >&2
  exit 1
fi
mkdir -p "$EVIDENCE_DIR"

cleanup() {
  docker exec -i "$DB_CONTAINER" psql -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 >/dev/null <<SQL
delete from public.audit_logs where entity_id = '$COLLECTION_ID'::uuid;
delete from public.collections where id = '$COLLECTION_ID'::uuid;
delete from auth.users where id in ('$OWNER_ID'::uuid, '$MEMBER_ID'::uuid);
SQL
}
trap cleanup EXIT
cleanup

docker exec -i "$DB_CONTAINER" psql -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 >"$EVIDENCE_DIR/setup.log" <<SQL
insert into auth.users (
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('$OWNER_ID', 'authenticated', 'authenticated', '+250781000901', now(), '{}', '{}', now(), now()),
  ('$MEMBER_ID', 'authenticated', 'authenticated', '+250781000902', now(), '{}', '{}', now(), now());

update public.profiles
set display_name = case id
  when '$OWNER_ID'::uuid then 'Concurrent owner'
  else 'Concurrent member'
end
where id in ('$OWNER_ID'::uuid, '$MEMBER_ID'::uuid);

insert into public.collections (
  id, slug, creator_user_id, title, description, category,
  visibility, public_status, receiver_display_label, collection_type
) values (
  '$COLLECTION_ID', 'concurrent-join-uat', '$OWNER_ID',
  'Concurrent join UAT', 'Synthetic local concurrency fixture', 'Other',
  'private', 'private', 'Synthetic receiver', 'other'
);

insert into public.collection_members (collection_id, user_id, role, status)
values ('$COLLECTION_ID', '$OWNER_ID', 'owner', 'active');

insert into public.collection_share_secrets (
  collection_id, share_code, rotated_by
) values ('$COLLECTION_ID', '$SHARE_CODE', '$OWNER_ID');
SQL

join_sql="begin;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', '$MEMBER_ID', 'role', 'authenticated')::text, true);
select pg_sleep(0.25);
select public.join_group_by_share_code('$SHARE_CODE');
commit;"

docker exec "$DB_CONTAINER" psql -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c "$join_sql" >"$EVIDENCE_DIR/join-1.log" 2>&1 &
join_one_pid=$!
docker exec "$DB_CONTAINER" psql -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 \
  -c "$join_sql" >"$EVIDENCE_DIR/join-2.log" 2>&1 &
join_two_pid=$!

join_status=0
wait "$join_one_pid" || join_status=1
wait "$join_two_pid" || join_status=1
if [[ "$join_status" -ne 0 ]]; then
  sed -n '1,160p' "$EVIDENCE_DIR/join-1.log" >&2
  sed -n '1,160p' "$EVIDENCE_DIR/join-2.log" >&2
  printf '[concurrent-join-uat][FAIL] Concurrent join caller failed.\n' >&2
  exit 1
fi

docker exec -i "$DB_CONTAINER" psql -U postgres -d "$DB_NAME" -v ON_ERROR_STOP=1 >"$EVIDENCE_DIR/verification.log" <<SQL
do \$\$
declare
  membership_count integer;
  audit_count integer;
  notification_count integer;
begin
  select count(*) into membership_count
  from public.collection_members
  where collection_id = '$COLLECTION_ID'
    and user_id = '$MEMBER_ID'
    and role = 'member'
    and status = 'active';

  select count(*) into audit_count
  from public.audit_logs
  where entity_id = '$COLLECTION_ID'
    and action = 'group.joined';

  select count(*) into notification_count
  from public.notification_events
  where collection_id = '$COLLECTION_ID'
    and user_id = '$OWNER_ID'
    and type = 'group_update';

  if membership_count <> 1 then
    raise exception 'expected one active member row, found %', membership_count;
  end if;
  if audit_count <> 1 then
    raise exception 'expected one group.joined audit, found %', audit_count;
  end if;
  if notification_count <> 1 then
    raise exception 'expected one owner notification, found %', notification_count;
  end if;
end;
\$\$;
select 'LOCAL_CONCURRENT_JOIN_UAT_PASS';
SQL

printf '[concurrent-join-uat] pass evidence=%s\n' "$EVIDENCE_DIR"
