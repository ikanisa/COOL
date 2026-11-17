#!/usr/bin/env bash
# Real ApiClient, fake URL connection. Does not verify TLS/network/Android.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
CORE=(); while IFS= read -r -d '' source; do CORE+=("$source"); done < <(find "$HERE/core/src/main/kotlin" -name '*.kt' -print0)
kotlinc "${CORE[@]}" "$HERE/repository-tests/JsonAdapter.kt" "$HERE"/http-tests/*.kt "$HERE"/app/src/main/kotlin/rw/ikanisa/wire/*.kt "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/data/NativeWireData.kt" "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/data/ApiClient.kt" "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/data/SupportContactClient.kt" -include-runtime -d "$TMP/http.jar"
java -jar "$TMP/http.jar"
