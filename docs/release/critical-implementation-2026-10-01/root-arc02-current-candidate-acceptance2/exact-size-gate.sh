WARN=500
FAIL=1200
EXIT_CODE=0

while IFS= read -r file; do
  lines=$(wc -l < "$file" | tr -d ' ')
  case "$file" in
    lib/l10n/app_localizations.dart|lib/l10n/app_localizations_*.dart|*.g.dart)
      continue
      ;;
  esac
  if [ "$lines" -gt "$FAIL" ]; then
    echo "::error::$file ($lines lines) exceeds hard limit ($FAIL)"
    EXIT_CODE=1
  elif [ "$lines" -gt "$WARN" ]; then
    echo "::warning::$file ($lines lines) exceeds soft limit ($WARN)"
  fi
done < <(find lib/ -name '*.dart' -type f 2>/dev/null)

while IFS= read -r file; do
  lines=$(wc -l < "$file" | tr -d ' ')
  if [ "$lines" -gt "$FAIL" ]; then
    echo "::error::$file ($lines lines) exceeds hard limit ($FAIL)"
    EXIT_CODE=1
  elif [ "$lines" -gt "$WARN" ]; then
    echo "::warning::$file ($lines lines) exceeds soft limit ($WARN)"
  fi
done < <(find supabase/functions -name '*.ts' -type f 2>/dev/null)

exit $EXIT_CODE
