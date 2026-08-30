#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
case "${1:-}" in
  "") ;;
  --json) output_format="json" ;;
  *)
    printf 'usage: %s [--json]\n' "$0" >&2
    exit 2
    ;;
esac

fail() {
  if [[ "$output_format" == "json" ]]; then
    IOS_APP_STORE_FAILURE="$*" ruby -r json -r time -e '
      puts JSON.pretty_generate(
        {
          "generated_at" => Time.now.utc.iso8601,
          "status" => "fail",
          "failures" => [ENV.fetch("IOS_APP_STORE_FAILURE")]
        }
      )
    '
  else
    printf '[ios-app-store-readiness][FAIL] %s\n' "$*" >&2
  fi
  exit 1
}

validate_png_set() {
  local pattern="$1"
  local expected_width="$2"
  local expected_height="$3"
  local expected_count="$4"
  local count=0

  while IFS= read -r png; do
    count=$((count + 1))
    local width height alpha
    width="$(sips -g pixelWidth "$png" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    height="$(sips -g pixelHeight "$png" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    alpha="$(sips -g hasAlpha "$png" 2>/dev/null | awk '/hasAlpha/ {print $2}')"
    [[ "$width" == "$expected_width" && "$height" == "$expected_height" ]] ||
      fail "Unexpected screenshot dimensions for $png: ${width}x${height}."
    [[ "$alpha" == "no" ]] || fail "Screenshot contains an alpha channel: $png."
  done < <(find fastlane/screenshots/en-GB -maxdepth 1 -type f -name "$pattern" | sort)

  [[ "$count" -eq "$expected_count" ]] ||
    fail "Expected $expected_count screenshots matching $pattern, found $count."
}

for plist in \
  ios/Runner/Info.plist \
  ios/Runner/PrivacyInfo.xcprivacy \
  ios/Runner/Runner.entitlements \
  ios/ExportOptionsAppStore.plist; do
  plutil -lint "$plist" >/dev/null || fail "Invalid plist: $plist."
done

grep -q 'PrivacyInfo.xcprivacy in Resources' ios/Runner.xcodeproj/project.pbxproj ||
  fail 'PrivacyInfo.xcprivacy is not included in the Runner resources build phase.'
grep -q '<string>FlutterSceneDelegate</string>' ios/Runner/Info.plist ||
  fail 'Flutter UIScene lifecycle configuration is missing.'
grep -q '<key>CFBundleAllowMixedLocalizations</key>' ios/Runner/Info.plist ||
  fail 'Apple-platform share-sheet localization support is missing.'
plutil -extract UIBackgroundModes json -o - ios/Runner/Info.plist | grep -q 'remote-notification' ||
  fail 'Remote-notification background mode is missing.'
[[ "$(plutil -extract aps-environment raw -o - ios/Runner/Runner.entitlements)" == '$(APS_ENVIRONMENT)' ]] ||
  fail 'APNs entitlement is missing or not configuration-driven.'
[[ "$(plutil -extract CollectAPNSEnvironment raw -o - ios/Runner/Info.plist)" == '$(APS_ENVIRONMENT)' ]] ||
  fail 'APNs runtime environment is not aligned with the signed entitlement.'
grep -q 'com.apple.Push' ios/Runner.xcodeproj/project.pbxproj ||
  fail 'Xcode Push Notifications capability is missing.'
grep -q '^APS_ENVIRONMENT=production$' ios/Flutter/Release-production.xcconfig ||
  fail 'Production Release APNs environment is not production.'
grep -q 'APNS_ENVIRONMENT' fastlane/Fastfile ||
  fail 'Fastlane production Dart environment does not declare APNs production.'
grep -q -- '-t tool/main_store_preview.dart' scripts/app_store_ios_capture_assets.sh ||
  fail 'App Store screenshots are not bound to the dedicated synthetic preview target.'
if rg -n 'main_store_preview\.dart|CollectRepository\.fixture' \
  scripts/ios_app_store_build.sh fastlane/Fastfile ios/Runner.xcodeproj/project.pbxproj; then
  fail 'The store-preview fixture target is referenced by a production build path.'
fi

plutil -convert json -o - ios/Runner/PrivacyInfo.xcprivacy | ruby -r json -e '
  manifest = JSON.parse($stdin.read)
  abort("App-level tracking must be disabled.") unless manifest["NSPrivacyTracking"] == false
  abort("Tracking domains must be empty.") unless Array(manifest["NSPrivacyTrackingDomains"]).empty?
  required = %w[
    NSPrivacyCollectedDataTypePhoneNumber
    NSPrivacyCollectedDataTypeUserID
    NSPrivacyCollectedDataTypeDeviceID
    NSPrivacyCollectedDataTypePaymentInfo
    NSPrivacyCollectedDataTypeOtherFinancialInfo
    NSPrivacyCollectedDataTypePhotosorVideos
    NSPrivacyCollectedDataTypeCustomerSupport
    NSPrivacyCollectedDataTypeOtherUserContent
  ]
  rows = Array(manifest["NSPrivacyCollectedDataTypes"])
  types = rows.map { |row| row.fetch("NSPrivacyCollectedDataType") }
  missing = required - types
  abort("Missing privacy-manifest data types: #{missing.join(", ")}") unless missing.empty?
  abort("Privacy-manifest data types must be unique.") unless types.uniq.length == types.length
  rows.each do |row|
    abort("Collected data must be linked to the user.") unless row["NSPrivacyCollectedDataTypeLinked"] == true
    abort("Collected data must not be used for tracking.") unless row["NSPrivacyCollectedDataTypeTracking"] == false
    purposes = Array(row["NSPrivacyCollectedDataTypePurposes"])
    abort("Collected data must be limited to app functionality.") unless purposes == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
  end
' || fail 'App privacy manifest is incomplete or invalid.'

while IFS= read -r icon; do
  alpha="$(sips -g hasAlpha "$icon" 2>/dev/null | awk '/hasAlpha/ {print $2}')"
  [[ "$alpha" == "no" ]] || fail "App icon contains an alpha channel: $icon."
done < <(find ios/Runner/Assets.xcassets/AppIcon.appiconset -maxdepth 1 -type f -name '*.png' | sort)

validate_png_set 'iphone65-*.png' 1242 2688 5
validate_png_set 'ipadPro129-*.png' 2048 2732 5

for metadata in \
  fastlane/metadata/en-GB/description.txt \
  fastlane/metadata/en-GB/keywords.txt \
  fastlane/metadata/en-GB/marketing_url.txt \
  fastlane/metadata/en-GB/privacy_url.txt \
  fastlane/metadata/en-GB/promotional_text.txt \
  fastlane/metadata/en-GB/release_notes.txt \
  fastlane/metadata/en-GB/review_notes.txt \
  fastlane/metadata/en-GB/subtitle.txt \
  fastlane/metadata/en-GB/support_url.txt \
  fastlane/metadata/copyright.txt; do
  [[ -s "$metadata" ]] || fail "Missing App Store metadata: $metadata."
done

if rg -n -i '\b(?:stripe|momo|mobile money|card payment|direct debit)\b' \
  fastlane/metadata/en-GB; then
  fail 'Current App Store metadata still references a retired payment rail.'
fi

package_version="$(awk '/^version:[[:space:]]*/ { print $2; exit }' pubspec.yaml)"
package_build_number="${package_version##*+}"
grep -q 'DEFAULT_BUILD_NUMBER="${PACKAGE_VERSION##\*+}"' scripts/ios_app_store_build.sh ||
  fail 'The iOS production wrapper does not derive its default build from pubspec.yaml.'
[[ "$package_build_number" =~ ^[0-9]+$ ]] || fail 'The pubspec build number is invalid.'

ruby -r json -e '
  path = "fastlane/app_privacy_details.json"
  rows = JSON.parse(File.read(path))
  abort("App Privacy details must be a non-empty array.") unless rows.is_a?(Array) && !rows.empty?
  categories = rows.map { |row| row.fetch("category") }
  abort("App Privacy categories must be unique.") unless categories.uniq.length == categories.length
  required = %w[CUSTOMER_SUPPORT DEVICE_ID NAME OTHER_DATA_TYPES OTHER_FINANCIAL_INFO OTHER_USER_CONTENT PHONE_NUMBER PHOTOS_OR_VIDEOS USER_ID]
  missing = required - categories
  abort("Missing App Privacy categories: #{missing.join(", ")}") unless missing.empty?
  abort("Payment information must not be declared because banking details stay outside Collect.") if categories.include?("PAYMENT_INFORMATION")
' || fail "App Privacy details are incomplete or invalid."
privacy_type_count="$(ruby -r json -e 'puts JSON.parse(File.read("fastlane/app_privacy_details.json")).length')"

for build_contract in \
  'SUPABASE_PRODUCTION_URL' \
  'SUPABASE_PRODUCTION_ANON_KEY' \
  'APP_ENVIRONMENT'; do
  grep -q "$build_contract" fastlane/Fastfile ||
    fail "Fastlane production build contract is missing $build_contract."
done
if rg -q 'APP_REVIEW_AUTH_(ENABLED|PHONE|OTP)|signInForAppReview|appReviewDemo' \
  lib fastlane/Fastfile .github/workflows/ios-app-store.yml; then
  fail 'Production App Review packaging must not embed reviewer credentials or a local auth bypass.'
fi

if [[ "$output_format" == "json" ]]; then
  PRIVACY_TYPE_COUNT="$privacy_type_count" ruby -r json -r time -e '
    puts JSON.pretty_generate(
      {
        "generated_at" => Time.now.utc.iso8601,
        "status" => "pass",
        "screenshots" => 10,
        "icons" => 15,
        "plists" => 4,
        "metadata_fields" => 10,
        "privacy_types" => Integer(ENV.fetch("PRIVACY_TYPE_COUNT")),
        "failures" => []
      }
    )
  '
else
  printf '[ios-app-store-readiness] pass screenshots=10 icons=15 plists=4 metadata=10 privacy_types=%s\n' "$privacy_type_count"
fi
