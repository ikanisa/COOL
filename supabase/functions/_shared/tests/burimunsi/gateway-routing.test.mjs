import test from 'node:test';
import assert from 'node:assert/strict';
import {routingFixture,I,OLD} from './gateway-routing-fixture.mjs';
import {NON_BURIMUNSI_PAIR_CONDITION} from '../../domain/burimunsi/postgres-gateway-classification.js';

test('actual canonical route dispatches exact Buri candidate into closed native pairing without legacy reads',async t=>{
 const f=await routingFixture();t.after(f.close);const response=await f.invoke(),body=await response.json();
 assert.equal(response.status,200);assert.equal(body.binding.id,OLD);assert.equal(body.binding.owner_user_id,I.principal);
 assert.equal(body.binding.collection_id,I.group);
 assert.match(body.gateway_token,/^[a-f0-9]{64}$/);assert.equal(f.route.reads.length,0);assert.equal(f.count('app.momo_gateway_credentials'),1);
 const retry=await(await f.invoke()).json();assert.equal(retry.binding.collection_id,I.group);assert.equal(retry.gateway_token,body.gateway_token);
 assert.equal(f.count('app.momo_gateway_credentials'),1);assert.equal(f.route.reads.length,0);
});
for(const change of ['wrong-config','disabled-feature','disabled-scope','dropped-binding','wrong-installation','owner-session','native-grant'])
 test('actual route cannot fall back to legacy after Buri '+change,async t=>{
  const f=await routingFixture();t.after(f.close);let overrides={};
  if(change==='wrong-config')f.env.BURIMUNSI_COLLECTION_ID='other-group';
  if(change==='disabled-feature')f.env.BURIMUNSI_NATIVE_ENABLED='false';
  if(change==='disabled-scope')f.execute('UPDATE private.burimunsi_scopes SET enabled=0');
  if(change==='dropped-binding')f.execute('UPDATE private.burimunsi_scopes SET active_binding_id=NULL');
  if(change==='wrong-installation')overrides={installation_id:'30000000-0000-4000-8000-000000000099'};
  if(change==='owner-session')f.h.ownerLive=false;
  if(change==='native-grant')f.execute('UPDATE private.burimunsi_device_grants SET active=0');
  await assert.rejects(f.invoke(overrides),e=>[401,403,503].includes(e.status));
  assert.equal(f.route.reads.length,0);assert.equal(f.count('app.momo_gateway_credentials'),0);
 });
