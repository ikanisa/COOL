import test from 'node:test';
import assert from 'node:assert/strict';
import {uploadFixture,I,OLD} from './gateway-upload-fixture.mjs';
import {momoGatewayRoute} from '../../domain/momo_gateway.js';

const request=(secret,query='')=>new Request('https://qualification.invalid/v1/momo/gateway/profile'+query,
 {headers:{Authorization:'Bearer '+secret}});

test('receiver gets only its current approved scoped classifier profile',async t=>{
 const f=await uploadFixture();t.after(f.close);
 const response=await momoGatewayRoute(request(f.secret),f.env),value=await response.json();
 assert.equal(response.status,200);assert.equal(response.headers.get('cache-control'),'no-store');
 assert.deepEqual(Object.keys(value).sort(),['bindingId','bindingVersion','collectionId','contractVersion','expiresAt',
  'installationId','issuedAt','offsetMinutes','profileVersion','receivingAccountId','senders','incomingPrefixes','currencyAliases','transactionIdPrefixes'].sort());
 assert.equal(value.contractVersion,1);assert.equal(value.collectionId,I.group);assert.equal(value.installationId,I.installation);
 assert.equal(value.bindingId,OLD);assert.equal(value.bindingVersion,3);assert.equal(value.receivingAccountId,'wallet-1');
 assert.equal(value.profileVersion,'fixture-approved-v1');assert.equal(value.offsetMinutes,120);assert.deepEqual(value.senders,['M-Money']);
 assert.deepEqual(value.incomingPrefixes,['You have received']);assert.deepEqual(value.currencyAliases,['RWF']);assert.deepEqual(value.transactionIdPrefixes,['FT Id:']);
 assert.equal(value.expiresAt-value.issuedAt,24*60*60*1000);
 assert.equal(JSON.stringify(value).includes(f.secret),false);assert.equal(f.upload.puts,0);assert.equal(f.sources().length,0);
 const profile={sender_allowlist:['ALT-PROVIDER','ALT-PROVIDER',' Sender 2 '],currency_aliases:['RWF'],incoming_prefixes:['You have received'],transaction_id_prefixes:['FT Id:'],date_format:'YMD_HMS',utc_offset_minutes:60};
 f.execute('UPDATE app.momo_receiving_accounts SET profile_json=?,profile_version=?',JSON.stringify(profile),'profile v2 / approved');
 const updated=await(await momoGatewayRoute(request(f.secret),f.env)).json();
 assert.deepEqual(updated.senders,['ALT-PROVIDER','ALT-PROVIDER',' Sender 2 ']);assert.equal(updated.offsetMinutes,60);assert.equal(updated.profileVersion,'profile v2 / approved');
});

test('profile or authority changes after preflight prevent the second scoped read from issuing a snapshot',async t=>{
 for(const changed of ['profile','grant','lease']){
  await t.test(changed,async t=>{
  const f=await uploadFixture();t.after(f.close);const prior=f.db.statement;
  f.db.statement=async(tx,st)=>{
   if(st.sql.endsWith(' AS admitted')){
    if(changed==='profile')f.execute("UPDATE app.momo_receiving_accounts SET profile_version='changed'");
    if(changed==='grant')f.h.operatorApproved=false;
    if(changed==='lease')f.state.workRevoked=true;
   }
   return prior(tx,st);
  };
  await assert.rejects(momoGatewayRoute(request(f.secret),f.env));
  assert.equal(f.upload.puts,0);assert.equal(f.sources().length,0);
  });
 }
});

test('unapproved profile, revoked grant, wrong token, query override and held uploads never expose policy',async t=>{
 const f=await uploadFixture();t.after(f.close);
 await assert.rejects(momoGatewayRoute(request('a'.repeat(64)),f.env),e=>e.status===401);
 await assert.rejects(momoGatewayRoute(request(f.secret,'?collection=other'),f.env),e=>e.status===400);
 f.env.BURIMUNSI_NATIVE_UPLOADS_ENABLED='false';
 await assert.rejects(momoGatewayRoute(request(f.secret),f.env),e=>e.status===503);
 f.env.BURIMUNSI_NATIVE_UPLOADS_ENABLED='true';
 f.execute("UPDATE app.momo_receiving_accounts SET profile_status='unverified'");
 await assert.rejects(momoGatewayRoute(request(f.secret),f.env),e=>[403,503].includes(e.status));
 f.execute("UPDATE app.momo_receiving_accounts SET profile_status='approved'");
 f.execute('UPDATE private.burimunsi_device_grants SET active=0');
 await assert.rejects(momoGatewayRoute(request(f.secret),f.env),e=>[403,503].includes(e.status));
 assert.equal(f.upload.puts,0);assert.equal(f.sources().length,0);
});
