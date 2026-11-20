#!/usr/bin/env bash
# Real controller + repository + DTO + journal. Only platform/storage/HTTP/JSON are doubles.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KOTLIN_HOME="${KOTLIN_HOME:-$(cd "$(dirname "$(command -v kotlinc)")/.." && pwd)}"
COROUTINES="$KOTLIN_HOME/lib/kotlinx-coroutines-core-jvm.jar"
test -f "$COROUTINES"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
SOURCES=(); while IFS= read -r -d '' source; do SOURCES+=("$source"); done < <(find "$HERE/core/src/main/kotlin" "$HERE/cross-layer-tests" -name '*.kt' -print0)
for name in ComposeStub LifecycleStub BuildConfigStub GatewayStub StorageStub AndroidPermissionStub AndroidManifestStub NetworkStub; do SOURCES+=("$HERE/viewmodel-tests/$name.kt");done
for name in ContextStub JsonAdapter StorageStub; do SOURCES+=("$HERE/repository-tests/$name.kt");done
for name in data/NativeRepository data/Dto data/NativeWireData storage/AndroidOperationStore storage/AndroidReceiverRetirementStore gateway/GatewayPort export/ListingExportData ui/UiFeedbackModels ui/BuriViewModel ui/BuriController ui/NativeCollectionPosting ui/NativeReceiverStatus SessionNetworkObserver; do SOURCES+=("$HERE/app/src/main/kotlin/rw/ikanisa/burimunsi/$name.kt");done
SOURCES+=("$HERE"/app/src/main/kotlin/rw/ikanisa/wire/*.kt)
kotlinc "${SOURCES[@]}" -cp "$COROUTINES" -include-runtime -d "$TMP/checks.jar"
java -cp "$TMP/checks.jar:$COROUTINES" rw.ikanisa.burimunsi.crosslayertests.CommandViewChecksKt
