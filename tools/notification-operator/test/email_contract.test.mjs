import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {emailVerification,hasFreshEmailVerification,sensitiveAuthorityKey,authorityKey,publicSession} from '../src/contract.mjs';

const now=Date.parse('2026-10-22T20:00:00.000Z');
function user(){return {id:randomUUID(),email:'synthetic@example.invalid',role:'owner',sessionId:randomUUID(),expiresAt:new Date(now+3600000).toISOString(),permissions:['assisted_sms.read','assisted_sms.manage'],assuranceLevel:1,mfaAt:null,principalId:randomUUID(),financialModel:'canonical_evidence_ledger'};}

test('same-session sidecar preserves the exact public AAL1 DTO and accepts authoritative null',()=>{
 const u=publicSession(user(),now),before=structuredClone(u);
 const proof={contractVersion:1,sessionId:u.sessionId,emailVerifiedAt:new Date(now).toISOString()};
 assert.deepEqual(emailVerification(proof,u.sessionId,now),proof);assert.deepEqual(u,before);
 assert.deepEqual(emailVerification({...proof,emailVerifiedAt:null},u.sessionId,now),{...proof,emailVerifiedAt:null});
 assert.throws(()=>publicSession({...u,emailVerifiedAt:proof.emailVerifiedAt},now),/unsupported_or_missing/);
});

test('sidecar refuses caller authority, token and CSRF envelopes, wrong SID and future/non-UTC values',()=>{
 const u=user(),proof={contractVersion:1,sessionId:u.sessionId,emailVerifiedAt:new Date(now).toISOString()};
 for(const extra of [{csrfToken:'synthetic-unacceptable'},{access_token:'synthetic-unacceptable'},{assuranceLevel:2},{futureField:true}])assert.throws(()=>emailVerification({...proof,...extra},u.sessionId,now),/unsupported_or_missing/);
 for(const value of [{...proof,contractVersion:2},{...proof,sessionId:randomUUID()},{...proof,sessionId:'00000000-0000-0000-0000-000000000000'}])assert.throws(()=>emailVerification(value,u.sessionId,now));
 for(const date of [new Date(now+1).toISOString(),'2026-10-22T20:00:00+00:00','2026-02-31T20:00:00.000Z','not-a-date'])assert.throws(()=>emailVerification({...proof,emailVerifiedAt:date},u.sessionId,now));
});

test('proof freshness never comes from AAL, null, unavailable state, a future clock or an expired session',()=>{
 const u=user(),current={user:u,emailVerifiedAt:new Date(now).toISOString(),proofState:'available'};
 assert.equal(hasFreshEmailVerification(current,now),true);
 assert.equal(hasFreshEmailVerification({...current,emailVerifiedAt:new Date(now-300000).toISOString()},now),true);
 for(const changed of [{emailVerifiedAt:null},{proofState:'unavailable'},{emailVerifiedAt:new Date(now+1).toISOString()},{emailVerifiedAt:new Date(now-300001).toISOString()},{user:{...u,expiresAt:new Date(now).toISOString()}}])assert.equal(hasFreshEmailVerification({...current,...changed},now),false);
 for(const limit of [300001,NaN,-1])assert.equal(hasFreshEmailVerification(current,now,limit),false);
 assert.equal(hasFreshEmailVerification({...current,user:{...u,assuranceLevel:2,mfaAt:new Date(now).toISOString()},emailVerifiedAt:null},now),false);
});

test('same BFF and actor remain identifiable while a renewed email proof has different operator authority',()=>{
 const u=user(),old=new Date(now-1000).toISOString(),fresh=new Date(now).toISOString();
 assert.equal(authorityKey(u),authorityKey(structuredClone(u)));
 assert.notEqual(sensitiveAuthorityKey(u,old),sensitiveAuthorityKey(u,fresh));
 assert.notEqual(sensitiveAuthorityKey(u,null),sensitiveAuthorityKey(u,fresh));
 assert.equal(u.assuranceLevel,1);assert.equal(u.mfaAt,null);
});
