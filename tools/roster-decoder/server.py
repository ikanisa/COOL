"""Authenticated HTTP supervisor. Child decoders never have network access."""
from __future__ import annotations
import hashlib
import ctypes
import hmac
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

POLICY = "collect-roster-decoder-v1"
BUILD_HASH = hashlib.sha256(json.dumps({name:hashlib.sha256(Path(__file__).with_name(path).read_bytes()).hexdigest()
    for name,path in {"decoder.py":"decoder.py","server.py":"server.py","requirements.lock":"requirements.lock","Dockerfile":"build.Dockerfile"}.items()},
    sort_keys=True,separators=(",",":")).encode()).hexdigest()
LIMIT = 8 * 1024 * 1024
SECRET = os.environ.get("ROSTER_DECODER_SECRET", "")
if len(SECRET.encode()) < 32:
    raise SystemExit("ROSTER_DECODER_SECRET must contain at least 32 bytes")
if sys.platform != "linux" or ctypes.CDLL(None).prctl(4, 0, 0, 0, 0) != 0:
    raise SystemExit("Linux proc credential isolation is required")
DB = os.environ.get("ROSTER_DECODER_NONCE_DB", "/state/nonces.sqlite3")
UUID = re.compile(r"^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$")
SHA = re.compile(r"^[a-f0-9]{64}$")
NONCE_LOCK = threading.Lock()
with sqlite3.connect(DB) as db:
    db.execute("create table if not exists nonces (nonce text primary key, issued_at integer not null)")


def signature(value):
    return hmac.new(SECRET.encode(), value, hashlib.sha256).hexdigest()


class BoundedServer(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 4
    # Bound connection threads BEFORE reading any untrusted body. Two active
    # decoders fit the container's 896MiB memory cap (384MiB each plus parent).
    connections = threading.BoundedSemaphore(2)
    def process_request(self, request, address):
        if not self.connections.acquire(blocking=False):
            try:
                request.sendall(b"HTTP/1.1 429 Too Many Requests\r\nConnection: close\r\nContent-Length: 0\r\n\r\n")
            finally:
                self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except BaseException:
            self.connections.release()
            raise
    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.connections.release()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *_):
        pass  # No authorization, body, client source, filename or parser text.
    def reply(self, value, status=200):
        data = json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        self.close_connection = True
    def do_POST(self):
        try:
            self.connection.settimeout(5)
            length = self.headers.get("Content-Length", "")
            if self.path != "/decode" or self.headers.get("Transfer-Encoding") or not length.isdigit() or not 1 <= int(length) <= LIMIT:
                return self.reply({"error": "roster_decoder_request_invalid"}, 400)
            body = self.rfile.read(int(length))
            supplied = self.headers.get("Authorization", "")
            if len(body) != int(length) or not hmac.compare_digest(supplied, "Roster-HMAC " + signature(body)):
                return self.reply({"error": "roster_decoder_authentication_required"}, 401)
            request = json.loads(body)
            fields = {"request_id", "reservation_id", "source_sha256", "mime", "kind", "content_base64", "policy_version", "nonce", "issued_at"}
            if not isinstance(request, dict) or set(request) != fields or request["policy_version"] != POLICY or not all(isinstance(request[k], str) for k in fields - {"issued_at"}) or not all(UUID.fullmatch(request[k]) for k in ("request_id", "reservation_id", "nonce")) or not SHA.fullmatch(request["source_sha256"]) or type(request["issued_at"]) is not int or abs(int(time.time()) - request["issued_at"]) > 30 or request["kind"] not in ("image", "pdf", "xlsx"):
                return self.reply({"error": "roster_decoder_request_invalid"}, 400)
            with NONCE_LOCK, sqlite3.connect(DB) as db:
                db.execute("delete from nonces where issued_at < ?", (int(time.time()) - 60,))
                if db.execute("select count(*) from nonces").fetchone()[0] >= 5000:
                    return self.reply({"error": "roster_decoder_limit"}, 429)
                try:
                    db.execute("insert into nonces values (?,?)", (request["nonce"], request["issued_at"]))
                except sqlite3.IntegrityError:
                    return self.reply({"error": "roster_decoder_replay"}, 409)
            # Content enters a clean child via stdin. stderr goes nowhere and
            # environment contains no signing/provider/database credentials.
            command = [sys.executable, "-I", str(Path(__file__).with_name("decoder.py"))]
            process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, env={"PATH": "/usr/local/bin:/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"}, cwd="/tmp")
            try:
                output, _ = process.communicate(body, timeout=8)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                return self.reply({"error": "roster_decoder_resource_limit"}, 422)
            if process.returncode or len(output) > 550_000:
                return self.reply({"error": "roster_decoder_resource_limit"}, 422)
            decoded = json.loads(output)
            if decoded.get("ok") is not True:
                code = decoded.get("error")
                if not isinstance(code, str) or not re.fullmatch(r"roster_[a-z_]{1,60}", code):
                    code = "roster_invalid_file"
                return self.reply({"error": code}, 422)
            payload = json.dumps({"contract_version": 1, "request_id": request["request_id"],
                                  "reservation_id": request["reservation_id"], "nonce": request["nonce"],
                                  "issued_at": int(time.time()), "kind": request["kind"], "mime": request["mime"],
                                  "decoder_build_sha256": BUILD_HASH,
                                  **decoded}, separators=(",", ":"), ensure_ascii=False)
            return self.reply({"payload": payload, "signature": signature(payload.encode())})
        except BaseException:
            return self.reply({"error": "roster_decoder_unavailable"}, 503)


if __name__ == "__main__":
    BoundedServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
