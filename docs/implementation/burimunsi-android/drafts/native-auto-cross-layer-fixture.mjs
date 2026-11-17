// Synthetic-only encrypted object for the isolated native worker rehearsal.
import {encrypt} from '../../../../supabase/functions/_shared/domain/encryption.js';
import {digest} from '../../../../supabase/functions/_shared/domain/core.js';
import {canonicalJson} from '../../../../supabase/functions/_shared/domain/burimunsi/values.js';

const principal='f3000000-0000-4000-8000-000000000001';
const request='fe910000-0000-4000-8000-000000000001';
const hash=await digest(`collect.storage.entity.v1\nburimunsi.native.observation.v1\n${principal}\n${request}`);
const source=`${hash.slice(0,8)}-${hash.slice(8,12)}-5${hash.slice(13,16)}-8${hash.slice(17,20)}-${hash.slice(20,32)}`;
const body='Received 250 RWF. Reference: 1234. Thank you.';
const now=new Date().toISOString();
const payload={raw_sender:'Example Money',raw_body:body,source_mode:'catch_up',complete:false,captured_at:now,
 service_centre_at:null,inbox_received_at:now,subscription_id:1,provenance:'native_observation_unverified'};
const bytes=new TextEncoder().encode(JSON.stringify(payload));
const objectSha=await digest(bytes),bodySha=await digest(body),fingerprint='d'.repeat(64),keyId='synthetic-key';
const dataKey=btoa(String.fromCharCode(...new Uint8Array(32).fill(19))),aad=`sms:${source}:${objectSha}`;
const sealed=await encrypt({DATA_KEY_ID:keyId,DATA_ENCRYPTION_KEY:dataKey},bytes,aad);
const descriptor={scope:{ownerId:principal,purpose:'sms_receipt',entityId:source},aad,keyId,
 plaintextSha256:objectSha,requestDigest:fingerprint,httpMetadata:{contentType:'application/octet-stream'},
 customMetadata:{sha256:objectSha,key_id:keyId}};
process.stdout.write(JSON.stringify({principal,request,source,objectSha,bodySha,fingerprint,keyId,dataKey,sealed,
 sourceFingerprint:await digest(canonicalJson(descriptor)),cipherSha:await digest(new TextEncoder().encode(sealed)),
 cipherSize:new TextEncoder().encode(sealed).length,plainSize:bytes.length}));
