#!/usr/bin/env bash
# Actual receiver GatewayFactory/pure binding policy; explicit Android/queue doubles.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
TMP="$(cd "$TMP" && pwd -P)"
python3 "$HERE/scripts/prepare_receiver.py" --output "$TMP/build/receiver" > "$TMP/extraction.json"
SOURCES=();while IFS= read -r -d '' source;do SOURCES+=("$source");done < <(find "$HERE/core/src/main/kotlin" "$HERE/gateway-tests" -name '*.kt' -print0)
kotlinc "${SOURCES[@]}" "$HERE/repository-tests/JsonAdapter.kt" "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/gateway/GatewayPort.kt" \
 "$HERE/app/src/internal_receiver/kotlin/rw/ikanisa/burimunsi/gateway/GatewayFactory.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/BuriReceiverReliability.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/BuriReceiverProfile.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/BuriCapturePolicy.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/ObservationLegacyOwnership.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/ContinuousSyncWork.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/HeldRecoveryJournal.kt" "$HERE/observation-adapter-tests/SecureStoreStub.kt" \
 "$TMP/build/receiver/MomoGatewayPolicy.kt" "$TMP/build/receiver/MomoGatewayHttp.kt" \
 "$REPO/android/app/src/main/kotlin/app/cool/mobile/receiver_sms/ReceiptAckPolicy.kt" -include-runtime -d "$TMP/checks.jar"
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.gatewaytests.GatewayChecksKt
