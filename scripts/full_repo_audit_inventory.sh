#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

format="markdown"
if [[ "${1:-}" == "--json" ]]; then
  format="json"
elif [[ "${1:-}" == "--markdown" || "${1:-}" == "" ]]; then
  format="markdown"
else
  printf 'usage: %s [--json|--markdown]\n' "$0" >&2
  exit 2
fi

FORMAT="$format" ROOT_DIR="$ROOT_DIR" ruby -r json -r time <<'RUBY'
root = ENV.fetch("ROOT_DIR")
format = ENV.fetch("FORMAT")

def run(command)
  output = `#{command} 2>&1`
  {
    "command" => command,
    "exit_code" => $?.exitstatus,
    "output" => output.strip
  }
end

def files_under(*dirs)
  dirs.flat_map do |dir|
    next [] unless Dir.exist?(dir)

    Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH).select do |path|
      File.file?(path) && !path.include?("/.git/") && !path.include?("/.dart_tool/")
    end
  end.sort
end

def relative(path)
  path.sub(%r{\A\./}, "")
end

def route_rows(path)
  return [] unless File.file?(path)

  File.readlines(path, chomp: true).each_with_index.map do |line, index|
    match = line.match(/path:\s*'([^']+)'/)
    next unless match

    {
      "file" => path,
      "line" => index + 1,
      "path" => match[1]
    }
  end.compact
end

def route_constant_rows(path, const_name)
  return [] unless File.file?(path)

  in_const = false
  File.readlines(path, chomp: true).each_with_index.map do |line, index|
    in_const = true if line.include?("const #{const_name}") && line.include?("<String>[")
    if in_const && line.strip == "];"
      in_const = false
      next
    end
    next unless in_const

    match = line.match(/'([^']+)'/)
    next unless match

    {
      "file" => path,
      "line" => index + 1,
      "path" => match[1]
    }
  end.compact
end

def file_rows(paths)
  paths.map do |path|
    {
      "path" => relative(path),
      "bytes" => File.size(path)
    }
  end
end

