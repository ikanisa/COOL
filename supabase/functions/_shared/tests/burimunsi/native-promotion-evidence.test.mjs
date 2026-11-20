import test from 'node:test';
import assert from 'node:assert/strict';
import {sha256} from '../../domain/burimunsi/values.js';
import {nativePromotionEvidence} from '../../domain/burimunsi/native-promotion-evidence.js';

const fixture=async()=>{
 const profile={sender_allowlist:['SYNTHETIC-MOMO'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],
  transaction_id_prefixes:['TxId:'],date_format:'YMD_HMS',utc_offset_minutes:120,
  recipient_rules:[{role:'recipient',kind:'public_code',prefix:'Receiver code: ',suffix:'.',digit_count:5,format:'digits'}]};
 const body='You have received RWF 1,500 from +250788111222 at 2026-11-10 08:10:20. Fee: 0 RWF. Balance: 9,000 RWF. TxId: TX-556677. Receiver code: 48271.';
 return {observation:{sourceId:'a1000000-0000-4000-8000-000000000001',collectionId:'synthetic-group',
  nativeAccountId:'a2000000-0000-4000-8000-000000000001',nativeSessionId:'a3000000-0000-4000-8000-000000000001',
  installationId:'a4000000-0000-4000-8000-000000000001',grantId:'a5000000-0000-4000-8000-000000000001',grantVersion:1,
  bodySha256:await sha256(body),objectSha256:'a'.repeat(64),profileTupleSha256:'b'.repeat(64)},
  source:{raw_sender:'SYNTHETIC-MOMO',raw_body:body,source_mode:'live',complete:true,provenance:'native_observation_unverified'},
  scope:{collectionId:'synthetic-group',collectionStatus:'active',enabled:true,version:1,receivingAccountId:'synthetic-wallet'},
  account:{id:'synthetic-wallet',status:'active',provider:'mtn_momo',profile_status:'approved',profile_version:'synthetic.v1',
   profile_json:JSON.stringify(profile),currency:'RWF',timezone:'Africa/Kigali',public_code:'48271',receiver_hash:await sha256('48271')}};
};
const reject=async(input,reason)=>{const r=await nativePromotionEvidence(input);assert.deepEqual(r,{status:'source_unresolved',reason,promotionAllowed:false,financialEffects:0});};

test('explicit unique recipient and current approved profile produce a typed candidate without financial authority',async()=>{
 const f=await fixture(),r=await nativePromotionEvidence(f);
 assert.equal(r.status,'recipient_match_candidate');assert.equal(r.financialEffects,0);assert.equal(r.promotionAllowed,false);
 assert.equal(r.source.kind,'native_observation');assert.equal(r.source.nativeSessionId,f.observation.nativeSessionId);
 assert.equal(r.sourceAssurance,'unverified');assert.equal(r.completeness,'client_claim');
 assert.deepEqual(r.canonicalUnique,{provider:'mtn_momo',receivingAccountId:'synthetic-wallet',eventKind:'incoming_receipt',providerTransactionId:'TX-556677'});
 assert.equal(f.source.raw_body.slice(r.recipientEvidence.identifier.start,r.recipientEvidence.identifier.end),'48271');
 assert.equal(r.amountMinor,1500);assert.equal(JSON.stringify(r).includes(f.source.raw_body),false);
});

test('incomplete, non-live, forged or altered plaintext never produces a candidate',async()=>{
 for(const delta of [{complete:false},{source_mode:'catch_up'},{provenance:'other'},{raw_body:'changed'}]){
  const f=await fixture();Object.assign(f.source,delta);await reject(f,'source_incomplete_or_changed');
 }
});

test('current account, collection, receiving profile and route must match',async()=>{
 for(const change of [f=>f.scope.enabled=false,f=>f.scope.collectionStatus='suspended',f=>f.scope.receivingAccountId='other',
  f=>f.account.profile_status='unverified',f=>f.account.status='suspended',f=>f.account.provider='other',
  f=>f.scope.collectionId='other']){const f=await fixture();change(f);await reject(f,'account_scope_unavailable');}
 for(const change of [f=>f.account.public_code='22222',f=>f.account.receiver_hash='f'.repeat(64)]){
  const f=await fixture();change(f);await reject(f,'recipient_scope_mismatch');
 }
});

test('missing, ambiguous and masked receiving evidence stays unresolved',async()=>{
 for(const replacement of ['', 'Receiver code: 48271. Receiver code: 48271.', 'Receiver code: ****1.']){
  const f=await fixture();f.source.raw_body=f.source.raw_body.replace('Receiver code: 48271.',replacement);
  f.observation.bodySha256=await sha256(f.source.raw_body);await reject(f,'recipient_or_parse_unresolved');
 }
 const f=await fixture(),p=JSON.parse(f.account.profile_json);delete p.recipient_rules;f.account.profile_json=JSON.stringify(p);
 await reject(f,'recipient_or_parse_unresolved');
});

test('numeric coincidence in payer/reference and unrecognized sender never proves a recipient',async()=>{
 const f=await fixture();f.source.raw_body='You have received RWF 48271. TxId: 48271. Payer: 48271.';
 f.observation.bodySha256=await sha256(f.source.raw_body);await reject(f,'recipient_or_parse_unresolved');
 const g=await fixture();g.source.raw_sender='OTHER';await reject(g,'recipient_or_parse_unresolved');
});

test('invalid native session or provenance identities are not replaced with a managed session',async()=>{
 for(const key of ['sourceId','nativeAccountId','nativeSessionId','installationId','grantId']){
  const f=await fixture();f.observation[key]='invalid';await reject(f,'invalid_source_identity');
 }
 const f=await fixture();f.observation.grantVersion=0;await reject(f,'invalid_source_identity');
});
