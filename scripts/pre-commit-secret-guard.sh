#!/usr/bin/env bash
# Pre-commit hook: prevents committing secrets, credentials, or blocked files.
#
# Install:
#   cp scripts/pre-commit-secret-guard.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit

set -euo pipefail

RED='\033[0;31m'
NC='\033[0m'

BLOCKED_PATTERNS='\.jks$|\.keystore$|\.bak$|\.old$|\.orig$|sa-key.*\.json$|\.env$|\.env\.json$|key\.properties$'
ALLOW_LIST='\.gitignore$|\.env\.example$|supabase/functions/\.env\.example$'

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACM)

if [ -z "$STAGED_FILES" ]; then
  exit 0
fi

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

echo "✅ Pre-commit secret guard: no blocked files detected."
