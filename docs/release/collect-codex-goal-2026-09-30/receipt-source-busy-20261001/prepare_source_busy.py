#!/usr/bin/env python3
"""Prepare narrow source-contention maintenance from exact accepted predecessors."""
import hashlib,json,pathlib,re,shutil
ROOT=pathlib.Path('/Volumes/PRO-G40/Projects/Recovered-G-PRO/COOL')
STAGE=pathlib.Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
originals={}
def capture(path):
 b=path.read_bytes();rel=str(path.relative_to(ROOT));originals[rel]=sha(b)
 dest=STAGE/'originals'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
 return b.decode()
def definition(text,name):
 found=re.search(r'create(?: or replace)? function '+re.escape(name)+r'\([\s\S]*?as (\$[A-Za-z_0-9]*\$)([\s\S]*?)\1;',text,re.I)
 assert found,name
 return found.group(0),found.group(2)
language=ROOT/'supabase/migrations/20261001250000_sms_receipt_language_selection.sql'
if not language.exists():language=ROOT/'.cache/sms-receipt-language-20261001'/language.name
assert sha(language.read_bytes())=='ee3168ff191a9ba9a623fb4d31ca2b1d3f354f44d0d617824786e41fdc8f1d8e'
lang=language.read_text();(STAGE/'accepted250.sql').write_bytes(language.read_bytes())
ensure,ensure_body=definition(lang,'collect_receipt_operations.ensure_snapshot')
source_def,source_body=definition(capture(ROOT/'supabase/migrations/20261001140000_receipt_deferral_exceptions.sql'),'collect_ops.receipt_exception_source')
bounded=capture(ROOT/'supabase/migrations/20261001210000_receipt_worker_bounded_sweep.sql')
section=bounded.split("body:=pg_get_functiondef('collect_ops.receipt_exception_source(text,uuid)'::regprocedure);")[1].split("body:=pg_get_functiondef",1)[0]
needle,replacement=re.findall(r'(?:needle|replacement):=\$patch\$([\s\S]*?)\$patch\$;',section)
assert source_body.count(needle)==1
source_body=source_body.replace(needle,replacement)
old_start=" -- Canonical payment lock fences posting/reversal; current contact, policy and\n -- consent locks fence changes until immutable enqueue and its proof commit.\n select * into p from public.payments where id=s.payment_id for update;"
new_start=" -- A caught subtransaction releases any earlier row locks on contention.\n -- No receipt, proof or handling acknowledgement is written on SOURCE_BUSY.\n -- Successful locks still fence posting, reversal, membership and policy\n -- until the caller durably commits its immutable receipt and evidence.\n begin\n select * into p from public.payments where id=s.payment_id for update nowait;"
assert ensure.count(old_start)==1
updated=ensure.replace(old_start,new_start)
updated=updated.replace("template_key='buri_munsi.payment_received'for update;","template_key='buri_munsi.payment_received'for update nowait;")
updated=updated.replace(' for share;',' for share nowait;')
end=" select * into settings from collect_receipt_operations.policy where singleton;"
assert updated.count(end)==1
updated=updated.replace(end,end+"\n exception when lock_not_available then\n  return jsonb_build_object('ok',false,'code','SOURCE_BUSY','business_handled',false,'receipt_id',null);\n end;")
assert updated.count('nowait;')==8
allowed="'CATCHUP_WINDOW_EXCEEDED','CONTENT_REFUSED','LEGACY_CONTENT_REVIEW_REQUIRED','QUOTA_EXHAUSTED')then"
assert source_body.count(allowed)==1
reason_text=re.search(r'add constraint exceptions_reason_code_check\s+check\(reason_code in\((.*?)\)\);',(STAGE/'originals/supabase/migrations/20261001140000_receipt_deferral_exceptions.sql').read_text(),re.S).group(1)
codes=re.findall(r"'([^']+)'",reason_text)
expected_constraint="CHECK ((reason_code = ANY (ARRAY["+', '.join("'"+c+"'::text"for c in codes)+"])))"
guards=[('collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)',sha(ensure_body.encode())),('collect_ops.receipt_exception_source(text,uuid)',sha(source_body.encode()))]
guardvalues=',\n'.join(" ('"+name+"','"+digest+"')"for name,digest in guards)
new_source_body=source_body.replace(allowed,"'CATCHUP_WINDOW_EXCEEDED','CONTENT_REFUSED','LEGACY_CONTENT_REVIEW_REQUIRED','QUOTA_EXHAUSTED','SOURCE_BUSY')then")
source_new=re.sub(r'^create function','create or replace function',source_def,count=1)
original_body=definition(source_def,'collect_ops.receipt_exception_source')[1]
source_new=source_new.replace(original_body,new_source_body)
sql="""begin;
-- Ordinary-owner, additive source-contention maintenance. The receipt worker
-- records a bounded durable deferral and leaves business work unhandled.
select pg_advisory_xact_lock(hashtext('collect-receipt-exception-worker'));
lock table collect_ops.exceptions in share row exclusive mode;
do $guard$ declare expected record;oid_value oid;actual_constraint text;begin
 for expected in select * from(values
"""+guardvalues+"""
 )v(signature,body_sha256)loop
  oid_value:=to_regprocedure(expected.signature);
  if oid_value is null or (select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc where oid=oid_value)
   is distinct from expected.body_sha256 then
   raise exception 'receipt_source_busy_predecessor_drift:%',expected.signature using errcode='55000';end if;
 end loop;
 select pg_get_constraintdef(oid)into actual_constraint from pg_constraint
 where conrelid='collect_ops.exceptions'::regclass and conname='exceptions_reason_code_check'
  and contype='c'and convalidated and not connoinherit;
 if actual_constraint is distinct from $expected$"""+expected_constraint+"""$expected$then
  raise exception 'receipt_source_busy_constraint_drift'using errcode='55000';end if;
end $guard$;
alter table collect_ops.exceptions drop constraint exceptions_reason_code_check;
alter table collect_ops.exceptions add constraint exceptions_reason_code_check
 check(reason_code in("""+reason_text+",'RECEIPT_OPERATION_SOURCE_BUSY'));\n\n"+updated+'\n\n'+source_new+'\ncommit;\n'
