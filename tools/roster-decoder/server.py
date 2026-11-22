"""Authenticated HTTP supervisor. Child decoders never have network access."""
from __future__ import annotations
import hashlib
import ctypes
import hmac
import json
import os
from pathlib import Path
import re
import signal
import socket
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
INPUT_TIMEOUT = 5
DECODE_TIMEOUT = 8
IO_TIMEOUT = INPUT_TIMEOUT + DECODE_TIMEOUT
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
    # Join active handlers; each handler reaps its decoder before returning.
    daemon_threads = False
    block_on_close = True
    stopping = False
    request_queue_size = 4
    # Bound connection threads BEFORE reading any untrusted body. Two active
    # decoders fit the container's 896MiB memory cap (384MiB each plus parent).
    connections = threading.BoundedSemaphore(2)
    def get_request(self):
        request, address = super().get_request()
        # Also bound overload replies and request-line/header reads.
        request.settimeout(INPUT_TIMEOUT)
        return request, address
    def verify_request(self, request, address):
        return not self.stopping and super().verify_request(request, address)
    def process_request(self, request, address):
        if self.stopping:
            self.shutdown_request(request)
            return
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
    def setup(self):
        super().setup()
        self.connection.settimeout(INPUT_TIMEOUT)
        self._input_lock = threading.Lock()
        self._input_finished = False
        self._input_expired = False
        self._input_deadline = time.monotonic() + INPUT_TIMEOUT
        # A socket timeout alone resets on progress. Absolute deadlines prevent
        # slow headers/body or a non-reading peer from holding worker joins.
        self._input_timer = threading.Timer(INPUT_TIMEOUT, self._expire_input)
        self._io_timer = threading.Timer(IO_TIMEOUT, self._expire_connection)
        self._input_timer.daemon = self._io_timer.daemon = True
        self._input_timer.start()
        self._io_timer.start()
    def _expire_connection(self):
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
    def _expire_input(self):
        with self._input_lock:
            if self._input_finished:
                return
            self._input_expired = True
        self._expire_connection()
    def _finish_input(self):
        with self._input_lock:
            if self._input_expired or time.monotonic() >= self._input_deadline:
                raise TimeoutError("request input deadline exceeded")
            self._input_finished = True
        self._input_timer.cancel()
    def finish(self):
        try:
            super().finish()
        finally:
            for timer in (self._input_timer, self._io_timer):
                timer.cancel()
            for timer in (self._input_timer, self._io_timer):
                timer.join()
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
            length = self.headers.get("Content-Length", "")
            if self.path != "/decode" or self.headers.get("Transfer-Encoding") or not length.isdigit() or not 1 <= int(length) <= LIMIT:
                return self.reply({"error": "roster_decoder_request_invalid"}, 400)
            body = self.rfile.read(int(length))
            self._finish_input()
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
                output, _ = process.communicate(body, timeout=DECODE_TIMEOUT)
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


def serve_until_signalled(server):
    # Python runs signal handlers on the main (serving) thread. Only set a flag
    # there: shutdown() must wait on serve_forever() from a different thread.
    finished = False
    def request_stop(_signum, _frame):
        server.stopping = True
    def stop_serving():
        while not finished:
            if server.stopping:
                server.shutdown()
                return
            time.sleep(0.05)
    previous = {sig: signal.signal(sig, request_stop)
                for sig in (signal.SIGTERM, signal.SIGINT)}
    controller = threading.Thread(target=stop_serving, name="decoder-shutdown")
    controller.start()
    try:
        server.serve_forever(poll_interval=0.1)
    finally:
        finished = True
        try:
            # ThreadingMixIn closes the listener before joining non-daemon
            # handlers, which in turn wait for their bounded decoder children.
            server.server_close()
        finally:
            controller.join()
            for sig, handler in previous.items():
                signal.signal(sig, handler)


if __name__ == "__main__":
    serve_until_signalled(BoundedServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler))
