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

add_blocker() {
  blocker_keys+=("$1")
  blockers+=("$2")
}

if [[ "${COLLECT_PRODUCT_SIGNOFF_APPROVED:-0}" != "1" ]]; then
  add_blocker "product_signoff" "Corrected SMS-first Groups product definition is not signed off."
fi

if [[ "${COLLECT_ANDROID_SMS_UAT_APPROVED:-0}" != "1" ]]; then
  add_blocker "android_sms_access_uat" "Real Android MoMo SMS ingestion/parser/allocation UAT is not approved."
fi

mobile_gate_json="$(mktemp)"
trap 'rm -f "$mobile_gate_json"' EXIT
if "$ROOT_DIR/scripts/flutter_mobile_release_gate.sh" --json >"$mobile_gate_json"; then
  :
else
  mobile_gate_exit=$?
  if [[ "$mobile_gate_exit" -eq 99 ]] &&
    ruby -r json -e 'data = JSON.parse(File.read(ARGV.fetch(0))); exit(Array(data["blocker_keys"]).include?("android_release_artifacts") ? 0 : 1)' "$mobile_gate_json"; then
    add_blocker "android_release_artifacts" "Current Android release APK/AAB artifacts are missing or stale."
  fi
fi

if [[ -z "${ADMIN_PWA_LIVE_URL:-}" ]]; then
  add_blocker "admin_pwa_live_url" "Admin PWA live deployment URL is missing."
fi

if [[ "${COLLECT_LINKED_SMS_FIRST_UAT_PASSED:-0}" != "1" ]]; then
  add_blocker "linked_supabase_sms_first_migration" "Linked Supabase SMS-first payment-intent UAT is not passed."
fi

if [[ "${COLLECT_RELEASE_OWNER_SIGNOFF_APPROVED:-0}" != "1" ]]; then
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
    printf '    "product_signoff": %s,\n' "$(json_escape "${COLLECT_PRODUCT_SIGNOFF_APPROVED:-0}")"
    printf '    "android_sms_uat": %s,\n' "$(json_escape "${COLLECT_ANDROID_SMS_UAT_APPROVED:-0}")"
    printf '    "android_release_artifacts": %s,\n' "$(json_escape "$([[ " ${blocker_keys[*]} " == *" android_release_artifacts "* ]] && printf stale || printf current)")"
    printf '    "admin_pwa_live_url": %s,\n' "$(json_escape "${ADMIN_PWA_LIVE_URL:+present}")"
    printf '    "linked_sms_first_uat": %s,\n' "$(json_escape "${COLLECT_LINKED_SMS_FIRST_UAT_PASSED:-0}")"
    printf '    "release_owner_signoff": %s\n' "$(json_escape "${COLLECT_RELEASE_OWNER_SIGNOFF_APPROVED:-0}")"
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
