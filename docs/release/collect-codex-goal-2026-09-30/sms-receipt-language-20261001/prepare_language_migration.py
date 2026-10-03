#!/usr/bin/env python3
"""Generate an additive language migration from exact current predecessors."""
import hashlib,json,pathlib,re
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
STAGE=pathlib.Path(__file__).resolve().parent
NAME='20261001250000_sms_receipt_language_selection.sql'
captured={}
def sha(b):return hashlib.sha256(b).hexdigest()
def function(filename,name):
 p=ROOT/'supabase/migrations'/filename;b=p.read_bytes();captured[str(p.relative_to(ROOT))]=sha(b)
 m=re.search(r'create(?: or replace)? function '+re.escape(name)+r'\([\s\S]*?as (\$[A-Za-z_0-9]*\$)([\s\S]*?)\1;',b.decode(),re.I)
 assert m,name
 return m.group(0),m.group(2)
def replace(s,old,new):
 assert s.count(old)==1,(old,s.count(old));return s.replace(old,new)
def redef(s):return re.sub(r'^create(?: or replace)? function','create or replace function',s,count=1)
financial='20261001100000_receipt_financial_policy.sql'
governance='20260930150000_runtime_control_governance.sql'
bindings=[
 (governance,'collect_security.runtime_control_spec','text'),
 (governance,'collect_security.runtime_control_check_values','text,jsonb'),
 (financial,'collect_receipt_policy.render_v2','bigint,bigint,timestamp with time zone,text,text'),
 (financial,'collect_receipt_policy.render_snapshot','collect_hybrid.momo_balance_snapshots,integer,text'),
 (financial,'collect_receipt_policy.snapshot_is_eligible','collect_hybrid.momo_balance_snapshots'),
 (financial,'collect_receipt_policy.body_for_job','collect_hybrid.sms_notification_outbox'),
 (financial,'collect_receipt_policy.content_is_valid','collect_hybrid.sms_notification_outbox'),
 (financial,'collect_hybrid.enqueue_sms_receipt_from_snapshot',''),
 (financial,'collect_hybrid.sms_receipt_job_is_current','uuid'),
 (financial,'public.admin_get_collect_investigation_v1','text,uuid'),
 ('20261001110000_receipt_operational_authority.sql','collect_receipt_operations.ensure_snapshot','uuid,boolean,boolean'),
 ('20261001130000_android_dispatch_authority.sql','collect_gateway_dispatch.segment_count','text'),
 ('20260903091000_hybrid_verified_account_claim.sql','collect_hybrid.claim_verified_current_account','')]
functions={};guards=[]
for filename,name,args in bindings:
 definition,body=function(filename,name);functions[name]=definition
 guards.append((name+'('+args+')',sha(body.encode())))
