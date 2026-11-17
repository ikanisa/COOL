#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/burimunsi-pdu.XXXXXX")";trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
python3 "$HERE/scripts/prepare_receiver.py" --output "$TMP/build/receiver" > "$TMP/extraction.json"
SOURCES=();while IFS= read -r -d '' source;do SOURCES+=("$source");done < <(find "$HERE/core/src/main/kotlin" "$HERE/pdu-tests" -name '*.kt' -print0)
kotlinc "${SOURCES[@]}" "$HERE/repository-tests/JsonAdapter.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/PduInboxCorrelation.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/PduCorrelationStore.kt" \
 "$TMP/build/receiver/MomoGatewayPolicy.kt" "$TMP/build/receiver/MomoMultipartPolicy.kt" \
 -include-runtime -d "$TMP/checks.jar"
java -jar "$TMP/checks.jar"
