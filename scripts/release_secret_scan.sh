#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf '[secret-scan] %s\n' "$*"
}

# The reviewed upstream example contains Supabase's published dummy JWTs.
# Permit only its exact admitted bytes/provenance, never an edited secret file.
# Keep the original vendor bytes; the release generator creates fresh keys.
if [[ -e deploy/self-hosted/upstream/.env.example ]]; then
  python3 - <<'PY_PUBLIC_FIXTURE'
import hashlib, json
from pathlib import Path
path=Path('deploy/self-hosted/upstream/.env.example')
lock_path=Path('deploy/self-hosted/upstream.lock.json')
reviewed='d27fb4516702358ac5965fb06d207736abeb3c26c7d949f19b90e88b25e694ef'
try:
    lock=json.loads(lock_path.read_text())
    entries=[entry for entry in lock['files'] if entry['path']=='.env.example']
    valid=(not path.is_symlink() and not lock_path.is_symlink()
        and lock['format']=='collect.selfhost.upstream.v1'
        and lock['repository']=='https://github.com/supabase/supabase'
        and lock['tag']=='self-hosted/v0.8.3'
        and lock['commit']=='bc27d2661edd09a5d0b8d76ce33da6d4071a756e'
        and len(entries)==1 and entries[0]['sha256']==reviewed
        and hashlib.sha256(path.read_bytes()).hexdigest()==reviewed)
except (OSError,KeyError,TypeError,ValueError):
    valid=False
if not valid:
    raise SystemExit('[secret-scan][FAIL] Upstream public example changed; no placeholder exemption applies.')
PY_PUBLIC_FIXTURE
fi

if command -v gitleaks >/dev/null 2>&1; then
  log "running gitleaks detect with redacted output"
  args=(detect --source "$ROOT_DIR" --redact --no-banner)
  if [[ -f "$ROOT_DIR/.gitleaks.toml" ]]; then
    args+=(--config "$ROOT_DIR/.gitleaks.toml")
  fi
  gitleaks "${args[@]}"
  log "gitleaks detect passed"
  exit 0
fi

log "gitleaks not installed; running tracked-file fallback secret scan"

failures=0

should_scan_file() {
  local path="$1"

  case "$path" in
    .dart_tool/*|.git/*|build/*|coverage/*|ios/Pods/*|node_modules/*)
      return 1
      ;;
    .env.example)
      return 1
      ;;
    deploy/self-hosted/upstream/.env.example)
      # The exact-byte/provenance preflight above is mandatory.
      return 1
      ;;
    *.png|*.jpg|*.jpeg|*.webp|*.gif|*.ico|*.mp4|*.mov|*.tflite|*.ttf|*.otf|*.jar|*.zip|*.gz)
      return 1
      ;;
  esac

  [[ -f "$path" ]] || return 1
  LC_ALL=C grep -Iq . "$path" 2>/dev/null
}

scan_file() {
  local path="$1"
  LC_ALL=C perl -0777 -e '
    my $file = shift @ARGV;
    open my $fh, "<:raw", $file or exit 0;
    local $/;
    my $text = <$fh>;
    my @rules = (
      ["OpenAI API key", qr/sk-proj-[A-Za-z0-9_-]{20,}/],
      ["Opaque access token", qr/sbp_[A-Za-z0-9]{20,}/],
      ["JWT-like token", qr/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/],
      ["Postgres password URL", qr/postgresql:\/\/[A-Za-z0-9_.%+-]+:[A-Za-z0-9_:%+\-.~!$&()*+,;=]+@/],
      ["Meta Graph API token", qr/EAAG[A-Za-z0-9]{20,}/],
    );
    for my $rule (@rules) {
      if ($text =~ $rule->[1]) {
        print "Potential secret pattern: $rule->[0] in $file\n";
        exit 42;
      }
    }
  ' "$path"
}

while IFS= read -r -d '' path; do
  if ! should_scan_file "$path"; then
    continue
  fi

  if scan_file "$path"; then
    continue
  else
    status=$?
    if [[ "$status" -eq 42 ]]; then
      failures=$((failures + 1))
    else
      printf '[secret-scan][WARN] Could not scan %s\n' "$path" >&2
      failures=$((failures + 1))
    fi
  fi
done < <(git ls-files -z --cached --others --exclude-standard)

if [[ "$failures" -gt 0 ]]; then
  printf '[secret-scan][FAIL] %s potential secret finding(s). Values were not printed.\n' "$failures" >&2
  exit 1
fi

log "fallback secret scan passed"
