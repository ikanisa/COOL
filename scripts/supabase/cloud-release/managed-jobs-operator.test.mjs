import assert from 'node:assert/strict';
import {parseManagedReadiness,verifyNativeBudget} from './managed-jobs-operator.mjs';
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
