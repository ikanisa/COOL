#!/usr/bin/env python3
"""Exact authenticated publisher admission and prepared physical SDK writer.

CLI supports read-only admission only. The writer requires a separately
authorized future calling task. No SDK, hook, Git or bootstrap is executed here.
"""
import contextlib
import datetime
import hashlib
import importlib.util
import json
import os
import shutil
import signal
import stat
import time
import zipfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
FOUNDATION = HERE.parent / "kotlin-sdk-foundation-batch1"
ROOT_REVIEW = HERE.parent / "root-sdk-foundation-review-batch1/exact-checkout-delta-review.json"
ARCHIVE = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/public-artifacts/flutter_macos_arm64_3.44.4-stable.zip")
DESTINATION = Path("/Volumes/PRO-G40/Development/Codex-Candidates/COOL-ARC09/flutter-3.44.4-collect-kotlin-2.4.20-candidate1")
INSTALLED = Path("/Volumes/PRO-G40/Development/Flutter/flutter")
ARCHIVE_SHA = "eac833fe956c670d1f27946f25de8bc4fe4fb86146d5ef8d53e79a971a3ba042"
FOUNDATION_MANIFEST_SHA = "35afe09b9fcc8fc97b2f8ede9e65dfd8cbc05ae5d07e1097cc2096baa021aa4e"
FOUNDATION_FREEZE_SHA = "2885cc31f500defc1eaf5b5b6b3b45ce792928360a7d6a30e75c9828e1350a11"
ROOT_REVIEW_SHA = "1e66b0090c19b803b9e4823976d6c1be37ced19d03342147a5188aada06dab7d"
EOL_MANIFEST_SHA = "a2973071acadf279d9e22535611167705a9f1918d76270f3938ca93d85da435c"
LINK_MANIFEST_SHA = "69dba636e0276c26b935101770a9f45f24ac135fe010043d75646f1fe19bb774"


def sha_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024**2), b""):
            digest.update(chunk)
    return digest.hexdigest()


def exact_json(path, expected):
    body = Path(path).read_bytes()
    if hashlib.sha256(body).hexdigest() != expected:
        raise ValueError("exact reviewed metadata drift: " + str(path))
    return json.loads(body)


@contextlib.contextmanager
def deadline(seconds):
    def expired(signum, frame):
        raise TimeoutError("fixed actual SDK admission/expansion deadline expired")
    old = signal.signal(signal.SIGALRM, expired)
    signal.alarm(seconds)
    try:
        yield
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old)


def bindings():
    manifest = exact_json(FOUNDATION / "packet-files.json", FOUNDATION_MANIFEST_SHA)
    exact_json(FOUNDATION / "source-freeze.json", FOUNDATION_FREEZE_SHA)
    for name, digest in manifest["files"].items():
        if sha_file(FOUNDATION / name) != digest:
            raise ValueError("sealed foundation leaf drift: " + name)
    review = exact_json(ROOT_REVIEW, ROOT_REVIEW_SHA)
    if not review["admit_exact_manifest_only"] or review["blanket_normalization_allowed"]:
        raise ValueError("root source review does not authorize exact-only checkout representation")
    eol = exact_json(FOUNDATION / "publisher-checkout-eol-deltas.json", EOL_MANIFEST_SHA)
    links = exact_json(FOUNDATION / "reviewed-framework-links.json", LINK_MANIFEST_SHA)
    if (review["archive_source_manifest_sha256"] != EOL_MANIFEST_SHA
            or eol["archive_sha256"] != ARCHIVE_SHA or links["archive_sha256"] != ARCHIVE_SHA):
        raise ValueError("archive/review trust anchors disagree")
    eol_rows = {r["path"]: r for r in eol["expected_checkout_deltas"]}
    review_rows = {r["path"]: r for r in review["files"]}
    if len(eol_rows) != 33 or set(eol_rows) != set(review_rows):
        raise ValueError("exact checkout whitelist set drift")
    for path, row in eol_rows.items():
        checked = review_rows[path]
        if (row["actual_sha256"] != checked["archive_sha256"]
                or row["canonical_git_sha256"] != checked["canonical_sha256"]
                or row["canonical_git_blob_sha1"] != checked["canonical_git_blob_sha1"]
                or not checked["exact_attribute_checkout_only"]):
            raise ValueError("exact checkout review pair drift")
    helper_path = FOUNDATION / "prepare_safe_expansion.py"
    specification = importlib.util.spec_from_file_location("sealed_sdk_archive_safety", helper_path)
    helper = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(helper)
    tree = json.loads((FOUNDATION / "public-origin/official-recursive-tree-attempt3.body").read_text())
    nodes = {"flutter/" + n["path"]: n for n in tree["tree"] if n["mode"] != "040000"}
    official = json.loads((FOUNDATION / "official-symlink-validation.json").read_text())
    source_links = {"flutter/" + r["path"]: r["target"] for r in official["official_symlinks"]}
    all_links = {**source_links, **links["links"]}
    if len(all_links) != 17:
        raise ValueError("exact source/framework link whitelist set drift")
    return helper, nodes, eol_rows, source_links, links["links"], all_links


