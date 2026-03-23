#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"

if [[ ! -d "$MIGRATIONS_DIR" ]]; then
  echo "Missing migrations directory: $MIGRATIONS_DIR" >&2
  exit 1
fi

echo "==> validating Supabase migrations"

migration_files=()
while IFS= read -r file; do
  migration_files+=("$file")
done < <(find "$MIGRATIONS_DIR" -maxdepth 1 -type f -name '*.sql' | sort)

if [[ ${#migration_files[@]} -eq 0 ]]; then
  echo "No SQL migrations found under $MIGRATIONS_DIR" >&2
  exit 1
fi

declare -a versions=()
declare -a errors=()

for file in "${migration_files[@]}"; do
  base_name="$(basename "$file")"
  versions+=("${base_name%%_*}")

  if [[ ! "$base_name" =~ ^[0-9]{14}_[a-z0-9_]+\.sql$ ]]; then
    errors+=("Invalid migration filename format: $base_name")
  fi

  if [[ ! -s "$file" ]]; then
    errors+=("Migration is empty: $base_name")
    continue
  fi

  if grep -n -E '^\*\*\* (Begin Patch|Add File:|Update File:|Delete File:|Move to:|End Patch)$' "$file" >/dev/null; then
    errors+=("Migration contains raw patch markers: $base_name")
  fi

  if grep -n -E '/Volumes/|file:///|[A-Za-z]:\\\\' "$file" >/dev/null; then
    errors+=("Migration contains machine-local absolute paths: $base_name")
  fi

  last_sql_line="$(
    awk '
      NF == 0 { next }
      /^[[:space:]]*--/ { next }
      { line = $0 }
      END { print line }
    ' "$file"
  )"
  if [[ -z "$last_sql_line" ]]; then
    errors+=("Migration has no non-empty SQL content: $base_name")
  elif [[ ! "$last_sql_line" =~ \;[[:space:]]*$ ]]; then
    errors+=("Migration does not end with a semicolon: $base_name")
  fi
done

duplicate_versions="$(printf '%s\n' "${versions[@]}" | sort | uniq -d || true)"
if [[ -n "$duplicate_versions" ]]; then
  while IFS= read -r version; do
    [[ -z "$version" ]] && continue
    errors+=("Duplicate migration version prefix: $version")
  done <<< "$duplicate_versions"
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  printf 'Supabase migration validation failed:\n' >&2
  for error in "${errors[@]}"; do
    printf '  - %s\n' "$error" >&2
  done
  exit 1
fi

printf 'Validated %s migration files.\n' "${#migration_files[@]}"
