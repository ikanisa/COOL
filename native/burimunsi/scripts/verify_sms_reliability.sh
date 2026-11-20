#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/burimunsi.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
python3 "$HERE/scripts/prepare_receiver.py" --output "$TMP/build/receiver" > "$TMP/extraction.json"
K="$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms"
kotlinc "$TMP/build/receiver/ReceiptCipher.kt" "$TMP/build/receiver/ReceiptAckPolicy.kt" \
  "$K/BuriQueueFile.kt" "$K/BuriReceiverReliability.kt" "$HERE/receiver-tests/ReliabilityChecks.kt" \
  -include-runtime -d "$TMP/reliability.jar"
java -cp "$TMP/reliability.jar" app.cool.mobile.receiver_sms.ReliabilityChecksKt
