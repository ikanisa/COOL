#!/usr/bin/env python3
"""Prepare Collect's 40-image bank. No network, paid API, app or group writes.

Export standalone prompts for one built-in image_gen call per asset.
The script does not generate pixels or approve artwork. save-source copies
an operator-provided original PNG without overwriting an existing asset.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import unicodedata
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "assets/group_covers/rwanda/catalog.v1.json"
OUTPUT = ROOT / "docs/plans/rwanda-group-asset-bank-2026-09-06/production"
SUBTYPES = {
    "ikimina": {"group_savings", "family_friends", "community_event"},
    "sport": {"fan_club", "team_support", "away_travel"},
    "church": {"offering", "tithe", "project_support"},
    "wedding": {"committee", "gift", "ceremony_support"},
    "other": {"custom"},
}
CONTEXTS = {"christian", "muslim", "bereavement", "health", "new_baby"}


def workspace_path(value):
    path = (ROOT / value).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError(f"Path escapes the workspace: {value}")
    return path


def validate(catalog):
    assets, errors = catalog["assets"], []
    if len(assets) != 40 or catalog["planned_asset_count"] != 40:
        errors.append("Exactly 40 concepts are required.")
    if sorted(a["number"] for a in assets) != list(range(1, 41)):
        errors.append("Asset numbers must cover 1 through 40 exactly once.")
    for field in ("id", "theme"):
        if len({a[field] for a in assets}) != len(assets):
            errors.append(f"Duplicate {field}.")
    counts = dict(collections.Counter(a["family"] for a in assets))
    if counts != {f["id"]: f["planned_count"] for f in catalog["families"]}:
        errors.append("Family counts do not match the plan.")
    batched = [n for b in catalog["batches"] for n in b["asset_numbers"]]
    if sorted(batched) != list(range(1, 41)):
        errors.append("Batches must cover all concepts exactly once.")
    source_ids, paths = {s["id"] for s in catalog["sources"]}, []
    for a in assets:
        aid, types = a["id"], set(a["collection_types"])
        if not re.fullmatch(r"rw-\d{2}-[a-z0-9-]+", aid):
            errors.append(f"{aid}: invalid id.")
        if not types or not types <= SUBTYPES.keys():
            errors.append(f"{aid}: unknown group type.")
        allowed = set().union(*(SUBTYPES[t] for t in types & SUBTYPES.keys()))
        if not set(a["category_subtypes"]) <= allowed:
            errors.append(f"{aid}: subtype is outside the mapped product types.")
        if not set(a["source_ids"]) <= source_ids:
            errors.append(f"{aid}: unknown source.")
        if a["explicit_context"] and a["explicit_context"] not in CONTEXTS:
            errors.append(f"{aid}: unknown context.")
        if a["explicit_context"] and a["general_default"]:
            errors.append(f"{aid}: sensitive context cannot be a general default.")
        if a["explicit_context"] == "muslim" and "church" in types:
            errors.append(f"{aid}: Muslim imagery must not be mapped to Church.")
        if set(a["labels"]) != {"en", "rw", "fr"}:
            errors.append(f"{aid}: missing language draft.")
        for field in ("scene", "materials_and_details", "lighting_and_palette", "focal_subject"):
            if not a["prompt_spec"].get(field, "").strip():
                errors.append(f"{aid}: missing {field}.")
        for value in a["planned_files"].values():
            if not workspace_path(value).is_relative_to(ROOT / "assets/group_covers/rwanda"):
                errors.append(f"{aid}: output escapes the bank.")
            paths.append(value)
        if a["runtime_ready"]:
            errors.append(f"{aid}: this planning catalogue cannot certify runtime readiness.")
    if len(paths) != len(set(paths)):
        errors.append("Output paths must be unique.")
    if errors:
        raise ValueError("\n".join(errors))
    return {"valid": True, "concepts": len(assets), "families": counts,
            "source_pngs_saved": sum(workspace_path(a["planned_files"]["source"]).is_file() for a in assets),
            "runtime_ready": 0, "scope": "Planning preparation; not mobile acceptance"}


def prompt_for(catalog, asset):
    art, spec = catalog["art_direction"], asset["prompt_spec"]
    return "\n\n".join([
        "Use case: " + art["use_case"],
        "Asset type: One original photographic cover for a Collect contribution group. "
        + "Working concept: " + asset["labels"]["en"] + ".",
        "Scene and subjects: " + spec["scene"],
        "Materials and details: " + spec["materials_and_details"],
        "Lighting and palette: " + spec["lighting_and_palette"],
        "Primary focal subject: " + spec["focal_subject"] + ".",
        "Style: " + art["style"],
        "Composition and intended crops: " + art["composition"],
        "Text: None. Do not render any words, numbers or interface.",
        "Constraints: " + art["constraints"],
    ]) + "\n"


def tokens(value):
    text = unicodedata.normalize("NFKD", value.casefold())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return set(re.findall(r"[^\W_]+", text, flags=re.UNICODE))


def select_assets(catalog, *, group_type=None, subtype=None, family=None,
                  theme=None, query="", contexts=(), browse_all=False):
    """Planning implementation of deterministic local suggestion rules."""
    if group_type and group_type not in SUBTYPES:
        raise ValueError("Unknown group type.")
    if subtype and (not group_type or subtype not in SUBTYPES[group_type]):
        raise ValueError("Subtype must belong to the selected group type.")
    if family and family not in {f["id"] for f in catalog["families"]}:
        raise ValueError("Unknown image family.")
    themes = {a["theme"]: a for a in catalog["assets"]}
    if theme and theme not in themes:
        raise ValueError("Unknown image theme.")
    active = set(contexts)
    if not active <= CONTEXTS:
        raise ValueError("Unknown explicit context.")
    if group_type == "church":
        active.add("christian")
    if theme and themes[theme]["explicit_context"]:
        active.add(themes[theme]["explicit_context"])
    query_tokens, results = tokens(query), []
    for a in catalog["assets"]:
        if a["explicit_context"] and a["explicit_context"] not in active:
            continue
        if family and a["family"] != family:
            continue
        if theme and a["theme"] != theme:
            continue
        type_match = group_type in a["collection_types"]
        if group_type and not browse_all and not type_match:
            continue
        searchable = " ".join([*a["labels"].values(), *a["search_terms"], a["theme"].replace("_", " ")])
        if query_tokens and not query_tokens <= tokens(searchable):
            continue
        score = a["editorial_priority"] + 5 * len(query_tokens)
        score += 100 if theme == a["theme"] else 0
        score += 50 if type_match and not browse_all else 0
        score += 20 if subtype and subtype in a["category_subtypes"] else 0
        results.append({"asset": a, "score": score})
    return sorted(results, key=lambda r: (-r["score"], r["asset"]["id"]))


def write_prepared(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def export(catalog, output):
    validate(catalog)
    output = output.resolve()
    if not output.is_relative_to(ROOT / "docs/plans"):
        raise ValueError("Export destination must be inside this workspace's docs/plans.")
    jobs, fence = [], chr(96) * 3
    book = [
        "# Collect Rwanda — 40 standalone image-generation prompts", "",
        "Status: prompts prepared; generation, visual review and app integration remain separate work.",
        "Generated from assets/group_covers/rwanda/catalog.v1.json. Edit the catalogue, then re-export.", "",
        "Run one built-in image_gen call per job; never a 40-panel collage. No API key is needed.",
        "No real group data is an input. All English, Kinyarwanda and French labels remain drafts.", "",
        "| No. | Concept | Image family | Current group types | Batch |",
        "| --- | --- | --- | --- | --- |",
    ]
    for a in catalog["assets"]:
        book.append(f'| {a["number"]:02d} | {a["labels"]["en"]} | {a["family"]} | '
                    f'{", ".join(a["collection_types"])} | {a["generation_batch"]} |')
    for a in catalog["assets"]:
        prompt = prompt_for(catalog, a)
        write_prepared(output / "prompts" / (a["id"] + ".txt"), prompt)
        jobs.append({
            "asset_id": a["id"], "batch": a["generation_batch"],
            "tool": "image_gen.imagegen", "arguments": {"prompt": prompt},
            "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
            "save_source_after_generation": a["planned_files"]["source"],
            "note": "Only arguments is passed to imagegen. Save the returned output afterward; "
                    "the tool has no output-path argument. No reference images are needed.",
        })
        book.extend([
            "", f'## {a["number"]:02d}. {a["labels"]["en"]}', "",
            f'Asset ID: {a["id"]} · Batch {a["generation_batch"]}',
            f'English / Kinyarwanda / French label drafts: {" / ".join(a["labels"].values())}.',
            f'Image theme: {a["theme"]}. Explicit context: {a["explicit_context"] or "neutral"}.',
            f'Planned source: {a["planned_files"]["source"]}',
            f'Review: {a["review_note"]}',
            f'Context evidence: {", ".join(a["source_ids"]) or "Creative/product-use-case proposal"}. '
            + a["source_scope"], "", fence + "text", prompt.rstrip(), fence,
        ])
    write_prepared(output / "imagegen-jobs.jsonl",
                   "".join(json.dumps(j, ensure_ascii=False) + "\n" for j in jobs))
    write_prepared(output / "PROMPTBOOK.md", "\n".join(book) + "\n")
    with (output / "asset-index.csv").open("w", newline="", encoding="utf-8-sig") as handle:
        writer = csv.writer(handle)
        writer.writerow(["number", "asset_id", "family", "theme", "label_en", "label_rw_draft",
                         "label_fr_draft", "collection_types", "context", "search_terms", "batch",
                         "source_path", "cover_path", "thumbnail_path", "status"])
        for a in catalog["assets"]:
            writer.writerow([a["number"], a["id"], a["family"], a["theme"],
                             a["labels"]["en"], a["labels"]["rw"], a["labels"]["fr"],
                             "|".join(a["collection_types"]), a["explicit_context"] or "",
                             "|".join(a["search_terms"]), a["generation_batch"],
                             a["planned_files"]["source"], a["planned_files"]["cover"],
                             a["planned_files"]["thumbnail"], a["status"]])
    notes = ["# Context sources and limits", "",
             "Checked 6 September 2026. Sources inform context; their photos are not copied. "
             "Every scene is fictional. The selection is editorial, not a national prevalence survey."]
    for s in catalog["sources"]:
        notes.extend(["", f'## {s["id"]} — {s["publisher"]}', "",
                      f'[{s["title"]}]({s["url"]})', "", f'Access: {s["access"]}', "",
                      s["supports"], "", f'Limits: {s["limits"]}'])
    write_prepared(output / "SOURCE-REVIEW.md", "\n".join(notes) + "\n")
    return {"prompt_files": len(jobs), "jobs": len(jobs), "output": str(output),
            "images_generated_by_this_command": 0}


def save_source(catalog, asset_id, source_path):
    a = next((a for a in catalog["assets"] if a["id"] == asset_id), None)
    if a is None:
        raise ValueError("Unknown asset id.")
    data = source_path.read_bytes()
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("Expected the original PNG; do not rename another format to PNG.")
    width, height = struct.unpack(">II", data[16:24])
    if min(width, height) < 1024:
        raise ValueError("Master needs a minimum 1024-pixel short edge; regenerate.")
    destination = workspace_path(a["planned_files"]["source"])
    receipt_path = workspace_path(a["planned_files"]["production_record"])
    if destination.exists() or receipt_path.exists():
        raise ValueError("Output already exists; plan a new version. Nothing was overwritten.")
    digest = hashlib.sha256(data).hexdigest()
    receipt = {
        "asset_id": asset_id, "status": "generated_unreviewed",
        "source": a["planned_files"]["source"], "source_sha256": digest,
        "source_dimensions": {"width": width, "height": height}, "source_format": "png",
        "prompt_sha256": hashlib.sha256(prompt_for(catalog, a).encode()).hexdigest(),
        "imported_at_utc": datetime.now(timezone.utc).isoformat(),
        "generator": "Operator-provided output intended from built-in image_gen; verify provenance",
        "operation": "Byte-for-byte copy; no pixel edits", "reviews": a["reviews"],
        "runtime_ready": False, "derivatives": [],
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("xb") as handle:
        handle.write(data)
    with receipt_path.open("x", encoding="utf-8") as handle:
        json.dump(receipt, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    return {"saved": str(destination), "sha256": digest, "width": width,
            "height": height, "status": "generated_unreviewed"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate")
    exp = commands.add_parser("export")
    exp.add_argument("--out", type=Path, default=OUTPUT)
    sug = commands.add_parser("suggest", help="Preview planned metadata filters, not runtime images")
    sug.add_argument("--type", choices=sorted(SUBTYPES), dest="group_type")
    sug.add_argument("--subtype")
    sug.add_argument("--family")
    sug.add_argument("--theme")
    sug.add_argument("--query", default="")
    sug.add_argument("--context", action="append", default=[], choices=sorted(CONTEXTS))
    sug.add_argument("--all", action="store_true", dest="browse_all",
                     help="Browse all group types; explicit-context rules still apply")
    sug.add_argument("--limit", type=int, default=40)
    save = commands.add_parser("save-source")
    save.add_argument("asset_id")
    save.add_argument("source_path", type=Path)
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    check = validate(catalog)
    if args.command == "validate":
        result = check
    elif args.command == "export":
        result = export(catalog, args.out)
    elif args.command == "save-source":
        result = save_source(catalog, args.asset_id, args.source_path)
    else:
        if not 1 <= args.limit <= 40:
            raise ValueError("Limit must be between 1 and 40.")
        rows = select_assets(catalog, group_type=args.group_type, subtype=args.subtype,
                             family=args.family, theme=args.theme, query=args.query,
                             contexts=args.context, browse_all=args.browse_all)
        result = {"scope": "Planning metadata preview; no runtime images are available",
                  "total_matches": len(rows), "matches": [
                      {"id": r["asset"]["id"], "label": r["asset"]["labels"]["en"],
                       "theme": r["asset"]["theme"], "score": r["score"]}
                      for r in rows[:args.limit]]}
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError) as error:
        print(f"Asset bank preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
