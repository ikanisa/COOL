import assert from 'node:assert/strict';
import {parseManagedReadiness} from './managed-jobs-operator.mjs';
const now=Date.now(),base={format:'collect.jobs.readiness.v1',project_ref:'rrlduytparvsjfmegalh',endpoint:'https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs',
 deployment_sha256:'1'.repeat(64),runtime_evidence_sha256:'2'.repeat(64),token_custody_evidence_sha256:'3'.repeat(64),copy_inventory_evidence_sha256:'4'.repeat(64),quota_evidence_sha256:'5'.repeat(64),
 verified_at:new Date(now).toISOString(),momo_processing_paused:true,remaining_invocations:10000};
const admission={contract:'collect.native-sms-automation.v1',source_sha256:'a'.repeat(64),approval_sha256:'b'.repeat(64),model_id:'fixture-model',batch_limit:1};
const native={...base,native_sms_admission:admission,native_provider_evidence_sha256:'c'.repeat(64),native_guard_evidence_sha256:'d'.repeat(64),remaining_native_provider_requests:400};
const parse=x=>parseManagedReadiness(Buffer.from(JSON.stringify(x)),now);
assert.equal(parse(base).native,false);assert.equal(parse(native).native,true);
for(const bad of [{...native,native_sms_admission:{...admission,batch_limit:2}},{...native,native_sms_admission:{...admission,model_id:'bad\nmodel'}},
 {...native,native_sms_admission:{...admission,extra:true}},{...native,native_guard_evidence_sha256:null},
 {...native,remaining_native_provider_requests:1},{...native,remaining_native_provider_requests:401},{...base,native_provider_evidence_sha256:'c'.repeat(64)},
 {...base,remaining_invocations:9999},{...base,verified_at:new Date(now-3601000).toISOString()},
 {...base,endpoint:'https://wrong.example'}])assert.throws(()=>parse(bad));
console.log(JSON.stringify({suite:'managed-jobs-operator-readiness',checks:12,network_calls:0}));
