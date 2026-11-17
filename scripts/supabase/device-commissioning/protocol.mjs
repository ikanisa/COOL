// Unintegrated protocol candidate. This module does not authenticate a real
// account or establish the source queue, fences, mapping, or target authority.
const encoder=new TextEncoder();
const HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const fields=['account_group_mapping_sha256','application','approved_operator_sha256','expires_epoch','format',
 'installation_sha256','queue_generation','queue_revision','queue_watermark','reconciliation_sha256','role',
 'sealed_queue_sha256','source_account_sha256','source_api_sha256','source_auth_sha256','source_fence_sha256',
 'source_gateway_sha256','target_api_sha256','target_auth_sha256','target_device_key_sha256','target_fence_sha256',
 'target_gateway_sha256','target_primary_account_sha256','target_project','transition_id'];
const hashes=fields.filter(x=>x.endsWith('_sha256'));
const plain=x=>x!==null&&typeof x==='object'&&!Array.isArray(x)&&Object.getPrototypeOf(x)===Object.prototype;
const exact=(x,names)=>plain(x)&&Object.keys(x).sort().join('\0')===[...names].sort().join('\0');
const fail=()=>{throw new Error('commissioning_invalid');};
export function canonical(value){
 if(typeof value==='string')return JSON.stringify(value);
 if(plain(value))return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
 fail();
}
export function parseCanonical(text,maxBytes=16384){
 if(typeof text!=='string'||encoder.encode(text).length>maxBytes)fail();
 let value;try{value=JSON.parse(text);}catch{fail();}
 if(canonical(value)!==text)fail();return value;
}
export const encode64=bytes=>btoa(String.fromCharCode(...new Uint8Array(bytes))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
function decode64(value,length){
 if(typeof value!=='string'||!/^[A-Za-z0-9_-]+$/.test(value))fail();
 let bytes;try{bytes=Uint8Array.from(atob(value.replaceAll('-','+').replaceAll('_','/')+'='.repeat((4-value.length%4)%4)),c=>c.charCodeAt(0));}catch{fail();}
 if(bytes.length!==length||encode64(bytes)!==value)fail();return bytes;
}
export async function keyFingerprint(raw){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',raw))].map(x=>x.toString(16).padStart(2,'0')).join('');}
export async function rawPublicKey(key){
 if(!key||key.type!=='public'||key.algorithm?.name!=='Ed25519'||!key.usages.includes('verify'))fail();
 const raw=new Uint8Array(await crypto.subtle.exportKey('raw',key));if(raw.length!==32)fail();return raw;
}
async function verifyKey(raw){return crypto.subtle.importKey('raw',raw,{name:'Ed25519'},false,['verify']);}
function signKey(key){if(!key||key.type!=='private'||key.algorithm?.name!=='Ed25519'||!key.usages.includes('sign'))fail();return key;}
export async function signDomain(key,domain,value){
 if(typeof domain!=='string'||!/^collect\.commissioning\.[a-z-]+\.v1$/.test(domain))fail();
 return encode64(await crypto.subtle.sign('Ed25519',signKey(key),encoder.encode(domain+'\n'+canonical(value))));
}
async function verifyDomain(key,signature,domain,value){
 try{return await crypto.subtle.verify('Ed25519',key,decode64(signature,64),encoder.encode(domain+'\n'+canonical(value)));}catch{return false;}
}
export function validateBinding(value,{targetProject,primaryAccountSha256,targetApiSha256,targetAuthSha256,targetGatewaySha256,operatorSha256}={}){
 if(!exact(value,fields)||Object.values(value).some(v=>typeof v!=='string')||value.format!=='collect.commissioning-binding.v1'
  ||typeof targetProject!=='string'||value.target_project!==targetProject||!UUID.test(value.transition_id)
  ||!((value.application==='rw.ikanisa.burimunsi.gateway'&&value.role==='receiver')||(value.application==='rw.ikanisa.burimunsi.staff'&&value.role==='staff'))
  ||!(/^[1-9][0-9]{0,14}$/.test(value.queue_generation))||!(/^(0|[1-9][0-9]{0,14})$/.test(value.queue_revision))
  ||!(/^(0|[1-9][0-9]{0,14})$/.test(value.queue_watermark))||!(/^[1-9][0-9]{0,11}$/.test(value.expires_epoch))
  ||hashes.some(name=>!HASH.test(value[name]))||value.source_api_sha256===value.target_api_sha256||value.source_auth_sha256===value.target_auth_sha256
  ||value.target_primary_account_sha256!==primaryAccountSha256||value.target_api_sha256!==targetApiSha256||value.target_auth_sha256!==targetAuthSha256
  ||value.target_gateway_sha256!==targetGatewaySha256||value.approved_operator_sha256!==operatorSha256)fail();
 return value;
}
export function validateFresh(binding,now,allowExpired=false){
 if(!Number.isSafeInteger(now)||now<0)fail();const seconds=Math.floor(now/1000),expiry=Number(binding.expires_epoch);
 if(!Number.isSafeInteger(expiry)||expiry>seconds+900||(!allowExpired&&expiry<=seconds))fail();
}
export async function verifyCommand(command,policy,operatorPublicKey,now){
 if(!plain(command)||!['issue','status','consume'].includes(command.action))fail();
 const names=['action','binding','device_public_key','device_signature','format','operator_signature'];
 if(command.action==='consume')names.push('consume_id','receipt');
 if(!exact(command,names)||command.format!=='collect.commissioning-command.v1'||(command.action==='consume'&&!UUID.test(command.consume_id??'')))fail();
 validateBinding(command.binding,policy);validateFresh(command.binding,now,command.action==='status');
 const operatorRaw=await rawPublicKey(operatorPublicKey),deviceRaw=decode64(command.device_public_key,32);
 if(await keyFingerprint(operatorRaw)!==policy.operatorSha256||await keyFingerprint(deviceRaw)!==command.binding.target_device_key_sha256
  ||encode64(operatorRaw)===command.device_public_key)fail();
 const {operator_signature,device_signature,...payload}=command;
 const operatorOk=await verifyDomain(operatorPublicKey,operator_signature,'collect.commissioning.operator-'+command.action+'.v1',payload);
 const deviceOk=await verifyDomain(await verifyKey(deviceRaw),device_signature,'collect.commissioning.device-'+command.action+'.v1',payload);
 if(!operatorOk||!deviceOk)fail();return payload;
}
export async function signEnvelope(privateKey,keyId,kind,payload){
 if(!/^[a-z0-9_-]{1,40}$/.test(keyId??'')||!['receipt','ack'].includes(kind)||!plain(payload))fail();
 const content={format:'collect.commissioning-'+kind+'.v1',key_id:keyId,payload};
 return {...content,signature:await signDomain(privateKey,'collect.commissioning.target-'+kind+'.v1',content)};
}
export async function verifyEnvelope(envelope,publicKey,keyId,kind){
 if(!exact(envelope,['format','key_id','payload','signature'])||envelope.format!=='collect.commissioning-'+kind+'.v1'||envelope.key_id!==keyId||!plain(envelope.payload))fail();
 const {signature,...content}=envelope;if(!await verifyDomain(publicKey,signature,'collect.commissioning.target-'+kind+'.v1',content))fail();return envelope.payload;
}
