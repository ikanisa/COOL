#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
case "${1:-}" in
  --json) output_format="json" ;;
  "") ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

json_escape() {
  ruby -r json -e 'puts JSON.generate(ARGV.fetch(0))' "$1"
}

blockers=()
blocker_keys=()
approval_gate_json="$(mktemp)"
mobile_gate_json="$(mktemp)"
trap 'rm -f "$approval_gate_json" "$mobile_gate_json"' EXIT

add_blocker() {
  blocker_keys+=("$1")
  blockers+=("$2")
}

has_blocker() {
  local needle="$1"
  local key
  [[ "${#blocker_keys[@]}" -eq 0 ]] && return 1
  for key in "${blocker_keys[@]}"; do
    [[ "$key" == "$needle" ]] && return 0
  done
  return 1
}

if "$ROOT_DIR/scripts/release_approval_evidence_gate.sh" --json >"$approval_gate_json"; then
  :
else
  approval_gate_exit=$?
  if [[ "$approval_gate_exit" -ne 99 ]]; then
    :
  fi
fi

approval_approved() {
  ruby -r json -e 'data = JSON.parse(File.read(ARGV.fetch(0))); puts(data.dig("approvals", ARGV.fetch(1), "approved") == true ? "1" : "0")' "$approval_gate_json" "$1" 2>/dev/null || printf '0\n'
}

product_signoff_approved="${COLLECT_PRODUCT_SIGNOFF_APPROVED:-}"
if [[ -z "$product_signoff_approved" ]]; then
  product_signoff_approved="$(approval_approved product_signoff)"
fi

android_sms_uat_approved="${COLLECT_ANDROID_SMS_UAT_APPROVED:-}"
if [[ -z "$android_sms_uat_approved" ]]; then
  android_sms_uat_approved="$(approval_approved android_sms_access_uat)"
fi

release_owner_signoff_approved="${COLLECT_RELEASE_OWNER_SIGNOFF_APPROVED:-}"
if [[ -z "$release_owner_signoff_approved" ]]; then
  release_owner_signoff_approved="$(approval_approved release_owner_signoff)"
fi

if [[ "$product_signoff_approved" != "1" ]]; then
  add_blocker "product_signoff" "Corrected SMS-first Groups product definition is not signed off."
fi

if [[ "$android_sms_uat_approved" != "1" ]]; then
  add_blocker "android_sms_access_uat" "Real Android MoMo SMS ingestion/parser/allocation UAT is not approved."
fi

if "$ROOT_DIR/scripts/flutter_mobile_release_gate.sh" --json >"$mobile_gate_json"; then
  :
else
  mobile_gate_exit=$?
  if [[ "$mobile_gate_exit" -eq 99 ]]; then
    while IFS= read -r key; do
      case "$key" in
        android_release_artifacts)
          add_blocker "android_release_artifacts" "Current Android release APK/AAB artifacts are missing or stale."
          ;;
        android_release_signing_review)
          add_blocker "android_release_signing_review" "Android release signing / Play App Signing review is not approved."
          ;;
        ios_release_scope)
          add_blocker "ios_release_scope" "iOS release scope is not signed off or explicitly marked out of scope."
          ;;
      esac
    done < <(ruby -r json -e 'data = JSON.parse(File.read(ARGV.fetch(0))); Array(data["blocker_keys"]).each { |key| puts key }' "$mobile_gate_json")
  fi
fi

if [[ -z "${ADMIN_PWA_LIVE_URL:-}" ]]; then
  add_blocker "admin_pwa_live_url" "Admin PWA live deployment URL is missing."
fi

linked_sms_first_uat="${COLLECT_LINKED_SMS_FIRST_UAT_PASSED:-}"
if [[ -z "$linked_sms_first_uat" ]]; then
  if "$ROOT_DIR/scripts/collect_linked_uat.sh" >/dev/null 2>&1; then
    linked_sms_first_uat="1"
  else
    linked_sms_first_uat="0"
  fi
fi

if [[ "$linked_sms_first_uat" != "1" ]]; then
  add_blocker "linked_supabase_sms_first_migration" "Linked Supabase SMS-first payment-intent UAT is not passed."
fi

if [[ "$release_owner_signoff_approved" != "1" ]]; then
  add_blocker "release_owner_signoff" "Release-owner signoff for the current evidence packet is not approved."
fi

decision="NO-GO"
status="blocked"
if [[ "${#blocker_keys[@]}" -eq 0 ]]; then
  decision="GO"
  status="pass"
fi

if [[ "$output_format" == "json" ]]; then
  {
    printf '{\n'
    printf '  "decision": %s,\n' "$(json_escape "$decision")"
    printf '  "status": %s,\n' "$(json_escape "$status")"
    printf '  "supabase_strict": %s,\n' "$(json_escape "$status")"
    printf '  "blocker_keys": ['
    for i in "${!blocker_keys[@]}"; do
      [[ "$i" -gt 0 ]] && printf ', '
      printf '%s' "$(json_escape "${blocker_keys[$i]}")"
    done
    printf '],\n'
    printf '  "blockers": ['
    for i in "${!blockers[@]}"; do
      [[ "$i" -gt 0 ]] && printf ', '
      printf '%s' "$(json_escape "${blockers[$i]}")"
    done
    printf '],\n'
    printf '  "evidence_flags": {\n'
    printf '    "product_signoff": %s,\n' "$(json_escape "$product_signoff_approved")"
    printf '    "android_sms_uat": %s,\n' "$(json_escape "$android_sms_uat_approved")"
    printf '    "android_release_artifacts": %s,\n' "$(json_escape "$(has_blocker android_release_artifacts && printf stale || printf current)")"
    printf '    "android_release_signing_review": %s,\n' "$(json_escape "$(has_blocker android_release_signing_review && printf missing || printf current)")"
    printf '    "ios_release_scope": %s,\n' "$(json_escape "$(has_blocker ios_release_scope && printf missing || printf current)")"
    printf '    "admin_pwa_live_url": %s,\n' "$(json_escape "${ADMIN_PWA_LIVE_URL:+present}")"
    printf '    "linked_sms_first_uat": %s,\n' "$(json_escape "$linked_sms_first_uat")"
    printf '    "release_owner_signoff": %s\n' "$(json_escape "$release_owner_signoff_approved")"
    printf '  }\n'
    printf '}\n'
  }
else
  printf '[release-status] decision=%s\n' "$decision"
  printf '[release-status] status=%s\n' "$status"
  if [[ "${#blockers[@]}" -gt 0 ]]; then
    printf '[release-status] blockers:\n'
    for blocker in "${blockers[@]}"; do
      printf '  - %s\n' "$blocker"
    done
  fi
fi

exit 0
