#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

inventory="$(mktemp)"
trap 'unlink "$inventory"' EXIT
if ! git ls-files -z --cached --others --exclude-standard > "$inventory"; then
  log "[FAIL] Could not inventory repository files."
  exit 1
fi

# Read each candidate once in one process.
LC_ALL=C perl - "$inventory" <<'PERL'
use strict;
use warnings;

my @rules = (
  ["OpenAI API key", qr/sk-proj-[A-Za-z0-9_-]{20,}/],
  ["Opaque access token", qr/sbp_[A-Za-z0-9]{20,}/],
  ["JWT-like token", qr/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/],
  ["Postgres password URL", qr/postgresql:\/\/[A-Za-z0-9_.%+-]+:[A-Za-z0-9_:%+\-.~!\$&()*+,;=]+@/],
  ["Meta Graph API token", qr/EAAG[A-Za-z0-9]{20,}/],
);
open my $inventory, '<:raw', $ARGV[0] or die "Could not read repository file inventory\n";
local $/ = "\0";
my $failures = 0;
while (defined(my $path = <$inventory>)) {
  chomp $path;
  next if $path =~ m{\A(?:\.dart_tool|\.git|build|coverage|ios/Pods|node_modules)/};
  next if $path =~ /\.(?:png|jpg|jpeg|webp|gif|ico|mp4|mov|tflite|ttf|otf|jar|zip|gz)\z/;
  next unless -f $path;

  my $display_path = $path;
  $display_path =~ s/[\x00-\x1f\x7f]/?/g;
  unless (open my $file, '<:raw', $path) {
    warn "[secret-scan][WARN] Could not open $display_path\n";
    $failures++;
    next;
  } else {
    local $/;
    my $content = <$file> // '';
    my $read_error = $file->error;
    if (!close($file) || $read_error) {
      warn "[secret-scan][WARN] Could not read $display_path\n";
      $failures++;
      next;
    }
    for my $rule (@rules) {
      if ($content =~ $rule->[1]) {
        warn "Potential secret pattern: $rule->[0] in $display_path\n";
        $failures++;
        last;
      }
    }
  }
}
if ($inventory->error || !close($inventory)) {
  die "Could not read repository file inventory\n";
}
if ($failures) {
  warn "[secret-scan][FAIL] $failures finding(s) or read error(s). Values were not printed.\n";
  exit 1;
}
PERL

log "fallback secret scan passed"
