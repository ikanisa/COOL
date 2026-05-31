#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

output_format="text"
if [[ "${1:-}" == "--json" ]]; then
  output_format="json"
elif [[ "${1:-}" != "" ]]; then
  printf 'usage: %s [--json]\n' "$0" >&2
  exit 2
fi

OUTPUT_FORMAT="$output_format" ruby -r json -r open3 -r time <<'RUBY'
output_format = ENV.fetch("OUTPUT_FORMAT")

def git(*args)
  stdout, stderr, status = Open3.capture3("git", *args)
  [stdout, stderr, status.exitstatus]
end

def git_text(*args)
  stdout, _stderr, status = git(*args)
  status == 0 ? stdout.strip : nil
end

def iso8601_utc?(value)
  Time.iso8601(value.to_s)
  value.to_s.end_with?("Z")
rescue ArgumentError, TypeError
  false
end

root = git_text("rev-parse", "--show-toplevel")
unless root
  result = {
    "generated_at" => Time.now.utc.iso8601,
    "status" => "fail",
    "blocker_keys" => ["worktree_not_git"],
    "failures" => ["Current directory is not inside a git worktree."]
  }
  puts output_format == "json" ? JSON.pretty_generate(result) : "[release-worktree-review][FAIL] not a git worktree"
  exit 1
end

branch = git_text("branch", "--show-current")
upstream = git_text("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
head = git_text("rev-parse", "--short", "HEAD")
status_lines = git_text("status", "--porcelain=v1")&.lines&.map(&:chomp) || []
ahead_behind = nil
if upstream && !upstream.empty?
  counts = git_text("rev-list", "--left-right", "--count", "#{upstream}...HEAD")
  if counts
    behind, ahead = counts.split(/\s+/).map(&:to_i)
    ahead_behind = { "ahead" => ahead, "behind" => behind }
  end
end

items = status_lines.map do |line|
  match = line.match(/\A(.{2}) (.*)\z/)
  status = match ? match[1] : line[0, 2]
  path = match ? match[2] : line.split(/\s+/, 2).last.to_s
  {
    "status" => status,
    "path" => path
  }
end

dirty = !items.empty?
reviewed = ENV["RELEASE_WORKTREE_REVIEWED"] == "1"
review_note = ENV["RELEASE_WORKTREE_REVIEW_NOTE"].to_s.strip
reviewer = ENV["RELEASE_WORKTREE_REVIEWER"].to_s.strip
reviewed_at = ENV["RELEASE_WORKTREE_REVIEWED_AT"].to_s.strip
review_evidence = ENV["RELEASE_WORKTREE_REVIEW_EVIDENCE"].to_s.strip

failures = []
blockers = []

if dirty && !reviewed
  blockers << "worktree_review"
  failures << "Worktree has uncommitted changes and RELEASE_WORKTREE_REVIEWED=1 was not provided."
end

if dirty && reviewed && review_note.empty?
  blockers << "worktree_review_note"
  failures << "Dirty worktree review requires RELEASE_WORKTREE_REVIEW_NOTE."
end

if dirty && reviewed && reviewer.length < 2
  blockers << "worktree_review_reviewer"
  failures << "Dirty worktree review requires RELEASE_WORKTREE_REVIEWER."
end

if dirty && reviewed && !iso8601_utc?(reviewed_at)
  blockers << "worktree_review_timestamp"
  failures << "Dirty worktree review requires RELEASE_WORKTREE_REVIEWED_AT as ISO-8601 UTC."
end

if dirty && reviewed && review_evidence.length < 3
  blockers << "worktree_review_evidence"
  failures << "Dirty worktree review requires RELEASE_WORKTREE_REVIEW_EVIDENCE."
end

status =
  if failures.empty?
    "pass"
  else
    "blocked"
  end

summary = {
  "generated_at" => Time.now.utc.iso8601,
  "status" => status,
  "blocker_keys" => blockers.uniq,
  "root" => root,
  "branch" => branch,
  "upstream" => upstream,
  "head" => head,
  "ahead_behind" => ahead_behind,
  "dirty" => dirty,
  "reviewed" => reviewed,
  "reviewer" => reviewer.empty? ? nil : reviewer,
  "reviewed_at" => reviewed_at.empty? ? nil : reviewed_at,
  "review_evidence" => review_evidence.empty? ? nil : review_evidence,
  "review_note_present" => !review_note.empty?,
  "changed_count" => items.count,
  "changed_paths" => items,
  "failures" => failures,
  "secret_handling" => "This gate records git metadata and paths only; it never prints file contents or environment values."
}

if output_format == "json"
  puts JSON.pretty_generate(summary)
else
  puts "[release-worktree-review] status=#{status}"
  puts "[release-worktree-review] branch=#{branch} upstream=#{upstream} head=#{head}"
  puts "[release-worktree-review] changed_count=#{items.count}"
  failures.each { |failure| warn "[release-worktree-review][BLOCKED] #{failure}" }
end

exit(status == "pass" ? 0 : 99)
RUBY
