import test from 'node:test';import assert from 'node:assert/strict';
import {postingPreparationIdentity} from '../../domain/burimunsi/posting-preparation.js';
const requestId='11111111-1111-4111-8111-111111111111',sessionId='22222222-2222-4222-8222-222222222222';
function input(mode='historical'){
 const receipt={id:'transaction-1',groupId:'group-1',version:1,currency:'RWF',amountRwf:1000,
  receivingAccountId:'wallet-1',providerTransactionId:'FT123',sourceBindingId:null,sourceBindingVersion:null,
  nativeOrigin:{kind:'native_observation',sourceId:'source-1',sourceTag:'native.auto.v1',transactionMode:mode}};
 const command={groupId:'group-1',receiptId:receipt.id,memberId:'member-1',expectedVersion:1,requestId,
  mode:'automatic',policyVersion:'approved-1',identityIds:['identity-1'],receipt};
 const principal={kind:'admitted_worker',groupId:'group-1',receiptId:receipt.id,requestId,mode:'automatic',policyVersion:'approved-1',
  principalUserId:'operator-1',principalSessionId:sessionId,actorId:'operator-1',sessionId};
 return {command,principal};
}
test('typed native identity is stable without a fabricated gateway binding',async()=>{
 const {command,principal}=input();const a=await postingPreparationIdentity(command,principal);
 assert.deepEqual(await postingPreparationIdentity(command,principal),a);
 assert.deepEqual(a.target.nativeOrigin,command.receipt.nativeOrigin);
 assert.equal(a.target.nativeOrigin.transactionMode,'historical');
 assert.equal('sourceBindingId' in a.target,false);assert.equal('sourceBindingVersion' in a.target,false);
 assert.equal('providerAuthenticated' in a.target.nativeOrigin,false);
});
test('different native source identity or transaction mode cannot reuse the preparation',async()=>{
 const a=input(),before=await postingPreparationIdentity(a.command,a.principal);
 a.command.receipt.nativeOrigin.sourceId='source-2';assert.notEqual((await postingPreparationIdentity(a.command,a.principal)).requestDigest,before.requestDigest);
 a.command.receipt.nativeOrigin.sourceId='source-1';a.command.receipt.nativeOrigin.transactionMode='live';
 assert.notEqual((await postingPreparationIdentity(a.command,a.principal)).requestDigest,before.requestDigest);
});
test('native and genuine gateway identity calculations have separate descriptors',async()=>{
 const native=input(),a=await postingPreparationIdentity(native.command,native.principal);
 const gateway=input();delete gateway.command.receipt.nativeOrigin;gateway.command.receipt.sourceBindingId='binding-1';gateway.command.receipt.sourceBindingVersion=1;
 const b=await postingPreparationIdentity(gateway.command,gateway.principal);
 assert.notEqual(a.requestDigest,b.requestDigest);assert.notEqual(a.paymentId,b.paymentId);
});
for(const change of [
 r=>r.sourceBindingId='forged-binding',r=>r.sourceBindingVersion=1,r=>r.nativeOrigin.kind='gateway',
 r=>r.nativeOrigin.sourceTag='approved-policy-not-source-tag',r=>r.nativeOrigin.transactionMode='correlated-authenticated',
 r=>r.nativeOrigin.sourceId='/',r=>r.nativeOrigin.extra=true
])test('native identity rejects ambiguous or fabricated source data '+String(change),async()=>{
 const {command,principal}=input();change(command.receipt);await assert.rejects(postingPreparationIdentity(command,principal));
});
test('native identity is only calculated for automatic work with an admitted-worker principal',async()=>{
 let {command,principal}=input();command.mode='exception';principal.mode='exception';principal.kind='native_operator';
 await assert.rejects(postingPreparationIdentity(command,principal));
 ({command,principal}=input());principal.kind='native_operator';await assert.rejects(postingPreparationIdentity(command,principal));
});
test('caller mutation after entry cannot change an in-flight identity calculation',async()=>{
 const {command,principal}=input();const expected=await postingPreparationIdentity(command,principal);
 const pending=postingPreparationIdentity(command,principal);command.receipt.nativeOrigin.sourceId='different';
 assert.deepEqual(await pending,expected);
});
test('native source tag is distinct from the approved matching policy',async()=>{
 const f=input();const before=await postingPreparationIdentity(f.command,f.principal);
 f.command.policyVersion='approved-2';f.principal.policyVersion='approved-2';
 const after=await postingPreparationIdentity(f.command,f.principal);
 assert.equal(after.target.nativeOrigin.sourceTag,'native.auto.v1');assert.equal(after.target.policyVersion,'approved-2');
 assert.notEqual(before.requestDigest,after.requestDigest);
});
