#!/usr/bin/env bash
# ── clean_local.sh ─────────────────────────────────────────────
# Removes local logs, temp output, design exports, and build
# artifacts from the working tree. Safe to run at any time.
# Does NOT touch version-controlled files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "🧹 Cleaning local artifacts from $ROOT_DIR"

# ── Logs ──────────────────────────────────────────────────────
rm -f firebase-debug.log
rm -f flutter_*.log
echo "  ✓ Removed log files"

# ── Kotlin build error logs ───────────────────────────────────
rm -rf android/.kotlin/errors/
echo "  ✓ Removed Kotlin error logs"

# ── Design tool exports ──────────────────────────────────────
rm -rf stitch_exports/
rm -f stitch.json
echo "  ✓ Removed design tool exports"

# ── Local release output ─────────────────────────────────────
# Keep the directory structure but remove generated content
rm -f output/play_store/play-store-sa-key.json 2>/dev/null || true
echo "  ✓ Cleaned local release output"

# ── Flutter build caches ─────────────────────────────────────
rm -rf .dart_tool/
rm -rf build/
echo "  ✓ Removed Flutter build caches"

# ── Scratch / analysis output ────────────────────────────────
rm -f analysis_output*.txt
echo "  ✓ Removed scratch/analysis output"

echo ""
echo "✅ Local cleanup complete. Run 'flutter pub get' to restore dependencies."
