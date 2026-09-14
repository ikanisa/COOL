#!/usr/bin/env python3
"""Export route/entrypoint discovery; this is not an acceptance case inventory."""

import csv
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "docs/plans/fullstack-qa-2026-09-14"
MOBILE_CASES = "docs/release/mobile-design/mobile-parity-contract.json"
rows = []


def append(surface, entry, source, line, case_source="", applicability="declared"):
    path = ROOT / source
    identity = f"{surface}:{entry}"
    rows.append(
        {
            "scope_id": hashlib.sha256(identity.encode()).hexdigest()[:12],
            "surface": surface,
            "route_or_entrypoint": entry,
            "source_path": source,
            "source_line": line,
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "applicability": applicability,
            "review_status": "unverified",
            "case_inventory_source": case_source,
        }
    )


def catalog(source, name):
    text = (ROOT / source).read_text()
    match = re.search(rf"\b{name}\s*=\s*<String>[\[{{](.*?)[\]}}];", text, re.S)
    if match is None:
        raise ValueError(f"Missing catalog {name} in {source}")
    for item in re.finditer(r"'([^']+)'", match.group(1)):
        yield item.group(1), text[: match.start(1) + item.start()].count("\n") + 1


for surface in ["android_member", "ios_member", "member_browser"]:
    for route, line in catalog("lib/app/router.dart", "collectRoutePaths"):
        append(
            surface, route, "lib/app/router.dart", line, MOBILE_CASES,
            "runtime_availability_unverified" if surface == "member_browser" else "declared",
        )

for surface in ["admin_browser", "admin_installed_pwa"]:
    for route, line in catalog("lib/admin/admin_router.dart", "adminRoutePaths"):
        append(surface, route, "lib/admin/admin_router.dart", line)

for surface in ["public_flutter", "public_static"]:
    for route, line in catalog("lib/features/landing/public_page_content.dart", "publicWebsitePaths"):
        append(surface, route, "lib/features/landing/public_page_content.dart", line)

for path in sorted((ROOT / "supabase/functions").glob("*/index.ts")):
    append("edge_function", path.parent.name, str(path.relative_to(ROOT)), 1)

for path in sorted((ROOT / "supabase/migrations").glob("*.sql")):
    append("database_migration", path.stem, str(path.relative_to(ROOT)), 1)

server_path = "tools/collect-notification-mcp/src/server.ts"
server = (ROOT / server_path).read_text()
for match in re.finditer(r'server\.registerTool\(\s*"([^"]+)"', server):
    append("notification_operator_tool", match.group(1), server_path, server[:match.start()].count("\n") + 1)

if not rows or len({row["scope_id"] for row in rows}) != len(rows):
    raise ValueError("Empty or duplicate scope inventory")
OUTPUT.mkdir(parents=True, exist_ok=True)
with (OUTPUT / "scope.csv").open("w", newline="") as output:
    writer = csv.DictWriter(output, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
summary = {
    "status": "route_and_entrypoint_discovery_only",
    "product_acceptance": "unverified",
    "rows": len(rows),
    "by_surface": {surface: sum(row["surface"] == surface for row in rows) for surface in sorted({row["surface"] for row in rows})},
    "remaining_inventory": [
        "Overlays and component states", "Roles, membership and geographic cases",
        "Platform and installed runtime availability", "API/RPC/table/storage dependencies",
        "Source comparators and independent acceptance evidence",
    ],
    "mobile_case_authority": MOBILE_CASES,
    "scope_sha256": hashlib.sha256((OUTPUT / "scope.csv").read_bytes()).hexdigest(),
}
(OUTPUT / "scope-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps(summary, indent=2))
