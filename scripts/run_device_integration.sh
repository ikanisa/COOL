#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"

FLAVOR="${FLAVOR:-staging}"
DEVICE="${DEVICE:-}"
TARGET="${TARGET:-integration_test/critical_journeys_test.dart}"

if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

cmd=(
  "$FLUTTER_BIN" test
  "$TARGET"
  "--flavor=$FLAVOR"
  "--dart-define=FLAVOR=$FLAVOR"
  "--dart-define=SUPABASE_URL=${SUPABASE_URL:-}"
  "--dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}"
  "--dart-define=COOL_APP_MOMO_NUMBER=${COOL_APP_MOMO_NUMBER:-}"
  "--dart-define=GOOGLE_MAPS_ANDROID_MAP_ID=${GOOGLE_MAPS_ANDROID_MAP_ID:-}"
  "--dart-define=GOOGLE_MAPS_IOS_MAP_ID=${GOOGLE_MAPS_IOS_MAP_ID:-}"
  "--dart-define=COOL_DEEP_LINK_HOST=${COOL_DEEP_LINK_HOST:-cool.app}"
)

if [[ -n "$DEVICE" ]]; then
  cmd+=("-d" "$DEVICE")
fi

printf '==> %q ' "${cmd[@]}"
printf '\n'
"${cmd[@]}"
