#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PUBLIC_BUILD_DIR="${PUBLIC_BUILD_DIR:-build/public_web}"
PUBLIC_BUILD_DIR="$PUBLIC_BUILD_DIR" ruby scripts/public_static_site_build.rb