dest=STAGE/'supabase/migrations/20261001260000_receipt_source_busy_deferral.sql';dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(sql)
for rel,old,new in [
 ('supabase/functions/collect-receipt-supervisor/operations_contract.ts','  "SOURCE_CHANGED",','  "SOURCE_CHANGED",\n  "SOURCE_BUSY",'),
 ('tools/collect-notification-mcp/src/unattended_contract.ts','"SOURCE_CHANGED",','"SOURCE_CHANGED", "SOURCE_BUSY",'),
 ('lib/admin/core/admin_exception_models.dart',"  'SOURCE_CHANGED': 'Receipt source changed',","  'SOURCE_CHANGED': 'Receipt source changed',\n  'SOURCE_BUSY': 'Receipt source is busy',")]:
 text=capture(ROOT/rel);assert text.count(old)==1,rel
 out=STAGE/rel;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(text.replace(old,new))
edge=STAGE/'supabase/functions/collect-receipt-supervisor/operations_contract.ts'
text=edge.read_text();old='    return value.business_handled === handled &&';assert text.count(old)==1
edge.write_text(text.replace(old,old+"\n      (value.code !== \"SOURCE_BUSY\" || value.receipt_id === null) &&"))
mcp=STAGE/'tools/collect-notification-mcp/src/unattended_contract.ts'
text=mcp.read_text();old='    (value.receipt_id === null || uuid(value.receipt_id)) &&';assert text.count(old)==1
mcp.write_text(text.replace(old,old+'\n    (value.code !== "SOURCE_BUSY" || value.receipt_id === null) &&'))
rel='lib/admin/core/admin_receipt_deferral_models.dart';text=capture(ROOT/rel)
old="    if (handled != (disposition == 'durably_handled') ||";assert text.count(old)==1
text=text.replace(old,old+"\n        current == 'SOURCE_BUSY' && receipt != null ||")
out=STAGE/rel;out.parent.mkdir(parents=True,exist_ok=True);out.write_text(text)
(STAGE/'predecessor-bindings.json').write_text(json.dumps(dict(accepted250_sha256=sha(language.read_bytes()),inputs=originals,guards=guards,constraint_definition_sha256=sha(expected_constraint.encode()),outputs={str(p.relative_to(STAGE)):sha(p.read_bytes())for p in [dest]+[STAGE/x for x in originals if x.endswith('.ts')or x.endswith('.dart')]}),indent=2)+'\n')
print(json.dumps(dict(migration_sha256=sha(sql.encode()),guards=guards,source_locks=8)))
