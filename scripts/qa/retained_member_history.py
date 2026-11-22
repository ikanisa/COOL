"""Run the shipping Flutter decoder against the recorded 175-migration SQL cohort."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PACKET = Path("test/fixtures/retained-member-history")
VALIDATION_SHA256 = "aef09eac80bc10de49e6046f62f53c4602ae263c645258d548d4c60423f3a0c3"
TEST = "test/actual_member_history_sql_receipts_test.dart"


def committed_source(repository, revision):
    # Runs from a physical fixture directory also work in exports without Git tooling.
    from release_tree_custody import output

    commit = output(repository, "rev-parse", "--verify", "--end-of-options",
                    revision + "^{commit}").decode().strip()
    tree = output(repository, "rev-parse", "--verify", commit + ":" + PACKET.as_posix()).decode().strip()

    def read(relative):
        entry = output(repository, "--literal-pathspecs", "ls-tree", "-z", tree, "--", relative.as_posix())
        if not entry:
            raise ValueError(f"Committed history input is missing at {relative}")
        header, name = entry.removesuffix(b"\0").split(b"\t", 1)
        mode, kind, blob = header.split()
        if mode not in (b"100644", b"100755") or kind != b"blob" or os.fsdecode(name) != relative.as_posix():
            raise ValueError(f"Expected a committed regular file at {relative}")
        return output(repository, "cat-file", "blob", blob.decode("ascii"))

    return {"kind": "git", "commit": commit, "tree": tree}, read


def directory_reader(packet):
    root = packet.resolve(strict=True)

    def read(relative):
        path = root / relative
        if path.resolve() != path or not path.is_file():
            raise ValueError(f"Expected a retained regular file at {relative}")
        return path.read_bytes()

    return read


def retained_source(archive=None, git_source=None):
    if git_source is not None:
        return committed_source(*git_source)
    if archive is not None or os.path.lexists(ROOT / PACKET):
        return {"kind": "directory"}, directory_reader(archive if archive is not None else ROOT / PACKET)
    return committed_source(ROOT, "HEAD")


def original_defines(packet=ROOT / PACKET, *, read_file=None, records=None):
    if read_file is None:
        read_file = directory_reader(packet)

    def read_checked(relative, expected):
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"History input escapes the retained unit at {relative}")
        raw = read_file(relative)
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError(f"Recorded SQL evidence changed at {relative.name}")
        if records is not None:
            records.append({"path": (PACKET / relative).as_posix(), "sha256": expected, "bytes": len(raw)})
        return json.loads(raw)

    scope = read_checked(Path("validation.json"), VALIDATION_SHA256)["actual_sql_history_scope"]
    data = Path("actual-history-sql")
    result = read_checked(data / "result.json", scope["result_sha256"])
    previous = read_checked(data / "retained-unsafe-result.json", scope["retained_unsafe_scope"]["result_sha256"])
    inputs = {name: read_checked(data / name, digest) for name, digest in scope["artifact_sha256"].items()}
    if result["artifact_sha256"] != scope["artifact_sha256"]:
        raise ValueError("Historical server result and decoder inputs disagree")
    unsafe_rows = [row for row in previous["precision_boundary_observations"] if row.get("actual_response") is not None]
    # Preserve the original encoder's field order and JSON separators. The
    # historical capture independently recorded the digest of this exact file.
    fixture = {
        "pages": inputs["actual-member-history-pages.json"],
        "balances": inputs["actual-member-balances.json"],
        "precision_observations": result["precision_boundary_observations"] + unsafe_rows,
        "aggregate_observation": previous["aggregate_boundary_observation"],
        "synthetic_mechanics_only": True,
        "concurrent_sorts": inputs["actual-concurrent-sort-receipts.json"],
        "historical_unsafe_observation_count": 2,
    }
    encoded = base64.b64encode(json.dumps(fixture).encode()).decode("ascii")
    body = (json.dumps({"MEMBER_HISTORY_SQL_RECEIPTS_BASE64": encoded}, separators=(",", ":")) + "\n").encode()
    if hashlib.sha256(body).hexdigest() != scope["define_file_sha256"]:
        raise ValueError("Reconstructed defines differ from the original reviewed decoder run")
    return body


def verified_inputs(archive, git_source):
    files = []
    source, read = retained_source(archive, git_source)
    body = original_defines(read_file=read, records=files)
    return body, {"format": "collect.retained-member-history-inputs.v1", "source": source,
                  "unit": PACKET.as_posix(), "files": sorted(files, key=lambda row: row["path"]),
                  "bytes": sum(row["bytes"] for row in files), "defines_sha256": hashlib.sha256(body).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--archive", type=Path, help="Read only this physical retained-history fixture directory")
    source.add_argument("--git-source", nargs=2, metavar=("REPOSITORY", "REVISION"),
                        help="Read committed inputs; the default uses this checkout's HEAD when its packet is absent")
    parser.add_argument("--list-inputs", action="store_true",
                        help="Print verified input paths, digests and source identity without running Flutter")
    args = parser.parse_args()
    try:
        body, report = verified_inputs(args.archive, args.git_source)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Retained member-history verification failed. {error}", file=sys.stderr)
        return 2
    if args.list_inputs:
        print(json.dumps(report, sort_keys=True))
        return 0
    if report["source"]["kind"] == "git":
        print("Reading retained SQL inputs from commit " + report["source"]["commit"], flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix="collect-retained-history-") as directory:
            defines = Path(directory) / "defines.json"
            defines.write_bytes(body)
            flutter = os.environ.get("FLUTTER_BIN", "flutter")
            for platform in ("vm", "chrome"):
                platform_args = ["--platform", "chrome"] if platform == "chrome" else []
                subprocess.run([flutter, "test", "--no-pub", "--tags=integration", *platform_args,
                                f"--dart-define-from-file={defines}", TEST], cwd=ROOT, check=True)
    except subprocess.CalledProcessError as error:
        return error.returncode
    except OSError as error:
        print(f"Retained member-history verification failed. {error}", file=sys.stderr)
        return 2
    print("Historical SQL decoder passed on VM and Chrome.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
