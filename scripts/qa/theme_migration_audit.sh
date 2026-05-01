#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-lib}"
FAIL_ON_MATCHES="${FAIL_ON_MATCHES:-0}"

if ! command -v rg >/dev/null 2>&1; then
  echo "ripgrep (rg) is required for theme_migration_audit.sh" >&2
  exit 2
fi

declare -a RG_EXCLUDES=(
  "--glob=!lib/core/theme/app_colors.dart"
  "--glob=!lib/core/theme/cool_palette.dart"
  "--glob=!lib/core/theme/cool_foundations.dart"
  "--glob=!lib/core/theme/app_theme_text.dart"
  "--glob=!lib/core/theme/rs_colors.dart"
  "--glob=!lib/core/theme/rs_text_styles.dart"
)

declare -a CHECKS=(
  "legacy_app_colors|AppColors\\."
  "legacy_palette|CoolPalette"
  "raw_color_literals|Color\\(0x"
  "hardcoded_font_size|fontSize:"
  "hardcoded_radius|BorderRadius\\.circular"
  "hardcoded_edge_insets|EdgeInsets\\."
  "hardcoded_box_shadow|BoxShadow\\("
)

printf 'Theme migration audit for %s\n\n' "$ROOT"
printf 'Excluding token/theme definition files under lib/core/theme.\n\n'
printf '%-24s %8s\n' 'Check' 'Matches'
printf '%-24s %8s\n' '------------------------' '--------'

total=0
for check in "${CHECKS[@]}"; do
  name="${check%%|*}"
  pattern="${check#*|}"
  count="$(
    {
      rg -n --glob '*.dart' "${RG_EXCLUDES[@]}" "$pattern" "$ROOT" 2>/dev/null || true
    } \
      | wc -l \
      | tr -d ' '
  )"
  total=$((total + count))
  printf '%-24s %8s\n' "$name" "$count"
done

printf '\nTop offenders\n'
printf '%-8s %s\n' 'Matches' 'File'
printf '%-8s %s\n' '-------' '----'
{
  rg -n \
    --glob '*.dart' \
    "${RG_EXCLUDES[@]}" \
    -e 'AppColors\.' \
    -e 'CoolPalette' \
    -e 'Color\(0x' \
    -e 'fontSize:' \
    -e 'BorderRadius\.circular' \
    -e 'EdgeInsets\.' \
    -e 'BoxShadow\(' \
    "$ROOT" || true
} \
  | cut -d: -f1 \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -20 \
  | while read -r matches file; do
      printf '%-8s %s\n' "$matches" "$file"
    done

printf '\nTotal matches: %s\n' "$total"

if [[ "$FAIL_ON_MATCHES" == "1" && "$total" -gt 0 ]]; then
  exit 1
fi
