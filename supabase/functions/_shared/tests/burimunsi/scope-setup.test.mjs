import test from 'node:test';
import assert from 'node:assert/strict';
import {setupFixture,SETUP} from './scope-setup-fixture.mjs';
import {scopeCommand} from '../../domain/burimunsi/admin-scope-setup.js';
import {resolveNativeCollection,INSTALLATION_SCOPE_SQL} from '../../domain/burimunsi/postgres-scope-discovery.js';
import {sha256} from '../../domain/burimunsi/values.js';
test('scope prepare returns only a disabled versioned public receipt',async()=>{
 const f=setupFixture(),result=await f.service.apply(f.prepare);assert.equal(result.enabled,false);assert.equal(result.scopeVersion,2);
 assert.equal(result.bindingId,null);assert.equal(JSON.stringify(result).includes('ciphertext'),false);
});
test('cancelling a missing prepare creates only an original-request tombstone, never a scope',async()=>{
 const f=setupFixture();f.state.scope=null;
 const cancelled=await f.service.cancel(SETUP.group,SETUP.prepare);
 assert.deepEqual(cancelled,{contractVersion:1,collectionId:SETUP.group,requestId:SETUP.prepare,operation:'cancelled',applied:false});
 assert.equal(f.state.scope,null);
 await assert.rejects(f.service.apply({...f.prepare,expectedScopeVersion:0}),e=>e.code==='burimunsi_setup_cancelled');
 assert.equal(f.state.calls.filter(c=>c.sql.includes('setup_apply')).length,0);
 assert.deepEqual((await f.service.lookup(SETUP.group,SETUP.prepare)).receipt,cancelled);
});
test('cancellation recovers an activation that committed first without claiming it was cancelled',async()=>{
 const f=setupFixture(),committed=await f.service.apply(f.activate);
 assert.deepEqual(await f.service.cancel(SETUP.group,SETUP.activate),committed);
 assert.equal(f.state.scope.enabled,true);
 assert.equal(f.state.calls.filter(c=>c.sql.includes('setup_apply')).length,1);
});
test('an unknown cancellation remains unknown until the exact original request is read back',async()=>{
 const f=setupFixture();f.state.unknown=true;
 await assert.rejects(f.service.cancel(SETUP.group,SETUP.prepare),/lost COMMIT/);
 assert.equal(f.state.calls.filter(c=>c.sql.includes('setup_cancel')).length,1);
 const recovered=await f.service.lookup(SETUP.group,SETUP.prepare);
 assert.equal(recovered.receipt.operation,'cancelled');assert.equal(recovered.receipt.applied,false);
 assert.equal(f.state.scope.enabled,false);
});
test('activation retains purpose-bound ciphertext and reveals the code only through explicit revalidated delivery',async()=>{
 const f=setupFixture(),receipt=await f.service.apply(f.activate);
 assert.equal(receipt.enabled,true);assert.equal(receipt.installationId,SETUP.installation);assert.equal(Object.hasOwn(receipt,'pairingCode'),false);
 const stored=f.state.commands.get(SETUP.activate);assert.equal(typeof stored.delivery.ciphertext,'string');
 const delivery=await f.service.delivery(SETUP.group,SETUP.activate);assert.match(delivery.pairingCode,/^[a-f0-9]{64}$/);
 assert.equal(JSON.stringify([...f.state.commands]).includes(delivery.pairingCode),false);
 assert.equal(await sha256(delivery.pairingCode),stored.delivery.codeHash);
 assert.equal(f.state.calls.filter(c=>c.sql.includes('setup_lookup')&&c.values[6]).length,2);
});
test('same original activation is recovered without another challenge or mutation',async()=>{
 const f=setupFixture(),first=await f.service.apply(f.activate),again=await f.service.apply(f.activate);assert.deepEqual(again,first);
 assert.equal(f.state.calls.filter(c=>c.sql.includes('setup_apply')).length,1);
 await assert.rejects(f.service.apply({...f.activate,reason:'Changed original intent'}),e=>e.status===409);
});
test('unknown activation COMMIT is looked up rather than automatically retried',async()=>{
 const f=setupFixture();f.state.unknown=true;await assert.rejects(f.service.apply(f.activate));
 const found=await f.service.lookup(SETUP.group,SETUP.activate);assert.equal(found.found,true);assert.equal(Object.hasOwn(found,'fingerprint'),false);
 assert.equal(f.state.calls.filter(c=>c.sql.includes('setup_apply')).length,1);
});
test('working paired phone refuses activation before any code or SQL mutation is created',async()=>{
 const f=setupFixture();f.state.scope.paired=true;await assert.rejects(f.service.apply(f.activate),e=>e.code==='burimunsi_scope_changed');
 assert.equal(f.state.calls.some(c=>c.sql.includes('setup_apply')),false);
});
function replacementFixture(){
 const f=setupFixture();Object.assign(f.state.scope,{paired:true,enabled:true,bindingId:'working-binding',bindingVersion:7,receiverKeyId:'working-key',receiverInstallationId:'fd400000-0000-4000-8000-000000000099'});
 f.replacement={...f.activate,operation:'prepare_replacement',requestId:'fd600000-0000-4000-8000-000000000003',expectedBindingId:'working-binding',expectedBindingVersion:7,expectedReceiverKeyId:'working-key'};
 return f;
}
test('automatic NULL-custody installation is returned with its genuine effective candidate and explicit assignment status',async()=>{
 const f=setupFixture(),directory=await f.service.directory(SETUP.group);
 assert.equal(directory.installations[0].custodianAccountId,SETUP.custodian);assert.equal(directory.installations[0].custodyAssigned,false);
});
test('replacement preparation binds a new target and source revisions without retiring or bumping the working scope',async()=>{
 const f=replacementFixture(),before=structuredClone(f.state.scope),r=await f.service.apply(f.replacement);
 assert.equal(r.operation,'prepare_replacement');assert.equal(r.scopeVersion,before.version);assert.equal(r.handoffId,f.replacement.requestId);
 assert.equal(r.retirementRequired,true);assert.notEqual(r.bindingId,before.bindingId);assert.equal(r.expectedReceiverKeyId,'working-key');
 assert.deepEqual(f.state.scope,before);
 const protectedBinding=f.state.commands.get(f.replacement.requestId).delivery.binding;
 for(const field of ['expectedBindingId','expectedBindingVersion','expectedReceiverKeyId'])assert.equal(protectedBinding[field],f.replacement[field]);
 const delivery=await f.service.delivery(SETUP.group,f.replacement.requestId);
 assert.equal(delivery.phase,'prepared');assert.equal(delivery.retirementRequired,true);assert.equal(delivery.handoffId,r.handoffId);
 assert.deepEqual(Object.keys(delivery).sort(),['contractVersion','collectionId','requestId','bindingId','installationId','subscriptionId','pairingCode','expiresAt','handoffId','retirementRequired','phase'].sort());
 const again=await f.service.apply(f.replacement);assert.deepEqual(again,r);assert.equal(f.state.calls.filter(c=>c.sql.includes('setup_apply')).length,1);
});
test('Owner lost-phone finalization produces its actual method and reuses only original H delivery',async()=>{
 const f=replacementFixture();const prepared=await f.service.apply(f.replacement),first=await f.service.delivery(SETUP.group,f.replacement.requestId);
 const finalize={...f.prepare,operation:'finalize_replacement',requestId:'fd600000-0000-4000-8000-000000000004',handoffId:f.replacement.requestId};
 const result=await f.service.apply(finalize);
 assert.equal(result.retirementMethod,'owner_lost');assert.equal(result.reauthenticationRequired,true);assert.equal(result.scopeVersion,2);
 assert.equal(result.bindingId,prepared.bindingId);assert.equal(result.bindingVersion,1);assert.equal(Object.hasOwn(result,'retired'),false);
 const recovered=await f.service.delivery(SETUP.group,f.replacement.requestId);
 assert.equal(recovered.phase,'retired');assert.equal(recovered.retirementRequired,false);assert.equal(recovered.pairingCode,first.pairingCode);assert.equal(recovered.expiresAt,first.expiresAt);
 await assert.rejects(f.service.delivery(SETUP.group,finalize.requestId));
});
test('revoked old receiver keeps paired=false while exact history prepares explicit Owner-lost replacement',async()=>{
 const f=replacementFixture();f.state.scope.paired=false;const before=structuredClone(f.state.scope);
 const observed=await f.service.directory(SETUP.group);
 assert.equal(observed.scopes[0].paired,false);assert.equal(observed.scopes[0].receiverKeyId,'working-key');
 const prepared=await f.service.apply(f.replacement);
 assert.equal(prepared.operation,'prepare_replacement');assert.equal(prepared.scopeVersion,before.version);assert.equal(prepared.retirementRequired,true);
 assert.equal(prepared.expectedBindingId,before.bindingId);assert.equal(prepared.expectedBindingVersion,before.bindingVersion);assert.equal(prepared.expectedReceiverKeyId,before.receiverKeyId);
 assert.deepEqual(f.state.scope,before,'preparation must not manufacture active pairing or advance scope');
 const finalize={...f.prepare,operation:'finalize_replacement',requestId:'fd600000-0000-4000-8000-000000000004',handoffId:f.replacement.requestId};
 const result=await f.service.apply(finalize);
 assert.equal(result.operation,'finalize_replacement');assert.equal(result.retirementMethod,'owner_lost');assert.equal(result.scopeVersion,before.version+1);
 assert.equal(Object.hasOwn(result,'retired'),false,'Owner result must never impersonate a native retirement ACK');
 assert.deepEqual(f.state.calls.filter(c=>c.sql.includes('setup_apply')).map(c=>JSON.parse(c.values[4]).operation),['prepare_replacement','finalize_replacement']);
});
for(const change of [
 {receiverKeyId:null},{receiverKeyId:''},{receiverKeyId:'bad/key'},{receiverKeyId:undefined},
 {bindingId:null},{bindingId:undefined},{bindingVersion:0},{bindingVersion:'7'},
 {receiverInstallationId:null},{receiverInstallationId:undefined},{receiverInstallationId:'not-a-uuid'},{enabled:false}
])test('revoked receiver cannot prepare replacement from missing or malformed history '+JSON.stringify(change),async()=>{
 const f=replacementFixture();Object.assign(f.state.scope,{paired:false,...change});
 await assert.rejects(f.service.apply(f.replacement));
 assert.equal(f.state.calls.some(c=>c.sql.includes('setup_apply')),false);assert.equal(f.state.commands.size,0);
});
for(const field of ['expectedBindingId','expectedBindingVersion','expectedReceiverKeyId'])test('replacement protected delivery denies source '+field+' tampering',async()=>{
 const f=replacementFixture();await f.service.apply(f.replacement);f.state.commands.get(f.replacement.requestId).delivery.binding[field]='changed';
 await assert.rejects(f.service.delivery(SETUP.group,f.replacement.requestId));
});
test('stale source and same target refuse before creating a replacement challenge',async()=>{
 for(const patch of [{expectedBindingId:'different'},{expectedBindingVersion:8},{expectedReceiverKeyId:'different'},{installationId:'fd400000-0000-4000-8000-000000000009'}]){
  const f=replacementFixture();if(patch.installationId)f.state.scope.receiverInstallationId=patch.installationId;
  await assert.rejects(f.service.apply({...f.replacement,...patch}),e=>e.code==='burimunsi_scope_changed');
  assert.equal(f.state.calls.some(c=>c.sql.includes('setup_apply')),false);
 }
});
for(const field of ['profileSha','actorId','sessionId','collectionId','bindingId','installationId','grantVersion','subscriptionId'])
 test('delivery cannot cross original protected '+field,async()=>{
  const f=setupFixture();await f.service.apply(f.activate);f.state.commands.get(SETUP.activate).delivery.binding[field]='different';
  await assert.rejects(f.service.delivery(SETUP.group,SETUP.activate));
 });
