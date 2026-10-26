#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf '[notification-readiness][FAIL] %s\n' "$*" >&2
  exit 1
}

grep -q 'notificationTapPayloads' lib/core/notifications/collect_notification_service.dart ||
  fail 'Notification tap stream is missing.'
grep -q 'normalizeNotificationDeepLink' lib/core/notifications/collect_notification_service.dart ||
  fail 'Notification deep-link allowlist is missing.'
grep -q 'requestRemoteRegistration' lib/core/notifications/collect_notification_service.dart ||
  fail 'Native push registration is missing.'
grep -q 'FirebaseMessaging.onBackgroundMessage' lib/core/notifications/collect_notification_service.dart ||
  fail 'Android FCM background handler is missing.'
grep -q 'FirebaseMessaging.onMessageOpenedApp' lib/core/notifications/collect_notification_service.dart ||
  fail 'Android FCM notification-tap handling is missing.'
grep -q 'AndroidNotificationChannel' lib/core/notifications/collect_notification_service.dart ||
  fail 'Android native notification channels are missing.'
grep -q 'registerForRemoteNotifications' ios/Runner/AppDelegate.swift ||
  fail 'UIApplication remote registration is missing.'
grep -q 'didRegisterForRemoteNotificationsWithDeviceToken' ios/Runner/AppDelegate.swift ||
  fail 'APNs token callback is missing.'
grep -q '<key>aps-environment</key>' ios/Runner/Runner.entitlements ||
  fail 'APNs entitlement is missing.'
grep -q '<string>remote-notification</string>' ios/Runner/Info.plist ||
  fail 'Remote-notification background mode is missing.'

backend="${COLLECT_BACKEND:-supabase}"
[[ "$backend" == supabase ]] || fail 'Current notification readiness requires the selected Supabase backend.'
STORE='supabase/migrations/20261020134444_collect_curated_platform_baseline.sql'
DISPATCH='supabase/functions/_shared/domain/notifications.js'
[[ -s supabase/functions/collect-api/index.ts &&
   -s supabase/functions/_shared/serve.js &&
   -s supabase/functions/_shared/postgres.js ]] ||
  fail 'The Supabase notification entrypoint or Postgres adapter is missing.'
grep -Fq "createHandler('collect-api')" supabase/functions/collect-api/index.ts &&
  grep -Fq 'new PostgresDatabase(connection(env.COLLECT_DATABASE_URL))' supabase/functions/_shared/serve.js &&
  grep -Fq "from './notifications.js'" supabase/functions/_shared/domain/index.js &&
  grep -Fq "import {notificationRpc} from './notifications.js'" supabase/functions/_shared/domain/operations.js &&
  grep -Fq "['rpc','notifications.js',notificationRpc,[" supabase/functions/_shared/domain/operations.js ||
  fail 'The Supabase notification data-plane wiring is missing.'
python3 -B - <<'PY' || fail 'The Supabase notification registration operations are not routed to their handler.'
from pathlib import Path
import re

source = Path('supabase/functions/_shared/domain/operations.js').read_text()
row = re.search(r"\['rpc','notifications\.js',notificationRpc,\[(.*?)\]\]", source, re.S)
required = {'register_notification_device', 'unregister_notification_device'}
if row is None or not required.issubset(re.findall(r"'([^']+)'", row[1])):
    raise SystemExit('Notification registration routing is incomplete.')
PY
[[ -s "$STORE" && -s "$DISPATCH" ]] || fail 'Current notification store or handler is missing.'
for contract in notification_events notification_devices notification_preferences; do
  grep -Eq "CREATE TABLE (app\\.)?${contract}[[:space:]]*\\(" "$STORE" ||
    fail "Current notification table is missing: $contract."
done
for contract in register_notification_device unregister_notification_device; do
  grep -Fq "case '$contract':" "$DISPATCH" || fail "Current notification handler case is missing: $contract."
done
for contract in owner_session_id token_ciphertext; do
  grep -q "$contract" "$DISPATCH" || fail "Current notification handler contract is missing: $contract."
done
printf '[notification-readiness] source-pass backend=%s outbound_delivery=requires_hosted_acceptance\n' "$backend"
