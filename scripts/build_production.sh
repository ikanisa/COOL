#!/usr/bin/env bash
# Build production release APK (signed)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
readonly FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/scripts/flutterw}"

echo "══════════════════════════════════════════════════════"
echo "  Building PRODUCTION release APK"
echo "══════════════════════════════════════════════════════"

production_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-production-release.apk"
rm -f "$production_apk"

# Source env vars from .env if available
if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

"$FLUTTER_BIN" build apk \
  --release \
  --flavor production \
  --dart-define=FLAVOR=production \
  --dart-define=SUPABASE_URL="${SUPABASE_URL:-}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-}" \
  --dart-define=GOOGLE_MAPS_ANDROID_MAP_ID="${GOOGLE_MAPS_ANDROID_MAP_ID:-}" \
  --dart-define=GOOGLE_MAPS_IOS_MAP_ID="${GOOGLE_MAPS_IOS_MAP_ID:-}" \
  --dart-define=COOL_DEEP_LINK_HOST="${COOL_DEEP_LINK_HOST:-cool.app}"

if [[ ! -f "$production_apk" ]]; then
  echo "Production APK was not generated: $production_apk" >&2
  exit 1
fi

echo ""
echo "✅ Production APK: $production_apk"