def source_identity(path, body, mode, nodes, checkout, helper):
    if path not in nodes:
        return None
    node = nodes[path]
    expected_mode = int(node["mode"], 8)
    if stat.S_IFMT(mode) != stat.S_IFMT(expected_mode):
        raise ValueError("source type drift: " + path)
    if stat.S_ISREG(expected_mode) and bool(mode & 0o111) != bool(expected_mode & 0o111):
        raise ValueError("source executable distinction drift: " + path)
    raw_sha = hashlib.sha256(body).hexdigest()
    canonical = body
    if path in checkout:
        pair = checkout[path]
        # Check exact publisher raw bytes BEFORE conversion; no suffix-based or
        # blanket normalization ever admits unreviewed file bytes.
        if raw_sha != pair["actual_sha256"] or len(body) != pair["actual_bytes"]:
            raise ValueError("reviewed checkout raw-byte drift: " + path)
        canonical = body.replace(b"\r\n", b"\n")
        if (canonical.replace(b"\n", b"\r\n") != body
                or hashlib.sha256(canonical).hexdigest() != pair["canonical_git_sha256"]
                or len(canonical) != pair["canonical_git_bytes"]):
            raise ValueError("reviewed exact checkout inverse drift: " + path)
    if helper.blob_id(canonical) != node["sha"] or len(canonical) != node["size"]:
        raise ValueError("official source blob identity drift: " + path)
    return {"official_git_blob_sha1": node["sha"], "canonical_sha256": hashlib.sha256(canonical).hexdigest(),
            "canonical_bytes": len(canonical), "exact_reviewed_CRLF_checkout": path in checkout}


def reject_external_git_pointers(name, body):
    if name in {"flutter/.git/commondir", "flutter/.git/gitdir", "flutter/.git/objects/info/alternates"}:
        raise ValueError("external Git object/worktree pointer")
    if name.startswith("flutter/.git/worktrees/"):
        raise ValueError("unreviewed external Git worktree metadata")
    if name == "flutter/.git/config":
        text = body.decode("utf-8").lower()
        for forbidden in ("[include", "worktree =", "hookspath =", "fsmonitor =", "credential.helper"):
            if forbidden in text:
                raise ValueError("unreviewed executable/external Git config")


