#!/usr/bin/env bash
# Compile actual pinned pure policies. Does not stub or compile Android APIs.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/burimunsi.XXXXXX")"
# Canonicalize only the directory just created and owned by this invocation.
# macOS /var is an alias; the receiver guard still rejects untrusted links.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
python3 "$HERE/scripts/prepare_receiver.py" --output "$TMP/build/receiver" > "$TMP/extraction.json"
BASE="$TMP/build/receiver"
FILES=(ReceiptCipher.kt ReceiptAckPolicy.kt SmsQueueOwnerPolicy.kt MomoGatewayPolicy.kt MomoMultipartPolicy.kt MomoGatewayWakeupGate.kt SmsQueueEventBus.kt)
SOURCES=()
for file in "${FILES[@]}"; do SOURCES+=("$BASE/$file"); done
kotlinc "${SOURCES[@]}" "$HERE/receiver-tests/ReceiverChecks.kt" -include-runtime -d "$TMP/receiver-checks.jar"
java -jar "$TMP/receiver-checks.jar"
