#!/usr/bin/env python3
"""Compile actual fork sources and capture plugin logs on a local JVM.

Only android.util.Log is a test sink. Other Android/Flutter API classes come
from the pinned cached libraries. This is not Android device or APK proof.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "scripts/tests/fixtures/file_saver_native_log"
JBR = Path("/Volumes/PRO-G40/Applications/Android Studio.app/Contents/jbr/Contents/Home")
CACHE = Path.home() / ".gradle/caches/modules-2/files-2.1"
ENGINE = "a10d8ac38de835021c8d2f920dbf50a920ccc030"
RUNTIME = "third_party/file_saver/android/src/main/kotlin/com/incrediblezayed/file_saver"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def jar(group, name, version):
    paths = sorted((CACHE / group / name / version).glob("*/*.jar"))
    assert len(paths) == 1, f"Pinned cached jar unavailable or ambiguous: {name} {version}"
    return paths[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--packet", type=Path, required=True)
    args = parser.parse_args()
    source, packet = args.source_root.resolve(), args.packet.resolve()
    packet.mkdir(parents=True, exist_ok=False)
    classes = packet / "classes"
    classes.mkdir()
    inputs = [source / RUNTIME / name for name in ("FileUtils.kt", "Dialog.kt", "FileSaverPlugin.kt")]
    inputs += sorted((source / "third_party/file_saver/ios/file_saver/Sources/file_saver").glob("*.swift"))
    inputs += sorted(FIXTURES.glob("*")) + [Path(__file__).resolve()]
    before = {str(p): digest(p) for p in inputs}
    snapshots = packet / "source"
    for path in inputs:
        relative = path.relative_to(source) if path.is_relative_to(source) else path.relative_to(ROOT)
        target = snapshots / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        assert digest(path) == digest(target) == before[str(path)], "Source changed during copy"
    dependencies = [
        jar("org.jetbrains.kotlin", "kotlin-compiler-embeddable", "2.2.20"),
        jar("org.jetbrains.kotlin", "kotlin-stdlib", "2.2.20"),
        jar("org.jetbrains.kotlin", "kotlin-script-runtime", "2.2.20"),
        jar("org.jetbrains.kotlin", "kotlin-reflect", "1.6.10"),
        jar("org.jetbrains", "annotations", "13.0"),
        jar("org.jetbrains.kotlinx", "kotlinx-coroutines-core-jvm", "1.8.1"),
        jar("androidx.annotation", "annotation-jvm", "1.7.0"),
        jar("io.flutter", "flutter_embedding_release", "1.0.0-" + ENGINE),
        Path.home() / "Library/Android/sdk/platforms/android-36/android.jar",
    ]
    commands = []
    def run(name, argv):
        start = time.monotonic()
        result = subprocess.run([str(a) for a in argv], capture_output=True, timeout=120)
        (packet / f"{name}.stdout").write_bytes(result.stdout)
        (packet / f"{name}.stderr").write_bytes(result.stderr)
        commands.append({"name": name, "argv": [str(a) for a in argv], "exit_code": result.returncode,
                         "elapsed_seconds": round(time.monotonic()-start, 2),
                         "stdout_sha256": hashlib.sha256(result.stdout).hexdigest(),
                         "stderr_sha256": hashlib.sha256(result.stderr).hexdigest()})
        return result.returncode
    code = run("java-log-sink", [JBR / "bin/javac", "-d", classes, snapshots / "scripts/tests/fixtures/file_saver_native_log/Log.java"])
    if not code:
        cp = os.pathsep.join(str(p) for p in [classes] + dependencies[1:])
        code = run("actual-kotlin-compile", [JBR / "bin/java", "-cp", os.pathsep.join(str(p) for p in dependencies),
                   "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler", "-no-stdlib", "-no-reflect", "-jvm-target", "17",
                   "-classpath", cp, "-d", classes, *[snapshots / RUNTIME / p.name for p in inputs[:3]],
                   snapshots / "scripts/tests/fixtures/file_saver_native_log/NativeLogProbe.kt"])
    if not code:
        code = run("actual-plugin-log-capture", [JBR / "bin/java", "-ea", "-cp", os.pathsep.join(str(p) for p in [classes] + dependencies[1:]),
                    "collect.logprobe.NativeLogProbeKt"])
    unsafe = []
    for path in inputs[:3]:
        content = path.read_text()
        if "printStackTrace" in content:
            unsafe.append(str(path) + ": exception stack output")
        for match in re.finditer(r'Log\.[deiwv]\(([^\n]*)\)', content):
            if not re.fullmatch(r'(?:"[^"\n]*"|tag|TAG),\s*"[^"\n]*"', match.group(1).strip()):
                unsafe.append(str(path) + ": dynamic routine log")
    for path in inputs[3:5]:
        for match in re.finditer(r'print\(([^\n]*)\)', path.read_text()):
            if not re.fullmatch(r'"[^"\n]*"', match.group(1).strip()):
                unsafe.append(str(path) + ": dynamic routine print")
    changes = [str(p) for p in inputs if digest(p) != before[str(p)]]
    (packet / "validation.json").write_text(json.dumps({
        "status": "pass" if not code and not unsafe and not changes else "fail", "commands": commands,
        "source_sha256": before, "source_changes": changes, "unsafe_source_sinks": unsafe,
        "toolchain_dependencies": {str(p): digest(p) for p in dependencies},
        "jvm": str(JBR), "jvm_java_sha256": digest(JBR / "bin/java"),
        "scope": "Actual three production Kotlin sources compile against cached Android36/Flutter engine API; real plugin method/exception branches with local Log capture. Swift routine print source check only; current unsigned Swift/native APK build acceptance is separate.",
    }, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"exit_code": code, "unsafe_source_sinks": len(unsafe), "source_changes": changes}))
    raise SystemExit(0 if not code and not unsafe and not changes else 1)


if __name__ == "__main__":
    main()
