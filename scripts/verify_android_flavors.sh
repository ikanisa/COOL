#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> android flavor build (staging)"
bash "$ROOT_DIR/scripts/build_staging.sh"

staging_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-staging-debug.apk"
if [[ ! -f "$staging_apk" ]]; then
  echo "Expected staging APK missing: $staging_apk" >&2
  exit 1
fi

echo "==> android flavor build (production)"
bash "$ROOT_DIR/scripts/build_production.sh"

production_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-production-release.apk"
if [[ ! -f "$production_apk" ]]; then
  echo "Expected production APK missing: $production_apk" >&2
  exit 1
fi
