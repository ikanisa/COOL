#!/usr/bin/env bash
# Build production iOS app without codesigning for release validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"
readonly IOS_MAPS_KEYS_XCCONFIG="$ROOT_DIR/ios/Flutter/MapsKeys.xcconfig"

MAPS_KEYS_BACKUP=""

restore_ios_maps_keys() {
  if [[ -n "$MAPS_KEYS_BACKUP" && -f "$MAPS_KEYS_BACKUP" ]]; then
    mv "$MAPS_KEYS_BACKUP" "$IOS_MAPS_KEYS_XCCONFIG"
    return
  fi

  rm -f "$IOS_MAPS_KEYS_XCCONFIG"
}

prepare_ios_maps_keys() {
  if [[ -n "${GOOGLE_MAPS_IOS_API_KEY:-}" ]]; then
    if [[ -f "$IOS_MAPS_KEYS_XCCONFIG" ]]; then
      MAPS_KEYS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/cool-maps-keys.XXXXXX")"
      cp "$IOS_MAPS_KEYS_XCCONFIG" "$MAPS_KEYS_BACKUP"
    fi

    cat > "$IOS_MAPS_KEYS_XCCONFIG" <<EOF
// Generated temporarily by scripts/build_ios_production.sh.
// Do not commit this file with real keys.
GOOGLE_MAPS_IOS_API_KEY=${GOOGLE_MAPS_IOS_API_KEY}
EOF
    chmod 600 "$IOS_MAPS_KEYS_XCCONFIG"
    trap restore_ios_maps_keys EXIT
    return
  fi

  if [[ -f "$IOS_MAPS_KEYS_XCCONFIG" ]] &&
    grep -Eq '^GOOGLE_MAPS_IOS_API_KEY=.+' "$IOS_MAPS_KEYS_XCCONFIG"; then
    return
  fi

  echo "Set GOOGLE_MAPS_IOS_API_KEY or create ios/Flutter/MapsKeys.xcconfig before building iOS." >&2
  exit 1
}

require_build_env() {
  : "${SUPABASE_URL:?Set SUPABASE_URL before building the production iOS app.}"
  : "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY before building the production iOS app.}"
  prepare_ios_maps_keys
}

echo "══════════════════════════════════════════════════════"
echo "  Building PRODUCTION iOS app"
echo "══════════════════════════════════════════════════════"

if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

require_build_env

"$FLUTTER_BIN" build ios \
  --release \
  --flavor production \
  --no-codesign \
  --dart-define=FLAVOR=production \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_API_KEY="${GOOGLE_MAPS_ANDROID_API_KEY:-}" \
  --dart-define=GOOGLE_MAPS_IOS_API_KEY="${GOOGLE_MAPS_IOS_API_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_MAP_ID="${GOOGLE_MAPS_ANDROID_MAP_ID:-}" \
  --dart-define=GOOGLE_MAPS_IOS_MAP_ID="${GOOGLE_MAPS_IOS_MAP_ID:-}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}"

echo ""
echo "✅ Production iOS build: build/ios/iphoneos/Cool.app"
