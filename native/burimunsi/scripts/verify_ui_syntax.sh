#!/usr/bin/env bash
# Uses Kotlin's real parser, not a brace count. No claim of Android/Compose compilation.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KOTLIN_HOME="${KOTLIN_HOME:-$(cd "$(dirname "$(command -v kotlinc)")/.." && pwd)}"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
kotlinc "$HERE/syntax-tests/ParseKotlin.kt" -cp "$KOTLIN_HOME/lib/kotlin-compiler.jar" -include-runtime -d "$TMP/parser.jar"
java -cp "$TMP/parser.jar:$KOTLIN_HOME/lib/*" ParseKotlinKt "$HERE/app/src/main/kotlin" "$HERE/app/src/androidTest/kotlin" "$HERE/core/src/main/kotlin"
