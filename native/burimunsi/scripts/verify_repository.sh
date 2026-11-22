#!/usr/bin/env bash
# Compile actual repository, DTO and operation-store code; use explicit platform/API/storage doubles.
# JSON fixture adapter is test-only and is not Android org.json verification.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
SOURCES=(); while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$HERE/core/src/main/kotlin" "$HERE/repository-tests" -name '*.kt' -print0)
source "$HERE/scripts/repository_sources.sh"
kotlinc "${SOURCES[@]}" "${BURI_REPOSITORY_SOURCES[@]}" \
    "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/storage/AndroidNavigationCheckpointStore.kt" \
    -include-runtime -d "$TMP/checks.jar"
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.repositorytests.RepositoryChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.observationownershiptests.ObservationOwnershipChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.observationhinttests.ObservationHintsChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.memberpaymenttests.MemberPaymentsChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.staffsecretchecks.StaffSecretChecksKt

java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.recoverytests.RecoveryChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.a04tests.A04ChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.commandrecoveryintegrationtests.CommandRecoveryIntegrationChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.commandrecoveryintegrationtests.RecoveryRetryIntegrationChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.receiverretirementrepositorytests.ReceiverRetirementChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.smartonboardingrepositorytests.SmartOnboardingRepositoryChecksKt
java -cp "$TMP/checks.jar" rw.ikanisa.burimunsi.listingrepositorytests.ListingRepositoryChecksKt
