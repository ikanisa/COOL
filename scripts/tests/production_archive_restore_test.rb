require 'minitest/autorun'
require_relative 'production_archive_restore'

class ProductionArchiveRestoreTest < Minitest::Test
  def test_copy_order_is_irrelevant_but_values_and_sequences_are_not
    prefix = "COPY public.example (id, amount) FROM stdin;\n"
    suffix = "\\.\nSELECT pg_catalog.setval('public.example_id_seq', 2, true);\n"
    source = prefix + "1\t1000\n2\t2000\n" + suffix
    assert_equal data_fingerprint(source), data_fingerprint(prefix + "2\t2000\n1\t1000\n" + suffix)
    refute_equal data_fingerprint(source), data_fingerprint(source.sub('2000', '2001'))
    refute_equal data_fingerprint(source), data_fingerprint(source.sub(', 2, true', ', 3, true'))
  end

  def test_incomplete_and_duplicate_copy_fail_closed
    assert_raises(RuntimeError) { data_fingerprint("COPY public.example (id) FROM stdin;\n1\n") }
    part = "COPY public.example (id) FROM stdin;\n1\n\\.\n"
    assert_raises(RuntimeError) { data_fingerprint(part + part) }
  end

  def test_normalization_never_hides_ddl_grants_or_changed_bounds
    statement = "GRANT SELECT ON TABLE public.example TO anon;"
    assert_equal statement, normalized_dump("\\restrict synthetic\n#{statement}\n\\unrestrict synthetic\n")
    refute_equal normalized_dump(statement), normalized_dump(statement.sub('SELECT', 'ALL'))
    refute_equal normalized_dump('CHECK (amount <= 120);'), normalized_dump('CHECK (amount <= 121);')
    assert_equal normalized_dump('FOR SELECT TO authenticated, anon USING (enabled);'),
      normalized_dump('FOR SELECT TO anon, authenticated USING (enabled);')
    refute_equal normalized_dump('FOR SELECT TO anon USING (enabled);'),
      normalized_dump('FOR SELECT TO anon, authenticated USING (enabled);')
  end

  def test_extension_ownership_preserves_source_role_attributes
    metadata = {'project'=>REF, 'wrapper'=>{'extension_owners'=>[
      {'name'=>'pgcrypto','owner'=>'postgres'}, {'name'=>'plpgsql','owner'=>'supabase_admin'}]}}
    roles = "ALTER ROLE postgres WITH NOSUPERUSER INHERIT CREATEROLE CREATEDB LOGIN NOREPLICATION NOBYPASSRLS;\n"
    statement = 'CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;'
    result = preserve_extension_owners(statement, metadata, roles)
    assert_includes result, "SET SESSION AUTHORIZATION postgres;\n#{statement}"
    assert result.end_with?("RESET SESSION AUTHORIZATION;\n#{roles}")
    assert_raises(RuntimeError) { preserve_extension_owners('', metadata, roles) }
    assert_raises(RuntimeError) { preserve_extension_owners(statement, metadata, roles.sub('NOSUPERUSER', 'SUPERUSER')) }
    metadata['project']='other'
    assert_raises(RuntimeError) { preserve_extension_owners(statement, metadata, roles) }
  end

  def test_default_grant_sort_keeps_every_permission_and_revoke_boundary
    a="ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;\n"
    b="ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;\n"
    revoke="ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public REVOKE ALL ON TABLES FROM anon;\n"
    assert_equal normalized_dump(a+b), normalized_dump(b+a)
    refute_equal normalized_dump(a+b), normalized_dump(a)
    refute_equal normalized_dump(a+revoke+b), normalized_dump(b+revoke+a)
  end

  def test_database_settings_extraction_does_not_reconnect_or_create_database
    source = "-- Name: postgres; Type: DATABASE PROPERTIES; Schema: -; Owner: postgres\n" +
      "ALTER DATABASE postgres SET search_path TO 'public';\n\\connect postgres\n" +
      "-- Name: DATABASE postgres; Type: ACL; Schema: -; Owner: postgres\n" +
      "GRANT CREATE ON DATABASE postgres TO dashboard_user;\n"
    assert_equal "ALTER DATABASE postgres SET search_path TO 'public';\nGRANT CREATE ON DATABASE postgres TO dashboard_user;\n",
      database_restore_properties(source)
    assert_raises(RuntimeError) { database_restore_properties(source + source) }
  end

  def test_graphql_source_and_acl_guard
    definition='CREATE OR REPLACE FUNCTION graphql_public.graphql() RETURNS void LANGUAGE sql AS $$SELECT$$'
    metadata={'project'=>REF,'definition_sha256'=>Digest::SHA256.hexdigest(definition),
      'wrapper'=>{'definition'=>definition,'owner'=>'supabase_admin','extension'=>'pg_graphql'}}
    acl="\nGRANT ALL ON FUNCTION graphql_public.graphql(text,text,jsonb,jsonb) TO postgres;\n"
    assert_includes add_graphql_bootstrap(acl * 4, metadata), definition
    assert_raises(RuntimeError) { add_graphql_bootstrap(acl * 3, metadata) }
    metadata['definition_sha256']='wrong'
    assert_raises(RuntimeError) { add_graphql_bootstrap(acl * 4, metadata) }
  end
end