def admit_readonly(progress=None):
    start = time.monotonic()
    with deadline(300):
        helper, nodes, checkout, source_links, framework_links, all_links = bindings()
        before = ARCHIVE.lstat()
        if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1 or sha_file(ARCHIVE) != ARCHIVE_SHA:
            raise ValueError("publisher archive raw-byte/type/link drift")
        members = {}
        source_seen = set()
        skills = []
        with zipfile.ZipFile(ARCHIVE) as archive:
            infos = archive.infolist()
            targets = {}
            for info in infos:
                if helper.kind(info) == "symlink":
                    if info.file_size > 4096:
                        raise ValueError("link byte bound")
                    targets[info.filename] = archive.read(info).decode("utf-8")
            if targets != all_links:
                raise ValueError("actual ZIP link path/target set differs from exact17 whitelist")
            metadata = helper.check_metadata(infos, targets, source_links, framework_links)
            if not metadata["admitted"]:
                raise ValueError("unsafe/unreviewed archive metadata: " + json.dumps(metadata["issues"]))
            if any(parent not in metadata["entries"] for name in metadata["entries"]
                   for parent in [str(Path(name).parent)] if parent not in (".", "")):
                raise ValueError("implicit unmanifested archive parent directory")
            for index, info in enumerate(infos):
                name = helper.canonical(info.filename)
                file_kind = helper.kind(info)
                mode = info.external_attr >> 16
                digest = hashlib.sha256(); crc = 0; count = 0
                source_body = bytearray() if name in nodes else None
                git_body = bytearray() if name == "flutter/.git/config" else None
                with archive.open(info) as stream:
                    while True:
                        chunk = stream.read(1024**2)
                        if not chunk: break
                        count += len(chunk)
                        if count > info.file_size:
                            raise ValueError("expanded member overrun")
                        digest.update(chunk); crc = zlib.crc32(chunk, crc)
                        if source_body is not None:
                            if count > 8 * 1024**2: raise ValueError("source RAM bound")
                            source_body.extend(chunk)
                        if git_body is not None:
                            if count > 1024**2: raise ValueError("Git config RAM bound")
                            git_body.extend(chunk)
                if count != info.file_size or crc != info.CRC:
                    raise ValueError("actual expanded member length/CRC drift")
                reject_external_git_pointers(name, bytes(git_body or b""))
                row = {"kind": file_kind, "bytes": count, "sha256": digest.hexdigest(), "CRC": crc,
                       "publisher_mode": mode, "safe_materialized_mode": (mode & 0o777) & ~0o022,
                       "compression_method": info.compress_type, "compressed_bytes": info.compress_size}
                if source_body is not None:
                    row["source"] = source_identity(name, bytes(source_body), mode, nodes, checkout, helper)
                    source_seen.add(name)
                if file_kind == "symlink":
                    row["target"] = targets[name]
                    row["resolved_archive_target"] = next(r["resolved_target"] for r in metadata["links"] if r["path"] == name)
                if name.rsplit("/", 1)[-1].lower() == "skill.md":
                    if name != "flutter/.agents/skills/find-release/SKILL.md" or row.get("source") is None:
                        raise ValueError("unreviewed/competing upstream skill member")
                    skills.append(name)
                members[name] = row
                if progress and index % 1000 == 0:
                    progress({"verified_members": index + 1, "elapsed_seconds": round(time.monotonic() - start, 2)})
        if source_seen != set(nodes):
            raise ValueError("missing official source/license entry")
        after = ARCHIVE.lstat()
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) != (
                after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError("archive changed during exact read-only admission")
        return {"schema_version": 1, "status": "EXACT_PUBLISHER_ARCHIVE_ADMITTED__NO_EXPANSION",
                "recorded_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                "archive_sha256": ARCHIVE_SHA, "root_review_sha256": ROOT_REVIEW_SHA,
                "eol_whitelist_sha256": EOL_MANIFEST_SHA, "framework_whitelist_sha256": LINK_MANIFEST_SHA,
                "archive_stat": {"dev": after.st_dev, "inode": after.st_ino, "bytes": after.st_size, "mtime_ns": after.st_mtime_ns},
                "members": members, "source_entries": len(nodes), "exact_checkout_pairs": len(checkout),
                "exact_links": len(all_links), "technical_skills": skills,
                "all_expanded_member_bytes_and_CRC_readonly_verified": True,
                "expanded_bytes": sum(r["bytes"] for r in members.values()),
                "elapsed_seconds": round(time.monotonic() - start, 3), "actual_deadline_seconds": 300,
                "SDK_executed": False, "filesystem_expansion_performed": False,
                "production_release_approval": False}


def fsync_directory(path):
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0))
    try: os.fsync(fd)
    finally: os.close(fd)


