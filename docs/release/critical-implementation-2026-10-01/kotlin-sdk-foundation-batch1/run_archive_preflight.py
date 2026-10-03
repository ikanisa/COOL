#!/usr/bin/env python3
"""Read actual authenticated ZIP metadata/source in RAM; never expand to disk."""
import copy
import datetime
import hashlib
import json
import shutil
import signal
import stat
import time
import zipfile
from collections import Counter
from pathlib import Path
from prepare_safe_expansion import PACKET, blob_id, check_metadata, source_compare, require_admission

started = time.monotonic()
def expired(signum, frame):
    raise TimeoutError("actual fixed read-only preflight deadline expired")
signal.signal(signal.SIGALRM, expired)
signal.alarm(180)
foundation = json.loads((PACKET / "foundation-results.json").read_text())
identity = foundation["archive"]
archive_path = Path(identity["task_local_path"])
initial = archive_path.lstat()
assert stat.S_ISREG(initial.st_mode) and initial.st_nlink == 1
assert (initial.st_size, initial.st_ino, initial.st_dev, initial.st_mtime_ns) == (
    identity["bytes"], identity["local_inode"], identity["local_device"], identity["mtime_ns"])
tree = json.loads((PACKET / "public-origin/official-recursive-tree-attempt3.body").read_text())["tree"]
official_links = {"flutter/" + r["path"]: r["target"] for r in
                  json.loads((PACKET / "official-symlink-validation.json").read_text())["official_symlinks"]}
reviewed = json.loads((PACKET / "reviewed-framework-links.json").read_text())
assert reviewed["archive_sha256"] == identity["published_and_readback_sha256"]
negatives = []

with zipfile.ZipFile(archive_path) as archive:
    infos = archive.infolist()
    targets = {}
    skill_rows = []
    central_rows = []
    for info in infos:
        assert time.monotonic() - started < 180
        mode = info.external_attr >> 16
        central_rows.append({"path": info.filename, "bytes": info.file_size,
                             "compressed_bytes": info.compress_size, "CRC": info.CRC,
                             "mode": oct(mode), "compression": info.compress_type,
                             "flag_bits": info.flag_bits, "header_offset": info.header_offset})
        if stat.S_ISLNK(mode):
            assert info.file_size <= 4096
            targets[info.filename] = archive.read(info).decode("utf-8")
        if info.filename.rsplit("/", 1)[-1].lower() == "skill.md":
            assert info.file_size <= 1024**2
            body = archive.read(info)
            # This classification follows actual inspected bytes. No skill is invoked.
            assert info.filename == "flutter/.agents/skills/find-release/SKILL.md"
            assert b"name: find-release" in body
            assert b"lowest Dart and Flutter release containing a given commit" in body
            skill_rows.append({"path": info.filename, "bytes": len(body),
                               "sha256": hashlib.sha256(body).hexdigest(),
                               "Git_blob_sha1": blob_id(body),
                               "classification": "technical Dart/Flutter commit release lookup",
                               "competing_UI_design_authority": False, "registered_or_executed": False})
    legacy = check_metadata(infos, targets, official_links)
    metadata = check_metadata(infos, targets, official_links, reviewed["links"])
    source = source_compare(archive, infos, tree)
    (PACKET / "archive-central-directory.json").write_text(json.dumps({
        "archive_sha256": identity["published_and_readback_sha256"],
        "members": central_rows}, indent=2, sort_keys=True) + "\n")

    license_info = next(i for i in infos if i.filename == "flutter/LICENSE")
    def mutate(name, change, expected_kind, expected_path=None, link_change=None):
        changed = list(infos)
        change(changed)
        changed_targets = dict(targets)
        if link_change:
            link_change(changed_targets)
        observed = check_metadata(changed, changed_targets, official_links, reviewed["links"])
        relevant = [r for r in observed["issues"] if r["kind"] == expected_kind
                    and (expected_path is None or r.get("path") == expected_path)]
        if not relevant:
            raise AssertionError("actual ZIP mutation was not specifically rejected: " + name)
        negatives.append({"case": name, "rejected": True, "specific_findings": relevant})
    def replace_license(rows, field, value):
        idx = next(i for i, r in enumerate(rows) if r.filename == "flutter/LICENSE")
        item = copy.copy(rows[idx]); setattr(item, field, value); rows[idx] = item
    mutate("actual_duplicate_member", lambda r: r.append(copy.copy(license_info)),
           "member_rejected", "flutter/LICENSE")
    mutate("actual_parent_traversal", lambda r: replace_license(r, "filename", "flutter/../outside"),
           "member_rejected", "flutter/../outside")
    mutate("actual_absolute_member", lambda r: replace_license(r, "filename", "/outside/LICENSE"),
           "member_rejected", "/outside/LICENSE")
    mutate("actual_NFC_case_alias", lambda r: r.append(
        (lambda i: (setattr(i, "filename", "flutter/license"), i)[1])(copy.copy(license_info))),
        "member_rejected", "flutter/license")
    mutate("actual_FIFO_member", lambda r: replace_license(r, "external_attr", (stat.S_IFIFO | 0o600) << 16),
           "member_rejected", "flutter/LICENSE")
    mutate("actual_oversized_member_and_total", lambda r: replace_license(r, "file_size", 13 * 1024**3),
           "total_size_bound")
    mutate("actual_encrypted_member", lambda r: replace_license(r, "flag_bits", license_info.flag_bits | 1),
           "member_rejected", "flutter/LICENSE")
    mutate("actual_unreviewed_compression", lambda r: replace_license(r, "compress_type", zipfile.ZIP_BZIP2),
           "member_rejected", "flutter/LICENSE")
    mutate("actual_external_object_store_pointer", lambda r: replace_license(
        r, "filename", "flutter/.git/objects/info/alternates"),
        "member_rejected", "flutter/.git/objects/info/alternates")
    mutate("actual_symlink_parent_collision", lambda r: r.append(
        (lambda i: (setattr(i, "filename", "flutter/.claude/skills/unreviewed"), i)[1])(copy.copy(license_info))),
        "ancestor_collision", "flutter/.claude/skills/unreviewed")
    mutate("actual_tracked_symlink_escape", lambda r: None, "link_rejected", "flutter/.claude/skills",
           lambda t: t.update({"flutter/.claude/skills": "../../outside"}))
    current_link = next(n for n in reviewed["links"] if n.endswith("/Versions/Current"))
    mutate("actual_cached_framework_cycle", lambda r: None, "link_rejected", current_link,
           lambda t: t.update({current_link: "../Versions/Current"}))
    mutate("actual_cached_framework_target_drift", lambda r: None, "link_rejected", current_link,
           lambda t: t.update({current_link: "../../../../../outside-framework"}))
    framework_link = next(i for i in infos if i.filename in reviewed["links"]
                          and i.filename.endswith("/Headers"))
    unreviewed_alias = framework_link.filename.rsplit("/", 1)[0] + "/Surprise"
    mutate("actual_extra_internally_contained_framework_alias", lambda r: r.append(
        (lambda i: (setattr(i, "filename", unreviewed_alias), i)[1])(copy.copy(framework_link))),
        "unreviewed_extra_link", unreviewed_alias,
        lambda t: t.update({unreviewed_alias: "Versions/Current/Headers"}))
    # Full real archive source comparison above establishes the baseline. These
    # source negatives use its exact LICENSE leaf and actual retained bytes.
    license_node = next(n for n in tree if n["path"] == "LICENSE")
    subset = [license_node]
    assert source_compare(archive, infos, subset)["passed"]
    mode_changed = list(infos)
    replace_license(mode_changed, "external_attr", license_info.external_attr | (0o111 << 16))
    mode_drift = source_compare(archive, mode_changed, subset)
    assert not mode_drift["passed"] and mode_drift["mode_mismatches"][0]["path"] == "flutter/LICENSE"
    negatives.append({"case": "actual_source_executable_mode_drift", "rejected": True,
                      "mode_mismatches": mode_drift["mode_mismatches"]})
    omitted = source_compare(archive, [i for i in infos if i.filename != "flutter/LICENSE"], subset)
    assert omitted["missing"] == ["flutter/LICENSE"] and not omitted["passed"]
    negatives.append({"case": "actual_license_member_loss", "rejected": True, "missing": omitted["missing"]})
    class ChangedLicenseBytes:
        def read(self, info):
            return archive.read(info) + b"changed"
    changed = source_compare(ChangedLicenseBytes(), infos, subset)
    assert not changed["passed"] and changed["changed"][0]["path"] == "flutter/LICENSE"
    negatives.append({"case": "actual_expanded_license_byte_drift", "rejected": True,
                      "changed_identity": changed["changed"][0]})

