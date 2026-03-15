#!/usr/bin/env bash
# Build production iOS app without codesigning for release validation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"
# shellcheck source=scripts/_ios_release_env.sh
source "$ROOT_DIR/scripts/_ios_release_env.sh"

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
    if ios_value_is_placeholder "$GOOGLE_MAPS_IOS_API_KEY"; then
      return
    fi

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

  local existing_maps_key
  existing_maps_key="$(resolve_ios_maps_key || true)"
  if ! ios_value_is_placeholder "$existing_maps_key"; then
    return
  fi
}

require_build_env() {
  : "${SUPABASE_URL:?Set SUPABASE_URL before building the production iOS app.}"
  : "${SUPABASE_ANON_KEY:?Set SUPABASE_ANON_KEY before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_API_KEY:?Set FIREBASE_IOS_PRODUCTION_API_KEY before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_APP_ID:?Set FIREBASE_IOS_PRODUCTION_APP_ID before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID:?Set FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_PROJECT_ID:?Set FIREBASE_IOS_PRODUCTION_PROJECT_ID before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET:?Set FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET before building the production iOS app.}"
  : "${FIREBASE_IOS_PRODUCTION_BUNDLE_ID:?Set FIREBASE_IOS_PRODUCTION_BUNDLE_ID before building the production iOS app.}"
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

if [[ -f .env.json ]]; then
  for json_key in \
    SUPABASE_URL \
    SUPABASE_ANON_KEY \
    GOOGLE_MAPS_ANDROID_API_KEY \
    GOOGLE_MAPS_IOS_API_KEY \
    GOOGLE_MAPS_ANDROID_MAP_ID \
    GOOGLE_MAPS_IOS_MAP_ID \
    COOL_DEEP_LINK_HOST \
    FIREBASE_IOS_PRODUCTION_API_KEY \
    FIREBASE_IOS_PRODUCTION_APP_ID \
    FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID \
    FIREBASE_IOS_PRODUCTION_PROJECT_ID \
    FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET \
    FIREBASE_IOS_PRODUCTION_BUNDLE_ID; do
    if [[ -z "${!json_key:-}" ]]; then
      json_value="$(jq -r --arg key "$json_key" '.[$key] // empty' .env.json)"
      if [[ -n "$json_value" ]]; then
        export "$json_key=$json_value"
      fi
    fi
  done
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
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_API_KEY="${FIREBASE_IOS_PRODUCTION_API_KEY}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_APP_ID="${FIREBASE_IOS_PRODUCTION_APP_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID="${FIREBASE_IOS_PRODUCTION_MESSAGING_SENDER_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_PROJECT_ID="${FIREBASE_IOS_PRODUCTION_PROJECT_ID}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET="${FIREBASE_IOS_PRODUCTION_STORAGE_BUCKET}" \
  --dart-define=FIREBASE_IOS_PRODUCTION_BUNDLE_ID="${FIREBASE_IOS_PRODUCTION_BUNDLE_ID}"

echo ""
echo "✅ Production iOS build: build/ios/iphoneos/Cool.app"
