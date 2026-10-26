#!/usr/bin/env python3
"""Serve one frozen fixture build on loopback; never proxies external resources."""
import argparse
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
CSP = "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data:; font-src 'self'; connect-src 'self'; worker-src 'self' blob:; base-uri 'self'; form-action 'none'; frame-ancestors 'none'"
class LocalHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Content-Security-Policy', CSP)
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()
    def log_message(self, fmt, *args):
        pass
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--port', type=int, required=True)
    args = parser.parse_args()
    root = args.directory.resolve(strict=True)
    if not root.is_dir() or not 1024 <= args.port <= 65535:
        raise ValueError('A bounded loopback build directory and port are required')
    for path in root.rglob('*'):
        if path.is_symlink():
            raise ValueError('The fixture build cannot contain aliases')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), lambda *a, **k: LocalHandler(*a, directory=str(root), **k))
    print(f'Local fixture: http://127.0.0.1:{args.port}', flush=True)
    server.serve_forever()
