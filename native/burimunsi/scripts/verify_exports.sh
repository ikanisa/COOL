#!/usr/bin/env bash
# Genuine JVM OOXML/CSV renderers; synthetic inputs, no Gradle/APK/device actions.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/burimunsi-export.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
kotlinc "$HERE"/core/src/main/kotlin/rw/ikanisa/burimunsi/core/export/*.kt \
 "$HERE"/export-tests/ExportChecks.kt -include-runtime -d "$TMP/checks.jar"
java -jar "$TMP/checks.jar" "$@"