test('authority loss after decrypt cannot return a pairing code',async()=>{
 const f=setupFixture();await f.service.apply(f.activate);let reads=0;
 f.state.afterLookup=delivery=>{if(delivery&&++reads===2)f.state.revoked=true;};
 await assert.rejects(f.service.delivery(SETUP.group,SETUP.activate));
});
for(const change of [{reason:'short'},{reason:'Private '+ 'a'.repeat(64)},{expectedScopeVersion:-1},{subscriptionId:2147483647},{extra:'unsupported'}])
 test('setup rejects invalid or secret-bearing intent '+JSON.stringify(change),()=>assert.throws(()=>scopeCommand({...setupFixture().activate,...change})));
test('dynamic discovery uses verified request DB and hashed exact device proof, with no group input',async()=>{
 const calls=[],work={assert:async()=>{}},env={DB:{applicationWork:work,prepare:sql=>({bind:(...values)=>({sql,values})}),
  batch:async statements=>{calls.push(...statements);return [{success:true,results:[{scope:{collectionId:SETUP.group}}]}];}}};
 assert.equal(await resolveNativeCollection({env,installationId:SETUP.installation,deviceToken:'c'.repeat(64)}),SETUP.group);
 assert.deepEqual(calls,[{sql:INSTALLATION_SCOPE_SQL,values:[SETUP.installation,await sha256('c'.repeat(64))]}]);
});
test('absent/ambiguous scope or wrong rollout cannot select a client group',async()=>{
 for(const scope of [null,{collectionId:SETUP.group,other:'secret'}]){
  const env={DB:{applicationWork:{assert:async()=>{}},prepare:sql=>({bind:()=>({sql})}),batch:async()=>[{success:true,results:[{scope}]}]}};
  await assert.rejects(resolveNativeCollection({env,installationId:SETUP.installation,deviceToken:'c'.repeat(64)}));
 }
});
