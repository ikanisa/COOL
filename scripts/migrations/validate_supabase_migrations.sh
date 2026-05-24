#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
migrations_dir="$root_dir/supabase/migrations"
admin_migration="$migrations_dir/202605230008_admin_panel.sql"

if [ ! -d "$migrations_dir" ]; then
  echo "Missing Supabase migrations directory: $migrations_dir" >&2
  exit 1
fi

duplicates="$(
  find "$migrations_dir" -maxdepth 1 -type f -name '*.sql' -print |
    sed -E 's#^.*/([0-9]{12}).*#\1#' |
    sort |
    uniq -d
)"

if [ -n "$duplicates" ]; then
  echo "Duplicate Supabase migration version prefixes:" >&2
  echo "$duplicates" >&2
  exit 1
fi

if [ ! -f "$admin_migration" ]; then
  echo "Missing admin migration: $admin_migration" >&2
  exit 1
fi

required_patterns=(
  'create table if not exists admin_roles'
  'create table if not exists admin_permissions'
  'create table if not exists admin_role_permissions'
  'create table if not exists admin_user_roles'
  'create table if not exists admin_sensitive_access_logs'
  'create table if not exists feature_flags'
  'create table if not exists system_settings'
  'create table if not exists moderation_flags'
  'create table if not exists admin_notes'
  'create or replace function has_admin_permission'
  'create or replace function assert_admin_permission'
  'create or replace function create_audit_log'
  'create or replace function admin_bootstrap_platform_owner'
  'create or replace function admin_review_public_request'
  'create or replace function admin_moderate_collection'
  'create or replace function admin_manual_allocate_payment'
  'create or replace function admin_reveal_raw_sms'
  'create policy "feature flags read admins"'
  'revoke all on raw_payment_sms from anon, authenticated'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$admin_migration"; then
    echo "Admin migration is missing required pattern: $pattern" >&2
    exit 1
  fi
done

if grep -Eq 'grant select .*raw_body.* on raw_payment_sms to authenticated' "$admin_migration"; then
  echo "Admin migration grants direct raw_body access to authenticated clients" >&2
  exit 1
fi

if ! grep -Fq 'revoke execute on function admin_moderate_collection(uuid, text, text) from public, anon, authenticated' "$migrations_dir/202605230015_admin_collection_moderation.sql"; then
  echo "Admin collection moderation migration must revoke default PUBLIC execute" >&2
  exit 1
fi

echo "Supabase migration validation passed"
