\set ON_ERROR_STOP on
-- Root must first verify the dedicated local Docker labels/port. Invoke with
-- PGOPTIONS='-c collect.reconciliation_qa=isolated_clone'. Every write rolls back.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_setting('collect.reconciliation_qa',true) is distinct from 'isolated_clone'
   or (select count(*) from supabase_migrations.schema_migrations)<>140
   or (select max(version) from supabase_migrations.schema_migrations)<>'20260929170000'
   or exists(select 1 from auth.users where id::text like '99900000-%') then
  raise exception 'Verified isolated 140-migration fixture and unused synthetic identities required'; end if;
end $$;
create temporary table reconciliation_test_results(label text primary key);
grant all on reconciliation_test_results to authenticated,service_role,anon;
do $$ begin execute format('grant usage on schema %I to authenticated,service_role,anon',pg_my_temp_schema()::regnamespace::text); end $$;
create function pg_temp.assert_reconciliation(ok boolean,label text) returns void language plpgsql as $$ begin
 if ok is not true then raise exception 'FAIL: %',label; end if;
 insert into pg_temp.reconciliation_test_results values(label);
end $$;
create function pg_temp.reconciliation_snapshot() returns jsonb language plpgsql security definer set search_path='' as $$
declare relation_name text; body jsonb; result jsonb:='{}'; begin
 foreach relation_name in array array['public.payments','collect_security.reconciliation_reviews','public.provider_finality_requests',
 'public.payment_provider_confirmations','public.ledger_entries','collect_hybrid.momo_journal_entries','collect_hybrid.momo_journal_lines',
 'collect_hybrid.collection_balances','collect_hybrid.member_balances','collect_hybrid.momo_balance_snapshots','public.audit_logs'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',relation_name::regclass) into body;
  result:=result||jsonb_build_object(relation_name,body);
 end loop; return result;
end $$;
create function pg_temp.expect_reconciliation_error(command text,expected_state text,label text)
returns void language plpgsql as $$
declare caught_state text; before_state jsonb:=pg_temp.reconciliation_snapshot(); begin
 begin execute command; exception when others then get stacked diagnostics caught_state=returned_sqlstate; end;
 perform pg_temp.assert_reconciliation(caught_state=expected_state,label);
 perform pg_temp.assert_reconciliation(pg_temp.reconciliation_snapshot()=before_state,label||' preserves financial/audit rows');
end $$;
create function pg_temp.actor(which_actor text,aal text default 'aal2') returns void language plpgsql as $$ begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',case which_actor when 'maker' then '99900000-0000-4000-8000-000000000001'
 when 'checker' then '99900000-0000-4000-8000-000000000002' else '99900000-0000-4000-8000-000000000003' end,
 'role','authenticated','aal',aal,'session_id',case which_actor when 'maker' then '99900000-0000-4000-8000-000000000011'
 when 'checker' then '99900000-0000-4000-8000-000000000012' else '99900000-0000-4000-8000-000000000013' end)::text,true);
end $$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data) values
 ('99900000-0000-4000-8000-000000000001','authenticated','authenticated','250788909001',now(),'{}','{}'),
 ('99900000-0000-4000-8000-000000000002','authenticated','authenticated','250788909002',now(),'{}','{}'),
 ('99900000-0000-4000-8000-000000000003','authenticated','authenticated','250788909003',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id::text like '99900000-%';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason) values
 ('99900000-0000-4000-8000-000000000001','+250788909001',now()-interval '2 minutes','Synthetic maker approval'),
 ('99900000-0000-4000-8000-000000000002','+250788909002',now()-interval '2 minutes','Synthetic checker approval');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
 select actor.id,role.id,'Synthetic reconciliation test',now()-interval '1 minute'
 from (values('99900000-0000-4000-8000-000000000001'::uuid),('99900000-0000-4000-8000-000000000002'::uuid)) actor(id)
 cross join public.admin_roles role where role.name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal) values
 ('99900000-0000-4000-8000-000000000011','99900000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal2'),
 ('99900000-0000-4000-8000-000000000012','99900000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour','aal2'),
 ('99900000-0000-4000-8000-000000000013','99900000-0000-4000-8000-000000000003',now(),now(),now()+interval '1 hour','aal2');
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,
 contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin) values
 ('99900000-0000-4000-8000-000000000021','reconciliation-140-synthetic','99900000-0000-4000-8000-000000000003',
 'Synthetic workflow UAT','Family / friends','private','private','ikimina','members',false,false,'member_app');
