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
  fail 'Native APNs registration bridge is missing.'
grep -q 'registerForRemoteNotifications' ios/Runner/AppDelegate.swift ||
  fail 'UIApplication remote registration is missing.'
grep -q 'didRegisterForRemoteNotificationsWithDeviceToken' ios/Runner/AppDelegate.swift ||
  fail 'APNs token callback is missing.'
grep -q '<key>aps-environment</key>' ios/Runner/Runner.entitlements ||
  fail 'APNs entitlement is missing.'
grep -q '<string>remote-notification</string>' ios/Runner/Info.plist ||
  fail 'Remote-notification background mode is missing.'

MIGRATION='supabase/migrations/20260804150000_native_push_delivery.sql'
[[ -s "$MIGRATION" ]] || fail 'Native push delivery migration is missing.'
for contract in \
  'notification_deliveries' \
  'notification_delivery_attempts' \
  'register_notification_device' \
  'unregister_notification_device' \
  'claim_notification_deliveries' \
  'complete_notification_delivery' \
  'enqueue_contribution_confirmation_notification' \
  'for update of delivery skip locked' \
  'legacy_token_not_deliverable'; do
  grep -q "$contract" "$MIGRATION" || fail "Missing backend contract: $contract."
done

DISPATCH='supabase/functions/dispatch-notifications/index.ts'
[[ -s "$DISPATCH" ]] || fail 'APNs dispatch function is missing.'
grep -q 'requireInternalRequest(req)' "$DISPATCH" ||
  fail 'APNs dispatcher is not internal-only.'
grep -q 'complete_notification_delivery' "$DISPATCH" ||
  fail 'APNs dispatcher does not persist outcomes.'
grep -q 'APNS_PRIVATE_KEY_BASE64' "$DISPATCH" ||
  fail 'APNs dispatcher secret contract is missing.'

for script in scripts/supabase_deploy.sh scripts/supabase_production_readiness.sh; do
  grep -q 'dispatch-notifications' "$script" ||
    fail "dispatch-notifications is missing from $script."
done

printf '[notification-readiness] source-pass transport=apns producers=1 delivery_attempts=enabled\n'
