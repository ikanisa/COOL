#!/usr/bin/env bash
# Real inbox and coordinator logic with synthetic platform/storage/network doubles.
# This is not an Android-device or backend test.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/burimunsi-observation.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
python3 "$HERE/scripts/prepare_receiver.py" --output "$TMP/build/receiver" > "$TMP/extraction.json"
SOURCES=(); while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$HERE/core/src/main/kotlin" -name '*.kt' -print0)
kotlinc "${SOURCES[@]}" "$HERE"/observation-adapter-tests/*.kt "$HERE/repository-tests/JsonAdapter.kt" \
 "$HERE"/gateway-tests/{ManifestStub,PermissionStub,SubscriptionStub,BuildConfigStub,ApiFailureStub,ReceiverStub,ContinuousSyncStub}.kt \
 "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/gateway/GatewayPort.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/ContinuousSyncHealth.kt" \
 "$HERE"/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/{BuriReceiverReliability,BuriReceiverProfile,BuriCapturePolicy,HeldRecoveryJournal,ObservationLegacyOwnership,ObservationConfigStore,ObservationCapture,ObservationPduCapture,ObservationSmsReceiver,PduInboxCorrelation,PduCorrelationStore,ObservationRecovery,ObservationHeldInbox,ObservationInboxAudit,ObservationInboxBackfill,ObservationInboxQueries,ObservationCoordinator,ObservationSyncCycle,ObservationSyncDiagnostics,ContinuousSyncWork}.kt \
 "$TMP"/build/receiver/{MomoGatewayPolicy,MomoMultipartPolicy,MomoGatewayHttp,ReceiptAckPolicy}.kt -include-runtime -d "$TMP/adapter-checks.jar"
java -jar "$TMP/adapter-checks.jar"