def validate_exact_admission(admission):
    """Reject internally inconsistent receipts before creating any directory."""
    helper, nodes, checkout, source_links, framework_links, all_links = bindings()
    if (admission["status"] != "EXACT_PUBLISHER_ARCHIVE_ADMITTED__NO_EXPANSION"
            or admission["archive_sha256"] != ARCHIVE_SHA or admission["root_review_sha256"] != ROOT_REVIEW_SHA
            or admission["eol_whitelist_sha256"] != EOL_MANIFEST_SHA
            or admission["framework_whitelist_sha256"] != LINK_MANIFEST_SHA
            or not admission["all_expanded_member_bytes_and_CRC_readonly_verified"]
            or admission["SDK_executed"] or admission["filesystem_expansion_performed"]
            or admission["source_entries"] != len(nodes) or admission["exact_checkout_pairs"] != 33
            or admission["exact_links"] != 17):
        raise ValueError("unreviewed/fake/stale admission")
    rows = admission["members"]
    if set(n for n, r in rows.items() if "source" in r) != set(nodes):
        raise ValueError("admission official source/license set drift")
    targets = {n: r["target"] for n, r in rows.items() if r["kind"] == "symlink"}
    if targets != all_links:
        raise ValueError("admission exact17 link whitelist drift")
    infos = []
    for name, row in rows.items():
        if helper.canonical(name) != name:
            raise ValueError("admission noncanonical member path")
        info = zipfile.ZipInfo(name + ("/" if row["kind"] == "directory" else ""))
        info.external_attr = row["publisher_mode"] << 16
        info.file_size = row["bytes"]; info.compress_size = row["compressed_bytes"]
        info.compress_type = row["compression_method"]; infos.append(info)
        if (helper.kind(info) != row["kind"]
                or row["safe_materialized_mode"] != (row["publisher_mode"] & 0o777) & ~0o022
                or not 0 <= row["CRC"] <= 0xffffffff
                or len(row["sha256"]) != 64):
            raise ValueError("admission member metadata drift")
        if name in nodes:
            expected_mode = int(nodes[name]["mode"], 8)
            identity = row["source"]
            if (stat.S_IFMT(row["publisher_mode"]) != stat.S_IFMT(expected_mode)
                    or (stat.S_ISREG(expected_mode)
                        and bool(row["publisher_mode"] & 0o111) != bool(expected_mode & 0o111))
                    or identity["official_git_blob_sha1"] != nodes[name]["sha"]
                    or identity["canonical_bytes"] != nodes[name]["size"]
                    or identity["exact_reviewed_CRLF_checkout"] != (name in checkout)):
                raise ValueError("admission official source identity/mode drift")
            if name in checkout:
                pair = checkout[name]
                if (row["bytes"] != pair["actual_bytes"] or row["sha256"] != pair["actual_sha256"]
                        or identity["canonical_sha256"] != pair["canonical_git_sha256"]):
                    raise ValueError("admission exact checkout pair drift")
            elif row["bytes"] != nodes[name]["size"] or row["sha256"] != identity["canonical_sha256"]:
                raise ValueError("admission raw source identity drift")
    metadata = helper.check_metadata(infos, targets, source_links, framework_links)
    if not metadata["admitted"]:
        raise ValueError("unsafe admission member metadata")
    if any(str(Path(n).parent) not in rows for n in rows if n != "flutter"):
        raise ValueError("admission implicit parent")
    if admission["expanded_bytes"] != sum(r["bytes"] for r in rows.values()):
        raise ValueError("admission total expanded size drift")
    for link in metadata["links"]:
        if rows[link["path"]]["resolved_archive_target"] != link["resolved_target"]:
            raise ValueError("admission recursive link target drift")
    return helper


