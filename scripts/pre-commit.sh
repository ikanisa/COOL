#!/usr/bin/env bash
# Pre-commit hook: prevents committing secrets and enforces static analysis.
#
# Install:
#   cp scripts/pre-commit.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# This hook runs TWO gates before every commit:
# 1. Secret/credential file guard (fast, always runs)
# 2. flutter analyze --fatal-infos (ensures zero analysis issues)
#
# To bypass in emergencies (NOT recommended):
#   git commit --no-verify

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ── Resolve project root ─────────────────────────────────────────────
ROOT_DIR="$(git rev-parse --show-toplevel)"

# ── Gate 1: Secret / credential file guard ────────────────────────────
echo -e "${YELLOW}🔒 Pre-commit gate 1/2: Secret file guard${NC}"

BLOCKED_PATTERNS='\.jks$|\.keystore$|\.bak$|\.old$|\.orig$|sa-key.*\.json$|\.env$|\.env\.json$|key\.properties$'
ALLOW_LIST='\.gitignore$|\.env\.example$|supabase/functions/\.env\.example$'

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -n "$STAGED_FILES" ]; then
  BLOCKED=""
  while IFS= read -r file; do
    if echo "$file" | grep -qE "$BLOCKED_PATTERNS" && ! echo "$file" | grep -qE "$ALLOW_LIST"; then
      BLOCKED="$BLOCKED\n  $file"
    fi
  done <<< "$STAGED_FILES"

  if [ -n "$BLOCKED" ]; then
    echo -e "${RED}🚨 Blocked files detected in staging area:${NC}"
    echo -e "$BLOCKED"
    echo ""
    echo "These files match blocked patterns (secrets, credentials, backups)."
    echo "Remove them from staging with:  git reset HEAD <file>"
    echo ""
    echo "To bypass (NOT recommended):  git commit --no-verify"
    exit 1
  fi
  echo -e "${GREEN}✅ No blocked secret/credential files detected.${NC}"
else
  echo -e "${GREEN}✅ No staged files to check.${NC}"
fi

# ── Gate 2: Flutter static analysis ───────────────────────────────────
echo -e "${YELLOW}🔍 Pre-commit gate 2/2: flutter analyze --fatal-infos${NC}"

# Only run if Dart/Flutter files were changed (skip for docs-only commits).
DART_FILES_CHANGED=$(echo "$STAGED_FILES" | grep -E '\.(dart)$' || true)

if [ -n "$DART_FILES_CHANGED" ]; then
  cd "$ROOT_DIR"

  # Use the project's flutter wrapper if available, otherwise system flutter.
  FLUTTER_BIN="${FLUTTER_BIN:-}"
  if [ -z "$FLUTTER_BIN" ]; then
    if [ -x "$ROOT_DIR/scripts/flutterw" ]; then
      FLUTTER_BIN="$ROOT_DIR/scripts/flutterw"
    else
      FLUTTER_BIN="flutter"
    fi
  fi

  # Hooks export repository-local Git variables. Flutter queries its own SDK
  # repository; inherited GIT_DIR can turn its version into 0.0.0-unknown.
  # Clear them only for Flutter, keeping the staged-file guard in this repo.
  if ! (
    while IFS= read -r git_variable; do
      unset "$git_variable"
    done < <(git rev-parse --local-env-vars)
    "$FLUTTER_BIN" analyze --fatal-infos
  ); then
    echo ""
    echo -e "${RED}❌ Static analysis failed. Fix the issues above before committing.${NC}"
    echo ""
    echo "Quick fix:  flutter analyze --fatal-infos"
    echo "Auto-fix:   dart fix --apply"
    echo ""
    echo "To bypass (NOT recommended):  git commit --no-verify"
    exit 1
  fi
  echo -e "${GREEN}✅ Static analysis passed (0 issues).${NC}"
else
  echo -e "${GREEN}✅ No Dart files changed — skipping analysis.${NC}"
fi

echo ""
echo -e "${GREEN}✅ All pre-commit gates passed.${NC}"
