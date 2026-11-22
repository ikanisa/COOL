#!/usr/bin/env bash
# Actual generated broadcast receiver and wake gate with isolated platform doubles.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/burimunsi.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
python3 "$HERE/scripts/prepare_receiver.py" --output "$TMP/build/receiver" > "$TMP/extraction.json"
kotlinc "$HERE"/capture-tests/*.kt "$HERE/repository-tests/JsonAdapter.kt" \
 "$TMP/build/receiver/CollectSmsReceiver.kt" "$TMP/build/receiver/MomoGatewayWakeupGate.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/ObservationWakeup.kt" \
 -include-runtime -d "$TMP/capture-checks.jar"
java -jar "$TMP/capture-checks.jar"