end = archive_path.lstat()
assert (initial.st_size, initial.st_ino, initial.st_dev, initial.st_mtime_ns) == (
    end.st_size, end.st_ino, end.st_dev, end.st_mtime_ns)
free = shutil.disk_usage(archive_path.parent).free
metadata_report = {k: v for k, v in metadata.items() if k != "entries"}
report = {"schema_version": 1, "recorded_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "elapsed_seconds": round(time.monotonic() - started, 3), "deadline_seconds": 180,
          "archive_sha256": identity["published_and_readback_sha256"],
          "archive_stat_matches_authenticated_complete_readback": True,
          "entry_count": len(infos), "root": "flutter", "expanded_bytes": metadata["expanded_bytes"],
          "maximum_member_bytes": max(i.file_size for i in infos),
          "compression_counts": dict(Counter(i.compress_type for i in infos)),
          "Unix_type_counts": dict(Counter(oct(stat.S_IFMT(i.external_attr >> 16)) for i in infos)),
          "free_bytes_now": free, "required_headroom_bytes": metadata["expanded_bytes"] + 2 * 1024**3,
          "enough_headroom": free > metadata["expanded_bytes"] + 2 * 1024**3,
          "original_tree_only_plan_issue_count": len(legacy["issues"]),
          "original_tree_only_plan_issues": legacy["issues"],
          "metadata": metadata_report, "source_comparison": source, "skills": skill_rows,
          "competing_UI_design_skill_count": 0, "negative_results": negatives,
          "archive_extracted": False, "SDK_executed": False, "patch_applied": False,
          "scope": "Actual bounded ZIP metadata, link targets and all tracked-source bytes read in RAM only. No filesystem expansion, SDK execution, instruction/skill registration or production acceptance."}
try:
    require_admission(report)
    report["strict_source_and_link_admission"] = True
except ValueError as error:
    report["strict_source_and_link_admission"] = False
    report["remaining_admission_error"] = str(error)
    negatives.append({"case": "actual_unreviewed_source_exceptions_block_writer_admission",
                      "rejected": True, "error": str(error), "filesystem_writes": False})
(PACKET / "archive-preflight.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
signal.alarm(0)
print(json.dumps({"entry_count": report["entry_count"], "expanded_bytes": report["expanded_bytes"],
                  "metadata_admitted_after_exact_link_review": metadata["admitted"],
                  "source_matches": source["matched"], "source_missing": len(source["missing"]),
                  "source_changed": source["changed"], "source_mode_mismatches": source["mode_mismatches"],
                  "strict_admission": report["strict_source_and_link_admission"],
                  "negatives": len(negatives), "elapsed_seconds": report["elapsed_seconds"]}))
