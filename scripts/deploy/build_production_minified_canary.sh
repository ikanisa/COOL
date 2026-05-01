#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/lib/_android_release_build.sh"

export COOL_ENABLE_ANDROID_MINIFY=1

echo "==> building Android production APK with minification enabled"
build_android_release apk
