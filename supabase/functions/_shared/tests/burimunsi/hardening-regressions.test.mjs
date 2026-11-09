import test from 'node:test';import assert from 'node:assert/strict';
import {matchExistingMember,authorize} from '../../domain/burimunsi/policy.js';
import {parseReceipt} from '../../domain/burimunsi/receipt.js';
import {PostgresNativeAuthStore} from '../../domain/burimunsi/postgres-auth-store.js';
import {ContributionService} from '../../domain/burimunsi/contribution-service.js';
import {profile,fullSource,policy,member,identity,admin,binding} from './fixtures.mjs';
const receipt={...parseReceipt(fullSource,profile),groupId:'group-1'};
const match=(r=receipt,ms=[member],ids=[identity],p=policy)=>matchExistingMember(r,ms,ids,p);
for(const groupId of ['other',null,undefined])test('receipt scope cannot borrow another group identity '+groupId,()=>assert.equal(match({...receipt,groupId}).reason,'scope_mismatch'));
test('inactive overlapping identity owner remains ambiguous',()=>assert.equal(match(receipt,[member,{...member,id:'m2',active:false}],[identity,{...identity,id:'i2',memberId:'m2'}]).reason,'ambiguous_identity'));
test('unknown overlapping owner also blocks a guess',()=>assert.equal(match(receipt,[member],[identity,{...identity,id:'i2',memberId:'unlisted'}]).reason,'ambiguous_identity'));
test('duplicate membership rows fail closed',()=>assert.equal(match(receipt,[member,member]).reason,'member_ineligible'));
test('identity evidence IDs are required',()=>assert.equal(match(receipt,[member],[{...identity,id:undefined}]).reason,'no_verified_identity'));
test('malformed payer full phone does not throw or match',()=>assert.equal(match({...receipt,fullPayerPhone:'0780000816 OTP 1234'}).reason,'invalid_identity'));
test('boundary reuse selects the effective owner, not the present phone holder',()=>{
 const old={...identity,validUntil:receipt.at};const newer={...identity,id:'new-id',memberId:'m2',validFrom:receipt.at};
 assert.equal(match(receipt,[member,{...member,id:'m2'}],[old,newer]).memberId,'m2');
});
for(const installationProfile of ['staff',undefined,null])test('Admin SMS cannot come from non-receiver profile '+installationProfile,()=>assert.throws(()=>authorize({...admin,installationProfile},'group-1','sms.read',{binding}),/gateway_unavailable/));
test('missing session selector never emits a broad SQL read',async()=>{
 let touched=false;const db={applicationWork:{assert:async()=>{}},transaction:async fn=>fn({}),context:async()=>{},readContext:async()=>{}};
 const s=new PostgresNativeAuthStore({db,groupId:'g',createOperatorPrincipal:async()=>{}});
 await assert.rejects(s.session({unsafe:async()=>{touched=true;return[]}},{}),/session_unavailable/);assert.equal(touched,false);
});
test('automatic allocation cannot be invoked without a durable work witness',async()=>{
 let touched=false;const s=new ContributionService({store:{inCanonicalTransaction:async()=>{touched=true}},groupId:'group-1'});
 await assert.rejects(s.automaticallyAllocate('tx-1',crypto.randomUUID()),/automatic_work_required/);assert.equal(touched,false);
});
test('automatic admission is checked before reading or posting',async()=>{
 const touched=[];const tx=Object.fromEntries(['lockReceipt','loadApprovedPolicy','listEligibleMembers','listVerifiedIdentities','postCanonicalContribution','readCanonicalResult'].map(k=>[k,async()=>touched.push(k)]));
 tx.assertAutomaticAdmission=async()=>{throw Error('held')};
 const s=new ContributionService({store:{inCanonicalTransaction:fn=>fn(tx)},groupId:'group-1'});
 await assert.rejects(s.automaticallyAllocate('tx-1',crypto.randomUUID(),{kind:'receipt',jobId:crypto.randomUUID(),owner:'worker-1',leaseVersion:1}),/held/);assert.deepEqual(touched,[]);
});
test('already-posted conflict cannot bypass current eligibility fence',async()=>{
 const tx={assertAutomaticAdmission:async()=>{},lockReceipt:async()=>({...receipt,id:'tx-1',state:'posted',hasConflict:true}),
 loadApprovedPolicy:async()=>policy,listEligibleMembers:async()=>[member],listVerifiedIdentities:async()=>[identity],
 postCanonicalContribution:async()=>assert.fail('must not post'),readCanonicalResult:async()=>assert.fail('must not accept prior result')};
 const s=new ContributionService({store:{inCanonicalTransaction:fn=>fn(tx)},groupId:'group-1'});
 await assert.rejects(s.automaticallyAllocate('tx-1',crypto.randomUUID(),{kind:'receipt',jobId:crypto.randomUUID(),owner:'worker-1',leaseVersion:1}),/transaction_unavailable/);
});
