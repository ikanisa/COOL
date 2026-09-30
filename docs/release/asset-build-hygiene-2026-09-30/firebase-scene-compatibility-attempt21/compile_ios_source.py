#!/usr/bin/env python3
"""Compile both real full plugin sources with retained actual iOS Xcode flags."""
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent / "ios-source-compile1"
BUILD = OUT.parent.parent / "native-export-attempt18-ios"
RELATIVE = "ios/firebase_messaging/Sources/firebase_messaging/FLTFirebaseMessagingPlugin.m"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


assert not OUT.exists(), "Full native source compile requires a fresh output"
OUT.mkdir()
lines = (BUILD / "unsigned-ios-build.stdout").read_text().splitlines()
matches = [line.strip() for line in lines if line.strip().startswith("/Volumes/PRO-G40/Applications/Xcode.app/")
           and "clang -x objective-c" in line and "FLTFirebaseMessagingPlugin.m" in line]
assert len(matches) == 1
# Xcode display output leaves the space-containing compiler path unquoted;
# isolate that exact executable and parse only the remaining command arguments.
executable, arguments = matches[0].split("clang ", 1)
executable += "clang"
original = [executable, *shlex.split(arguments)]
expanded, response = [], {}
for argument in original:
    if argument.startswith("@"):
        path = Path(argument[1:])
        response[str(path)] = sha(path)
        (OUT / path.name).write_bytes(path.read_bytes())
        expanded.extend(shlex.split(path.read_text()))
    else:
        expanded.append(argument)
sources = {"prior": OUT.parent / "source-snapshot/upstream-package" / RELATIVE,
           "current": ROOT / "third_party/firebase_messaging" / RELATIVE}
bindings = {str(path): sha(path) for path in sources.values()}
bindings.update(response)
bindings[str(BUILD / "unsigned-ios-build.stdout")] = sha(BUILD / "unsigned-ios-build.stdout")
receipts = []
env = {key: value for key, value in os.environ.items() if key in {"HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"}}
env["DEVELOPER_DIR"] = "/Volumes/PRO-G40/Applications/Xcode.app/Contents/Developer"
for label, source in sources.items():
    command, index = [], 0
    while index < len(expanded):
        argument = expanded[index]
        if argument in {"-o", "-MF", "--serialize-diagnostics", "-c"}:
            replacements = {"-o": OUT / (label + ".o"), "-MF": OUT / (label + ".d"),
                            "--serialize-diagnostics": OUT / (label + ".dia"), "-c": source}
            command.extend([argument, str(replacements[argument])]); index += 2; continue
        if argument.startswith("-fmodules-cache-path="):
            command.append("-fmodules-cache-path=" + str(OUT / (label + "-module-cache")))
        elif argument.startswith("-fbuild-session-file=") or argument == "-fmodules-validate-once-per-build-session":
            pass
        else:
            command.append(argument)
        index += 1
    command.extend(["-Werror=mismatched-return-types", "-Werror=return-type"])
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
    stdout, stderr = OUT / (label + ".stdout"), OUT / (label + ".stderr")
    stdout.write_bytes(result.stdout); stderr.write_bytes(result.stderr)
    receipts.append({"source_kind": label, "command": command, "exit_code": result.returncode,
                     "stdout_sha256": sha(stdout), "stderr_sha256": sha(stderr)})
    if label == "prior":
        assert result.returncode != 0 and b"conflicting return type" in result.stderr, "Actual original full iOS source must fail native return gate"
    else:
        assert result.returncode == 0, "Corrected full iOS plugin source compile failed; retain diagnostics"
        assert b"conflicting return type" not in result.stderr
        assert (OUT / "current.o").is_file()
after = {path: sha(Path(path)) for path in bindings}
assert after == bindings, "Read-only native source/bindings changed"
report = {"status": "pass", "kind": "actual_full_plugin_ios_translation_unit_compile",
          "scope": "Real complete Firebase16.5.0 Objective-C source compiled for iOS arm64 against retained iOS27/Flutter3.44.4/Firebase dependencies; no whole-app link/device/provider acceptance",
          "prior_actual_ios_source_rejected": True, "corrected_actual_ios_source_compiles": True,
          "promoted_warnings_only": ["mismatched-return-types", "return-type"], "other_warnings_suppressed_by_this_gate": False,
          "outputs_and_module_cache_isolated": True, "sources_before": bindings, "sources_after": after,
          "commands": receipts, "object_sha256": sha(OUT / "current.o"), "object_bytes": (OUT / "current.o").stat().st_size,
          "recorder_sha256": sha(Path(__file__)), "whole_current_native_app_accepted": False,
          "provider_calls": 0, "hosted_calls": 0, "database_calls": 0}
(OUT / "verification.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
print(json.dumps({"status": "pass", "verification_sha256": sha(OUT / "verification.json"), "object_bytes": report["object_bytes"]}))
