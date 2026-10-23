#!/usr/bin/env bash
set -euo pipefail

# Called by the simulator runner, inside its bounded process supervisor. Build
# first: flutter drive can discover a stale VM service after a failed build.
flutter_executable="$1"
test_driver="$2"
test_target="$3"
simulator_id="$4"
bundle_id="$5"
app_binary="$6"
shift 6

"$flutter_executable" build ios --simulator --debug --no-pub \
  --target="$test_target" "$@"

if [[ ! -f "$app_binary/Info.plist" ]]; then
  printf '[ios-uat-build][FAIL] Fresh app bundle is missing.\n' >&2
  exit 1
fi
actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_binary/Info.plist")"
if [[ "$actual_bundle_id" != "$bundle_id" ]]; then
  printf '[ios-uat-build][FAIL] Built bundle does not match the approved fixture target.\n' >&2
  exit 1
fi
printf '[ios-uat-build] fresh-build-ready bundle=%s\n' "$actual_bundle_id"
"$flutter_executable" drive --no-pub --driver="$test_driver" \
  --target="$test_target" -d "$simulator_id" \
  --use-application-binary="$app_binary" "$@"
