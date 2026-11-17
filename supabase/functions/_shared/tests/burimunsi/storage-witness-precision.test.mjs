import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {StorageProtocolError,sha256,canonical} from '../../storage/protocol.js';

// Exercise the actual bucket and a synthetic durable witness. This catches
// disagreement between the timestamp used by native prepare and storage on
// the first attempt and on an exact retry, without accessing a provider.
const adapters=readFileSync(new URL('../../adapters.js',import.meta.url),'utf8');
const start=adapters.indexOf('export class SupabaseObjectBucket {'),end=adapters.indexOf('\n// Leave room for JSON escaping',start);
assert(start>=0&&end>start);
class ApiError extends Error{constructor(status,code,message){super(message);this.status=status;this.code=code;}}
const bytes=new TextEncoder().encode('synthetic plaintext');
const Bucket=new Function('StorageProtocolError','ApiError','unavailable','sha256','canonical','decrypt','digest',
 adapters.slice(start,end).replace('export class','class')+';return SupabaseObjectBucket;')(
 StorageProtocolError,ApiError,name=>new ApiError(503,name+'_unavailable','Synthetic unavailable'),sha256,canonical,
 async()=>bytes,async()=>sha256(bytes));
const key='sms/00000000-0000-4000-8000-000000000001';

for(let digits=4;digits<=9;digits++)test(`SMS witness preserves ${digits} fractional digits through storage and exact retry`,async()=>{
 const timestamp=`2026-11-11T12:00:00.${'123456789'.slice(0,digits)}Z`, calls=[];
 let reservation=null,committed=null;
 const journal={
  async getPayloadBinding(){return reservation&&{keyId:'synthetic',sourceFingerprint:reservation.sourceFingerprint};},
  async reservePayload(objectKey,descriptor,sealedBody,witness){
   calls.push(witness.inboxReceivedAt);
   // This is the same value supplied to PostgreSQL during native prepare.
   // A changed storage timestamp would permanently conflict with that witness.
   assert.equal(witness.inboxReceivedAt,timestamp);
   const sourceFingerprint=await sha256(canonical(descriptor));
   if(reservation){assert.equal(sourceFingerprint,reservation.sourceFingerprint);return {sealedBody:null,sourceFingerprint};}
   reservation={sourceFingerprint};return {sealedBody,sourceFingerprint};
  },
  async getPutByKey(){return committed;}
 };
 const media=Object.assign(Object.create(Bucket.prototype),{env:{DATA_KEY_ID:'synthetic'},journal,
  protocol:{async put(_key,_body,{customMetadata}){committed={customMetadata};return {stored:true};},
   async confirmCommitted(intent){assert.equal(intent,committed);return {stored:true};}}});
 const options={scope:{ownerId:'synthetic-owner',purpose:'sms_receipt',entityId:key.slice(4)},aad:'synthetic-aad',
  sourceDigest:'a'.repeat(64),smsWitness:{bodySha256:'b'.repeat(64),collectionId:'synthetic-group',inboxReceivedAt:timestamp},
  customMetadata:{sha256:await sha256(bytes),key_id:'synthetic'}};
 assert.deepEqual(await media.put(key,'synthetic-ciphertext',options),{stored:true});
 assert.deepEqual(await media.put(key,'synthetic-ciphertext',options),{stored:true});
 assert.deepEqual(calls,[timestamp,timestamp]);
});
