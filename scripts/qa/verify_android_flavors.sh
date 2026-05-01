#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/tmp/cool-gradle-home}"
mkdir -p "$GRADLE_USER_HOME"

if [[ "${COOL_PRODUCTION_ONLY_RELEASE:-0}" == "1" ]]; then
  echo "==> android staging build skipped (COOL_PRODUCTION_ONLY_RELEASE=1)"
else
  echo "==> android flavor build (staging)"
  bash "$ROOT_DIR/scripts/deploy/build_staging.sh"

  staging_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-staging-debug.apk"
  if [[ ! -f "$staging_apk" ]]; then
    echo "Expected staging APK missing: $staging_apk" >&2
    exit 1
  fi
fi

echo "==> android flavor build (production)"
bash "$ROOT_DIR/scripts/deploy/build_production.sh"

production_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-production-release.apk"
if [[ ! -f "$production_apk" ]]; then
  echo "Expected production APK missing: $production_apk" >&2
  exit 1
fi
