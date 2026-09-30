\set ON_ERROR_STOP on
-- Run only after the staged receipt/reconciliation SQL has been installed on
-- an isolated, disposable clone of the complete current schema. This script
-- rolls back its synthetic rows; it is not production evidence.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'collect_financial_revocation_uat_20260928'
     or current_setting('collect.financial_rehearsal', true) is distinct from 'staged-v2'
     or to_regprocedure('public.finalize_approved_reconciliation_v2(uuid)') is null
     or exists(select 1 from public.payments)
     or exists(select 1 from public.raw_payment_sms) then
    raise exception 'Isolated staged-v2 financial rehearsal clone required';
  end if;
end $$;

create temp table test_results(label text primary key);
grant all on pg_temp.test_results to authenticated, service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end; $$;
create function pg_temp.expect_error(command text, fragment text, label text)
returns void language plpgsql as $$
declare caught text;
begin
  begin execute command; exception when others then caught := sqlerrm; end;
  perform pg_temp.assert_true(caught is not null and position(fragment in caught)>0,label);
end; $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values
 ('99600000-0000-4000-8000-000000000001','authenticated','authenticated','250788996001',now(),'{}','{}'),
 ('99600000-0000-4000-8000-000000000002','authenticated','authenticated','250788996002',now(),'{}','{}'),
 ('99600000-0000-4000-8000-000000000003','authenticated','authenticated','250788996003',now(),'{}','{}');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,approved_by,reason)
values
 ('99600000-0000-4000-8000-000000000001','+250788996001',now()-interval '2 minutes',null,'Synthetic maker approval'),
 ('99600000-0000-4000-8000-000000000002','+250788996002',now()-interval '2 minutes',null,'Synthetic checker approval');
insert into public.admin_user_roles(user_id,role_id,granted_by,reason,created_at)
select actor.id, role.id, null, 'Synthetic reconciliation rehearsal', now()-interval '1 minute'
from (values
 ('99600000-0000-4000-8000-000000000001'::uuid),
 ('99600000-0000-4000-8000-000000000002'::uuid)
) actor(id) cross join public.admin_roles role where role.name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
values
 ('99600000-0000-4000-8000-000000000011','99600000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour'),
 ('99600000-0000-4000-8000-000000000012','99600000-0000-4000-8000-000000000002',now(),now(),now()+interval '1 hour');
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,
 collection_type,contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin)
values ('99600000-0000-4000-8000-000000000021','financial-revocation-uat',
 '99600000-0000-4000-8000-000000000003','Synthetic financial UAT',
 'Family / friends','private','private','ikimina','members',false,false,'member_app');
insert into public.payments(id,collection_id,contributor_user_id,receiver_user_id,
 receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,source,status,anonymity_choice,posted_at)
values ('99600000-0000-4000-8000-000000000031','99600000-0000-4000-8000-000000000021',
 '99600000-0000-4000-8000-000000000003','99600000-0000-4000-8000-000000000003',
 repeat('a',64),1234,'REVOCATION1234','mtn_momo','manual_admin','review','anonymous',null);

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"99600000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2","session_id":"99600000-0000-4000-8000-000000000011"}',true);
select pg_temp.assert_true(public.has_admin_permission('payments.allocate'),
 'maker has current verified Admin authority');
select pg_temp.expect_error(format(
 'select public.propose_payment_reconciliation_v2(%L,%L,%L,now(),%L)',
 '99600000-0000-4000-8000-000000000031',repeat('b',64),'   ',
 'Synthetic independent evidence proposal'),
 'violates check constraint','blank evidence reference is rejected');
select public.propose_payment_reconciliation_v2(
 '99600000-0000-4000-8000-000000000031',repeat('b',64),
 'SYNTHETIC-PROVIDER-996001',now()-interval '1 minute',
 'Synthetic independent evidence proposal') as review_id \gset
select pg_temp.expect_error(format(
 'select public.approve_payment_reconciliation_v2(%L,%L)',
 :'review_id','Synthetic self approval is prohibited'),
 'Independent current approval required','maker cannot approve own evidence');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
 '{"sub":"99600000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2","session_id":"99600000-0000-4000-8000-000000000012"}',true);
select pg_temp.assert_true(public.has_admin_permission('payments.allocate'),
 'checker has current verified Admin authority');
select pg_temp.assert_true(public.approve_payment_reconciliation_v2(
 :'review_id'::uuid,'Synthetic independent checker approval'),
 'distinct current checker can approve');
reset role;

-- Simulate access withdrawal after approval, before settlement. The finalizer
-- must re-evaluate both actors, even though approval was valid when stored.
update public.admin_user_roles set revoked_at=clock_timestamp()
where user_id='99600000-0000-4000-8000-000000000002' and revoked_at is null;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_error(format(
 'select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 'Reconciliation actor access revoked','revoked checker cannot authorize posting');
reset role;
update public.admin_user_roles set revoked_at=null
where user_id='99600000-0000-4000-8000-000000000002';
update public.admin_user_roles set revoked_at=clock_timestamp()
where user_id='99600000-0000-4000-8000-000000000001' and revoked_at is null;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_error(format(
 'select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 'Reconciliation actor access revoked','revoked maker cannot authorize posting');
reset role;
update public.admin_user_roles set revoked_at=null
where user_id='99600000-0000-4000-8000-000000000001';
update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp()
where user_id='99600000-0000-4000-8000-000000000002';
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.expect_error(format(
 'select public.finalize_approved_reconciliation_v2(%L)',:'review_id'),
 'Reconciliation actor access revoked','revoked verified identity cannot authorize posting');
reset role;
select pg_temp.assert_true(
 (select status='review' and posted_at is null from public.payments
  where id='99600000-0000-4000-8000-000000000031')
 and not exists(select 1 from public.ledger_entries
  where payment_id='99600000-0000-4000-8000-000000000031')
 and not exists(select 1 from public.payment_provider_confirmations
  where payment_id='99600000-0000-4000-8000-000000000031')
 and (select consumed_at is null from collect_security.reconciliation_reviews where id=:'review_id'::uuid),
 'both revoked-actor attempts leave payment, ledger and approval unchanged');
select pg_temp.assert_true(
 not has_function_privilege('authenticated','public.finalize_approved_reconciliation_v2(uuid)','execute')
 and not has_function_privilege('service_role',
 'public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text)',
 'execute'),
 'client and legacy service finality entrypoints remain closed');
select 'RECONCILIATION_REVOCATION_UAT_PASS: '||count(*)||' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
