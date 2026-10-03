from pathlib import Path
import hashlib, json, datetime
ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
errors = []
index = json.loads((OUT / "evidence-index.json").read_text())
for row in index["files"]:
    p = ROOT / row["path"]
    if p.is_symlink() or not p.is_file() or p.stat().st_size != row["bytes"] or sha(p) != row["sha256"]:
        errors.append(row["path"])
batch = json.loads((OUT / "batch.json").read_text())
if sha(OUT / "evidence-index.json") != batch["evidence_index"]["sha256"]:
    errors.append("evidence index")
run = json.loads((OUT / "applied-verification.json").read_text())
if run["status"] != "pass" or run["tests"] != {"passed": 109, "failed": 0} or [p["exit_code"] for p in run["phases"]] != [0,0,0,0]:
    errors.append("actual phase results")
for path, digest in run["source_current_after"].items():
    p = ROOT / path
    if p.is_symlink() or sha(p) != digest:
        errors.append("current:" + path)
for path, digest in run["remote_cache_after"].items():
    if sha(Path(path)) != digest:
        errors.append("cached:" + path)
runtime = ROOT / ".cache/roster-deno-2.5.6-20260929/deno"
if sha(runtime) != run["runtime_after"]:
    errors.append("pinned runtime")
prior = json.loads((OUT / "previous-packets-final-readback.json").read_text())
for packet in prior["packets"]:
    directory = OUT.parent / packet["packet"]
    if sha(directory / "batch.json") != packet["batch_sha256"] or sha(directory / "evidence-index.json") != packet["index_sha256"]:
        errors.append("prior sealed:" + packet["packet"])
    for row in json.loads((directory / "evidence-index.json").read_text())["files"]:
        p = ROOT / row["path"]
        if not p.is_file() or p.stat().st_size != row["bytes"] or sha(p) != row["sha256"]:
            errors.append("prior leaf:" + row["path"])
receipt = {"observed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "status": "pass" if not errors else "fail", "indexed_new_leaves": len(index["files"]), "current_source_inputs": len(run["source_current_after"]), "cached_remote_inputs": len(run["remote_cache_after"]), "preserved_prior_leaves": sum(p["indexed_leaves"] for p in prior["packets"]), "batch_sha256": sha(OUT / "batch.json"), "index_sha256": sha(OUT / "evidence-index.json"), "errors": errors, "whole_BE13_closed": False, "production_acceptance": False}
with (OUT / "seal-readback.json").open("x") as f:
    f.write(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt))
raise SystemExit(0 if not errors else 1)
