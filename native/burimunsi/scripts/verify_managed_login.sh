#!/usr/bin/env bash
# Actual transport/lifecycle sources with explicit no-network fixture connections.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
CORE=(); while IFS= read -r -d '' source; do CORE+=("$source"); done < <(find "$HERE/core/src/main/kotlin" -name '*.kt' -print0)
kotlinc "${CORE[@]}" "$HERE/repository-tests/JsonAdapter.kt" "$HERE"/managed-login-tests/*.kt "$HERE"/app/src/main/kotlin/rw/ikanisa/wire/*.kt "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/data/CollectAdminTransport.kt" -include-runtime -d "$TMP/managed-login.jar"
java -jar "$TMP/managed-login.jar"
