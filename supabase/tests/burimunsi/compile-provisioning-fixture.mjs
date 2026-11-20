// QUALIFICATION ONLY. Source PinHasher + encryption over synthetic credentials.
// No DB connection, application admission, provider, Auth exchange or native
// installation. Output contains protected records/hashes/ciphertexts only.
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PinHasher,newBearer} from '../../functions/_shared/domain/burimunsi/pin.js';
import {canonicalJson,sha256} from '../../functions/_shared/domain/burimunsi/values.js';
import {encrypt} from '../../functions/_shared/domain/encryption.js';

const group='buri-qualification-group',owner='f3000000-0000-4000-8000-000000000001';
const session='f2000000-0000-4000-8000-000000000001',newStaff='fc300000-0000-4000-8000-000000000003';
const nativeNew='fc700000-0000-4000-8000-000000000003',nativeStaff='f7000000-0000-4000-8000-000000000002';
const nativeOwner='f7000000-0000-4000-8000-000000000001',profileSha='1'.repeat(64);
const request=n=>'fc600000-0000-4000-8000-'+String(n).padStart(12,'0');
const device=n=>'fc900000-0000-4000-8000-'+String(n).padStart(12,'0');
const hasher=new PinHasher({pepper:Uint8Array.from({length:32},(_,i)=>i+89),pepperId:'qualification-provisioning-only'});
const custody={DATA_KEY_ID:'qualification-provisioning-only',DATA_ENCRYPTION_KEY:Buffer.alloc(32,73).toString('base64')};
const common=(operation,id,principal,expected)=>({operation,requestId:request(id),collectionId:group,scopeVersion:1,
 principalId:principal,approvalVersion:1,expectedAccountVersion:expected,reason:'Synthetic owner qualification only'});
const entries={},tokens=new Map();
async function pin(name,id,principal,account,phone,expected,syntheticPin){
 const original={...common('set_pin',id,principal,expected),pin:syntheticPin};
 const command={...original,pinHash:await hasher.hash(phone,syntheticPin),accountId:account};delete command.pin;
 entries[name]={command,fingerprint:await hasher.commandFingerprint(canonicalJson(original)),ciphertext:null};
}
const aad=binding=>'burimunsi-native-delivery-v1:'+canonicalJson([profileSha,owner,session,group,binding.requestId,
 binding.accountId,binding.grantId,binding.installationId,binding.profile,binding.grantVersion,
 binding.expectedAccountVersion,binding.approvalVersion,binding.scopeVersion]);
async function grant(name,id,principal,account,accountVersion,installation,grantId,profile,expectedGrantVersion){
 const original={...common('grant_installation',id,principal,accountVersion),accountId:account,
  installationId:installation,grantId:expectedGrantVersion===0?null:grantId,profile,expectedGrantVersion};
 const token=newBearer(),command={...original,grantId,tokenHash:await sha256(token)};tokens.set(name,token);
 entries[name]={command,fingerprint:await hasher.commandFingerprint(canonicalJson(original)),
  ciphertext:await encrypt(custody,new TextEncoder().encode(token),aad({...command,grantVersion:expectedGrantVersion+1}))};
}
await pin('initial',1,newStaff,nativeNew,'+250780000003',0,'7316');
await pin('resetStaff',2,'f3000000-0000-4000-8000-000000000002',nativeStaff,'+250780000002',1,'8492');
await pin('resetOwner',3,owner,nativeOwner,'+250780000001',1,'9641');
await grant('grantStaff',4,newStaff,nativeNew,1,device(1),device(2),'staff',0);
await grant('rotateStaff',5,newStaff,nativeNew,1,device(1),device(2),'staff',1);
const revoked={...common('revoke_installation',6,newStaff,1),accountId:nativeNew,installationId:device(1),
 grantId:device(2),profile:'staff',expectedGrantVersion:2};
entries.revokeStaff={command:revoked,fingerprint:await hasher.commandFingerprint(canonicalJson(revoked)),ciphertext:null};
await grant('grantReceiver',7,owner,nativeOwner,2,device(3),device(4),'internal_receiver',0);
await grant('secondReceiver',8,owner,nativeOwner,2,device(5),device(6),'internal_receiver',0);
await grant('rotateReceiver',9,owner,nativeOwner,2,device(3),device(4),'internal_receiver',1);
const revokeReceiver={...common('revoke_installation',10,owner,2),accountId:nativeOwner,installationId:device(3),
 grantId:device(4),profile:'internal_receiver',expectedGrantVersion:2};
entries.revokeReceiver={command:revokeReceiver,fingerprint:await hasher.commandFingerprint(canonicalJson(revokeReceiver)),ciphertext:null};
const expired={...entries.grantStaff.command,requestId:request(90),grantVersion:1};
entries.expiredDelivery={requestId:expired.requestId,
 ciphertext:await encrypt(custody,new TextEncoder().encode(tokens.get('grantStaff')),aad(expired))};
entries.sessionHashes={staff:await sha256(newBearer()),owner:await sha256(newBearer()),newStaff:await sha256(newBearer()),
 receiver:await sha256(newBearer()),receiverRevoked:await sha256(newBearer())};
tokens.clear();

const literal=value=>"'"+value.replaceAll("'","''")+"'";
const provisioning_inputs=`DO $provisioning_inputs$ BEGIN\n PERFORM set_config('burimunsi.provisioning.fixture',${literal(JSON.stringify(entries))},true);\nEND;$provisioning_inputs$;\n`+
 `CREATE FUNCTION pg_temp.provisioning_fixture(p_key text) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $fixture$\n`+
 ` SELECT current_setting('burimunsi.provisioning.fixture',true)::jsonb->p_key\n$fixture$;`;
const sources={};
for(const name of ['supabase/functions/_shared/domain/burimunsi/pin.js','supabase/functions/_shared/domain/burimunsi/values.js',
 'supabase/functions/_shared/domain/encryption.js','supabase/functions/_shared/domain/burimunsi/admin-provisioning.js',
 'supabase/migrations/20261110032620_burimunsi_native_provisioning.sql',
 'supabase/tests/burimunsi/provisioning-contract.sql','supabase/tests/burimunsi/compile-provisioning-fixture.mjs'])
 sources[name]=createHash('sha256').update(await readFile(new URL('../../../'+name,import.meta.url))).digest('hex');
process.stdout.write(JSON.stringify({format:'collect.burimunsi.provisioning-sql-fixture.v1',production_acceptance:false,
 scope:'Synthetic protected records/custody and SQL-only contract; no DB/provider/native admission or plaintext credential output',
 provisioning_inputs,sources})+'\n');
