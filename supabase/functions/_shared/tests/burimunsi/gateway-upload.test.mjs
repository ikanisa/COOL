import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {uploadFixture,I,OLD,SMS} from './gateway-upload-fixture.mjs';
import {momoGatewayRoute} from '../../domain/momo_gateway.js';
import {validateMomoExtraction} from '../../domain/momo_pipeline.js';
import {nativeGatewayUploadsEnabled} from '../../gateway-upload-hold.js';
import {commitNativeGatewayCapture} from '../../domain/burimunsi/postgres-gateway-upload.js';

test('both native and upload flags require exact explicit opt-in',()=>{
 for(const native of [undefined,'false','TRUE',true,'true'])for(const upload of [undefined,'false','TRUE',true,'true'])
  assert.equal(nativeGatewayUploadsEnabled({BURIMUNSI_NATIVE_ENABLED:native,BURIMUNSI_NATIVE_UPLOADS_ENABLED:upload}),native==='true'&&upload==='true');
});
test('approved alternate payment format reaches the existing extraction queue without a ledger posting',async t=>{
 const f=await uploadFixture();t.after(f.close);
 const fixture=JSON.parse(readFileSync(new URL('../../../../../deploy/platform-api/test/fixtures/momo-synthetic.json',import.meta.url),'utf8'));
 const profile=fixture.profile;
 f.execute('UPDATE app.momo_receiving_accounts SET profile_json=?',JSON.stringify(profile));
 const candidate=fixture.body;
 const ack=await(await f.invokeUpload({raw_sender:fixture.sender,raw_body:candidate})).json();
 assert.equal(ack.receipt.stored,true);assert.equal(f.count('app.sms_receipts'),1);assert.equal(f.count('app.momo_processing_jobs'),1);
 assert.equal(f.sources().length,1);assert.equal([...f.upload.objects.values()][0].value.includes(candidate),false);
 assert.equal(f.count('app.momo_gateway_captures'),1);
 const account={status:'active',profile_status:'approved',profile_version:'fixture-approved-v1',profile_json:JSON.stringify(profile),currency:'RWF',provider:'mtn_momo',timezone:'Africa/Kigali'};
 assert.equal(validateMomoExtraction(fixture.output,{raw_sender:fixture.sender,raw_body:candidate,completeness:'complete'},account).accepted,true);
});
test('actual upload route retains one encrypted scoped capture and exact duplicate ACK without a second PUT',async t=>{
 const f=await uploadFixture();t.after(f.close);
 const response=await f.invokeUpload(),ack=await response.json();assert.equal(response.status,200);assert.equal(ack.receipt.stored,true);
 assert.equal(ack.receipt.contract_version,2);assert.equal(ack.receipt.owner_user_id,I.principal);
 assert.equal(f.count('app.sms_receipts'),1);assert.equal(f.count('app.momo_processing_jobs'),1);assert.equal(f.sources().length,1);
 assert.equal(f.sources()[0].collection_id,I.group);assert.equal(f.sources()[0].binding_id,OLD);assert.equal(f.sources()[0].installation_id,I.installation);
 assert.equal(f.upload.puts,1);assert.equal([...f.upload.objects.values()][0].value.includes(SMS),false);
 const retry=await(await f.invokeUpload()).json();assert.deepEqual(retry,ack);assert.equal(f.upload.puts,1);assert.equal(f.count('app.sms_receipts'),1);
 assert.ok(f.upload.readOnlyReconciliations>=2);assert.equal(f.count('private.burimunsi_sessions'),1,'No native session is fabricated');
});
test('post-binding inbox catch-up is retained as incomplete without claiming a live PDU',async t=>{
 const f=await uploadFixture();t.after(f.close);
 const body={source_mode:'catch_up',complete:false};
 const ack=await(await f.invokeUpload(body)).json();assert.equal(ack.receipt.stored,true);
 const capture=f.sqlite.prepare('SELECT completeness,source_mode FROM app.momo_gateway_captures').get();
 assert.deepEqual({...capture},{completeness:'incomplete',source_mode:'catch_up'});
 assert.equal(f.count('app.sms_receipts'),1);assert.equal(f.count('app.momo_processing_jobs'),1);assert.equal(f.sources().length,1);
 const retry=await(await f.invokeUpload(body)).json();assert.deepEqual(retry,ack);assert.equal(f.count('app.sms_receipts'),1);assert.equal(f.upload.puts,1);
 const profile=JSON.parse(f.sqlite.prepare('SELECT profile_json FROM app.momo_receiving_accounts WHERE id=?').get('wallet-1').profile_json);
 const account={status:'active',profile_status:'approved',profile_version:'fixture-approved-v1',profile_json:JSON.stringify(profile),currency:'RWF',provider:'mtn_momo',timezone:'Africa/Kigali'};
 const validation=validateMomoExtraction({}, {raw_sender:'M-Money',raw_body:SMS,completeness:'incomplete'},account);
 assert.equal(validation.accepted,false);assert(validation.errors.some(e=>e.code==='incomplete_source'));
});
for(const change of ['native-off','uploads-off','disabled-scope','revoked-grant','wrong-profile','removed-account','unapproved-operator','revoked-credential','scope-reassigned'])
 test('before-body authority denies '+change,async t=>{
  const f=await uploadFixture();t.after(f.close);
  if(change==='native-off')f.env.BURIMUNSI_NATIVE_ENABLED='false';
  if(change==='uploads-off')f.env.BURIMUNSI_NATIVE_UPLOADS_ENABLED='false';
  if(change==='disabled-scope')f.execute('UPDATE private.burimunsi_scopes SET enabled=0');
  if(change==='revoked-grant')f.execute('UPDATE private.burimunsi_device_grants SET active=0');
  if(change==='wrong-profile')f.execute("UPDATE private.burimunsi_device_grants SET profile='staff'");
  if(change==='removed-account')f.execute('UPDATE private.burimunsi_accounts SET active=0,removed=1');
  if(change==='unapproved-operator')f.h.operatorApproved=false;
  if(change==='revoked-credential')f.execute("UPDATE app.momo_gateway_credentials SET revoked_at='2026-11-07T00:00:00Z'");
  if(change==='scope-reassigned')f.detach();
  const input=f.request();await assert.rejects(momoGatewayRoute(input,f.env),e=>[401,403,503].includes(e.status));
  assert.equal(input.bodyUsed,false);assert.equal(f.upload.puts,0);assert.equal(f.upload.gets,0);assert.equal(f.count('app.sms_receipts'),0);
 });
