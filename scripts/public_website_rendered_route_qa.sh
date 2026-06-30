#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
OUT_DIR="${PUBLIC_WEBSITE_QA_OUT:-output/public_website_route_rendered_qa}"
PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
SERVER_LOG="$OUT_DIR/server.log"

ruby scripts/public_static_site_build.rb >/dev/null
mkdir -p "$OUT_DIR"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$BUILD_DIR" >"$SERVER_LOG" 2>&1 &
SERVER_PID="$!"
trap 'kill "$SERVER_PID" >/dev/null 2>&1 || true' EXIT

for _ in $(seq 1 80); do
  if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

PUBLIC_WEBSITE_QA_URL="http://127.0.0.1:$PORT/" \
PUBLIC_WEBSITE_QA_OUT="$OUT_DIR" \
PUBLIC_BUILD_DIR="$BUILD_DIR" \
node scripts/public_website_route_rendered_qa.js