guard_values=',\n'.join(" ('"+signature+"','"+digest+"')"for signature,digest in guards)
parts=["""begin;
-- Approved canonical translations only; immutable content2 and configuration1
-- remain distinct. This grants no dispatch, resend or historical catch-up.
select pg_advisory_xact_lock(193517,141);
select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
lock table collect_hybrid.sms_receipt_policies in access exclusive mode;
lock table collect_security.runtime_control_heads in share row exclusive mode;
do $guard$ declare expected record;oid_value oid;begin
 for expected in select * from(values
"""+guard_values+"""
 )v(signature,body_sha256)loop
  oid_value:=to_regprocedure(expected.signature);
  if oid_value is null or (select encode(extensions.digest(prosrc,'sha256'),'hex') from pg_proc where oid=oid_value)
   is distinct from expected.body_sha256 then
   raise exception 'receipt_language_predecessor_drift:%',expected.signature using errcode='55000';end if;
 end loop;
end $guard$;
create temporary table receipt_language_adoption on commit drop as
 select p.collection_id,to_jsonb(p) old_row,jsonb_build_object('collection_id',p.collection_id) identity,
  h.revision previous_revision,h.content_sha256 old_sha256
 from collect_hybrid.sms_receipt_policies p left join collect_security.runtime_control_heads h
 on h.family='sms_receipt_policies' and h.identity=jsonb_build_object('collection_id',p.collection_id);
do $capture$ begin
 if exists(select 1 from pg_temp.receipt_language_adoption a where a.previous_revision is null
  or a.previous_revision>=1000000000 or a.old_sha256 is distinct from collect_security.runtime_control_hash(a.old_row))then
  raise exception 'receipt_language_governance_adoption_invalid'using errcode='55000';end if;
end $capture$;
alter table collect_hybrid.sms_receipt_policies add column receipt_language text not null default 'rw'
 constraint sms_receipt_policies_receipt_language_check check(receipt_language in('rw','en','fr'));
-- ALTER supplies the compatible default without triggering a business UPDATE.
-- Adopt the changed full-row fingerprint through a genuine owner schema event.
insert into collect_security.runtime_control_events(family,identity_sha256,previous_revision,revision,
 operation,old_sha256,new_sha256,changed_fields,actor_id,session_id,authority,reason_sha256,redacted,reason_characters,recorded_at)
select 'sms_receipt_policies',collect_security.runtime_control_hash(a.identity),a.previous_revision,a.previous_revision+1,
 'update',a.old_sha256,collect_security.runtime_control_hash(to_jsonb(p)),array['receipt_language'],null,null,'database_owner',
 encode(extensions.digest('Adopt governed receipt language with rw-compatible schema default','sha256'),'hex'),false,
 char_length('Adopt governed receipt language with rw-compatible schema default'),transaction_timestamp()
from pg_temp.receipt_language_adoption a join collect_hybrid.sms_receipt_policies p using(collection_id);
do $adopt$ declare changed integer;begin
 update collect_security.runtime_control_heads h set revision=a.previous_revision+1,
 content_sha256=collect_security.runtime_control_hash(to_jsonb(p)),updated_at=transaction_timestamp()
 from pg_temp.receipt_language_adoption a join collect_hybrid.sms_receipt_policies p using(collection_id)
 where h.family='sms_receipt_policies' and h.identity=a.identity
 and h.revision=a.previous_revision and h.content_sha256=a.old_sha256;
 get diagnostics changed=row_count;
 if changed<>(select count(*)from pg_temp.receipt_language_adoption)or exists(
  select 1 from pg_temp.receipt_language_adoption a join collect_hybrid.sms_receipt_policies p using(collection_id)
  left join collect_security.runtime_control_heads h on h.family='sms_receipt_policies'and h.identity=a.identity
  where to_jsonb(p)-'receipt_language' is distinct from a.old_row or p.receipt_language<>'rw'
  or h.revision is distinct from a.previous_revision+1
  or h.content_sha256 is distinct from collect_security.runtime_control_hash(to_jsonb(p)))then
  raise exception 'receipt_language_governance_adoption_invalid'using errcode='55000';end if;
end $adopt$;
alter table collect_receipt_policy.content_evidence drop constraint content_evidence_language_check;
alter table collect_receipt_policy.content_evidence add constraint content_evidence_language_check
 check(language in('rw','en','fr'));
"""]
spec=functions['collect_security.runtime_control_spec'];old_json=re.search(r"select '(.*)'::jsonb -> p_family",spec).group(1)
registry=json.loads(old_json);registry['sms_receipt_policies']['writable'].append('receipt_language')
registry['sms_receipt_policies']['types']['receipt_language']='text'
parts.append(redef(replace(spec,old_json,json.dumps(registry,separators=(',',':'),ensure_ascii=False))))
check=functions['collect_security.runtime_control_check_values']
parts.append(redef(replace(check,"  if typ='text' then", "  if p_family='sms_receipt_policies'and field.key='receipt_language'and clean not in('rw','en','fr')then\n   raise exception 'receipt_language_invalid'using errcode='22023';end if;\n  if typ='text' then")))
parts.append("""create function collect_receipt_policy.language_for_job(p_job collect_hybrid.sms_notification_outbox)
returns text language sql stable security definer set search_path=''as $$
 select case when p_job.template_version=1 then 'rw'when p_job.template_version=2 then
  (select e.language from collect_receipt_policy.content_evidence e where e.outbox_id=p_job.id and e.content_version=2)
 else null end
$$;
create function collect_receipt_policy.render_snapshot(p_snapshot collect_hybrid.momo_balance_snapshots,
 p_version integer,p_reference text,p_language text)returns text language sql stable security definer set search_path=''as $$
 select case when p_version=1 then collect_hybrid.render_buri_munsi_receipt(p_snapshot.delta_rwf,
  p_snapshot.member_balance_after_rwf,p_snapshot.group_balance_after_rwf,p_reference)
 when p_version=2 and p_language in('rw','en','fr')then collect_receipt_policy.render_v2(
  p_snapshot.delta_rwf,p_snapshot.member_balance_after_rwf,p_snapshot.captured_at,p_reference,p_language)else null end
$$;
revoke all on function collect_receipt_policy.language_for_job(collect_hybrid.sms_notification_outbox),
 collect_receipt_policy.render_snapshot(collect_hybrid.momo_balance_snapshots,integer,text,text)
 from public,anon,authenticated,service_role;
""")
body=functions['collect_receipt_policy.body_for_job']
parts.append(redef(replace(body,'render_snapshot(s,p_job.template_version,p_job.reference)',
 'render_snapshot(s,p_job.template_version,p_job.reference,collect_receipt_policy.language_for_job(p_job))')))