def verify_physical_readback(admission, destination=DESTINATION):
    validate_exact_admission(admission)
    helper, nodes, checkout, _, _, all_links = bindings()
    destination = Path(destination)
    if destination != DESTINATION or destination.is_symlink() or not destination.is_dir():
        raise ValueError("physical root is not the exact independent destination")
    actual = {"flutter": destination}
    pending = [destination]
    while pending:
        directory = pending.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = Path(entry.path); name = "flutter/" + str(path.relative_to(destination))
                if name in actual: raise ValueError("duplicate filesystem identity")
                actual[name] = path
                if stat.S_ISDIR(entry.stat(follow_symlinks=False).st_mode): pending.append(path)
    if set(actual) != set(admission["members"]):
        raise ValueError("expanded filesystem path set differs from exact admitted manifest")
    rows = {}; source_seen = set(); shared = []; licenses = []
    for name, expected in admission["members"].items():
        path = actual[name]; observation = path.lstat(); file_kind = expected["kind"]
        if file_kind == "directory":
            if not stat.S_ISDIR(observation.st_mode): raise ValueError("directory type drift")
        elif file_kind == "symlink":
            if not stat.S_ISLNK(observation.st_mode) or os.readlink(path) != all_links[name]:
                raise ValueError("physical exact link byte/type drift")
            if not path.resolve(strict=True).is_relative_to(destination.resolve(strict=True)):
                raise ValueError("physical outward link")
            if path.resolve(strict=True) != actual[expected["resolved_archive_target"]].resolve(strict=True):
                raise ValueError("physical link resolves to unexpected member")
            body = os.readlink(path).encode()
            if name in nodes:
                source_identity(name, body, stat.S_IFLNK, nodes, checkout, helper); source_seen.add(name)
        else:
            if not stat.S_ISREG(observation.st_mode) or observation.st_nlink != 1:
                raise ValueError("physical special/shared writable inode")
            digest = hashlib.sha256(); crc = 0; count = 0
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024**2), b""):
                    count += len(chunk); digest.update(chunk); crc = zlib.crc32(chunk, crc)
                    if count > expected["bytes"]: raise ValueError("physical readback byte bound")
            if (observation.st_size, count, digest.hexdigest(), crc) != (
                    expected["bytes"], expected["bytes"], expected["sha256"], expected["CRC"]):
                raise ValueError("full independent regular byte readback drift")
            if name in nodes:
                source_identity(name, path.read_bytes(), observation.st_mode, nodes, checkout, helper); source_seen.add(name)
            installed = INSTALLED / path.relative_to(destination)
            if installed.exists() and installed.is_file():
                other = installed.stat()
                if (other.st_dev, other.st_ino) == (observation.st_dev, observation.st_ino):
                    shared.append(name)
            if any(tag in path.name.lower() for tag in ("license", "copying", "notice")):
                licenses.append(name)
        if file_kind != "symlink" and stat.S_IMODE(observation.st_mode) != expected["safe_materialized_mode"]:
            raise ValueError("physical safe mode drift")
        rows[name] = {"kind": file_kind, "device": observation.st_dev, "inode": observation.st_ino,
                      "nlink": observation.st_nlink, "actual_mode": stat.S_IMODE(observation.st_mode),
                      "bytes": observation.st_size, "admitted_sha256": expected["sha256"]}
    if source_seen != set(nodes) or shared:
        raise ValueError("incomplete source readback/shared installed SDK inode")
    return {"passed": True, "member_count": len(rows), "source_entries_readback": len(source_seen),
            "license_notice_paths": licenses, "shared_installed_SDK_inodes": shared,
            "physical_identity_manifest": rows, "SDK_executed": False,
            "scope": "Fresh physical byte/mode/source/link/license-path/inode proof only; no ABI/advisory/legal/release acceptance."}