insert into public.payments(id,collection_id,contributor_user_id,receiver_user_id,receiver_momo_number_hash,
 amount_rwf,transaction_id,provider_network,source,status,anonymity_choice,posted_at) values
 ('99900000-0000-4000-8000-000000000031','99900000-0000-4000-8000-000000000021',
 '99900000-0000-4000-8000-000000000003','99900000-0000-4000-8000-000000000003',repeat('a',64),
 1234,'RECONCILE1401234','mtn_momo','manual_admin','review','anonymous',null);
-- Retained staged identity-unknown review does not acquire fabricated sessions.
insert into collect_security.reconciliation_reviews(id,payment_id,payment_fingerprint,evidence_sha256,
 source_reference,occurred_at,proposal_reason,proposed_by) select
 '99900000-0000-4000-8000-000000000041',id,collect_security.reconciliation_fingerprint(p),repeat('b',64),
 'RECONCILE140-REFERENCE','2026-09-28T12:00:00Z','Synthetic independent statement evidence','99900000-0000-4000-8000-000000000001'
 from public.payments p where id='99900000-0000-4000-8000-000000000031';
select set_config('collect.test.propose',format('select public.propose_payment_reconciliation_v2(%L,%L,%L,%L,%L)',
 '99900000-0000-4000-8000-000000000031',repeat('b',64),'RECONCILE140-REFERENCE','2026-09-28T12:00:00Z',
 'Synthetic independent statement evidence'),true);

set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.expect_reconciliation_error(current_setting('collect.test.propose'),'42501','anonymous proposal denied');
reset role;
set local role authenticated;
select pg_temp.actor('member');
select pg_temp.expect_reconciliation_error(current_setting('collect.test.propose'),'42501','member proposal denied');
select pg_temp.expect_reconciliation_error('select public.list_payment_reconciliations_v2()','42501','member review read denied');
select pg_temp.actor('maker','aal1');
select pg_temp.expect_reconciliation_error(current_setting('collect.test.propose'),'42501','AAL1 proposal denied');
select pg_temp.actor('maker');
select pg_temp.expect_reconciliation_error(replace(current_setting('collect.test.propose'),'2026-09-28T12:00:00Z','-infinity'),
 '22023','nonfinite evidence rejected');
select pg_temp.expect_reconciliation_error(replace(current_setting('collect.test.propose'),repeat('b',64),'invalid'),
 '22023','invalid evidence digest rejected');
select public.propose_payment_reconciliation_v2('99900000-0000-4000-8000-000000000031',repeat('b',64),
 'RECONCILE140-REFERENCE','2026-09-28T12:00:00Z','Synthetic independent statement evidence') as review_id \gset
select set_config('collect.test.review_id',:'review_id',true);
select pg_temp.assert_reconciliation(:'review_id'::uuid <> '99900000-0000-4000-8000-000000000041','legacy proposal replaced by newly reviewed evidence');
select pg_temp.assert_reconciliation(public.propose_payment_reconciliation_v2('99900000-0000-4000-8000-000000000031',
 upper(repeat('b',64)),' reconcile140-reference ','2026-09-28T14:00:00+02:00',' Synthetic independent statement evidence ') = :'review_id'::uuid,
 'normalized proposal retry is idempotent');
select pg_temp.expect_reconciliation_error(format('select public.approve_payment_reconciliation_v2(%L,%L)',:'review_id',
 'Synthetic independent checker approval'),'22023','maker self approval denied');
reset role;
select pg_temp.assert_reconciliation((select count(*)=1 from public.audit_logs where entity_id='99900000-0000-4000-8000-000000000031'
 and action='reconciliation.proposed'),'proposal retry creates one audit record');

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '22023','unapproved review cannot finalize');
select pg_temp.expect_reconciliation_error('select public.confirm_provider_payment(null,null,null,null,null,null,null,null)',
 '42501','direct service confirmation closed');
