#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
command -v kotlinc >/dev/null || { echo 'Kotlin compiler required'; exit 2; }
command -v java >/dev/null || { echo 'JVM required'; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
kotlinc "$ROOT/android/app/src/main/kotlin/app/cool/mobile/security/SnapshotCipher.kt" \
 "$ROOT/scripts/hardening/SnapshotCipherTest.kt" -include-runtime -d "$TMP/tests.jar"
java -jar "$TMP/tests.jar"
