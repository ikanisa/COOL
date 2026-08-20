#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
OUT_DIR="${PUBLIC_WEBSITE_QA_OUT:-output/public_website_route_rendered_qa}"
PORT="$(ruby -rsocket -e 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close')"
SERVER_LOG="$OUT_DIR/server.log"

NODE_BIN="${PUBLIC_WEBSITE_NODE_BIN:-}"
if [[ -z "$NODE_BIN" ]]; then
  if command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
  elif [[ -x "/Applications/Codex.app/Contents/Resources/cua_node/bin/node" ]]; then
    NODE_BIN="/Applications/Codex.app/Contents/Resources/cua_node/bin/node"
  else
    printf '[public-website-rendered-qa][FAIL] A Node.js executable is required. Set PUBLIC_WEBSITE_NODE_BIN.\n' >&2
    exit 1
  fi
fi
if [[ ! -x "$NODE_BIN" ]]; then
  printf '[public-website-rendered-qa][FAIL] Node.js executable is not runnable: %s\n' "$NODE_BIN" >&2
  exit 1
fi

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
"$NODE_BIN" scripts/public_website_route_rendered_qa.js
