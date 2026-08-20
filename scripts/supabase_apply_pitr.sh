#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

: "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN is required}"
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"

PITR_ADDON_VARIANT="${PITR_ADDON_VARIANT:-pitr_7}"
CONFIRM_ENABLE_PITR="${CONFIRM_ENABLE_PITR:-}"

log() {
  printf '[supabase-pitr] %s\n' "$*"
}

fail() {
  printf '[supabase-pitr][FAIL] %s\n' "$*" >&2
  exit 1
}

addons_json="$(curl -fsS "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/billing/addons" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN")"

ADDONS_JSON="$addons_json" ruby -r json - "$PITR_ADDON_VARIANT" <<'RUBY'
variant = ARGV.fetch(0)
data = JSON.parse(ENV.fetch("ADDONS_JSON"))
selected = data.fetch("selected_addons", []).find { |addon| addon["type"] == "pitr" }
pitr = data.fetch("available_addons", []).find { |addon| addon["type"] == "pitr" }
abort("[supabase-pitr][FAIL] PITR add-on is not available for this project.") unless pitr

variants = pitr.fetch("variants").map { |item| [item.fetch("id"), item] }.to_h
abort("[supabase-pitr][FAIL] Unknown PITR_ADDON_VARIANT=#{variant}. Available: #{variants.keys.join(", ")}") unless variants.key?(variant)

if selected
  selected_variant = selected.fetch("variant")
  puts "[supabase-pitr] current_pitr=#{selected_variant.fetch("id")} #{selected_variant.fetch("name")}"
else
  puts "[supabase-pitr] current_pitr=none"
end

choice = variants.fetch(variant)
price = choice.fetch("price")
puts "[supabase-pitr] requested_pitr=#{choice.fetch("id")} #{choice.fetch("name")} #{price.fetch("description")}"
RUBY

if [[ "$CONFIRM_ENABLE_PITR" != "$SUPABASE_PROJECT_REF:$PITR_ADDON_VARIANT" ]]; then
  fail "PITR is billable. Re-run with CONFIRM_ENABLE_PITR=$SUPABASE_PROJECT_REF:$PITR_ADDON_VARIANT to apply."
fi

log "applying PITR add-on variant $PITR_ADDON_VARIANT"
curl -fsS -X PATCH "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/billing/addons" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"addon_type\":\"pitr\",\"addon_variant\":\"$PITR_ADDON_VARIANT\"}" \
  >/dev/null

log "PITR add-on request accepted; rerun make supabase-ready-strict after Supabase finishes provisioning"
