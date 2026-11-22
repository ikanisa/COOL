#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
CORE=(); while IFS= read -r -d '' source; do CORE+=("$source"); done < <(find "$HERE/core/src/main/kotlin" "$HERE/presentation-tests" -name '*.kt' -print0)
kotlinc "${CORE[@]}" -include-runtime -d "$TMP/presentation.jar"
java -cp "$TMP/presentation.jar" rw.ikanisa.burimunsi.presentationtests.PresentationChecksKt
java -cp "$TMP/presentation.jar" rw.ikanisa.burimunsi.stateformattingtests.StateFormattingChecksKt
java -cp "$TMP/presentation.jar" rw.ikanisa.burimunsi.pagedrestorationtests.PagedRestorationChecksKt
