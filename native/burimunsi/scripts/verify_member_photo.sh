#!/usr/bin/env bash
# Synthetic host files only; actual camera/provider/image checks remain Android instrumentation.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
kotlinc "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/MemberPhotoFiles.kt" "$HERE/photo-tests/MemberPhotoChecks.kt" -include-runtime -d "$TMP/checks.jar"
java -jar "$TMP/checks.jar"
