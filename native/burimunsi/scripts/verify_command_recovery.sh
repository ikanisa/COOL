#!/usr/bin/env bash
# Pure JVM state-machine checks. No Android runtime, hosted service or database.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
for tool in kotlinc java; do
  command -v "$tool" >/dev/null || { echo "BLOCKED: missing $tool" >&2; exit 2; }
done
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SOURCES=(); while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$HERE/core/src/main/kotlin" "$HERE/recovery-tests" -name '*.kt' -print0)
kotlinc "${SOURCES[@]}" -include-runtime -d "$TMP/recovery.jar"
java -Xmx512m -cp "$TMP/recovery.jar" rw.ikanisa.burimunsi.commandrecoverytests.CommandRecoveryChecksKt
java -Xmx512m -cp "$TMP/recovery.jar" rw.ikanisa.burimunsi.commandidentitytests.CommandIdentityChecksKt

java -Xmx512m -cp "$TMP/recovery.jar" rw.ikanisa.burimunsi.recoveryretrytests.RecoveryRetryChecksKt
java -Xmx512m -cp "$TMP/recovery.jar" rw.ikanisa.burimunsi.receiverretirementtests.ReceiverRetirementChecksKt