def expand_after_separate_authorization(admission_file, expected_admission_sha, progress=None):
    """Prepared only. Current task never calls this function.

    A future authorized caller supplies the sealed exact read-only admission
    identity. SDK/bootstrap/patch/selection are not performed by this writer.
    """
    admission = exact_json(admission_file, expected_admission_sha)
    helper = validate_exact_admission(admission)
    with deadline(600):
        if sha_file(ARCHIVE) != ARCHIVE_SHA:
            raise ValueError("publisher archive changed before expansion")
        if DESTINATION.exists() or DESTINATION.is_symlink():
            raise ValueError("destination already exists; no replacement/reuse")
        if DESTINATION.parent.resolve() != DESTINATION.parent or any(p.is_symlink() for p in DESTINATION.parents):
            raise ValueError("independent destination has a link ancestor")
        if DESTINATION.is_relative_to(INSTALLED) or INSTALLED.is_relative_to(DESTINATION):
            raise ValueError("shared installed SDK/root overlap")
        if shutil.disk_usage(DESTINATION.parent).free < admission["expanded_bytes"] + 2 * 1024**3:
            raise ValueError("insufficient current physical headroom")
        start = time.monotonic(); last_progress = start
        DESTINATION.mkdir(mode=0o700)
        def local(name):
            return DESTINATION.joinpath(*helper.canonical(name).split("/")[1:])
        directories = sorted((n for n, r in admission["members"].items() if r["kind"] == "directory"),
                             key=lambda n: n.count("/"))
        for name in directories:
            path = local(name)
            if path != DESTINATION:
                if not stat.S_ISDIR(path.parent.lstat().st_mode): raise ValueError("unsafe physical parent")
                path.mkdir(mode=0o700)
        with zipfile.ZipFile(ARCHIVE) as archive:
            infos = {helper.canonical(i.filename): i for i in archive.infolist()}
            if set(infos) != set(admission["members"]): raise ValueError("ZIP member set changed")
            for name, expected in admission["members"].items():
                info = infos[name]
                if (helper.kind(info), info.file_size, info.CRC, info.external_attr >> 16,
                        info.compress_type, info.compress_size) != (
                        expected["kind"], expected["bytes"], expected["CRC"], expected["publisher_mode"],
                        expected["compression_method"], expected["compressed_bytes"]):
                    raise ValueError("ZIP metadata differs from exact sealed admission")
            completed = 0
            for name, expected in admission["members"].items():
                if expected["kind"] != "regular": continue
                path = local(name)
                if not stat.S_ISDIR(path.parent.lstat().st_mode): raise ValueError("unsafe physical parent")
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o600)
                digest = hashlib.sha256(); crc = 0; size = 0
                with os.fdopen(fd, "wb") as output, archive.open(infos[name]) as source:
                    for chunk in iter(lambda: source.read(1024**2), b""):
                        size += len(chunk)
                        if size > expected["bytes"]: raise ValueError("physical write byte bound")
                        output.write(chunk); digest.update(chunk); crc = zlib.crc32(chunk, crc)
                    if (size, digest.hexdigest(), crc) != (expected["bytes"], expected["sha256"], expected["CRC"]):
                        raise ValueError("physical stream bytes/CRC drift")
                    output.flush(); os.fchmod(output.fileno(), expected["safe_materialized_mode"])
                    os.fsync(output.fileno())
                if path.lstat().st_nlink != 1: raise ValueError("shared physical writable inode")
                completed += 1
                if progress and time.monotonic() - last_progress >= 20:
                    progress({"written_regular_members": completed, "elapsed_seconds": round(time.monotonic() - start, 2)})
                    last_progress = time.monotonic()
        for name, expected in admission["members"].items():
            if expected["kind"] != "symlink": continue
            path = local(name)
            if not stat.S_ISDIR(path.parent.lstat().st_mode): raise ValueError("unsafe physical link parent")
            os.symlink(expected["target"], path)
        for name in reversed(directories):
            path = local(name); os.chmod(path, admission["members"][name]["safe_materialized_mode"]); fsync_directory(path)
        fsync_directory(DESTINATION.parent)
        readback = verify_physical_readback(admission)
        if sha_file(ARCHIVE) != ARCHIVE_SHA: raise ValueError("archive drift after physical expansion/readback")
        return {"admission_sha256": expected_admission_sha, "archive_sha256": ARCHIVE_SHA,
                "destination": str(DESTINATION), "elapsed_seconds": round(time.monotonic() - start, 3),
                "actual_deadline_seconds": 600, "full_independent_readback": readback,
                "source_patch_applied": False, "SDK_executed": False, "candidate_promoted": False,
                "production_release_approval": False}


if __name__ == "__main__":
    # Read-only admission only. No writer invocation or extraction command exists.
    result = admit_readonly(lambda value: print(json.dumps(value), flush=True))
    (HERE / "exact-archive-admission.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": result["status"], "members": len(result["members"]),
                      "expanded_bytes_verified_in_RAM": result["expanded_bytes"],
                      "source_entries": result["source_entries"], "seconds": result["elapsed_seconds"]}))
