#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
native="$(cd "$here/../../../.." && pwd)/native/burimunsi"
output="$(mktemp -d "${TMPDIR:-/tmp}/held-recovery-v2.XXXXXX")"
trap 'rm -rf "$output"' EXIT

core=()
while IFS= read -r -d '' source; do
  core+=("$source")
done < <(find "$native/core/src/main/kotlin" -name '*.kt' -print0)

kotlinc "${core[@]}" "$native/repository-tests/JsonAdapter.kt" "$here/"*.kt \
  -include-runtime -d "$output/held-recovery-checks.jar"
java -jar "$output/held-recovery-checks.jar"
