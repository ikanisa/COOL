#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf '[secret-scan] %s\n' "$*"
}

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
    .env.example|supabase/functions/.env.example)
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
    use Digest::SHA qw(sha256_hex);
    my $file = shift @ARGV;
    open my $fh, "<:raw", $file or exit 0;
    local $/;
    my $text = <$fh>;
    # Public upstream JWT unit fixtures are retained byte-for-byte. A change
    # to either file revokes this exception; other secret rules still apply.
    my %upstream_jwt_fixtures = (
      "third_party/gotrue/test/client_test.dart" =>
        "4bdb86ee4499ba6332ba690ddfd9eb7990fdb0c2869c97af7f4563533319f6ee",
      "third_party/gotrue/test/get_claims_test.dart" =>
        "4172db82411fb90360f50af4a6e19abe0302d61530cf777043f0626ef58da6cb",
    );
    my @rules = (
      ["OpenAI API key", qr/sk-proj-[A-Za-z0-9_-]{20,}/],
      ["Supabase access token", qr/sbp_[A-Za-z0-9]{20,}/],
      ["JWT-like token", qr/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/],
      ["Postgres password URL", qr/postgresql:\/\/[A-Za-z0-9_.%+-]+:[A-Za-z0-9_:%+\-.~!$&()*+,;=]+@/],
      ["Meta Graph API token", qr/EAAG[A-Za-z0-9]{20,}/],
    );
    for my $rule (@rules) {
      next if $rule->[0] eq "JWT-like token" &&
        exists $upstream_jwt_fixtures{$file} &&
        sha256_hex($text) eq $upstream_jwt_fixtures{$file};
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
