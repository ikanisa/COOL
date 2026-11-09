#!/usr/bin/env bash
# Compiles the real ViewModel/Controller against isolated test-only platform/provider doubles.
# Does NOT compile Compose UI, APK, Android lifecycle, or production providers.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KOTLIN_HOME="${KOTLIN_HOME:-$(cd "$(dirname "$(command -v kotlinc)")/.." && pwd)}"
COROUTINES="$KOTLIN_HOME/lib/kotlinx-coroutines-core-jvm.jar"
test -f "$COROUTINES"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
SOURCES=(); while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$HERE/core/src/main/kotlin" "$HERE/viewmodel-tests" -name '*.kt' -print0)
kotlinc "${SOURCES[@]}" "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/BuriController.kt" "$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/ui/BuriViewModel.kt" -cp "$COROUTINES" -include-runtime -d "$TMP/checks.jar"
java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.viewmodeltests.ViewModelChecksKt

java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.foregroundtests.ForegroundChecksKt
java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.checkpointtests.CheckpointChecksKt
java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.journeytests.JourneyChecksKt
java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.presentationstatetests.PresentationStateChecksKt
java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.retryfreshnesstests.RetryFreshnessChecksKt
java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.pagedviewmodeltests.PagedRestorationChecksKt
