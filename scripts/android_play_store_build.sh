#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ ! -x "$FLUTTER_BIN" ]]; then
  printf 'FLUTTER_BIN must point to an executable Flutter binary.\n' >&2
  exit 2
fi
readonly FLUTTER_BIN
PACKAGE_VERSION="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)"
[[ "$PACKAGE_VERSION" == *+* ]] || {
  printf 'pubspec.yaml version must include a build number.\n' >&2
  exit 2
}
BUILD_NAME="${COLLECT_ANDROID_BUILD_NAME:-${PACKAGE_VERSION%%+*}}"
BUILD_NUMBER="${COLLECT_ANDROID_BUILD_NUMBER:-${PACKAGE_VERSION##*+}}"
readonly EXPECTED_PRODUCTION_SUPABASE_URL="https://lhbowpbcpwoiparwnwgt.supabase.co"
SUPABASE_URL_VALUE="${SUPABASE_PRODUCTION_URL:-}"
SUPABASE_ANON_KEY_VALUE="${SUPABASE_PRODUCTION_ANON_KEY:-}"
PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER_VALUE="${PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER:-}"
BUILD_STARTED_EPOCH="$(date +%s)"

if [[ $# -ne 0 ]]; then
  printf 'This production wrapper accepts no extra Flutter arguments. Update the reviewed script for any build-contract change.\n' >&2
  exit 2
fi

if [[ -z "$SUPABASE_URL_VALUE" || -z "$SUPABASE_ANON_KEY_VALUE" ]]; then
  printf 'SUPABASE_PRODUCTION_URL and SUPABASE_PRODUCTION_ANON_KEY are required.\n' >&2
  exit 2
fi

if [[ "$SUPABASE_URL_VALUE" != "$EXPECTED_PRODUCTION_SUPABASE_URL" ]]; then
  printf 'SUPABASE_PRODUCTION_URL does not match the reviewed Collect production project.\n' >&2
  exit 2
fi

if [[ ! "$PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER_VALUE" =~ ^[1-9][0-9]+$ ]]; then
  printf 'PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER must be the positive project number linked to Collect in Play Console.\n' >&2
  exit 2
fi
export PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER="$PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER_VALUE"

umask 077
BUILD_LOCK_DIR="${COLLECT_ANDROID_BUILD_LOCK_DIR:-$ROOT_DIR/.dart_tool/collect-android-play-store-build.lock}"
mkdir -p "$(dirname "$BUILD_LOCK_DIR")"
if ! mkdir "$BUILD_LOCK_DIR" 2>/dev/null; then
  lock_owner="$(sed -n '1p' "$BUILD_LOCK_DIR/pid" 2>/dev/null || true)"
  printf 'Another Android production build owns %s%s. Wait for it to finish; inspect a stale lock before removing it.\n' \
    "$BUILD_LOCK_DIR" "${lock_owner:+ (pid $lock_owner)}" >&2
  exit 3
fi
BUILD_LOCK_HELD=1
printf '%s\n' "$$" >"$BUILD_LOCK_DIR/pid"

DEFINES_DIR="$(mktemp -d "${TMPDIR:-/tmp}/collect-android-defines.XXXXXX")"
DEFINES_FILE="$DEFINES_DIR/defines.json"
cleanup() {
  rm -f "$DEFINES_FILE"
  rmdir "$DEFINES_DIR" 2>/dev/null || true
  if [[ "${BUILD_LOCK_HELD:-0}" == "1" ]]; then
    rm -f "$BUILD_LOCK_DIR/pid"
    rmdir "$BUILD_LOCK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

SUPABASE_URL_VALUE="$SUPABASE_URL_VALUE" \
SUPABASE_ANON_KEY_VALUE="$SUPABASE_ANON_KEY_VALUE" \
DEFINES_FILE="$DEFINES_FILE" \
ruby -r json <<'RUBY'
File.write(
  ENV.fetch("DEFINES_FILE"),
  JSON.generate(
    "SUPABASE_URL" => ENV.fetch("SUPABASE_URL_VALUE"),
    "SUPABASE_ANON_KEY" => ENV.fetch("SUPABASE_ANON_KEY_VALUE"),
    "APP_PUBLIC_URL" => ENV.fetch("APP_PUBLIC_URL", "https://collect.ikanisa.com"),
    "APP_ENVIRONMENT" => "production",
    "ENABLE_SMS_READER" => "true",
    "ENABLE_ANDROID_SMS_ACCESS" => "true",
    "COLLECT_MOBILE_EVIDENCE_MODE" => "false"
  )
)
RUBY

common_args=(
  --release
  --flavor production
  --build-name "$BUILD_NAME"
  --build-number "$BUILD_NUMBER"
  --dart-define-from-file "$DEFINES_FILE"
)

verify_public_runtime_config() {
  local archive="$1"
  local app_binary="$2"

  if ! unzip -p "$archive" "$app_binary" | \
    EXPECTED_SUPABASE_URL="$EXPECTED_PRODUCTION_SUPABASE_URL" ruby -e '
      expected = ENV.fetch("EXPECTED_SUPABASE_URL").b
      exit(STDIN.read.b.include?(expected) ? 0 : 1)
    '
  then
    printf 'Packaged release is missing the reviewed Supabase runtime URL: %s\n' "$archive" >&2
    exit 1
  fi
}

# Flutter recompiles its AOT binary when dart defines change, but Gradle can
# otherwise restore an older packaged APK/AAB whose stripped libapp.so does not
# contain those values. A clean, cache-disabled production build plus a binary
# assertion prevents that store-blocking failure from being published again.
export GRADLE_OPTS="${GRADLE_OPTS:+$GRADLE_OPTS }-Dorg.gradle.caching=false"
export COOL_SIGN_PRODUCTION_DEBUG_WITH_PLAY_KEY=false
"$ROOT_DIR/android/gradlew" --no-build-cache -p "$ROOT_DIR/android" :app:clean

# When Android intermediates live on an internal APFS volume, Flutter still
# resolves its final artifacts through the repository's conventional build/
# paths. Expose only those two generated output directories; all compilation
# remains in COLLECT_ANDROID_BUILD_ROOT.
if [[ -n "${COLLECT_ANDROID_BUILD_ROOT:-}" ]]; then
  COLLECT_ANDROID_BUILD_ROOT="$COLLECT_ANDROID_BUILD_ROOT" ROOT_DIR="$ROOT_DIR" ruby -e '
    root = File.expand_path(ENV.fetch("ROOT_DIR"))
    build_root = File.expand_path(ENV.fetch("COLLECT_ANDROID_BUILD_ROOT"))
    forbidden = ["/", root, File.dirname(root), ENV["HOME"]].compact.map { |path| File.expand_path(path) }
    abort("COLLECT_ANDROID_BUILD_ROOT is too broad") if forbidden.include?(build_root)
    abort("COLLECT_ANDROID_BUILD_ROOT must be an absolute child directory") unless build_root.start_with?(File::SEPARATOR) && build_root.length > 12
    abort("COLLECT_ANDROID_BUILD_ROOT must not be a symlink") if File.symlink?(build_root)
  '
  internal_outputs="$COLLECT_ANDROID_BUILD_ROOT/app/outputs"
  public_outputs="$ROOT_DIR/build/app/outputs"
  mkdir -p "$internal_outputs" "$public_outputs"
  for output_dir in flutter-apk bundle; do
    public_output="$public_outputs/$output_dir"
    internal_output="$internal_outputs/$output_dir"
    if [[ -L "$public_output" ]]; then
      rm -f "$public_output"
    elif [[ -d "$public_output" ]]; then
      if ! rmdir "$public_output" 2>/dev/null; then
        printf 'Generated output path is unexpectedly non-empty: %s\n' "$public_output" >&2
        exit 1
      fi
    elif [[ -e "$public_output" ]]; then
      printf 'Generated output path is not a directory or symlink: %s\n' "$public_output" >&2
      exit 1
    fi
    ln -s "$internal_output" "$public_output"
  done
fi

"$FLUTTER_BIN" build apk "${common_args[@]}"
verify_public_runtime_config \
  "$ROOT_DIR/build/app/outputs/flutter-apk/app-production-release.apk" \
  'lib/arm64-v8a/libapp.so'

"$FLUTTER_BIN" build appbundle "${common_args[@]}"
verify_public_runtime_config \
  "$ROOT_DIR/build/app/outputs/bundle/productionRelease/app-production-release.aab" \
  'base/lib/arm64-v8a/libapp.so'

"$ROOT_DIR/scripts/android_release_signing_preflight.sh"

artifact_manifest="$ROOT_DIR/.cache/android_play_store_build/${BUILD_NAME}+${BUILD_NUMBER}.json"
mkdir -p "$(dirname "$artifact_manifest")"
ROOT_DIR="$ROOT_DIR" \
BUILD_NAME="$BUILD_NAME" \
BUILD_NUMBER="$BUILD_NUMBER" \
BUILD_STARTED_EPOCH="$BUILD_STARTED_EPOCH" \
ARTIFACT_MANIFEST="$artifact_manifest" \
ruby -r digest -r json -r time <<'RUBY'
root = ENV.fetch("ROOT_DIR")
started_at = Time.at(Integer(ENV.fetch("BUILD_STARTED_EPOCH")))
paths = {
  "apk" => File.join(root, "build/app/outputs/flutter-apk/app-production-release.apk"),
  "aab" => File.join(root, "build/app/outputs/bundle/productionRelease/app-production-release.aab")
}
artifacts = paths.transform_values do |path|
  abort("Production artifact is missing: #{path}") unless File.file?(path)
  abort("Production artifact must not be a symlink: #{path}") if File.symlink?(path)
  abort("Production artifact predates this build: #{path}") if File.mtime(path) < started_at
  abort("Production artifact is unexpectedly small: #{path}") if File.size(path) < 1_000_000
  {
    "path" => path.sub(%r{\A#{Regexp.escape(root)}/?}, ""),
    "bytes" => File.size(path),
    "mtime" => File.mtime(path).utc.iso8601,
    "sha256" => Digest::SHA256.file(path).hexdigest
  }
end
manifest = {
  "status" => "pass",
  "generated_at" => Time.now.utc.iso8601,
  "application_id" => "app.cool.mobile",
  "artifact_version" => "#{ENV.fetch("BUILD_NAME")}+#{ENV.fetch("BUILD_NUMBER")}",
  "production_supabase_url" => "https://lhbowpbcpwoiparwnwgt.supabase.co",
  "mobile_evidence_mode" => false,
  "artifacts" => artifacts
}
File.write(ENV.fetch("ARTIFACT_MANIFEST"), JSON.pretty_generate(manifest) + "\n")
puts "[android-play-store-build] artifact_manifest=#{ENV.fetch("ARTIFACT_MANIFEST")}"
RUBY
