# frozen_string_literal: true

# Read-only reproduction of the maintained migration-body normalizer.
# This does not parse/execute SQL or change the original files.
require 'json'

rows = ARGV.map do |path|
  original = File.read(path, mode: 'r:BOM|UTF-8')
  sql = original.sub(/\Abegin\s*;\s*/i, '')
  sql = sql.sub(/\s*commit\s*;\s*\z/i, '')
  remaining = sql.match(/(^|\n)\s*(begin|commit)\s*;/i)
  {
    'path' => path,
    'source_prefix' => original.lines.first(4).join,
    'remaining_transaction_terminator' => !remaining.nil?,
    'maintained_normalizer_would_refuse' => !remaining.nil?
  }
end
puts JSON.pretty_generate(rows)
