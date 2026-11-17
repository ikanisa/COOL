#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/held-consent-journal.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
SOURCES=(); while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$HERE/core/src/main/kotlin" -name '*.kt' -print0)
kotlinc "${SOURCES[@]}" "$HERE/held-consent-tests/ContextStub.kt" \
 "$HERE/held-consent-tests/ConsentJournalChecks.kt" "$HERE/repository-tests/JsonAdapter.kt" \
 "$HERE/observation-adapter-tests/SecureStoreStub.kt" \
 "$HERE/app/src/internal_receiver/kotlin/app/cool/mobile/receiver_sms/HeldRecoveryJournal.kt" \
 -include-runtime -d "$TMP/held-consent.jar"
java -jar "$TMP/held-consent.jar"
