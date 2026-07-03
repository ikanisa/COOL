#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

section() {
  printf '\n## %s\n' "$1"
}

run_rg() {
  local label="$1"
  shift
  section "$label"
  rg --line-number --no-heading "$@" || true
}

section "Existing Supabase dynamic primitives"
rg --line-number --no-heading \
  "create table if not exists (feature_flags|system_settings|app_realtime_events|notification_|payment_instruction_templates)|create or replace function admin_list_(feature_flags|settings)|attach_app_realtime_event_trigger|admin_set_feature_flag" \
  supabase/migrations || true

run_rg "Public content, contacts, URLs, and policy copy" \
  "const _collect|WHATSAPP_NUMBER|DISPLAY_PHONE|USSD_CODE|SUPPORT_EMAIL|PUBLIC_URL|APP_DOWNLOAD_URL|REGISTERED_ENTITY|REGULATORY_FOOTER_NOTE|publicWebsitePaths|_public.*Pages|Privacy Policy|Terms|Data deletion|Account deletion" \
  lib scripts content docs

run_rg "Admin navigation, list specs, filters, and workflow copy" \
  "_adminNavDestinations|adminRoutePaths|_defaultStatuses|_defaultSorts|AdminFilterOption|_AdminQueueSignal|admin_list_" \
  lib/admin supabase/migrations

run_rg "Collection categories, statuses, and payment workflow labels" \
  "CollectionType|collection_type|category_subtype|_defaultCategorySubtype|_defaultProfileCategorySubtype|paymentStatusLabel|paymentStatusTone|_pipelineStep|cadence|network in|check \\(.* in \\(" \
  lib supabase/migrations

run_rg "Notifications, settings, realtime, and platform integration config" \
  "notification|feature_flags|system_settings|collectMobileRealtimeAreas|collectAdminRealtimeAreas|PLAY_INTEGRITY_PACKAGE_NAME|defaultPackageName|defaultCollectPublicUrl|defaultCollectAdminUrl" \
  lib supabase/functions supabase/migrations

run_rg "Fixtures and evidence that should normally stay local" \
  "fixture|evidence|mock|test|UAT|golden|browser_qa|smoke|route.*qa|developer_account_seed" \
  lib test scripts docs supabase/migrations