select pg_temp.expect_reconciliation_error('select public.process_provider_finality_event(null,null,null,null)',
 '42501','direct service gateway closed');
reset role;
set local role authenticated;
select pg_temp.actor('checker');
select pg_temp.expect_reconciliation_error('select public.approve_payment_reconciliation_v2(''99900000-0000-4000-8000-000000000041'',''Legacy approval prohibited'')',
 '42501','legacy review without maker session cannot be approved');
select pg_temp.assert_reconciliation(public.approve_payment_reconciliation_v2(:'review_id','Synthetic independent checker approval'),
 'independent checker approves');
select pg_temp.assert_reconciliation(public.approve_payment_reconciliation_v2(:'review_id','Synthetic independent checker approval'),
 'exact approval retry succeeds');
select pg_temp.expect_reconciliation_error(format('select public.approve_payment_reconciliation_v2(%L,%L)',:'review_id',
 'Changed independent approval reason'),'22023','approval reason immutable');
select pg_temp.assert_reconciliation(public.authorize_reconciliation_finalization_v2(:'review_id'),'same checker session may request finalization');
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','browser cannot call service finalizer directly');
select pg_temp.actor('maker');
select pg_temp.expect_reconciliation_error(format('select public.authorize_reconciliation_finalization_v2(%L)',:'review_id'),
 '42501','maker cannot submit checker finalization');
select pg_temp.assert_reconciliation((public.list_payment_reconciliations_v2('99900000-0000-4000-8000-000000000031')->>'total')::int=2,
 'approved Admin can page current and retained legacy reviews');
select pg_temp.assert_reconciliation(public.get_payment_reconciliation_v2(:'review_id')->>'collection_id'='99900000-0000-4000-8000-000000000021'
 and not (public.get_payment_reconciliation_v2(:'review_id') ? 'approved_session_id'),'detail links collection while withholding session identity');
reset role;
select pg_temp.assert_reconciliation((select count(*)=1 from public.audit_logs where entity_id='99900000-0000-4000-8000-000000000031'
 and action='reconciliation.approved'),'approval retry creates one audit record');
select pg_temp.expect_reconciliation_error(format('update collect_security.reconciliation_reviews set evidence_sha256=%L where id=%L',repeat('c',64),:'review_id'),
 '55000','original reviewed evidence immutable even to owner SQL');
select pg_temp.expect_reconciliation_error(format('delete from collect_security.reconciliation_reviews where id=%L',:'review_id'),
 '55000','review audit evidence cannot be deleted');

