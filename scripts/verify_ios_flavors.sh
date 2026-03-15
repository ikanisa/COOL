#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck source=scripts/_ios_release_env.sh
source "$ROOT_DIR/scripts/_ios_release_env.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "==> skipping iOS flavor verification (macOS required)"
  exit 0
fi

if ! has_ios_maps_key; then
  echo "==> iOS embedded Google Maps key not set; map widgets will stay hidden in this build"
fi

echo "==> iOS schemes"
xcodebuild -list -project ios/Runner.xcodeproj >/tmp/cool_ios_schemes.txt
cat /tmp/cool_ios_schemes.txt

if ! rg -q "staging" /tmp/cool_ios_schemes.txt; then
  echo "Missing staging scheme in ios/Runner.xcodeproj" >&2
  exit 1
fi

if ! rg -q "production" /tmp/cool_ios_schemes.txt; then
  echo "Missing production scheme in ios/Runner.xcodeproj" >&2
  exit 1
fi

echo "==> iOS staging build settings"
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme staging \
  -configuration Debug-staging \
  -showBuildSettings | rg "APP_DISPLAY_NAME|APP_BUNDLE_IDENTIFIER|PRODUCT_BUNDLE_IDENTIFIER"

echo "==> iOS production build settings"
xcodebuild \
  -workspace ios/Runner.xcworkspace \
  -scheme production \
  -configuration Release-production \
  -showBuildSettings | rg "APP_DISPLAY_NAME|APP_BUNDLE_IDENTIFIER|PRODUCT_BUNDLE_IDENTIFIER"
