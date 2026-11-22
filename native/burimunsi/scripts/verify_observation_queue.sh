#!/usr/bin/env bash
# Real local queue adapter with synthetic Android/session/storage doubles; no device or network.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
SOURCES=();while IFS= read -r -d '' source;do SOURCES+=("$source");done < <(find "$HERE/core/src/main/kotlin" "$HERE/queue-tests" -name '*.kt' -print0)
kotlinc "${SOURCES[@]}" "$HERE/gateway-tests/ManifestStub.kt" "$HERE/gateway-tests/PermissionStub.kt" "$HERE/gateway-tests/BuildConfigStub.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/ObservationGateway.kt" -include-runtime -d "$TMP/checks.jar"
java -cp "$TMP/checks.jar" app.cool.mobile.receiver_sms.QueueChecksKt
