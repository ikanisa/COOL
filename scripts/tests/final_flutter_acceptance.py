#!/usr/bin/env python3
"""Run all checked-in Flutter VM tests against an isolated declared source set.

Historical SQL receipts are immutable decoder inputs. This tool executes no
database, deployment, provider, signing or store command. Web-only tests retain
their recorded skip status and need separate browser evidence.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

import admin_read_gateway_gate as gate
import admin_matrix_acceptance as admin

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("native_export", ROOT / "scripts/qa/native_source_export.py")
native = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(native)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def release_fixture_patterns(text):
    """Resolve adjacent fixture literals without treating a prefix as a tree.

    Dart joins adjacent quoted literals. A constant containing only a release
    directory is a namespace, not permission to copy every historical export
    underneath it. Dynamic fixture filenames select their direct siblings.
    Generated PNG paths are test outputs, not decoder inputs.
    """
    tokens = list(re.finditer(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"", text))
    values, constants = [], {}
    index = 0
    while index < len(tokens):
        first = tokens[index]
        value = first.group()[1:-1]
        end = first.end()
        index += 1
        while index < len(tokens) and text[end:tokens[index].start()].strip() == "":
            value += tokens[index].group()[1:-1]
            end = tokens[index].end()
            index += 1
        values.append(value)
        assignment = re.search(r"\b(?:const|final)\s+(?:String\s+)?(\w+)\s*=\s*$", text[:first.start()])
        if assignment:
            constants[assignment.group(1)] = value

    interpolation = re.compile(r"\$\{(\w+)\}|\$(\w+)")
    def resolve(value):
        for _ in range(len(constants) + 1):
            updated = interpolation.sub(
                lambda match: constants.get(match.group(1) or match.group(2), match.group()), value)
            if updated == value:
                break
            value = updated
        return interpolation.sub("*", value)

    patterns = set()
    for value in values:
        value = resolve(value)
        if not value.startswith("docs/release/") or not re.search(r"\.(?:json|sql|stdout|md|txt)$", value):
            continue
        if ".." in Path(value).parts or "\\" in value:
            raise ValueError("Release fixture reference escapes its source namespace")
        patterns.add(value)
    return sorted(patterns)


def declared_files():
    names = subprocess.check_output([
        "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z",
        "--", *native.ROOTS, *native.FILES, "scripts/", "supabase/", "contracts/",
        "docs/", ".github/", "fastlane/Fastfile",
        "fastlane/metadata/android/en-US/images/icon.png",
        ".codex/environments/environment.toml", "Makefile", "README.md", ".gitignore", ".env.example",
    ], cwd=ROOT).decode().split("\0")
    selected = {name for name in names if name and not name.startswith("docs/release/")}
    selected.update(name for name in admin.CONFIG if (ROOT / name).is_file())
    # Retain only release inputs explicitly named by the tests. The broad
    # release tree contains historical build exports and is not a source input.
    release_inputs = set()
    for test in (ROOT / "test").rglob("*.dart"):
        for pattern in release_fixture_patterns(test.read_text()):
            matches = list(ROOT.glob(pattern))
            if not matches:
                raise ValueError("Declared release fixture is absent: " + pattern)
            for path in matches:
                if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(ROOT):
                    raise ValueError("Declared release fixture is not a regular contained file: " + str(path))
                release_inputs.add(path)
    if sum(path.stat().st_size for path in release_inputs) > 250 * 1024 * 1024:
        raise ValueError("Explicit test release inputs exceed the review bound")
    selected.update(str(path.relative_to(ROOT)) for path in release_inputs)
    result = {}
    for name in sorted(selected):
        # Pub regenerates these export-specific bindings. They are captured
        # after lock-enforced resolution, rather than copied as authored input.
        if name.startswith(".dart_tool/") or name == ".flutter-plugins-dependencies":
            continue
        path = ROOT / name
        if not path.is_file():
            continue
        if name != ".env.example" and (path.name in native.PRIVATE_NAMES
                or path.name.startswith(".env") or path.suffix.lower() in
                {".jks", ".keystore", ".p12", ".pfx", ".p8", ".pem", ".key", ".mobileprovision"}):
            continue
        if path.is_symlink() or not path.resolve().is_relative_to(ROOT):
            raise ValueError("Declared input is not a regular contained source: " + name)
        result[name] = sha(path)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter", type=Path, required=True)
    parser.add_argument("--export", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--history-defines", type=Path, required=True)
    for name in ("admin-receipts", "roster-original", "roster-reload", "roster-fresh"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--admin-actor", required=True)
    parser.add_argument("--timeout", type=int, default=2400)
    parser.add_argument("--concurrency", type=int, default=2)
    args = parser.parse_args()
    output, export = args.output.resolve(), args.export.resolve()
    if output.exists() or export.exists() or not output.is_relative_to(ROOT / "docs/release"):
        parser.error("Fresh release report and source export required")
    if export == ROOT or export.is_relative_to(ROOT):
        parser.error("Source export must be outside the checkout")
    output.mkdir(parents=True, mode=0o700)
    before = declared_files()
    save(output / "source-before.json", before)
    for name, digest in before.items():
        destination = export / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
        if sha(destination) != digest or sha(ROOT / name) != digest:
            raise ValueError("Source changed during copy: " + name)
    save(output / "source-export.json", {"inputs_sha256": before, "export": str(export)})
    defines = json.loads(args.history_defines.read_text())
    if not isinstance(defines.get("MEMBER_HISTORY_SQL_RECEIPTS_BASE64"), str):
        raise ValueError("Actual SQL history define is absent")
    receipts = {}
    for option, define in (("admin_receipts", "ADMIN_READ_SQL_RECEIPTS"),
                          ("roster_original", "ROSTER_SQL_RECEIPTS"),
                          ("roster_reload", "ROSTER_RELOAD_SQL_RECEIPTS"),
                          ("roster_fresh", "ROSTER_FRESH_SQL_RECEIPTS")):
        source = getattr(args, option).resolve(strict=True)
        target = output / (option + ".stdout")
        shutil.copy2(source, target)
        if sha(source) != sha(target):
            raise ValueError("Receipt changed during copy")
        defines[define] = str(target)
        receipts[define] = {"source": str(source), "sha256": sha(target)}
    defines["ADMIN_READ_SQL_ACTOR"] = args.admin_actor
    define_path = output / "decoder-defines.json"
    save(define_path, defines)
    save(output / "decoder-input-bindings.json", {
        "receipts": receipts, "history_defines_source": str(args.history_defines.resolve()),
        "history_defines_source_sha256": sha(args.history_defines), "sql_executed": False,
        "scope": "Separately dated genuine synthetic SQL receipts as decoder compatibility inputs; no current installation claim",
    })
    environment = {key: value for key, value in os.environ.items() if key in
                   {"HOME", "USER", "LOGNAME", "SHELL", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE"}}
    environment.update(CI="true", FLUTTER_SUPPRESS_ANALYTICS="true",
                       PUB_CACHE=str(ROOT / ".cache/pub-cache-hygiene-20260930"))
    commands = []
    tests = sorted(str(path.relative_to(export)) for path in (export / "test").rglob("*_test.dart"))
    save(output / "test-selection.json", tests)
    flutter = str(args.flutter.resolve(strict=True))
    sdk = Path(flutter).parent.parent
    environment["PATH"] = str(sdk / "bin") + ":" + environment["PATH"]
    critical = [sdk / "bin/cache/dart-sdk/bin/dart", sdk / "bin/cache/dart-sdk/bin/dartaotruntime",
                sdk / "bin/cache/flutter_tools.snapshot"]
    critical.extend((sdk / "bin/cache/artifacts/engine").glob("darwin*/flutter_tester"))
    sdk_before = {str(path): sha(path) for path in critical if path.is_file()}
    save(output / "sdk-before.json", sdk_before)
    toolchain_matches_pin = False
    generated_bindings = {}
    for name, argv in [
        # Source-hygiene tests invoke git ls-files/check-ignore. Give the
        # exported distribution its own empty repository rather than inheriting
        # the shared checkout's index or copying Git history/credentials.
        ("export-git", ["git", "init", "--quiet"]),
        ("toolchain", [flutter, "--version", "--machine"]),
        ("pub", [flutter, "pub", "get", "--offline", "--enforce-lockfile"]),
        ("analysis", [flutter, "analyze", "--no-pub", "--fatal-infos", "--fatal-warnings"]),
        ("vm", [flutter, "test", "--no-pub", "--concurrency=" + str(args.concurrency),
                "--dart-define-from-file=" + str(define_path), "--reporter=expanded",
                "--file-reporter=json:" + str(output / "vm.machine.jsonl"), *tests]),
    ]:
        print("START " + name, flush=True)
        previous = dict(os.environ)
        try:
            os.environ.clear()
            os.environ.update(environment)
            result = gate.run_command(argv, export, output / (name + ".log"), args.timeout)
        finally:
            os.environ.clear()
            os.environ.update(previous)
        commands.append({"name": name, **result})
        if name == "toolchain" and result["exit_code"] == 0:
            version = json.loads((output / "toolchain.log").read_text())
            toolchain_matches_pin = (
                version["frameworkVersion"] == json.loads((export / ".fvmrc").read_text())["flutter"]
                and version["frameworkRevision"] == "ad70ec4617166f1c38e5d2bfd388af71fda14f06"
                and version["dartSdkVersion"] == "3.12.2"
            )
            if not toolchain_matches_pin:
                break
        if name == "pub" and result["exit_code"] == 0:
            if sha(export / "pubspec.lock") != before["pubspec.lock"]:
                raise ValueError("Lock-enforced Pub restoration changed the declared lock")
            generated_bindings = {name: sha(export / name) for name in
                (".dart_tool/package_config.json", ".flutter-plugins-dependencies")}
            save(output / "generated-package-bindings-before.json", generated_bindings)
        save(output / "execution.json", {"status": "running", "commands": commands})
        print("END " + name + " " + str(result["exit_code"]), flush=True)
        if result["exit_code"] != 0 and name in {"export-git", "toolchain", "pub"}:
            break
    after = declared_files()
    export_drift = {name: digest for name, digest in before.items()
                    if not (export / name).is_file() or sha(export / name) != digest}
    source_drift = {name: {"before": before.get(name), "after": after.get(name)}
                    for name in before.keys() | after.keys() if before.get(name) != after.get(name)}
    machine = gate.machine_summary(output / "vm.machine.jsonl") if (output / "vm.machine.jsonl").exists() else None
    sdk_after = {name: sha(Path(name)) for name in sdk_before}
    generated_after = {name: sha(export / name) for name in generated_bindings}
    save(output / "generated-package-bindings-after.json", generated_after)
    passed = (len(commands) == 5 and all(row["exit_code"] == 0 for row in commands)
              and not source_drift and not export_drift and machine is not None
              and machine["runner_completed_successfully"] and not machine["failed"] and not machine["errors"]
              and not machine["unfinished"] and not machine["event_errors"]
              and toolchain_matches_pin and sdk_before == sdk_after
              and bool(generated_bindings) and generated_bindings == generated_after)
    save(output / "source-after.json", after)
    save(output / "validation.json", {
        "status": "pass" if passed else "fail", "commands": commands,
        "test_files": len(tests), "machine_summary": machine,
        "source_input_count": len(before), "source_drift": source_drift,
        "export_drift": export_drift, "decoder_defines_sha256": sha(define_path),
        "generated_package_bindings_unchanged": bool(generated_bindings) and generated_bindings == generated_after,
        "toolchain_matches_pin": toolchain_matches_pin, "sdk_inputs_unchanged": sdk_before == sdk_after,
        "web_only_skips_require_separate_browser_evidence": True,
        "export_git_scope": "Fresh distribution-only repository; shared checkout index/history not copied",
        "database_commands_executed": False, "deployment_commands_executed": False,
        "provider_credentials_supplied": False, "all_test_outbound_calls_instrumented": False,
        "scope": "All declared Flutter VM tests and fatal analysis on one isolated source set; no whole browser/native/backend/release acceptance",
    })
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
