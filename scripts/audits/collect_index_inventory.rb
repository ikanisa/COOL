# Explicit, unquoted migration indexes only. Resolve an unqualified index name
# in its table's schema, not always public. This is not a general SQL parser.
module CollectIndexInventory
  def self.qualified(name, default_schema = 'public')
    parts = name.split('.')
    raise 'Invalid unquoted SQL identifier' unless parts.length.between?(1, 2) && parts.all? { |p| p.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) }
    parts.length == 1 ? [default_schema, parts.first] : parts
  end

  def self.expected(sources)
    indexes = {}
    sources.each do |sql|
      events = []
      sql.to_enum(:scan, /^create(?: unique)? index(?: if not exists)?\s+([a-zA-Z_][\w.]*)\s+on\s+([a-zA-Z_][\w.]*)/i).each do
        m = Regexp.last_match
        table = qualified(m[2])
        events << [m.begin(0), :add, qualified(m[1], table.first), table]
      end
      sql.to_enum(:scan, /^drop index(?: if exists)?\s+([a-zA-Z_][\w.]*)/i).each do
        m = Regexp.last_match
        events << [m.begin(0), :drop_index, qualified(m[1]), nil]
      end
      sql.to_enum(:scan, /^drop table(?: if exists)?\s+([a-zA-Z_][\w.]*)/i).each do
        m = Regexp.last_match
        events << [m.begin(0), :drop_table, nil, qualified(m[1])]
      end
      events.sort_by(&:first).each do |_position, action, index, table|
        case action
        when :add then indexes[index] = table
        when :drop_index then indexes.delete(index)
        when :drop_table then indexes.delete_if { |_name, indexed_table| indexed_table == table }
        end
      end
    end
    indexes.keys.sort
  end

  def self.query(indexes)
    return 'select null where false;' if indexes.empty?
    values = indexes.map { |schema, name| "('#{schema}','#{name}')" }.join(',')
    <<~SQL
      with expected(schemaname,indexname) as (values #{values})
      select expected.schemaname || '.' || expected.indexname
      from expected left join pg_indexes
        on pg_indexes.schemaname=expected.schemaname
        and pg_indexes.indexname=expected.indexname
      where pg_indexes.indexname is null
      order by expected.schemaname,expected.indexname;
    SQL
  end
end

if $PROGRAM_NAME == __FILE__
  root = File.expand_path('../..', __dir__)
  puts CollectIndexInventory.query(CollectIndexInventory.expected(Dir[root + '/supabase/migrations/*.sql'].sort.map { |p| File.read(p) }))
end