def safe_risk_markers(paths)
  patterns = {
    "todo" => /\b(?:TODO|FIXME|HACK)\b/,
    "unimplemented" => /throw\s+UnimplementedError/,
    "debug_logging" => /\b(?:print|debugPrint)\s*\(/,
    "openai_key_shape" => /sk-(?:proj-)?[A-Za-z0-9_\-]{20,}/,
    "private_key_marker" => /BEGIN .*PRIVATE KEY/,
    "service_role_reference" => /\bservice_role\b/i,
    "client_secret_reference" => /\bclient_secret\b/i,
    "raw_secret_assignment_shape" => /\b(?:secret|token|api[_-]?key|password)\b\s*[:=]\s*["']?[A-Za-z0-9_\-]{12,}/i
  }

  text_extensions = %w[.dart .ts .js .mjs .sql .sh .md .json .yaml .yml .toml .plist .kts .gradle .html .txt]
  paths.flat_map do |path|
    next [] unless text_extensions.include?(File.extname(path).downcase)

    begin
      File.readlines(path, chomp: true).each_with_index.map do |line, index|
        markers = patterns.map { |name, pattern| name if line.match?(pattern) }.compact
        next if markers.empty?

        {
          "path" => relative(path),
          "line" => index + 1,
          "markers" => markers
        }
      end.compact
    rescue ArgumentError
      []
    end
  end
end

all_scope_files = files_under(
  "lib",
  "supabase",
  "android",
  "ios",
  "web",
  "scripts",
  "test",
  "integration_test",
  "docs"
)

dart_files = files_under("lib").select { |path| path.end_with?(".dart") }
test_files = files_under("test", "integration_test").select { |path| path.end_with?(".dart") }
script_files = files_under("scripts")
doc_files = files_under("docs")
native_files = files_under("android", "ios", "web")

supabase_functions = Dir.glob("supabase/functions/*").select { |path| File.directory?(path) }.sort.map { |path| relative(path) }
supabase_migrations = Dir.glob("supabase/migrations/*.sql").sort.map { |path| relative(path) }

inventory = {
  "generated_at" => Time.now.utc.iso8601,
  "root" => root,
  "baseline" => {
    "git_status" => run("git status --short --branch"),
    "git_head" => run("git log -1 --oneline --decorate"),
    "flutter_version" => run("/Users/jeanbosco/Developer/flutter/bin/flutter --version | head -n 1"),
    "make_commands" => run("make -n analyze test 2>/dev/null || true")
  },
  "counts" => {
    "scoped_files" => all_scope_files.count,
    "lib_dart_files" => dart_files.count,
    "test_dart_files" => test_files.count,
    "scripts" => script_files.count,
    "docs" => doc_files.count,
    "native_platform_files" => native_files.count,
    "supabase_functions" => supabase_functions.count,
    "supabase_migrations" => supabase_migrations.count
  },
  "mobile_route_contract" => route_constant_rows("lib/app/router.dart", "collectRoutePaths"),
  "mobile_route_entries" => route_rows("lib/app/router.dart"),
  "admin_route_contract" => route_constant_rows("lib/admin/admin_router.dart", "adminRoutePaths"),
  "admin_route_entries" => route_rows("lib/admin/admin_router.dart"),
  "supabase" => {
    "functions" => supabase_functions,
    "migrations" => supabase_migrations
  },
  "files" => {
    "lib_dart" => file_rows(dart_files),
    "tests" => file_rows(test_files),
    "scripts" => file_rows(script_files),
    "docs" => file_rows(doc_files),
    "native_platform" => file_rows(native_files)
  },
  "risk_markers" => {
    "secret_handling" => "Potential sensitive values are never printed; only marker names, paths, and line numbers are reported.",
    "rows" => safe_risk_markers(all_scope_files)
  }
}

if format == "json"
  puts JSON.pretty_generate(inventory)
  exit
end

puts "# Full Repo Audit Inventory"
puts
puts "- Generated at: #{inventory.fetch("generated_at")}"
puts "- Root: `#{root}`"
puts "- Git head: `#{inventory.dig("baseline", "git_head", "output")}`"
puts "- Git status: `#{inventory.dig("baseline", "git_status", "output").gsub("\n", " | ")}`"
puts "- Flutter: `#{inventory.dig("baseline", "flutter_version", "output")}`"
puts
puts "## Counts"
puts
inventory.fetch("counts").each do |key, value|
  puts "- #{key}: #{value}"
end
puts
puts "## Mobile Route Contract"
puts
inventory.fetch("mobile_route_contract").each do |row|
  puts "- `#{row.fetch("path")}` at `#{row.fetch("file")}:#{row.fetch("line")}`"
end
puts
puts "## Mobile GoRoute Entries"
puts
inventory.fetch("mobile_route_entries").each do |row|
  puts "- `#{row.fetch("path")}` at `#{row.fetch("file")}:#{row.fetch("line")}`"
end
puts
puts "## Admin Route Contract"
puts
inventory.fetch("admin_route_contract").each do |row|
  puts "- `#{row.fetch("path")}` at `#{row.fetch("file")}:#{row.fetch("line")}`"
end
puts
puts "## Admin GoRoute Entries"
puts
inventory.fetch("admin_route_entries").each do |row|
  puts "- `#{row.fetch("path")}` at `#{row.fetch("file")}:#{row.fetch("line")}`"
end
puts
puts "## Supabase Functions"
puts
inventory.dig("supabase", "functions").each { |path| puts "- `#{path}`" }
puts
puts "## Supabase Migrations"
puts
inventory.dig("supabase", "migrations").each { |path| puts "- `#{path}`" }
puts
puts "## Risk Marker Summary"
puts
puts "- Rows: #{inventory.dig("risk_markers", "rows").count}"
puts "- Secret handling: #{inventory.dig("risk_markers", "secret_handling")}"
puts
inventory.dig("risk_markers", "rows").first(200).each do |row|
  puts "- `#{row.fetch("path")}:#{row.fetch("line")}`: #{row.fetch("markers").join(", ")}"
end
if inventory.dig("risk_markers", "rows").count > 200
  puts "- Additional rows omitted from markdown; run `scripts/full_repo_audit_inventory.sh --json` for the complete list."
end
RUBY
