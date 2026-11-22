#!/usr/bin/env bash
# Uses Kotlin's real parser, not a brace count. No claim of Android/Compose compilation.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
KOTLIN_HOME="${KOTLIN_HOME:-$(cd "$(dirname "$(command -v kotlinc)")/.." && pwd)}"
TMP="$(mktemp -d)";trap 'rm -rf "$TMP"' EXIT
compiler="$KOTLIN_HOME/lib/kotlin-compiler.jar"
jar tf "$compiler" > "$TMP/compiler-classes"
psi=com.intellij
if grep -Fxq 'org/jetbrains/kotlin/com/intellij/psi/PsiErrorElement.class' "$TMP/compiler-classes"; then
    psi=org.jetbrains.kotlin.com.intellij
fi
# The standalone and embeddable compilers expose the same PSI under different packages.
bindings="$TMP/PsiBindings.kt"
echo 'import org.jetbrains.kotlin.config.CompilerConfiguration' > "$bindings"
options=(-cp "$compiler")
if grep -Fxq 'org/jetbrains/kotlin/K1Deprecation.class' "$TMP/compiler-classes"; then
    options+=(-opt-in=org.jetbrains.kotlin.K1Deprecation)
fi
if grep -Fxq 'org/jetbrains/kotlin/CoreEnvironmentDeprecation.class' "$TMP/compiler-classes" &&
    grep -Fxq 'org/jetbrains/kotlin/config/CompilerConfiguration$Internals.class' "$TMP/compiler-classes"; then
    options+=(-opt-in=org.jetbrains.kotlin.CoreEnvironmentDeprecation -opt-in=org.jetbrains.kotlin.config.CompilerConfiguration.Internals -opt-in=org.jetbrains.kotlin.compiler.plugin.ExperimentalCompilerApi)
    cat >> "$bindings" <<'KOTLIN'
import org.jetbrains.kotlin.cli.extensionsStorage
import org.jetbrains.kotlin.compiler.plugin.CompilerPluginRegistrar

fun psiConfiguration() = CompilerConfiguration().apply { extensionsStorage = CompilerPluginRegistrar.ExtensionStorage() }
KOTLIN
else
    echo 'fun psiConfiguration() = CompilerConfiguration()' >> "$bindings"
fi
cat >> "$bindings" <<KOTLIN
typealias Disposer = $psi.openapi.util.Disposer
typealias PsiErrorElement = $psi.psi.PsiErrorElement
typealias PsiTreeUtil = $psi.psi.util.PsiTreeUtil
KOTLIN
"$KOTLIN_HOME/bin/kotlinc" "${options[@]}" "$HERE/syntax-tests/ParseKotlin.kt" "$bindings" -d "$TMP/parser.jar"
java -cp "$TMP/parser.jar:$KOTLIN_HOME/lib/*" ParseKotlinKt "$HERE/app/src" "$HERE/core/src"
