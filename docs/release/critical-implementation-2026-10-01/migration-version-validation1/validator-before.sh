#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
migrations_dir="$root_dir/supabase/migrations"
admin_migration="$migrations_dir/202605230008_admin_panel.sql"
sms_first_migration="$migrations_dir/202605270001_sms_first_group_payment_intents.sql"

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

if [ ! -f "$sms_first_migration" ]; then
  echo "Missing SMS-first group payment intent migration: $sms_first_migration" >&2
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

sms_first_required_patterns=(
  'add column if not exists contributor_public_id char(6)'
  'create index if not exists payment_intents_member_sms_match_idx'
  'create or replace function create_contribution_intent'
  'create or replace function join_group_by_slug'
  'create or replace function allocate_parsed_payment_event'
  'auto_member_intent'
  'revoke execute on function report_payment_intent_paid(uuid, text)'
  'revoke execute on function manual_allocate_parsed_payment_event(uuid, uuid, uuid, text)'
  'revoke execute on function admin_manual_allocate_payment(uuid, uuid, uuid, text)'
  'revoke execute on function request_public_collection(uuid)'
  'revoke execute on function review_public_collection(uuid, boolean, text)'
  'revoke execute on function admin_review_public_request(uuid, boolean, text)'
  'revoke execute on function admin_list_public_requests(text, text)'
  'revoke execute on function admin_moderate_collection(uuid, text, text)'
  "delete from admin_permissions"
  "create or replace function admin_overview"
  'revoke all on public_collections_view'
  'revoke all on member_public_collection_requests_view'
  'revoke all on collection_summary_view'
  'revoke all on parsed_payment_events_review_view'
  'revoke all on payment_instruction_templates'
  'drop function if exists report_payment_intent_paid(uuid, text)'
  'drop function if exists manual_allocate_parsed_payment_event(uuid, uuid, uuid, text)'
  'drop function if exists admin_manual_allocate_payment(uuid, uuid, uuid, text)'
  'drop function if exists request_public_collection(uuid)'
  'drop function if exists review_public_collection(uuid, boolean, text)'
  'drop function if exists admin_review_public_request(uuid, boolean, text)'
  'drop function if exists admin_list_public_requests(text, text)'
  'drop function if exists admin_moderate_collection(uuid, text, text)'
  'drop function if exists create_collection_invite(uuid, text, text, member_role)'
  'drop function if exists create_collection_with_owner(text, text, text, bigint, text, text, text, text, boolean, jsonb)'
  'drop function if exists record_receiver_mode_consent(boolean, text, text, text)'
  'drop view if exists member_public_collection_requests_view'
  'drop view if exists public_collections_view'
  'drop view if exists collection_summary_view'
  'drop view if exists parsed_payment_events_review_view'
  'drop view if exists public_profiles_view'
  'drop view if exists public_contributions_view'
  'drop table if exists payment_instruction_templates'
  'drop table if exists public_collection_requests'
  'create or replace function admin_list_collections'
  'create or replace function admin_get_payment_event'
  'set sender_name = null'
  "'Collect ID ' || p.public_id"
  "'payments.allocate'"
  'grant execute on function join_group_by_slug'
  "'enable_android_sms_access'"
  "'enable_internal_receiver_mode'"
)

for pattern in "${sms_first_required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$sms_first_migration"; then
    echo "SMS-first migration is missing required pattern: $pattern" >&2
    exit 1
  fi
done

if grep -Eq "'ENABLE_(ANDROID_SMS_ACCESS|SMS_READER|INTERNAL_RECEIVER_MODE)'|'ADMIN_PANEL_ENABLED'" "$migrations_dir"/*.sql; then
  echo "Supabase feature flag keys must be lowercase to satisfy feature_flags_key_check" >&2
  exit 1
fi

echo "Supabase migration validation passed"
