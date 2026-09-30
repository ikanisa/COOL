require 'minitest/autorun'
require 'digest'

# Source contracts only. This does not execute or parse PostgreSQL bodies.
class RosterImportProvenanceSourceTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  SQL = File.read(File.join(ROOT,'supabase/migrations/20260930100000_roster_import_provenance.sql'))
  UAT = File.read(File.join(ROOT,'scripts/tests/roster_import_provenance_uat.sql'))
  CONTRACT = File.read(File.join(ROOT,'docs/admin/ROSTER_IMPORT_PROVENANCE_CONTRACT.md'))

  def body(name)
    match = SQL.match(/create(?: or replace)? function #{Regexp.escape(name)}\(.*?as \$\$(.*?)\$\$;/m)
    refute_nil match, "Function #{name} must exist"
    match[1]
  end

  def test_prior_revocation_migration_is_unchanged
    assert_equal 'b8335e9b70339a1a67d50db245147b483610a3a4c76f223bd7a17cfc4876a2bb',
      Digest::SHA256.file(File.join(ROOT,'supabase/migrations/20260929180000_notification_registration_sessions.sql')).hexdigest
  end

  def test_legacy_raw_row_writers_are_both_closed_even_to_owner
    %w[public.admin_add_assisted_roster public.admin_create_assisted_group_with_roster].each do |name|
      assert_match(/\Abegin raise exception 'roster_provenance_required' using errcode='55000'; end\s*\z/,body(name).strip)
    end
    assert_match(/revoke all on function public.admin_add_assisted_roster.*?public.admin_create_assisted_group_with_roster.*?from public,anon,authenticated,service_role;/m,SQL)
    refute_match(/grant execute on function public.admin_(?:add_assisted_roster|create_assisted_group_with_roster)/,SQL)
  end

  def test_service_roles_have_only_source_completion_and_failure_boundaries
    grants = SQL.scan(/grant execute on function (.*?) to service_role;/m).flatten.join
    %w[create_roster_import_source complete_roster_import_preview fail_roster_import_preview].each { |name| assert_includes grants,"public.#{name}(" }
    refute_match(/admin_(?:commit|review|get)_roster_import/,grants)
    %w[create_roster_import_source complete_roster_import_preview fail_roster_import_preview].each do |name|
      text=body("public.#{name}")
      assert_operator text.index('public._lock_notification_session_gate()'),:<,text.index("auth.role() is distinct from 'service_role'")
      assert_includes text,'collect_hybrid.require_roster_actor(p_actor_id,p_session_id)'
    end
  end

  def test_final_actor_comes_from_authenticated_claims_and_live_rows
    assert_includes body('collect_hybrid.require_roster_caller'),"auth.role() is distinct from 'authenticated'"
    assert_includes body('collect_hybrid.require_roster_caller'),'collect_hybrid.require_roster_actor(auth.uid(),sid::uuid)'
    actor=body('collect_hybrid.require_roster_actor')
    assert_operator actor.index('public._lock_notification_session_gate()'),:<,actor.index("hashtext('collect_admin_combined_roster')")
    assert_includes actor,'from auth.sessions where id=p_session and user_id=p_actor for share'
    %w[collections.moderate users.read hybrid_member_onboarding].each { |value| assert_includes actor,value }
    refute_match(/set_config\('request\.jwt/,SQL)
  end

  def test_new_tables_are_private_and_immutable
    tables=SQL.scan(/create table collect_hybrid\.(roster_import_\w+)/).flatten
    assert_equal %w[roster_import_sources roster_import_extractions roster_import_revisions roster_import_results roster_import_commits],tables
    tables.each { |name| assert_includes SQL,"'#{name}'" }
    assert_includes SQL,'alter table collect_hybrid.%I enable row level security'
    assert_includes SQL,'revoke all on collect_hybrid.%I from public,anon,authenticated,service_role'
    assert_includes SQL,'before update or delete on collect_hybrid.%I'
    assert_includes body('collect_hybrid.guard_roster_provenance'),"errcode='55000'"
  end

  def test_preview_is_server_normalized_and_human_review_is_required
    preview=body('collect_hybrid.roster_preview')
    assert_includes preview,'jsonb_array_length(p_candidates) not between 1 and 500'
    assert_includes preview,"octet_length(p_candidates::text)>512000"
    assert_includes preview,"member_name ~ '^[=+@-]'"
    assert_includes preview,'seen ? phone'
    assert_includes preview,'collect_hybrid.canonical_momo_number(compact)'
    assert_includes preview,"if p_human and ready<>n then raise exception 'roster_rows_invalid'"
    assert_includes body('public.admin_commit_roster_import'),"r.processing_method<>'human_review'"
    assert_includes body('public.admin_commit_roster_import'),'p_human_affirmed is distinct from true'
  end

  def test_hash_and_parent_chain_do_not_trust_client_rows_at_commit
    commit=body('public.admin_commit_roster_import')
    assert_includes commit,'collect_hybrid.roster_preview(r.normalized_rows,true)'
    assert_includes commit,"collect_hybrid.roster_digest(validation->'normalized_rows')<>p_reviewed_rows_sha256"
    refute_match(/p_rows/,commit)
    review=body('public.admin_review_roster_import')
    assert_includes review,"parent.id<>p_parent_revision_id"
    assert_includes review,'parent.revision_number>=20'
    assert_includes review,'parent.extraction_id,parent.revision_number+1'
  end

  def test_cached_source_receipt_prevents_silent_provider_retry
    source=body('public.create_roster_import_source')
    assert_includes source,"raise exception 'roster_import_in_progress'"
    assert_includes source,"'completed_preview',collect_hybrid.roster_revision_receipt(result.revision_id)"
    assert_includes source,'insert into collect_hybrid.roster_import_extractions'
    assert_includes source,"p_consent_version is distinct from 'roster-ai-extraction-v1'"
    refute_match(/net\.http|http_post|api\.openai|content_base64/,SQL)
  end

  def test_provenance_metadata_has_the_agreed_caller_keys
    receipt=body('collect_hybrid.roster_revision_receipt')
    %w[source_receipt request_id source_size client_filename declared_mime detected_type derived_sha256 derived_assurance
       extraction_id ai_consent consent_version parser_version schema_version].each { |key| assert_includes receipt,"'#{key}'" }
    refute_match(/'actor_id'|'session_id'/,receipt)
    assert_includes receipt,"'client_derived_tsv'"
    assert_includes CONTRACT,'SourceReceiptMetadata'
  end

  def test_commit_replay_checks_actor_and_complete_payload_before_expiry
    commit=body('public.admin_commit_roster_import')
    assert_operator commit.index('collect_hybrid.require_roster_caller()'),:<,commit.index('select * into prior')
    assert_operator commit.index("return prior.response||jsonb_build_object('replayed',true)"),:<,commit.index('s.expires_at<=clock_timestamp()')
    assert_includes commit,'p_mode,p_collection_id,title,reason,auth.uid(),sid'
    assert_includes commit,'p_import_id,p_revision_id,p_reviewed_rows_sha256,p_human_affirmed'
    assert_includes commit,"where import_id=s.id) then raise exception 'roster_import_committed'"
  end

  def test_commit_has_no_direct_financial_writer
    commit=body('public.admin_commit_roster_import')
    %w[payments ledger_entries momo_journal_entries momo_journal_lines member_balances collection_balances].each do |table|
      refute_match(/(?:insert into|update|delete from) (?:public|collect_hybrid)\.#{table}\b/i,commit)
    end
    assert_includes commit,'collect_hybrid.create_assisted_group_with_share'
    assert_includes commit,'collect_hybrid.add_roster(group_id,r.normalized_rows'
    assert_includes commit,"raise exception 'roster_commit_conflict'"
  end

  def test_existing_group_eligibility_is_actual_schema_data
    commit=body('public.admin_commit_roster_import')
    assert_includes commit,"visibility='private' and public_status='private' and not diaspora_enabled"
    getter=body('public.admin_get_collection')
    %w[creation_origin archived_at currency diaspora_enabled].each { |key| assert_includes getter,"'#{key}'" }
    refute_match(/collection\.(?:country_code|is_active)/,getter)
    refute_match(/grant .*admin_get_collection/,SQL)
  end

  def test_uat_is_exact142_rollback_and_never_disables_guards
    assert_includes UAT,"schema_migrations)<>142"
    assert_includes UAT,"schema_migrations)<>'20260930100000'"
    assert_includes UAT,"collect.roster_provenance_qa"
    assert_match(/\nrollback;\s*\z/,UAT)
    refute_match(/^commit;|disable trigger|setval\(/i,UAT)
    %w[roster_import_expired roster_commit_conflict roster_actor_unavailable roster_rows_invalid].each { |code| assert_includes UAT,code }
    assert_includes UAT,'leaves financial table unchanged'
  end
end