test('actual canonical Buri pairing resolves its existing DB scope without a deployment business group',async t=>{
 const f=await routingFixture();t.after(f.close);delete f.env.BURIMUNSI_COLLECTION_ID;
 const response=await f.invoke(),body=await response.json();assert.equal(response.status,200);assert.equal(body.binding.collection_id,I.group);
 assert.equal(f.route.reads.length,0);assert.equal(f.count('app.momo_gateway_credentials'),1);
});
test('missing classifier SQL fails closed before legacy pairing reads or writes',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();f.route.classifierError=true;
 await assert.rejects(f.invoke(),e=>e.status===503&&e.code==='gateway_classification_unavailable'&&!e.message.includes('PRIVATE'));
 assert.equal(f.route.reads.length,0);assert.equal(f.count('app.momo_gateway_credentials'),0);
});
test('Buri uncertain native write is never rerouted to a legacy claim',async t=>{
 const f=await routingFixture();t.after(f.close);f.failStatement=st=>st.sql.startsWith('INSERT INTO app.momo_gateway_credentials');
 await assert.rejects(f.invoke(),e=>e.status===503&&e.code==='gateway_pairing_unconfirmed');
 assert.equal(f.route.reads.length,0);assert.equal(f.count('app.momo_gateway_credentials'),0);
});
test('actual non-Buri route guards both claim and token return and preserves encrypted explicit retry',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();
 const first=await(await f.invoke()).json(),second=await(await f.invoke()).json();assert.equal(first.gateway_token,second.gateway_token);
 assert.equal(Object.hasOwn(first.binding,'collection_id'),false);assert.equal(Object.hasOwn(second.binding,'collection_id'),false);
 assert.equal(f.count('app.momo_gateway_credentials'),1);
 const custody=f.sqlite.prepare('SELECT * FROM app.momo_gateway_credentials').get();assert.notEqual(custody.token_ciphertext,first.gateway_token);
 const claims=f.route.batches.filter(batch=>batch.some(st=>st.sql.startsWith('INSERT INTO momo_gateway_credentials')));
 assert.equal(claims.length,1);assert.ok(claims[0][0].sql.includes(NON_BURIMUNSI_PAIR_CONDITION));
 const deliveries=f.route.batches.filter(batch=>batch.length===2&&batch[0].sql.includes(NON_BURIMUNSI_PAIR_CONDITION));
 assert.equal(deliveries.length,2);assert.equal(f.route.reads.some(read=>/ledger_entries|payments/.test(read.sql)),false);
});
test('legacy lost COMMIT reads the same retained credential without automatically claiming again',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();f.route.loseClaimAck=true;
 const response=await f.invoke();assert.equal(response.status,200);assert.equal(f.count('app.momo_gateway_credentials'),1);
 assert.equal(f.route.batches.filter(batch=>batch.some(st=>st.sql.startsWith('INSERT INTO momo_gateway_credentials'))).length,1);
 assert.equal(f.route.batches.filter(batch=>batch[0].sql.startsWith('SELECT private.burimunsi_gateway_pair_classify')).length,1);
});
test('legacy rolled-back claim remains unconfirmed and is not automatically reissued',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();f.failStatement=st=>st.sql.startsWith('INSERT INTO momo_gateway_credentials');
 await assert.rejects(f.invoke(),e=>e.status===409&&e.code==='pairing_changed');
 assert.equal(f.count('app.momo_gateway_credentials'),0);assert.equal(f.sqlite.prepare('SELECT claimed_installation_id FROM app.momo_gateway_pairings').get().claimed_installation_id,null);
 assert.equal(f.route.batches.filter(batch=>batch.some(st=>st.sql.startsWith('INSERT INTO momo_gateway_credentials'))).length,1);
});
test('scope attached after initial classification prevents the legacy claim in its own transaction',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();
 f.route.beforeBatch=batch=>{if(batch.some(st=>st.sql.startsWith('INSERT INTO momo_gateway_credentials')))f.attach();};
 await assert.rejects(f.invoke(),e=>e.status===409&&e.code==='pairing_changed');assert.equal(f.count('app.momo_gateway_credentials'),0);
 assert.equal(f.sqlite.prepare('SELECT active_binding_id FROM private.burimunsi_scopes').get().active_binding_id,OLD);
});
test('scope attached after commit prevents token delivery rather than claiming success',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();
 f.route.beforeBatch=batch=>{if(batch.length===2&&batch[0].sql.includes(NON_BURIMUNSI_PAIR_CONDITION))f.attach();};
 await assert.rejects(f.invoke(),e=>e.status===503&&e.code==='gateway_pairing_unconfirmed');assert.equal(f.count('app.momo_gateway_credentials'),1);
});
test('same-install retry cannot reveal a legacy token after scope changes during decryption/readback',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();await f.invoke();
 f.route.beforeBatch=batch=>{if(batch.length===2&&batch[0].sql.includes(NON_BURIMUNSI_PAIR_CONDITION))f.attach();};
 await assert.rejects(f.invoke(),e=>e.status===503&&e.code==='gateway_pairing_unconfirmed');assert.equal(f.count('app.momo_gateway_credentials'),1);
});
test('legacy same-install retry refuses a different installation',async t=>{
 const f=await routingFixture();t.after(f.close);f.detach();await f.invoke();
 await assert.rejects(f.invoke({installation_id:'30000000-0000-4000-8000-000000000099'}),e=>e.status===409&&e.code==='pairing_claimed');
 assert.equal(f.count('app.momo_gateway_credentials'),1);
});
