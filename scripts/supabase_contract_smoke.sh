#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

: "${SUPABASE_URL:?Set SUPABASE_URL before running the remote smoke checks.}"
: "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY before running the remote smoke checks.}"
: "${DATABASE_URL:?Set DATABASE_URL before running the remote smoke checks.}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "==> REST smoke: groups select"
groups_http="$(
  curl -sS \
    -o "$tmp_dir/groups.json" \
    -w "%{http_code}" \
    "$SUPABASE_URL/rest/v1/groups?select=id,name,invite_code&limit=1" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY"
)"
if [[ "$groups_http" != "200" ]]; then
  echo "groups select failed with HTTP $groups_http" >&2
  cat "$tmp_dir/groups.json" >&2
  exit 1
fi

echo "==> RPC smoke: get_group_invite_preview"
invite_http="$(
  curl -sS \
    -o "$tmp_dir/invite_preview.json" \
    -w "%{http_code}" \
    "$SUPABASE_URL/rest/v1/rpc/get_group_invite_preview" \
    -X POST \
    -H "apikey: $SUPABASE_ANON_KEY" \
    -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
    -H "Content-Type: application/json" \
    --data '{"p_invite_code":"SMOKETST"}'
)"
if [[ "$invite_http" != "200" ]]; then
  echo "get_group_invite_preview failed with HTTP $invite_http" >&2
  cat "$tmp_dir/invite_preview.json" >&2
  exit 1
fi

echo "==> DB smoke: create_group_atomic + join_group_via_invite (rollback only)"
psql "$DATABASE_URL" <<'SQL'
\set ON_ERROR_STOP on
begin;

do $$
declare
  v_user_one uuid := gen_random_uuid();
  v_user_two uuid := gen_random_uuid();
  v_phone_one text := '+2507' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_phone_two text := '+2507' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_create jsonb;
  v_join jsonb;
  v_group_id uuid;
begin
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_user_one::text, true);

  insert into auth.users (
    id,
    aud,
    role,
    phone,
    phone_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data
  )
  values
    (
      v_user_one,
      'authenticated',
      'authenticated',
      v_phone_one,
      now(),
      now(),
      now(),
      jsonb_build_object(),
      jsonb_build_object()
    ),
    (
      v_user_two,
      'authenticated',
      'authenticated',
      v_phone_two,
      now(),
      now(),
      now(),
      jsonb_build_object(),
      jsonb_build_object()
    );

  insert into public.users (
    id,
    phone,
    full_name,
    country,
    language_code,
    momo_provider,
    is_driver,
    is_admin
  )
  values
    (v_user_one, v_phone_one, 'Smoke User One', 'RW', 'en', '', false, false),
    (v_user_two, v_phone_two, 'Smoke User Two', 'RW', 'en', '', false, false);

  v_create := public.create_group_atomic(
    'Smoke Group',
    'private',
    'saving',
    null,
    'RW',
    1000,
    100,
    30,
    null,
    null,
    null,
    null
  );

  if coalesce(v_create->>'status', '') <> 'success' then
    raise exception 'create_group_atomic failed: %', coalesce(v_create->>'message', '<no message>');
  end if;

  v_group_id := nullif(v_create->>'group_id', '')::uuid;
  if v_group_id is null then
    raise exception 'create_group_atomic did not return a group id';
  end if;

  if nullif(v_create->>'invite_code', '') is null then
    raise exception 'create_group_atomic did not return an invite code';
  end if;

  perform set_config('request.jwt.claim.sub', v_user_two::text, true);
  v_join := public.join_group_via_invite(v_create->>'invite_code');

  if coalesce(v_join->>'status', '') not in ('joined', 'already_member') then
    raise exception 'join_group_via_invite failed: %', coalesce(v_join->>'message', '<no message>');
  end if;

  if (select count(*) from public.group_members where group_id = v_group_id) <> 2 then
    raise exception 'expected 2 group_members rows after join smoke';
  end if;
end
$$;

rollback;
SQL

echo "==> Supabase contract smoke passed"
