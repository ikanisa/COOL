import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {decodeAncillaryRegistration} from './ancillary-inventory.mjs';
import {createNativeConfigIntent,requireNativeConfigPreimage,createNativeConfigBridge,requireNativeConfigReadback} from './native-config-proof.mjs';
const sha=x=>createHash('sha256').update(x).digest('hex'),source='a'.repeat(64),evidence='b'.repeat(64),project='rrlduytparvsjfmegalh';
const side={slug:'collect-sms',id:'00000000-0000-4000-8000-000000000008',version:3,status:'ACTIVE',verify_jwt:false,
 ezbr_sha256:'c'.repeat(64),sourceSha256:'d'.repeat(64)};
const core=['collect-api','admin-api','collect-jobs'].map((slug,i)=>({slug,id:`00000000-0000-4000-8000-00000000000${i+1}`,
 version:4,status:'ACTIVE',verify_jwt:false,ezbr_sha256:'e'.repeat(64)}));
const proof=item=>{const bytes=Buffer.from(JSON.stringify({format:'collect.cloud-ancillary-inventory.v1',project,
 reviewedEvidenceSha256:'f'.repeat(64),functions:[item]}));return decodeAncillaryRegistration(bytes,sha(bytes));};
const provider=({sourceSha256,...x})=>x;
function fixture(){
 const changes=[{name:'MOMO_AI_ENABLED',value:'true'},{name:'MOMO_AI_MODEL',value:'synthetic-model'},
  {name:'COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256',value:'1'.repeat(64)},{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:'true'}];
 const pre={source,functions:[...structuredClone(core),provider(side)],ancillaryRegistration:proof(side),
  row:{enabled:true,active:true,pending:0,native_provider_source_sha256:source,native_provider_model_id:'synthetic-model',
   native_provider_approval_sha256:'1'.repeat(64),native_provider_used:'5',native_provider_limit:'400',native_provider_expires_at:null},
  secrets:new Map(Object.entries({BUILD_SOURCE_ID:sha(source),COLLECT_SMS_ENABLED:sha('true'),COLLECT_SMS_DISPATCH_PAUSED:sha('false'),
   BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:sha('false'),MOMO_AI_ENABLED:sha('true'),MOMO_AI_MODEL:sha('synthetic-model'),
   COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256:sha('1'.repeat(64)),OTHER_SECRET:sha('fixture-credential-never-logged')}))};
 const intent=createNativeConfigIntent(pre,evidence,changes),attempt={intentSha256:sha(JSON.stringify(intent)),at:'fixture'},
  ack={attemptSha256:sha(JSON.stringify(attempt)),status:201,at:'fixture'};
 function apply(){for(const change of changes)pre.secrets.set(change.name,sha(change.value));pre.row.enabled=false;pre.row.active=false;}
 function bump(change=x=>x){const next=change({...side,version:side.version+1});pre.ancillaryRegistration=proof(next);
  pre.functions=pre.functions.map(x=>x.slug==='collect-sms'?provider(next):x);}
 return {pre,intent,attempt,ack,changes,apply,bump};
}

test('acknowledged native configuration can be confirmed without any retry',()=>{
 const f=fixture();requireNativeConfigPreimage(f.intent,f.pre);f.apply();
 assert.equal(requireNativeConfigReadback(f.intent,f.attempt,f.ack,f.pre,evidence),true);
});
test('version change requires an exact explicit bridge and only hashes are retained',()=>{
 const f=fixture();f.apply();f.bump();assert.throws(()=>requireNativeConfigReadback(f.intent,f.attempt,f.ack,f.pre,evidence));
 const bridge=createNativeConfigBridge(f.intent,f.attempt,f.ack,f.pre,evidence);
 assert.equal(requireNativeConfigReadback(f.intent,f.attempt,f.ack,f.pre,evidence,bridge),true);
 assert(!JSON.stringify(f.intent).includes('fixture-credential-never-logged'));assert(!JSON.stringify(bridge).includes('fixture-credential-never-logged'));
});
test('an unacknowledged, altered, or non-successful provider call cannot be bridged',()=>{
 for(const mutate of [f=>f.ack=null,f=>f.ack.status=500,f=>f.ack.attemptSha256='0'.repeat(64),
  f=>f.attempt.intentSha256='0'.repeat(64),f=>f.pre.secrets.delete('MOMO_AI_MODEL'),
  f=>f.pre.secrets.set('MOMO_AI_MODEL',sha('other')),f=>f.pre.secrets.set('OTHER_SECRET',sha('changed')),
  f=>f.pre.secrets.set('EXTRA_SECRET',sha('extra')),f=>f.pre.secrets.set('COLLECT_SMS_DISPATCH_PAUSED',sha('true')),
  f=>f.pre.row.active=true,f=>f.pre.row.pending=1,f=>f.pre.row.native_provider_used='6',f=>f.pre.source='0'.repeat(64)]){
  const f=fixture();f.apply();f.bump();mutate(f);
  assert.throws(()=>createNativeConfigBridge(f.intent,f.attempt,f.ack,f.pre,evidence));
 }
});
test('no executable, role, status, id, source or version rollback can be bridged',()=>{
 for(const mutate of [x=>x.ezbr_sha256='0'.repeat(64),x=>x.id='00000000-0000-4000-8000-000000000009',
  x=>x.verify_jwt=true,x=>x.sourceSha256='0'.repeat(64),x=>x.version=2]){
  const f=fixture();f.apply();f.bump(x=>{mutate(x);return x;});
  assert.throws(()=>createNativeConfigBridge(f.intent,f.attempt,f.ack,f.pre,evidence));
 }
 const f=fixture();f.apply();f.bump();f.pre.functions.find(x=>x.slug==='collect-sms').status='INACTIVE';
 assert.throws(()=>createNativeConfigBridge(f.intent,f.attempt,f.ack,f.pre,evidence));
});
test('proof is bound to intent, acknowledgement, immutable provider budget and exact evidence',()=>{
 for(const mutation of ['ack','intent','budget','evidence','proof']){
  const f=fixture();f.apply();f.bump();const bridge=createNativeConfigBridge(f.intent,f.attempt,f.ack,f.pre,evidence);
  if(mutation==='ack')f.ack.status=200;if(mutation==='intent')f.intent.expected.MOMO_AI_ENABLED=sha('false');
  if(mutation==='budget')f.pre.row.native_provider_limit='401';if(mutation==='proof')bridge.previousDigest='0'.repeat(64);
  assert.throws(()=>requireNativeConfigReadback(f.intent,f.attempt,f.ack,f.pre,mutation==='evidence'?'0'.repeat(64):evidence,bridge));
 }
});
test('invalid pause and non-native configuration values cannot create an intent',()=>{
 const f=fixture();f.pre.secrets.set('COLLECT_SMS_DISPATCH_PAUSED',sha('true'));
 assert.throws(()=>createNativeConfigIntent(f.pre,evidence,f.changes));
 f.pre.secrets.set('COLLECT_SMS_DISPATCH_PAUSED',sha('false'));f.changes[0].value='false';
 assert.throws(()=>createNativeConfigIntent(f.pre,evidence,f.changes));
});
