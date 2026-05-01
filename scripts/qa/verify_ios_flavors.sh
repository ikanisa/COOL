#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "==> skipping iOS flavor verification (macOS required)"
  exit 0
fi

echo "==> iOS schemes"
xcodebuild -list -project ios/Runner.xcodeproj >/tmp/cool_ios_schemes.txt
cat /tmp/cool_ios_schemes.txt

if [[ "${COOL_PRODUCTION_ONLY_RELEASE:-0}" == "1" ]]; then
  echo "==> iOS staging scheme check skipped (COOL_PRODUCTION_ONLY_RELEASE=1)"
else
  if ! rg -q "staging" /tmp/cool_ios_schemes.txt; then
    echo "Missing staging scheme in ios/Runner.xcodeproj" >&2
    exit 1
  fi
fi

if ! rg -q "production" /tmp/cool_ios_schemes.txt; then
  echo "Missing production scheme in ios/Runner.xcodeproj" >&2
  exit 1
fi

if [[ "${COOL_PRODUCTION_ONLY_RELEASE:-0}" == "1" ]]; then
  echo "==> iOS staging build settings skipped (COOL_PRODUCTION_ONLY_RELEASE=1)"
else
  echo "==> iOS staging build settings"
  xcodebuild \
    -workspace ios/Runner.xcworkspace \
    -scheme staging \
    -configuration Debug-staging \
    -showBuildSettings | rg "APP_DISPLAY_NAME|APP_BUNDLE_IDENTIFIER|PRODUCT_BUNDLE_IDENTIFIER"
fi

echo "==> iOS production build settings"
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme production \
  -configuration Release-production \
  -showBuildSettings | rg "APP_DISPLAY_NAME|APP_BUNDLE_IDENTIFIER|PRODUCT_BUNDLE_IDENTIFIER"