-- Each revocation is independently rolled back; no role or identity is weakened
-- to make the success case pass. Every failed call preserves financial/audit rows.
savepoint maker_role_revoked;
update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='99900000-0000-4000-8000-000000000001' and revoked_at is null;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','maker_role_revoked');
reset role;
rollback to savepoint maker_role_revoked;
select pg_temp.assert_reconciliation(true,'maker_role_revoked denial verified and restored');
savepoint checker_role_revoked;
update public.admin_user_roles set revoked_at=clock_timestamp() where user_id='99900000-0000-4000-8000-000000000002' and revoked_at is null;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','checker_role_revoked');
reset role;
rollback to savepoint checker_role_revoked;
select pg_temp.assert_reconciliation(true,'checker_role_revoked denial verified and restored');
savepoint checker_identity_revoked;
update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp() where user_id='99900000-0000-4000-8000-000000000002';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','checker_identity_revoked');
reset role;
rollback to savepoint checker_identity_revoked;
select pg_temp.assert_reconciliation(true,'checker_identity_revoked denial verified and restored');
savepoint maker_session_expired;
update auth.sessions set not_after=clock_timestamp()-interval '1 second' where id='99900000-0000-4000-8000-000000000011';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','maker_session_expired');
reset role;
rollback to savepoint maker_session_expired;
select pg_temp.assert_reconciliation(true,'maker_session_expired denial verified and restored');
savepoint checker_session_deleted;
delete from auth.sessions where id='99900000-0000-4000-8000-000000000012';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','checker_session_deleted');
reset role;
rollback to savepoint checker_session_deleted;
select pg_temp.assert_reconciliation(true,'checker_session_deleted denial verified and restored');
savepoint checker_session_aal_downgraded;
update auth.sessions set aal='aal1' where id='99900000-0000-4000-8000-000000000012';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','checker_session_aal_downgraded');
reset role;
rollback to savepoint checker_session_aal_downgraded;
select pg_temp.assert_reconciliation(true,'checker_session_aal_downgraded denial verified and restored');
savepoint maker_verified_identity_changed;
update auth.users set phone='250788909099' where id='99900000-0000-4000-8000-000000000001';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','maker_verified_identity_changed');
reset role;
rollback to savepoint maker_verified_identity_changed;
select pg_temp.assert_reconciliation(true,'maker_verified_identity_changed denial verified and restored');
savepoint session_predates_renewed_role;
update public.admin_user_roles set created_at=clock_timestamp()+interval '1 second' where user_id='99900000-0000-4000-8000-000000000002' and revoked_at is null;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error(format('select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 '42501','session_predates_renewed_role');
reset role;
rollback to savepoint session_predates_renewed_role;
select pg_temp.assert_reconciliation(true,'session_predates_renewed_role denial verified and restored');
-- An expired retained decision cannot be revived by a new finalization call.
insert into collect_security.reconciliation_reviews(id,payment_id,payment_fingerprint,evidence_sha256,
 source_reference,occurred_at,proposal_reason,proposed_by,proposed_at,proposed_session_id,
 approved_by,approved_at,approval_reason,approved_session_id)
select '99900000-0000-4000-8000-000000000042',payment_id,payment_fingerprint,evidence_sha256,
 source_reference,occurred_at,proposal_reason,proposed_by,clock_timestamp()-interval '25 hours',proposed_session_id,
 approved_by,clock_timestamp()-interval '16 minutes',approval_reason,approved_session_id
from collect_security.reconciliation_reviews where id=:'review_id'::uuid;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_reconciliation_error('select public.finalize_approved_reconciliation_v2(''99900000-0000-4000-8000-000000000042'')',
 '22023','expired approval cannot finalize');
select public.finalize_approved_reconciliation_v2(:'review_id') as finalized_result \gset
select pg_temp.assert_reconciliation((:'finalized_result'::jsonb->>'replayed')::boolean is false
 and :'finalized_result'::jsonb->>'payment_status'='posted','approved workflow posts exactly once');
select pg_temp.assert_reconciliation((public.finalize_approved_reconciliation_v2(:'review_id')->>'replayed')::boolean,
 'exact finalization retry is acknowledged');
reset role;
select pg_temp.assert_reconciliation((select count(*)=1 from public.payment_provider_confirmations
 where payment_id='99900000-0000-4000-8000-000000000031') and (select count(*)=2 from public.ledger_entries
 where payment_id='99900000-0000-4000-8000-000000000031'),'one confirmation and two compatibility credits');
select pg_temp.assert_reconciliation((select count(*)=1 from collect_hybrid.momo_journal_entries
 where payment_id='99900000-0000-4000-8000-000000000031' and entry_type='receipt')
 and (select confirmed_rwf=1234 from collect_hybrid.collection_balances where collection_id='99900000-0000-4000-8000-000000000021'),
 'one canonical receipt and exact RWF1234 collection balance');
select pg_temp.assert_reconciliation((select count(*)=1 from public.audit_logs where entity_id='99900000-0000-4000-8000-000000000031'
 and action='reconciliation.finalized'),'finalization retry creates one immutable audit fact');
select pg_temp.assert_reconciliation(not has_function_privilege('service_role',
 'public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text)','EXECUTE')
 and not has_function_privilege('authenticated','public.finalize_approved_reconciliation_v2(uuid)','EXECUTE')
 and not has_table_privilege('authenticated','collect_security.reconciliation_reviews','INSERT,UPDATE,DELETE'),
 'no direct financial or review mutation bypass');
set constraints all immediate;
select pg_temp.assert_reconciliation(true,'deferred journal balance constraints passed');
select 'RECONCILIATION_WORKFLOW_UAT_PASS' as result,count(*) as assertions from reconciliation_test_results;
rollback;