for(const [name,changes] of [['wrong-sim',{subscription_id:2}],['missing-sim',{subscription_id:null}],['OTP',{raw_body:'Your OTP verification code is 123456'}],
 ['promotion',{raw_body:'Win a promotion with M-Money'}],['personal',{raw_sender:'A Friend'}],['incomplete',{complete:false}],
 ['historic-before-binding',{source_mode:'catch_up',complete:false,inbox_received_at:'2020-01-01T00:00:00Z'}],
 ['inbox-missing-time',{source_mode:'catch_up',complete:false,inbox_received_at:null}],
 ['inbox-falsely-claims-complete',{source_mode:'catch_up',complete:true}],
 ['incomplete-live',{source_mode:'live',complete:false}]])
 test('pre-retention source policy refuses '+name,async t=>{
  const f=await uploadFixture();t.after(f.close);await assert.rejects(f.invokeUpload(changes),e=>[403,409,422].includes(e.status));
  assert.equal(f.upload.puts,0);assert.equal(f.count('app.sms_receipts'),0);assert.equal(f.sources().length,0);
 });
for(const change of ['grant-version','custodian','scope-version','binding-version','receiver-profile','credential-revoked','flag-off','work-revoked'])
 test('authority change during media PUT returns no ACK and no capture: '+change,async t=>{
  const f=await uploadFixture();t.after(f.close);f.upload.onPut=()=>{
   if(change==='grant-version')f.execute('UPDATE private.burimunsi_device_grants SET version=version+1');
   if(change==='custodian')f.execute('UPDATE private.burimunsi_device_grants SET custodian_account_id=NULL');
   if(change==='scope-version')f.execute('UPDATE private.burimunsi_scopes SET version=version+1');
   if(change==='binding-version')f.execute('UPDATE app.momo_gateway_bindings SET version=version+1');
   if(change==='receiver-profile')f.execute("UPDATE app.momo_receiving_accounts SET profile_version='changed'");
   if(change==='credential-revoked')f.execute("UPDATE app.momo_gateway_credentials SET revoked_at='2026-11-07T00:00:00Z'");
   if(change==='flag-off')f.env.BURIMUNSI_NATIVE_UPLOADS_ENABLED='false';
   if(change==='work-revoked')f.state.workRevoked=true;
  };
  await assert.rejects(f.invokeUpload(),e=>[403,503].includes(e.status));assert.equal(f.upload.puts,1,'The intended authority change must actually occur during PUT');assert.equal(f.count('app.sms_receipts'),0);
  assert.equal(f.sources().length,0);assert.equal(f.count('app.momo_processing_jobs'),0);
 });
