require 'minitest/autorun'
require_relative '../audits/collect_index_inventory'

class CollectIndexInventoryTest < Minitest::Test
  def test_qualified_tables_and_drop_order
    actual = CollectIndexInventory.expected([
      "create index shared_name on public.items(id);\ncreate index shared_name on private.items(id);",
      "drop index public.shared_name;\ncreate unique index new_name on collect_hybrid.members(id);"
    ])
    assert_equal [['collect_hybrid', 'new_name'], ['private', 'shared_name']], actual
  end

  def test_dropping_table_only_removes_its_own_indexes
    assert_equal [['private', 'same']], CollectIndexInventory.expected([
      "create index same on public.items(id);\ncreate index same on private.items(id);\ndrop table public.items;"
    ])
  end

  def test_empty_and_invalid_identifiers
    assert_equal 'select null where false;', CollectIndexInventory.query([])
    assert_raises(RuntimeError) { CollectIndexInventory.qualified("name'; drop table x;") }
  end
end
