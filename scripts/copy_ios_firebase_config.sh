#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec sh "$ROOT_DIR/scripts/dev/copy_ios_firebase_config.sh" "$@"