test('missing trigger association rolls the entire capture back before ACK',async t=>{
 const f=await uploadFixture();t.after(f.close);f.upload.associate=false;
 await assert.rejects(f.invokeUpload(),e=>e.status===503);assert.equal(f.count('app.sms_receipts'),0);assert.equal(f.count('app.momo_gateway_captures'),0);
 assert.equal(f.count('app.momo_processing_jobs'),0);assert.equal(f.upload.puts,1);
});
test('offline media creates no receipt and does not expose provider diagnostics',async t=>{
 const f=await uploadFixture();t.after(f.close);f.upload.offline=true;
 await assert.rejects(f.invokeUpload(),e=>e.status===503&&!e.message.includes('PRIVATE'));
 assert.equal(f.count('app.sms_receipts'),0);assert.equal(f.sources().length,0);
});
test('lost capture COMMIT reconciles read-only and ACKs original exact source, never a second insert',async t=>{
 const f=await uploadFixture();t.after(f.close);f.upload.loseCaptureCommit=true;
 const response=await f.invokeUpload();assert.equal(response.status,200);assert.equal(f.count('app.sms_receipts'),1);
 assert.equal(f.count('app.momo_processing_jobs'),1);assert.equal(f.sources().length,1);assert.equal(f.upload.puts,1);
 assert.ok(f.upload.readOnlyReconciliations>=2);
 assert.equal(f.route.batches.filter(batch=>batch.some(st=>st.sql.startsWith('INSERT INTO sms_receipts'))).length,1);
});
test('revocation after uncertain capture commit prevents retained-media GET and ACK while retaining original evidence',async t=>{
 const f=await uploadFixture();t.after(f.close);f.upload.loseCaptureCommit=true;
 f.upload.onCaptureCommit=()=>f.execute('UPDATE private.burimunsi_device_grants SET active=0,version=version+1');
 await assert.rejects(f.invokeUpload(),e=>e.status===403);assert.equal(f.count('app.sms_receipts'),1);
 assert.equal(f.sources().length,1);assert.equal(f.upload.puts,1);assert.equal(f.upload.gets,0);
 assert.equal(f.route.batches.filter(batch=>batch.some(st=>st.sql.startsWith('INSERT INTO sms_receipts'))).length,1);
});
test('opt-in does not release a canonical credential without an actual Buri scope',async t=>{
 const f=await uploadFixture();t.after(f.close);f.detach();const input=f.request();
 await assert.rejects(momoGatewayRoute(input,f.env),e=>e.status===503&&e.code==='gateway_upload_held');
 assert.equal(input.bodyUsed,false);assert.equal(f.upload.puts,0);assert.equal(f.upload.gets,0);
});
test('collection is derived from current server scope with no fixed environment or client group selector',async t=>{
 const f=await uploadFixture();t.after(f.close);delete f.env.BURIMUNSI_COLLECTION_ID;
 const response=await f.invokeUpload({collection_id:'attacker-group'});assert.equal(response.status,200);
 assert.equal(f.sources()[0].collection_id,I.group);
});
test('status adds collection only for the actual Buri binding and preserves legacy projection',async t=>{
 const f=await uploadFixture();t.after(f.close);
 const request=()=>new Request('https://qualification.invalid/v1/momo/gateway/status',{headers:{Authorization:'Bearer '+f.secret}});
 const native=await(await momoGatewayRoute(request(),f.env)).json();assert.equal(native.binding.collection_id,I.group);
 f.detach();const legacy=await(await momoGatewayRoute(request(),f.env)).json();assert.equal(Object.hasOwn(legacy.binding,'collection_id'),false);
 assert.equal(f.upload.puts,0);assert.equal(f.upload.gets,0);
});
test('rolled-back capture remains unconfirmed instead of being automatically replayed',async t=>{
 const f=await uploadFixture();t.after(f.close);f.upload.failCapture=true;
 await assert.rejects(f.invokeUpload(),e=>e.status===503);assert.equal(f.count('app.sms_receipts'),0);
 assert.equal(f.route.batches.filter(batch=>batch.some(st=>st.sql.startsWith('INSERT INTO sms_receipts'))).length,1);
});
test('duplicate ACK cannot bypass missing immutable source association or reread its media',async t=>{
 const f=await uploadFixture();t.after(f.close);await f.invokeUpload();const gets=f.upload.gets;
 f.execute('DELETE FROM private.burimunsi_sms_source_scopes');
 await assert.rejects(f.invokeUpload(),e=>e.status===403);assert.equal(f.upload.puts,1);assert.equal(f.upload.gets,gets);
});
test('changed content cannot reuse original envelope identity',async t=>{
 const f=await uploadFixture();t.after(f.close);await f.invokeUpload();
 await assert.rejects(f.invokeUpload({raw_body:SMS.replace('1,000','1,001')}),e=>e.status===409&&e.code==='capture_conflict');assert.equal(f.upload.puts,1);
});
test('a caller cannot manufacture an admitted upload plan',async t=>{
 const f=await uploadFixture();t.after(f.close);
 await assert.rejects(commitNativeGatewayCapture(f.env,Object.freeze({}),[],{}),e=>e.status===503);
 assert.equal(f.upload.puts,0);assert.equal(f.count('app.sms_receipts'),0);
});
