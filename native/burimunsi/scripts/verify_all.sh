#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
node --test "$REPO"/supabase/functions/_shared/tests/burimunsi/*.test.mjs
python3 "$HERE/scripts/verify_native_boundary.py" --root "$HERE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CORE=(); while IFS= read -r -d '' source; do CORE+=("$source"); done < <(find "$HERE/core/src/main/kotlin" "$HERE/core/src/test/kotlin" -name '*.kt' -print0)
kotlinc "${CORE[@]}" -include-runtime -d "$TMP/core-checks.jar"
java -jar "$TMP/core-checks.jar"
bash "$HERE/scripts/verify_receiver_policies.sh"
bash "$HERE/scripts/verify_pdu_correlation.sh"
bash "$HERE/scripts/verify_capture_wakeup.sh"
bash "$HERE/scripts/verify_observation_queue.sh"
bash "$HERE/scripts/verify_observation_adapter.sh"
bash "$HERE/scripts/verify_sms_reliability.sh"
bash "$HERE/scripts/verify_presentation.sh"
bash "$HERE/scripts/verify_command_recovery.sh"
bash "$HERE/scripts/verify_viewmodel.sh"
bash "$HERE/scripts/verify_member_photo.sh"
bash "$HERE/scripts/verify_repository.sh"
bash "$HERE/scripts/verify_gateway.sh"
bash "$HERE/scripts/verify_cross_layer.sh"
bash "$HERE/scripts/verify_http.sh"
bash "$HERE/scripts/verify_managed_login.sh"
# A native build is a separate gate; this command does not claim an APK was compiled.
python3 "$REPO/scripts/generate_ui_copy.py" --check
python3 "$REPO/scripts/generate_burimunsi_wire.py" --check
python3 "$REPO/tests/uiux_contract_test.py"
bash "$HERE/scripts/verify_ui_syntax.sh"
