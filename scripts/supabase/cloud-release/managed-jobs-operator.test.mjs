import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {parseManagedReadiness,verifyNativeBudget,schedulerGuardDigests} from './managed-jobs-operator.mjs';
const migration=readFileSync(new URL('../../../supabase/migrations/20261117210000_burimunsi_held_recovery.sql',import.meta.url));
const migrationDigest=createHash('sha256').update(migration).digest('hex');
const baselineGuards=schedulerGuardDigests(null,null),heldGuards=schedulerGuardDigests(migrationDigest,migrationDigest);
assert.notEqual(heldGuards['private.burimunsi_auto_snapshot(text)'],baselineGuards['private.burimunsi_auto_snapshot(text)']);
assert(heldGuards['private.collect_sms_recovery_held(text)']);
assert.throws(()=>schedulerGuardDigests(migrationDigest,'0'.repeat(64)));
assert.throws(()=>schedulerGuardDigests('0'.repeat(64),migrationDigest));
assert.throws(()=>schedulerGuardDigests(undefined,migrationDigest));
const digest=body=>createHash('sha256').update(body).digest('hex');
const loadMigration=name=>readFileSync(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8');
const imported=loadMigration('20261117071343_collect_burimunsi_import_lineage_guard.sql'),held=migration.toString('utf8');
const sourceBody=(source,name)=>{
 const start=source.indexOf('CREATE FUNCTION private.'+name+'('),open=source.indexOf('$fn$',start),close=source.indexOf('$fn$;',open+4);
 assert(start>=0&&open>=0&&close>=0);return source.slice(open+4,close);
};
for(const [name,file,signature] of [
 ['burimunsi_auto_snapshot','20261112200100_burimunsi_native_auto_transactions.sql','private.burimunsi_auto_snapshot(text)'],
 ['burimunsi_auto_candidates','20261112200100_burimunsi_native_auto_transactions.sql','private.burimunsi_auto_candidates(text)'],
 ['burimunsi_native_work_candidates','20261113130300_burimunsi_native_financial_work.sql','private.burimunsi_native_work_candidates(uuid,integer)'],
 ['burimunsi_native_sms_post_candidates','20261113130900_burimunsi_native_sms_posting.sql','private.burimunsi_native_sms_post_candidates(integer)']
]){
 let body=sourceBody(loadMigration(file),name);
 const pre=new RegExp(`\\('private\\.${name}\\([^']*\\)',\\s*\\$old\\$([\\s\\S]*?)\\$old\\$,\\s*\\$new\\$([\\s\\S]*?)\\$new\\$\\)`).exec(imported);
 const post=new RegExp(`\\('private\\.${name}\\([^']*\\)','([a-f0-9]+)',\\s*\\$old\\$([\\s\\S]*?)\\$old\\$,\\s*\\$new\\$([\\s\\S]*?)\\$new\\$\\)`).exec(held);
 assert(pre&&post);assert.equal(body.split(pre[1]).length,2);body=body.replace(pre[1],pre[2]);
 assert.equal(digest(body),baselineGuards[signature]);assert.equal(digest(body),post[1]);
 assert.equal(body.split(post[2]).length,2);body=body.replace(post[2],post[3]);
 assert.equal(digest(body),heldGuards[signature]);
}
for(const [name,signature] of [
 ['collect_sms_held_source_guard','private.collect_sms_held_source_guard()'],
 ['collect_sms_recovery_held','private.collect_sms_recovery_held(text)'],
 ['collect_sms_recovery_work_guard','private.collect_sms_recovery_work_guard()'],
 ['collect_sms_recovery_raw_work_guard','private.collect_sms_recovery_raw_work_guard()'],
 ['collect_sms_witness_reserve','private.collect_sms_witness_reserve(text,text,text,text,text,text,timestamptz,text)'],
 ['burimunsi_sms_recovery_hold','private.burimunsi_sms_recovery_hold(text,uuid,text,text,timestamptz)'],
 ['burimunsi_sms_recovery_ack_snapshot','private.burimunsi_sms_recovery_ack_snapshot(text,uuid,text,text,text,text,timestamptz)'],
 ['burimunsi_observation_reconcile_verified_status','private.burimunsi_observation_reconcile_verified_status()']
])assert.equal(digest(sourceBody(held,name)),heldGuards[signature]);
assert.equal(digest(sourceBody(loadMigration('20261117180000_burimunsi_observation_reconcile_status.sql'),
 'burimunsi_observation_reconcile_status')),heldGuards['private.burimunsi_observation_reconcile_status()']);
for(const [name,signature] of [
 ['burimunsi_observation_actor','private.burimunsi_observation_actor(boolean)'],
 ['burimunsi_observation_consent_current','private.burimunsi_observation_consent_current()'],
 ['burimunsi_observation_own','private.burimunsi_observation_own(text,boolean)'],
 ['burimunsi_observation_lookup','private.burimunsi_observation_lookup(uuid,text)']
])assert.equal(digest(sourceBody(loadMigration('20261111121000_burimunsi_private_observations.sql'),name)),heldGuards[signature]);
const now=Date.now(),base={format:'collect.jobs.readiness.v1',project_ref:'rrlduytparvsjfmegalh',endpoint:'https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs',
 deployment_sha256:'1'.repeat(64),runtime_evidence_sha256:'2'.repeat(64),token_custody_evidence_sha256:'3'.repeat(64),copy_inventory_evidence_sha256:'4'.repeat(64),quota_evidence_sha256:'5'.repeat(64),
 verified_at:new Date(now).toISOString(),momo_processing_paused:true,remaining_invocations:50000};
const admission={contract:'collect.native-sms-automation.v1',source_sha256:'a'.repeat(64),approval_sha256:'b'.repeat(64),model_id:'fixture-model',batch_limit:1};
const native={...base,native_sms_admission:admission,native_provider_evidence_sha256:'c'.repeat(64),native_guard_evidence_sha256:'d'.repeat(64),remaining_native_provider_requests:null};
const parse=x=>parseManagedReadiness(Buffer.from(JSON.stringify(x)),now);
assert.equal(parse(base).native,false);assert.equal(parse(native).native,true);assert.equal(parse({...native,remaining_native_provider_requests:1000}).native,true);
for(const bad of [{...native,native_sms_admission:{...admission,batch_limit:2}},{...native,native_sms_admission:{...admission,model_id:'bad\nmodel'}},
 {...native,native_sms_admission:{...admission,extra:true}},{...native,native_guard_evidence_sha256:null},
 {...native,remaining_native_provider_requests:1},{...native,remaining_native_provider_requests:'1000'},{...base,native_provider_evidence_sha256:'c'.repeat(64)},
 {...base,remaining_invocations:49999},{...base,verified_at:new Date(now-3601000).toISOString()},
 {...base,endpoint:'https://wrong.example'}])assert.throws(()=>parse(bad));
const row={native_provider_source_sha256:admission.source_sha256,native_provider_model_id:admission.model_id,native_provider_approval_sha256:admission.approval_sha256,
 native_provider_used:'401',native_provider_limit:null,native_provider_expires_at:null};
const pre={source:admission.source_sha256,row};
verifyNativeBudget(pre,native,now);
verifyNativeBudget({...pre,row:{...row,native_provider_limit:'500',native_provider_expires_at:new Date(now+1000)}},{...native,remaining_native_provider_requests:99},now);
for(const bad of [
 {row:{...row,native_provider_used:'9007199254740992'},ready:native},
 {row:{...row,native_provider_used:'-1'},ready:native},
 {row:{...row,native_provider_limit:'500'},ready:native},
 {row:{...row,native_provider_limit:'500'},ready:{...native,remaining_native_provider_requests:100}},
 {row:{...row,native_provider_expires_at:new Date(now-1)},ready:native},
 {row:{...row,native_provider_expires_at:'bad'},ready:native},
 {row:{...row,native_provider_model_id:'other'},ready:native},
 {row:{...row,native_provider_approval_sha256:'e'.repeat(64)},ready:native},
 {row:{...row,native_provider_source_sha256:'f'.repeat(64)},ready:native},
])assert.throws(()=>verifyNativeBudget({...pre,row:bad.row},bad.ready,now));
console.log(JSON.stringify({suite:'managed-jobs-operator-readiness',checks:24,network_calls:0}));
