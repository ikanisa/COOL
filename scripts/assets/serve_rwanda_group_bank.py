#!/usr/bin/env python3
"""Read-only loopback preview of the generated Collect image bank.

Only the review page, a reduced catalogue and explicitly catalogued source
images are served. This is not the member app and exposes no group records.
"""
import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]
BANK = ROOT / "assets/group_covers/rwanda"
PAGE = ROOT / "docs/plans/rwanda-group-asset-bank-2026-09-06/production/review.html"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        route = unquote(urlsplit(self.path).path)
        if route in ("/", "/review.html"):
            return self.send_file(PAGE, "text/html; charset=utf-8")
        catalog = json.loads((BANK / "catalog.v1.json").read_text())
        if route == "/catalog.json":
            assets = []
            for a in catalog["assets"]:
                path = (ROOT / a["planned_files"]["source"]).resolve()
                present = path.is_file() and path.is_relative_to(BANK / "source")
                assets.append({
                    "id": a["id"], "number": a["number"], "labels": a["labels"],
                    "family": a["family"], "theme": a["theme"],
                    "types": a["collection_types"], "terms": a["search_terms"],
                    "context": a["explicit_context"], "focal": a["focal_point"],
                    "saved": present, "image": "/images/" + path.name if present else None,
                    "source_path": a["planned_files"]["source"],
                    "named_group": a.get("named_group"),
                    "card_eyebrow": a.get("card_eyebrow"),
                    "version": a["version"],
                })
            payload = {"scope": "Local asset review; not the live group-creation UI",
                       "planned": catalog["planned_asset_count"], "saved": sum(a["saved"] for a in assets),
                       "families": catalog["families"], "assets": assets}
            return self.send_bytes(json.dumps(payload, ensure_ascii=False).encode(), "application/json")
        images = {"/images/" + Path(a["planned_files"]["source"]).name:
                  (ROOT / a["planned_files"]["source"]).resolve() for a in catalog["assets"]}
        if route in images and images[route].is_relative_to(BANK / "source"):
            return self.send_file(images[route], "image/png")
        self.send_error(404)

    def send_file(self, path, kind):
        if not path.is_file():
            return self.send_error(404)
        self.send_bytes(path.read_bytes(), kind)

    def send_bytes(self, body, kind):
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; script-src 'self' 'unsafe-inline'; "
                         "style-src 'self' 'unsafe-inline'; img-src 'self'; "
                         "connect-src 'self'; frame-ancestors 'self'; base-uri 'none'")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4194)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Collect image review at http://collect.localhost:{args.port}/", flush=True)
    server.serve_forever()