valid=functions['collect_receipt_policy.content_is_valid']
valid=replace(valid,"e.language='rw'","e.language in('rw','en','fr')")
valid=replace(valid,'render_snapshot(s,2,p_job.reference)','render_snapshot(s,2,p_job.reference,e.language)')
parts.append(redef(valid))
claim=functions['collect_hybrid.claim_verified_current_account']
claim=replace(claim,'where item.id = identity.member_id\n  for update;',
 'where item.id = identity.member_id\n  for no key update;')
parts.append('-- Account claiming changes association, never the member key. The\n'
 '-- non-key lock still excludes competing edits/deletes/claims but permits\n'
 '-- financial INSERT foreign-key checks while claim waits on a payment.\n'+redef(claim))
enqueue=functions['collect_hybrid.enqueue_sms_receipt_from_snapshot']
enqueue=replace(enqueue,' if not collect_receipt_policy.snapshot_is_eligible(new)then return new;end if;',
 " if not collect_receipt_policy.snapshot_is_eligible(new)then return new;end if;\n -- Account claiming locks contact/member before payments. Never wait on an\n -- inverse-order recipient lock while financial posting owns the payment.\n -- Busy selection defers to the durable payment event/snapshot backlog; it\n -- does not mark the event handled or abort the financial transaction.\n begin\n perform 1 from public.payments where id=new.payment_id for update nowait;\n perform 1 from public.collections where id=new.collection_id for share nowait;\n perform 1 from collect_hybrid.member_records where id=new.member_record_id for share nowait;\n perform 1 from public.collection_members where collection_id=new.collection_id and member_record_id=new.member_record_id for share nowait;\n if not collect_receipt_policy.snapshot_is_eligible(new)then return new;end if;")
enqueue=replace(enqueue,"  and enabled and template_key='buri_munsi.payment_received'and template_version=1;", "  and enabled and template_key='buri_munsi.payment_received'and template_version=1 for share nowait;")
enqueue=replace(enqueue,'where member_record_id=new.member_record_id and enabled;','where member_record_id=new.member_record_id and enabled for share nowait;')
enqueue=replace(enqueue,'where member_id=new.member_record_id;','where member_id=new.member_record_id for share nowait;')
enqueue=replace(enqueue,' if identity.member_id is null then return new;end if;',
 ' if identity.member_id is null then return new;end if;\n exception when lock_not_available then return new;\n end;')
enqueue=replace(enqueue,"new.captured_at,reference_value,'rw')",'new.captured_at,reference_value,policy.receipt_language)')
enqueue=replace(enqueue,"values(job_id,2,'rw',new.captured_at",'values(job_id,2,policy.receipt_language,new.captured_at')
parts.append(redef(enqueue))
ensure=functions['collect_receipt_operations.ensure_snapshot']
ensure=replace(ensure,"s.captured_at,ref,'rw')",'s.captured_at,ref,policy.receipt_language)')
ensure=replace(ensure,"values(job_id,2,'rw',s.captured_at",'values(job_id,2,policy.receipt_language,s.captured_at')
parts.append(redef(ensure))
current=functions['collect_hybrid.sms_receipt_job_is_current']
current=replace(current,'  and policy.enabled and policy.revision=job.policy_revision and policy.template_key=job.template_key',
 '  and policy.receipt_language=collect_receipt_policy.language_for_job(job)\n  and policy.enabled and policy.revision=job.policy_revision and policy.template_key=job.template_key')
parts.append(redef(current))
preview=functions['public.admin_get_collect_investigation_v1']
preview=replace(preview,"render_snapshot(s,o.template_version,'snapshot-'||right(s.id::text,8))",
 "render_snapshot(s,o.template_version,'snapshot-'||right(s.id::text,8),collect_receipt_policy.language_for_job(o))")
parts.append(redef(preview))
segments=functions['collect_gateway_dispatch.segment_count']
segments=replace(segments,'^[A-Za-z0-9 .,/:_-]+$','^[A-Za-z0-9 Éé.,/:_-]+$')
parts.append('-- The approved renderer adds only É and é, both one default GSM septet.\n'
 '-- Keep the narrow alphabet, byte bound and native divideMessage equality.\n'+redef(segments))
parts.append('commit;\n')
out=STAGE/NAME;out.write_text('\n\n'.join(parts))
(STAGE/'predecessor-bindings.json').write_text(json.dumps({'source_files':captured,'function_body_guards':guards,'migration_sha256':sha(out.read_bytes())},indent=2)+'\n')
print('Generated',out.name,'bytes',out.stat().st_size,'guards',len(guards),'SHA256',sha(out.read_bytes()))
